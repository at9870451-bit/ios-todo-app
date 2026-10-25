/// Amore 数据模型（与 SwiftUI 版 ChatFriends.swift / ProviderStore.swift / AgentTemplates.swift 对齐）
/// 所有模型与 Rust Core 之间以 JSON 交换，字段名保持 snake_case。
library;

import 'attachments.dart';
import 'dart:convert';

/// 从 Rust 信封 data 里安全取 Map
Map<String, dynamic> asMap(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<Map<String, dynamic>> asList(Object? v) => v is List
    ? v.map<Map<String, dynamic>>((e) => asMap(e)).toList()
    : <Map<String, dynamic>>[];

class ChatFriend {
  String id;
  String name;
  String avatarFile; // Documents 内文件名（本期占位，不加载图片）
  String persona; // 人设提示词
  String desc; // 一句话简介（与智能体共用同一套表单字段）
  String gender; // male / female / ""
  String age;
  String sessionId; // 服务端会话 id
  int sort;
  String lastMessage;
  double lastAt;
  String voiceEngine; // local / server / cloud_sf / cloud_doubao / model / ""
  String voiceId;
  String ttsKey; // 专属 API Key（硅基流动 / 豆包）
  String aiProviderId; // 该好友使用的 AI 模型（ProviderStore id，空=跟随全局）
  List<String> memory; // 长期记忆：AI 记住的关于用户的事实

  ChatFriend({
    this.id = '',
    this.name = 'Amore',
    this.avatarFile = '',
    this.persona = '',
    this.desc = '',
    this.gender = '',
    this.age = '',
    this.sessionId = '',
    this.sort = 0,
    this.lastMessage = '',
    this.lastAt = 0,
    this.voiceEngine = '',
    this.voiceId = '',
    this.ttsKey = '',
    this.aiProviderId = '',
    List<String>? memory,
  }) : memory = memory ?? [];

  factory ChatFriend.fromJson(Map<String, dynamic> j) => ChatFriend(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Amore',
        avatarFile: j['avatar_file']?.toString() ?? '',
        persona: j['persona']?.toString() ?? '',
        desc: j['desc']?.toString() ?? '',
        gender: j['gender']?.toString() ?? '',
        age: j['age']?.toString() ?? '',
        sessionId: j['session_id']?.toString() ?? '',
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        lastMessage: j['last_message']?.toString() ?? '',
        lastAt: (j['last_at'] as num?)?.toDouble() ?? 0,
        voiceEngine: j['voice_engine']?.toString() ?? '',
        voiceId: j['voice_id']?.toString() ?? '',
        ttsKey: j['tts_key']?.toString() ?? '',
        aiProviderId: j['ai_provider_id']?.toString() ?? '',
        memory: (j['memory'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? _newId() : id,
        'name': name,
        'avatar_file': avatarFile,
        'persona': persona,
        'desc': desc,
        'gender': gender,
        'age': age,
        'session_id': sessionId,
        'sort': sort,
        'last_message': lastMessage,
        'last_at': lastAt,
        'voice_engine': voiceEngine,
        'voice_id': voiceId,
        'tts_key': ttsKey,
        'ai_provider_id': aiProviderId,
        'memory': memory,
      };

  String get genderText => gender == 'male'
      ? '男'
      : gender == 'female'
          ? '女'
          : '保密';
}

class ChatGroup {
  String id;
  String name;
  List<String> memberIds;
  String sessionId;
  String lastMessage;
  double lastAt;
  int sort;

  ChatGroup({
    this.id = '',
    this.name = '新群聊',
    List<String>? memberIds,
    this.sessionId = '',
    this.lastMessage = '',
    this.lastAt = 0,
    this.sort = 0,
  }) : memberIds = memberIds ?? [];

  factory ChatGroup.fromJson(Map<String, dynamic> j) => ChatGroup(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '新群聊',
        memberIds:
            (j['member_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
        sessionId: j['session_id']?.toString() ?? '',
        lastMessage: j['last_message']?.toString() ?? '',
        lastAt: (j['last_at'] as num?)?.toDouble() ?? 0,
        sort: (j['sort'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? _newId() : id,
        'name': name,
        'member_ids': memberIds,
        'session_id': sessionId,
        'last_message': lastMessage,
        'last_at': lastAt,
        'sort': sort,
      };
}

class ChatMessage {
  /// 附件列表（解析 content 中的 [atts] 块；空 = 无附件）
  List<Map<String, String>> get attachments => Attachments.parse(content);

  /// 剥离附件块后的纯文本
  String get textContent => Attachments.text(content);

  int id;
  String role; // user / assistant / system / tool
  String content;
  double ts;
  bool read; // iMessage 已读状态（自己发送的消息：true=对方已读）

  ChatMessage(
      {int? id,
      this.role = 'user',
      this.content = '',
      double? ts,
      this.read = false})
      : id = id ?? DateTime.now().microsecondsSinceEpoch,
        ts = ts ?? DateTime.now().millisecondsSinceEpoch / 1000;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] as num?)?.toInt(),
        role: j['role']?.toString() ?? 'user',
        content: j['content']?.toString() ?? '',
        ts: (j['ts'] as num?)?.toDouble(),
        read: j['read'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'role': role, 'content': content, 'ts': ts, 'read': read};
}

class AIProvider {
  String id;
  String label;
  String vendor; // AIVendorCatalog key 或 custom
  String kind; // main / secondary / tts / image
  String apiFormat; // chat / responses
  String apiKey;
  String baseURL; // 空 = 官方默认
  bool autoV1;
  String model;
  String ttsVoice;
  String ttsModel; // 语音模型名（与聊天 model 分开；兼容旧 tts 配置存 model）
  String imageModel;

  AIProvider({
    this.id = '',
    this.label = '新配置',
    this.vendor = 'openai_generic',
    this.kind = 'main',
    this.apiFormat = 'chat',
    this.apiKey = '',
    this.baseURL = '',
    this.autoV1 = true,
    this.model = '',
    this.ttsVoice = 'alloy',
    this.ttsModel = '',
    this.imageModel = '',
  });

  factory AIProvider.fromJson(Map<String, dynamic> j) => AIProvider(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? '新配置',
        vendor: j['vendor']?.toString() ?? 'openai_generic',
        kind: j['kind']?.toString() ?? 'main',
        apiFormat: j['api_format']?.toString() ?? 'chat',
        apiKey: j['api_key']?.toString() ?? '',
        baseURL: j['base_url']?.toString() ?? '',
        autoV1: j['auto_v1'] as bool? ?? true,
        model: j['model']?.toString() ?? '',
        ttsVoice: j['tts_voice']?.toString() ?? 'alloy',
        ttsModel: j['tts_model']?.toString() ?? '',
        imageModel: j['image_model']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? _newId() : id,
        'label': label,
        'vendor': vendor,
        'kind': kind,
        'api_format': apiFormat,
        'api_key': apiKey,
        'base_url': baseURL,
        'auto_v1': autoV1,
        'model': model,
        'tts_voice': ttsVoice,
        'tts_model': ttsModel,
        'image_model': imageModel,
      };

  String maskedKey() {
    final k = apiKey.trim();
    if (k.isEmpty) return '未填 Key';
    if (k.length <= 12) return k;
    return '${k.substring(0, 6)}...${k.substring(k.length - 4)}';
  }
}

class AgentTemplate {
  String id;
  String name;
  String desc;
  String persona;
  String gender;
  String age;
  String voiceEngine;
  String voiceId;
  String modelId;
  String avatarFile;
  List<String> memory;
  int sort;
  bool enabled;

  AgentTemplate({
    this.id = '',
    this.name = '',
    this.desc = '',
    this.persona = '',
    this.gender = '',
    this.age = '',
    this.voiceEngine = '',
    this.voiceId = '',
    this.modelId = '',
    this.avatarFile = '',
    List<String>? memory,
    this.sort = 0,
    this.enabled = true,
  }) : memory = memory ?? [];

  factory AgentTemplate.fromJson(Map<String, dynamic> j) => AgentTemplate(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        desc: j['desc']?.toString() ?? '',
        persona: j['persona']?.toString() ?? '',
        gender: j['gender']?.toString() ?? '',
        age: j['age']?.toString() ?? '',
        voiceEngine: j['voice_engine']?.toString() ?? '',
        voiceId: j['voice_id']?.toString() ?? '',
        modelId: j['model_id']?.toString() ?? '',
        avatarFile: j['avatar_file']?.toString() ?? '',
        memory: (j['memory'] as List?)?.map((e) => e.toString()).toList() ?? [],
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? _newId() : id,
        'name': name,
        'desc': desc,
        'persona': persona,
        'gender': gender,
        'age': age,
        'voice_engine': voiceEngine,
        'voice_id': voiceId,
        'model_id': modelId,
        'avatar_file': avatarFile,
        'memory': memory,
        'sort': sort,
        'enabled': enabled,
      };
}

class AIVendor {
  final String key;
  final String name;
  final String group;
  final String base;
  final String model;
  final String format; // chat / responses

  const AIVendor({
    required this.key,
    required this.name,
    required this.group,
    required this.base,
    required this.model,
    required this.format,
  });

  factory AIVendor.fromJson(Map<String, dynamic> j) => AIVendor(
        key: j['key']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        group: j['group']?.toString() ?? '',
        base: j['base']?.toString() ?? '',
        model: j['model']?.toString() ?? '',
        format: j['format']?.toString() ?? 'chat',
      );
}

String _newId() {
  final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = (DateTime.now().microsecondsSinceEpoch * 7919) & 0xFFFFFF;
  return '${r}-${rand.toRadixString(36)}';
}

String jsonPretty(Object? v) => const JsonEncoder.withIndent('  ').convert(v);
