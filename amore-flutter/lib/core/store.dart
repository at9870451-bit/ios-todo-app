/// Rust Core 存储层便捷封装（所有数据经 FFI JSON 总线落在 App 沙盒）
library;

import 'bridge.dart';
import 'models.dart';

class AmoreStore {
  AmoreStore._();

  /// 沙盒数据目录（启动时由 main 传入，头像等本机文件放这里）
  static String dataDir = '';

  // ---- 初始化 ----

  /// 初始化 Core（传入沙盒数据目录），App 启动时调用一次
  static void init(String dir) {
    dataDir = dir;
    AmoreBridge.dataDir = dir;
    AmoreBridge.call('core.init', {'data_dir': dir});
  }

  /// 沙盒内相对路径 → 绝对路径（头像等）
  static String filePath(String relative) =>
      relative.isEmpty ? '' : '$dataDir/$relative';

  // ---- 好友 ----

  static List<ChatFriend> listFriends() => asList(
        AmoreBridge.call('store.list_friends')['friends'],
      ).map(ChatFriend.fromJson).toList();

  static void saveFriend(ChatFriend f) =>
      AmoreBridge.call('store.save_friend', {'friend': f.toJson()});

  static void deleteFriend(String id) =>
      AmoreBridge.call('store.delete_friend', {'id': id});

  // ---- 群组 ----

  static List<ChatGroup> listGroups() => asList(
        AmoreBridge.call('store.list_groups')['groups'],
      ).map(ChatGroup.fromJson).toList();

  static void saveGroup(ChatGroup g) =>
      AmoreBridge.call('store.save_group', {'group': g.toJson()});

  static void deleteGroup(String id) =>
      AmoreBridge.call('store.delete_group', {'id': id});

  // ---- 智能体模板 ----

  static List<AgentTemplate> listAgents() => asList(
        AmoreBridge.call('store.list_agents')['agents'],
      ).map(AgentTemplate.fromJson).toList();

  static void saveAgent(AgentTemplate a) =>
      AmoreBridge.call('store.save_agent', {'agent': a.toJson()});

  static void deleteAgent(String id) =>
      AmoreBridge.call('store.delete_agent', {'id': id});

  // ---- AI 供应商 ----

  static List<AIProvider> listProviders() => asList(
        AmoreBridge.call('store.list_providers')['providers'],
      ).map(AIProvider.fromJson).toList();

  static void saveProvider(AIProvider p) =>
      AmoreBridge.call('store.save_provider', {'provider': p.toJson()});

  static void deleteProvider(String id) =>
      AmoreBridge.call('store.delete_provider', {'id': id});

  static String activeProviderId() =>
      (AmoreBridge.call('store.get_active_provider')['id'] ?? '').toString();

  static void setActiveProvider(String id) =>
      AmoreBridge.call('store.set_active_provider', {'id': id});

  // ---- 全局配置（KV）----

  static Map<String, String> allConfig() {
    final raw = asMap(AmoreBridge.call('store.get_all_config')['values']);
    return raw.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  static void setConfig(String key, String value) =>
      AmoreBridge.call('store.set_config', {'key': key, 'value': value});

  static String? getConfig(String key) => allConfig()[key];

  // ---- 厂商/模型目录 ----

  static List<AIVendor> vendors() => asList(
        AmoreBridge.call('catalog.vendors')['vendors'],
      ).map(AIVendor.fromJson).toList();

  static List<String> modelsOf(String vendorKey) {
    final r = AmoreBridge.call('catalog.models', {'vendor': vendorKey});
    return (r['models'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  static List<String> searchModels(String q) {
    final r = AmoreBridge.call('catalog.search', {'q': q});
    return (r['models'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  // ---- 历史 ----

  static List<ChatMessage> loadHistory(String key) => asList(
        AmoreBridge.call('history.load', {'key': key})['messages'],
      ).map(ChatMessage.fromJson).toList();

  static int appendHistory(String key, String role, String content) =>
      (AmoreBridge.call('history.append',
              {'key': key, 'role': role, 'content': content})['count'] as num?)
              ?.toInt() ??
          0;

  /// 删除单条历史（按消息 id）；id 空时删最后一条
  static int removeHistoryItem(String key, int id) =>
      (AmoreBridge.call('history.remove', {'key': key, 'id': id})['count']
                  as num?)
              ?.toInt() ??
          0;

  /// 覆盖整个历史列表（用于修正 read 标记等字段）
  static int replaceHistory(String key, List<ChatMessage> msgs) {
    final r = AmoreBridge.call('history.replace', {
      'key': key,
      'messages': msgs.map((m) => m.toJson()).toList(),
    });
    return (r['count'] as num?)?.toInt() ?? 0;
  }

  static int clearHistory(String key) =>
      (AmoreBridge.call('history.clear', {'key': key})['count'] as num?)
              ?.toInt() ??
          0;

  static int countHistory(String key) =>
      (AmoreBridge.call('history.count', {'key': key})['count'] as num?)
              ?.toInt() ??
          0;

  // ---- 工具调用 ----

  static String toolsGuide() =>
      (AmoreBridge.call('chat.tools_guide')['guide'] ?? '').toString();

  static ChatAssistantReply parseAssistant(String text) {
    final r = AmoreBridge.call('chat.parse_assistant', {'text': text});
    return ChatAssistantReply(
      clean: (r['clean'] ?? '').toString(),
      feedback: r['feedback']?.toString(),
      called: asList(r['called'])
          .map((e) => ToolCallInfo.fromJson(e))
          .toList(),
    );
  }

  static ToolResult execTool(String name, Map<String, String> params) {
    final r = AmoreBridge.call('chat.exec_tool',
        {'name': name, 'params': params.cast<String, dynamic>()});
    return ToolResult(
      status: (r['status'] ?? 'error').toString(),
      content: (r['content'] ?? '').toString(),
    );
  }

  /// 组装系统提示词（人设 + 记忆 + 说话分寸 + 工具指南）
  static String buildSystemPrompt(ChatFriend f) =>
      (AmoreBridge.call('chat.build_system_prompt', {'friend': f.toJson()})['prompt'] ?? '')
          .toString();

  /// 从回复里抽取 [记忆:xxx] 标记
  static List<String> extractMemory(String text) => asList(
        AmoreBridge.call('chat.extract_memory', {'text': text})['memories'],
      ).map((e) => e.toString()).toList();

  /// 剥离记忆标记后的展示文本
  static String stripMemory(String text) =>
      (AmoreBridge.call('chat.strip_memory', {'text': text})['text'] ?? '').toString();

  // ---- 语音（TTS 请求组装）----

  static Map<String, dynamic> ttsRequest({
    required String engine,
    required String voiceId,
    required String apiKey,
    required String text,
  }) =>
      asMap(AmoreBridge.call('tts.request',
          {'engine': engine, 'voice_id': voiceId, 'api_key': apiKey, 'text': text}));
}

/// chat.parse_assistant 的结果
class ChatAssistantReply {
  final String clean; // 剥离工具标记后的展示文本
  final String? feedback; // 工具结果回注（下一轮请求带上）
  final List<ToolCallInfo> called; // 本轮调用了哪些工具

  ChatAssistantReply({required this.clean, this.feedback, required this.called});
}

class ToolCallInfo {
  final String name;
  final Map<String, String> params;

  ToolCallInfo({required this.name, required this.params});

  factory ToolCallInfo.fromJson(Map<String, dynamic> j) => ToolCallInfo(
        name: (j['name'] ?? '').toString(),
        params: asMap(j['params']).map((k, v) => MapEntry(k, v?.toString() ?? '')),
      );
}

class ToolResult {
  final String status; // ok / error
  final String content;

  ToolResult({required this.status, required this.content});
}
