/// 聊天引擎（Dart 编排层）：
/// Rust 负责 存储/提示词组装/工具协议解析/本地工具执行，
/// 这里负责 HTTP 请求（dio）与多轮工具循环控制。
library;

import 'package:dio/dio.dart';

import 'models.dart';
import 'store.dart';

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
    final body = <String, dynamic>{
      'model': p.model.isEmpty ? p.label : p.model,
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
      throw Exception('服务返回 HTTP ${resp.statusCode}');
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
    void Function(String toolName)? onToolCall,
    String? extraSystem,
  }) async {
    final provider = providerFor(friend);
    if (provider == null) {
      return ChatTurnResult.error('尚未配置 AI 模型：请到「我的 → 模型配置」添加并激活一个供应商。');
    }

    final key = 'friend.${friend.id}';
    AmoreStore.appendHistory(key, 'user', userText);
    final history = AmoreStore.loadHistory(key);

    final system = [
      AmoreStore.buildSystemPrompt(friend),
      if (extraSystem != null && extraSystem.isNotEmpty) extraSystem,
    ].join('\n\n');

    // 组装消息（历史最近 24 条）
    final msgs = history.length <= 24
        ? history.map((m) => {'role': m.role, 'content': m.content}).toList()
        : history.sublist(history.length - 24).map((m) => {'role': m.role, 'content': m.content}).toList();

    String feedback; // 工具结果回注（追加为 tool 消息）
    String lastClean = '';
    final allTools = <ToolCallInfo>[];
    int rounds = 0;

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
      msgs.add({'role': 'assistant', 'content': reply});
      msgs.add({'role': 'tool', 'content': parsed.feedback!});
      feedback = parsed.feedback!;
      // 继续下一轮（feedback 已进 msgs）
    }

    AmoreStore.appendHistory(key, 'assistant', lastClean);
    _touchFriend(friend, lastClean);
    return ChatTurnResult(text: lastClean, tools: allTools);
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
