/// 聊天引擎（Dart 编排层）：
/// Rust 负责 存储/提示词组装/工具协议解析/本地工具执行，
/// 这里负责 HTTP 请求（dio）与多轮工具循环控制。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'models.dart';
import 'store.dart';
import 'attachments.dart';
import 'mcp_client.dart';
import 'skill_pack.dart';

class ChatEngine {
  ChatEngine._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
    validateStatus: (s) => s != null && s < 500,
  ));

  /// 全局激活的 Provider（工作流等非好友场景）
  static AIProvider? providerForGlobal() {
    final all = AmoreStore.listProviders();
    if (all.isEmpty) return null;
    final activeId = AmoreStore.activeProviderId();
    if (activeId.isNotEmpty) {
      final hit = all.where((p) => p.id == activeId).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    return all.first;
  }

  /// 解析某好友生效的 Provider（好友专属 > 全局激活；无任何配置返回 null）
  static AIProvider? providerFor(ChatFriend f) {
    final all = AmoreStore.listProviders();
    if (all.isEmpty) return null;
    if (f.aiProviderId.isNotEmpty) {
      final hit = all.where((p) => p.id == f.aiProviderId).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    final activeId = AmoreStore.activeProviderId();
    if (activeId.isNotEmpty) {
      final hit = all.where((p) => p.id == activeId).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    return all.first;
  }

  /// 是否本机直连（127.0.0.1 / localhost）
  static bool isDirect(AIProvider p) {
    final b = _effectiveBase(p).toLowerCase();
    return b.contains('127.0.0.1') || b.contains('localhost');
  }

  /// 官方默认端点（Rust catalog 提供），配置 base 为空时使用
  static String _effectiveBase(AIProvider p) {
    final b = p.baseURL.trim();
    if (b.isNotEmpty) return b;
    for (final v in AmoreStore.vendors()) {
      if (v.key == p.vendor) return v.base;
    }
    return '';
  }

  /// 组装 /chat/completions 端点（对齐 BackendStore.directChat 的补全规则）
  static String completionsUrl(AIProvider p) {
    var url = _effectiveBase(p).trim();
    if (url.isEmpty) {
      throw Exception('「${p.label}」缺少 Base URL：请到「我的 → 模型配置」填写接口地址');
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.contains('/chat/completions')) {
      // 原样
    } else if (url.endsWith('/v1')) {
      url += '/chat/completions';
    } else {
      url += '/v1/chat/completions';
    }
    return url;
  }

  /// 单次请求（非流式）→ assistant 文本
  static Future<String> request(
      AIProvider p, List<Map<String, String>> messages, String systemPrompt,
      {String? overrideUrl, String? extraSystem}) async {
    var url = overrideUrl ?? completionsUrl(p);
    if (p.apiFormat == 'responses' && !isDirect(p) && p.baseURL.trim().isNotEmpty) {
      // Responses API（OpenAI 新格式）：/v1/responses
      url = url.replaceAll('/chat/completions', '/responses');
    }
    final modelName = p.model.trim().isEmpty ? p.label.trim() : p.model.trim();
    if (modelName.isEmpty) {
      throw Exception('「${p.label}」还没有模型名：请在模型配置里选择或手动填写');
    }
    final body = <String, dynamic>{
      'model': modelName,
      'stream': false,
    };
    final msgs = <Map<String, String>>[
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      if (extraSystem != null && extraSystem.isNotEmpty)
        {'role': 'system', 'content': extraSystem},
      ...messages,
    ];
    if (p.apiFormat == 'responses') {
      // responses 格式：input 数组
      body['input'] = msgs.map((m) => {'role': m['role'], 'content': m['content']}).toList();
    } else {
      body['messages'] = msgs;
    }
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      if (p.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${p.apiKey.trim()}',
    };
    final resp = await _dio.post(url,
        data: body, options: Options(headers: headers));
    if (resp.statusCode != 200) {
      final data = resp.data;
      var detail = '';
      if (data is Map) {
        final err = data['error'];
        detail = err is Map
            ? (err['message'] ?? '').toString()
            : (data['message'] ?? err ?? '').toString();
      } else if (data != null) {
        detail = data.toString();
      }
      if (detail.length > 220) detail = detail.substring(0, 220);
      throw Exception(
          'HTTP ${resp.statusCode}${detail.trim().isEmpty ? '' : ' · ${detail.trim()}'}');
    }
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      if (p.apiFormat == 'responses') {
        // responses: {"output":[{"content":[{"text":...}]}]} 简化兼容：
        final out = data['output'];
        if (out is List && out.isNotEmpty) {
          final first = out.first;
          if (first is Map && first['content'] is List && (first['content'] as List).isNotEmpty) {
            final c = (first['content'] as List).first;
            if (c is Map && c['text'] != null) return c['text'].toString();
          }
        }
      }
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = (choices.first as Map)['message'];
        if (msg is Map && msg['content'] != null) return msg['content'].toString();
      }
    }
    throw Exception('响应格式无法解析：${data.toString().substring(0, data.toString().length.clamp(0, 160))}');
  }

  /// 完整对话轮：发消息 → 工具循环（≤3 轮）→ 落历史 → 返回最终回复与工具调用记录
  /// [onToolCall] 用于 UI 显示「🔧 调用工具：xxx」
  static Future<ChatTurnResult> send({
    required ChatFriend friend,
    required String userText,
    List<Map<String, String>>? attachments,
    void Function(String toolName)? onToolCall,
    String? extraSystem,
  }) async {
    final provider = providerFor(friend);
    if (provider == null) {
      return ChatTurnResult.error('尚未配置 AI 模型：请到「我的 → 模型配置」添加并激活一个供应商。');
    }
    if (provider.model.trim().isEmpty) {
      return ChatTurnResult.error(
          '「${provider.label}」还没有选择模型：请到「我的 → 模型配置」选择模型，或点「从 API 接口读取模型」。');
    }

    final key = 'friend.${friend.id}';
    final stored =
        Attachments.encode(attachments ?? const [], userText);
    AmoreStore.appendHistory(key, 'user', stored);
    final history = AmoreStore.loadHistory(key);

    final system = [
      AmoreStore.buildSystemPrompt(friend),
      if (extraSystem != null && extraSystem.isNotEmpty) extraSystem,
      ..._skillSystemParts(await _mcpToolLines()),
    ].join('\n\n');

    // 组装消息（历史最近 24 条）
    var msgs = history.length <= 24
        ? history.map((m) => {'role': m.role, 'content': m.content}).toList()
        : history.sublist(history.length - 24).map((m) => {'role': m.role, 'content': m.content}).toList();
    // 刚发送的附件消息：AI 只看文件名说明，不暴露本地路径
    if (attachments != null && attachments.isNotEmpty && msgs.isNotEmpty) {
      final names =
          attachments.map((a) => a['name'] ?? '').where((n) => n.isNotEmpty);
      final last = msgs.removeLast();
      if (last['role'] == 'user') {
        msgs.add({
          'role': 'user',
          'content': '$userText\n（我发送了 ${attachments.length} 个附件：${names.join('、')}）'
        });
      } else {
        msgs.add(last);
      }
    }

    String feedback; // 工具结果回注（追加为 tool 消息）
    String lastClean = '';
    final allTools = <ToolCallInfo>[];
    int rounds = 0;

    try {
      for (rounds = 0; rounds < 3; rounds++) {
      final reply = await request(provider, msgs, system);
      final parsed = AmoreStore.parseAssistant(reply);
      lastClean = parsed.clean;

      // 抽取记忆标记
      final mems = AmoreStore.extractMemory(reply);
      if (mems.isNotEmpty) {
        friend.memory = [...friend.memory, ...mems];
        AmoreStore.saveFriend(friend);
      }

      if (parsed.feedback == null || parsed.called.isEmpty) {
        // 无工具调用 → 结束
        AmoreStore.appendHistory(key, 'assistant', lastClean);
        _touchFriend(friend, lastClean);
        return ChatTurnResult(text: lastClean, tools: allTools);
      }

      allTools.addAll(parsed.called);
      for (final c in parsed.called) {
        onToolCall?.call(c.name);
      }
      // Dart 侧统一执行：mcp: 前缀走外部 MCP，其余走 Rust 本地工具
      feedback = await _execTools(parsed.called);
      msgs.add({'role': 'assistant', 'content': reply});
      msgs.add({'role': 'tool', 'content': feedback});
      // 继续下一轮（feedback 已进 msgs）
    }

      AmoreStore.appendHistory(key, 'assistant', lastClean);
      _touchFriend(friend, lastClean);
      return ChatTurnResult(text: lastClean, tools: allTools);
    } catch (e) {
      return ChatTurnResult.error(_friendlyError(e));
    }
  }

  /// 选择「图片」类型配置（kind=image），无则回退激活/首个
  static AIProvider? providerForImage() {
    final all = AmoreStore.listProviders();
    if (all.isEmpty) return null;
    final imgs = all.where((p) => p.kind == 'image').toList();
    if (imgs.isNotEmpty) return imgs.first;
    return providerForGlobal();
  }

  /// AI 生成图片（OpenAI /v1/images/generations 兼容）。
  /// 返回沙盒内的图片路径（已保存），失败抛异常。
  static Future<String> generateImage(AIProvider p, String prompt,
      {String size = '1024x1024'}) async {
    var url = _effectiveBase(p).trim();
    if (url.isEmpty) {
      throw Exception('「${p.label}」缺少 Base URL：请到「我的 → 模型配置」填写接口地址');
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.contains('/images/generations')) {
      url += url.endsWith('/v1') ? '/images/generations' : '/v1/images/generations';
    }
    final model = (p.imageModel.isNotEmpty ? p.imageModel : p.model).trim();
    final headers = {
      'Content-Type': 'application/json',
      if (p.apiKey.isNotEmpty) 'Authorization': 'Bearer ${p.apiKey}',
    };
    final body = {
      if (model.isNotEmpty) 'model': model,
      'prompt': prompt,
      'n': 1,
      'size': size,
    };
    final resp = await _dio.post<Map<String, dynamic>>(url,
        data: body, options: Options(headers: headers));
    final data = resp.data;
    if (data == null) throw Exception('图片接口无返回（HTTP ${resp.statusCode}）');
    final first = (data['data'] as List?)?.firstOrNull;
    if (first is! Map) {
      throw Exception('响应无法解析：${data.toString().substring(0, data.toString().length.clamp(0, 120))}');
    }
    final b64 = first['b64_json']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      // base64 直接落盘
      final bytes = _base64Decode(b64);
      return _saveImageBytes(bytes);
    }
    final imgUrl = first['url']?.toString() ?? '';
    if (imgUrl.isNotEmpty) {
      final r2 = await _dio.get<List<int>>(imgUrl,
          options: Options(responseType: ResponseType.bytes));
      if (r2.data == null || r2.data!.isEmpty) {
        throw Exception('图片下载失败（HTTP ${r2.statusCode}）');
      }
      return _saveImageBytes(r2.data!);
    }
    throw Exception('响应中没有图片数据');
  }

  static List<int> _base64Decode(String s) {
    // 兼容 data URL 前缀
    final clean = s.contains(',') ? s.substring(s.indexOf(',') + 1) : s;
    return base64Decode(clean);
  }

  static Future<String> _saveImageBytes(List<int> bytes) async {
    final dir = await Attachments.dir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$dir/${stamp}_ai_image.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// 把底层异常翻译成用户可读的原因
  static String _friendlyError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      var detail = '';
      if (data is Map) {
        final err = data['error'];
        detail = err is Map
            ? (err['message'] ?? '').toString()
            : (data['message'] ?? err ?? '').toString();
      } else if (data != null) {
        detail = data.toString();
      }
      if (detail.length > 200) detail = detail.substring(0, 200);
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '请求超时：请检查网络与 Base URL';
        case DioExceptionType.connectionError:
          return '无法连接服务器：请检查 Base URL（需要含 https://）与网络';
        case DioExceptionType.badCertificate:
          return 'TLS 证书校验失败：请确认接口地址可信';
        case DioExceptionType.cancel:
          return '请求已取消';
        default:
          break;
      }
      if (code != null) {
        return 'HTTP $code${detail.trim().isEmpty ? '' : ' · ${detail.trim()}'}';
      }
      return detail.trim().isEmpty
          ? '请求失败：${e.message ?? e.type.name}'
          : detail.trim();
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  static void _touchFriend(ChatFriend f, String msg) {
    f.lastMessage = msg;
    f.lastAt = DateTime.now().millisecondsSinceEpoch / 1000;
    AmoreStore.saveFriend(f);
  }
}

class ChatTurnResult {
  final String? text; // 最终回复
  final String? error; // 错误信息
  final List<ToolCallInfo> tools;

  ChatTurnResult({this.text, this.error, this.tools = const []});

  ChatTurnResult.error(this.error) : text = null, tools = const [];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

  // ---- 技能中心集成：技能/插件提示词 + MCP 工具指南 ----

  /// 从所有启用服务并行拉取 MCP 工具清单（单个失败不阻塞）
  Future<List<String>> _mcpToolLines() async {
    final services = enabledMcpServices();
    if (services.isEmpty) return const [];
    final results = await Future.wait(services.map((s) async {
      try {
        final tools = await McpClient(s).listTools();
        if (tools.isEmpty) return '- 服务「${s.name}」：暂无工具';
        return tools
            .map((t) {
              final props = (t.inputSchema['properties'] as Map?)?.keys.toList() ?? const [];
              final argDesc = props.isEmpty ? '无参数' : '参数：${props.join(' / ')}';
              return '- mcp:${s.name}:${t.name} —— ${t.description.isEmpty ? '外部工具' : t.description}（$argDesc）';
            })
            .join('\n');
      } catch (e) {
        return '- 服务「${s.name}」连接失败：${e.toString().substring(0, e.toString().length.clamp(0, 80))}';
      }
    }));
    return results;
  }

  /// 启用的技能/插件提示词 + MCP 工具调用说明
  List<String> _skillSystemParts(List<String> mcpLines) {
    final parts = <String>[];
    for (final p in SkillCatalog.enabledPacks()) {
      if (p.category == 'workflow') continue; // 工作包不进对话
      if (p.prompt.isNotEmpty) parts.add(p.prompt);
    }
    if (mcpLines.isNotEmpty) {
      parts.add(
          '【外部工具（MCP）】你可以调用以下外部服务工具，调用格式与本地工具一致：\n<tool name="mcp:服务名:工具名">\n<param name="参数名">值</param>\n</tool>\n可用工具：\n${mcpLines.join('\n')}');
    }
    return parts;
  }

  /// 执行一批工具调用并拼回注 XML（格式与 Rust 一致）
  Future<String> _execTools(List<ToolCallInfo> called) async {
    final buf = <String>[];
    for (final c in called) {
      final tag = _randomTag();
      try {
        final (status, content) = await _execOne(c);
        buf.add('<$tag name="${c.name}" status="$status">\n$content\n</$tag>');
      } catch (e) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        buf.add('<$tag name="${c.name}" status="error">\n$msg\n</$tag>');
      }
    }
    return buf.join('\n');
  }

  Future<(String, String)> _execOne(ToolCallInfo c) async {
    if (c.name.startsWith('mcp:')) {
      final rest = c.name.substring(4);
      final dot = rest.indexOf(':');
      if (dot <= 0) throw Exception('MCP 工具名格式：mcp:<服务名>:<工具名>');
      final svcName = rest.substring(0, dot);
      final toolName = rest.substring(dot + 1);
      final svc = enabledMcpServices()
          .where((s) => s.name == svcName)
          .toList()
          .firstOrNull;
      if (svc == null) {
        throw Exception('未找到 MCP 服务「$svcName」（请到技能中心启用）');
      }
      final result = await McpClient(svc).callTool(toolName, c.params);
      return ('ok', result);
    }
    final r = AmoreStore.execTool(c.name, c.params);
    return (r.status, r.content);
  }

  /// 6 位随机字母 tag（与 Rust random_tag 同形态）
  String _randomTag() {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    final t = DateTime.now().microsecondsSinceEpoch;
    var x = t;
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(letters[x % 26]);
      x = (x >> 3) | 7919;
    }
    return buf.toString();
  }
