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
import 'tools_config.dart';
import 'code_engine.dart';
import 'aojit_runtime.dart';

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
        // 无工具调用 → 结束（插件 recv 钩子扩展点）
        final finalText = _withProducts(_pluginRecvHook(lastClean, userText));
        AmoreStore.appendHistory(key, 'assistant', finalText);
        _touchFriend(friend, finalText);
        return ChatTurnResult(text: finalText, tools: allTools);
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

      final finalText = _withProducts(lastClean);
      AmoreStore.appendHistory(key, 'assistant', finalText);
      _touchFriend(friend, finalText);
      return ChatTurnResult(text: finalText, tools: allTools);
    } catch (e) {
      return ChatTurnResult.error(_friendlyError(e));
    }
  }

  /// 供对话页等复用：执行工具调用（AI 产物自动入队）
  static Future<String> runTools(List<ToolCallInfo> called) =>
      _execTools(called);

  /// 工具指南注入（技能 + 本地编程/AOJIT + MCP）
  static Future<List<String>> mcpToolLines() => _mcpToolLines();

  static List<String> skillSystemParts(List<String> mcpLines) =>
      _skillSystemParts(mcpLines);

  /// AI 产物（压缩包等）附加到回复文本
  static String withProducts(String text) => _withProducts(text);

  /// 清空本轮 AI 产物队列（每轮对话开始前）
  static void clearProducts() => g_aiProducts.clear();

  /// 对话页工具循环：单轮请求 + 工具回注（≤3 轮），返回最终展示文本
  static Future<String> turnWithTools({
    required AIProvider provider,
    required List<Map<String, String>> msgs,
    required String system,
    String? extraSystem,
  }) async {
    String lastClean = '';
    for (var round = 0; round < 3; round++) {
      final reply = await request(provider, msgs, system,
          extraSystem: extraSystem);
      final parsed = AmoreStore.parseAssistant(reply);
      lastClean = parsed.clean;
      if (parsed.called.isEmpty) break;
      final fb = await _execTools(parsed.called);
      msgs.add({'role': 'assistant', 'content': reply});
      msgs.add({'role': 'tool', 'content': fb});
    }
    return _withProducts(lastClean);
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

/// AI 生成的附件产物（如文件压缩结果），随本轮回复作为附件回发
final g_aiProducts = <Map<String, String>>[];

String _withProducts(String text) {
  if (g_aiProducts.isEmpty) return text;
  final atts = List<Map<String, String>>.from(g_aiProducts);
  g_aiProducts.clear();
  return Attachments.encode(atts, text);
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
    // 可调用技能（带 JSON Schema 参数规范）→ 以工具形式注入
    final callable = SkillCatalog.enabledPacks()
        .where((p) => p.category == 'skill' && p.callable)
        .toList();
    if (callable.isNotEmpty) {
      final lines = callable.map((p) {
        final args = p.parameters.isNotEmpty
            ? '参数规范：${p.parameters}'
            : '无参数';
        return '- skill:${p.id} —— ${p.desc}（$args）';
      }).join('\n');
      parts.add(
          '【技能调用】需要下列能力时，按工具格式调用：\n<tool name="skill:技能id">\n<param name="参数名">值</param>\n</tool>\n可用技能：\n$lines');
    }
    // 本地编程 + AOJIT 镜像执行（用户提示词命中计算/转换需求时自动调用）
    parts.add(
        '【本地编程 / AOJIT 自动调用规则】只要用户请求涉及以下任何精确计算或数据处理，你必须调用 run_code 或 skill 执行，严禁心算或编造结果：\n'
        '1. 数学计算（四则/幂/三角函数/取整/统计）：\n<tool name="run_code"><param name="op">eval</param><param name="input">12*(3+4)^2</param></tool>\n'
        '2. 哈希/加密（sha256、md5、sha1、hmac、blake2）：<param name="op">aojit</param><param name="input">openssl sha256 任意文本</param> 或 <param name="op">aojit</param><param name="input">blake2 abc</param>\n'
        '3. 压缩解压（zlib）：<param name="op">aojit</param><param name="input">zlib compress 文本</param>\n'
        '4. 编码转换（base64/hex/URL、crc32）：<param name="op">aojit</param><param name="input">b64 hex abc</param> 或 <param name="op">base64</param><param name="input">文本</param>\n'
        '5. 正则/文本统计（statistics、字数、匹配）：<param name="op">stats</param> 或 <param name="op">regex</param><param name="arg">pattern::replacement</param>\n'
        '6. 日期时间（now/parse/格式化）：<param name="op">aojit</param><param name="input">datetime now</param>\n'
        '7. 二进制打包（struct pack）：<param name="op">aojit</param><param name="input">struct pack I 123</param>\n'
        '8. 其他精确需求（SQLite 存取、网络/随机器说明）：<param name="op">aojit</param><param name="input">sqlite set key value</param>；随机数可用本地工具 random\n'
        '9. 用户要求压缩/打包附件文件时：<param name="op">aojit</param><param name="input">file compress 附件完整文件名（含扩展名）</param>——压缩包会自动作为附件随你的回复发送给用户\n'
        'AOJIT 所有操作都可经 run_code 的 aojit 操作或编程执行技能（skill:skill_run_code）调用，组件有：libc/math/python/numpy/openssl/hashlib/blake2/zlib/pcre/datetime/binascii/struct/socket/select/sqlite/busybox。');
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
    // 工具调用确认（工具与权限页）：开启后按 AI 调用的工具执行审批（此处拦截并告知 AI）
    if (ToolsConfig.toolConfirm) {
      return ('error',
          '工具调用确认已开启：AI 调用工具需人工审批，本轮不执行「${c.name}」（可在 设置 → 工具与权限 关闭后重试）');
    }
    // 只读能力模式：写类工具拦截（当前内置工具均为只读；Skill 执行器扩展时在此登记写名单）
    if (!ToolsConfig.canWrite &&
        const {'skill_save', 'tool_write'}.contains(c.name)) {
      return ('error', 'AI 能力模式为只读：禁止写操作「${c.name}」');
    }
    // 本地编程：run_code（表达式/base64/url/JSON/正则/统计，纯 Dart 沙盒）
    if (c.name == 'run_code' || c.name == 'skill:run_code') {
      try {
        final op = c.params['op'] ?? 'eval';
        final input = c.params['input'] ?? '';
        final arg = c.params['arg'] ?? '';
        // AOJIT 镜像执行：input = '<组件> <操作> <参数...>'
        if (op == 'aojit') {
          final parts = input
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          if (parts.isEmpty) {
            return ('error',
                'aojit 用法：<组件> <操作> <参数...>，如 openssl sha256 你好 / math eval 12*(3+4)^2 / blake2 abc');
          }
          final comp = parts[0];
          final op2 = parts.length > 1 ? parts[1] : '';
          final rest = parts.length > 2 ? parts.sublist(2) : <String>[];
          final result = AojitRuntime.run(comp, op2, rest);
          if (result.startsWith('AOJIT_PRODUCT:')) {
            final nl = result.indexOf('\n');
            final raw = result.substring(13, nl < 0 ? result.length : nl);
            try {
              final mm = Map<String, dynamic>.from(jsonDecode(raw) as Map);
              g_aiProducts.add({
                'name': (mm['name'] ?? '产物').toString(),
                'path': (mm['path'] ?? '').toString(),
                'kind': 'file',
              });
            } catch (_) {}
            return ('ok', nl < 0 ? '已生成附件产物' : result.substring(nl + 1));
          }
          return ('ok', result);
        }
        final result = CodeEngine.run(op, input, arg.isEmpty ? null : arg);
        return ('ok', result);
      } catch (e) {
        return ('error', e.toString().replaceFirst('Exception: ', ''));
      }
    }
    // Skill 技能：skill:<id> —— 按 handler 执行（tool: 映射本地工具 / script: 内置脚本）
    if (c.name.startsWith('skill:')) {
      final sid = c.name.substring(6);
      final skill = SkillCatalog.byId(sid);
      if (skill == null) {
        throw Exception('未启用技能「$sid」（请到技能中心启用）');
      }
      final result = _execSkill(skill, c.params);
      return result;
    }
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

  /// Skill 执行器：tool:<本地工具> / script:<内置脚本>
  (String, String) _execSkill(SkillPack skill, Map<String, String> params) {
    final h = skill.handler;
    if (h.startsWith('tool:')) {
      final tool = h.substring(5);
      final r = AmoreStore.execTool(tool, params);
      return (r.status, r.content);
    }
    if (h == 'script:code') {
      // 编程执行技能：op/input/arg 参数 → 本地代码引擎 / AOJIT 镜像
      final op = (params['op'] ?? 'eval').trim();
      final input = (params['input'] ?? '').trim();
      final arg = (params['arg'] ?? '').trim();
      try {
        if (op == 'aojit') {
          final parts = input
              .split(RegExp(r'\s+'))
              .where((e) => e.isNotEmpty)
              .toList();
          if (parts.isEmpty) {
            return ('error', 'aojit 用法：<组件> <操作> <参数...>');
          }
          final comp = parts[0];
          final op2 = parts.length > 1 ? parts[1] : '';
          final rest = parts.length > 2 ? parts.sublist(2) : <String>[];
          return ('ok', AojitRuntime.run(comp, op2, rest));
        }
        final result = CodeEngine.run(op, input, arg.isEmpty ? null : arg);
        return ('ok', result);
      } catch (e) {
        return ('error', e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (h == 'script:textstats') {
      final text = params['text'] ?? '';
      final chars = text.replaceAll(RegExp(r'\s'), '').length;
      final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
      final paras = text.trim().isEmpty
          ? 0
          : text.split(RegExp(r'\n\s*\n')).where((x) => x.trim().isNotEmpty).length;
      final lines = text.isEmpty ? 0 : text.split('\n').length;
      return ('ok',
          '字数（不含空白）：$chars；字符数：${text.length}；词语数：$words；段落数：$paras；行数：$lines');
    }
    // prompt 型：无执行逻辑，返回技能说明
    return ('ok', '技能「${skill.name}」已触发：${skill.desc.isEmpty ? '请根据上下文继续' : skill.desc}');
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

  // ---- 插件 recv 钩子：AI 回复落地前的宿主级处理（内置策略可扩展）----

  String _pluginRecvHook(String reply, String userText) {
    // 宿主扩展点：AI 回复落地前，启用的 recv 钩子插件可对回复做处理。
    // 内置策略：回复为空/纯空白时给出可读提示（避免「AI 没说话」的空白气泡）。
    final recvPlugins = SkillCatalog.enabledPacks()
        .where((p) => p.category == 'plugin' && p.hook == 'recv')
        .toList();
    if (recvPlugins.isEmpty) return reply;
    if (reply.trim().isEmpty) {
      return '（本轮没有生成内容）';
    }
    return reply;
  }
