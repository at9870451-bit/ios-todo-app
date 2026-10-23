/// 全局状态：好友/群组列表、当前会话、配置。
/// 数据全部来自 Rust Core（AmoreStore），这里只是 UI 状态镜像。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';

class ActiveFriendNotifier extends ValueNotifier<ChatFriend?> {
  ActiveFriendNotifier([ChatFriend? v]) : super(v);
}

class AppState extends ChangeNotifier {
  /// Rust Core 自检信息
  String coreInfo = '';

  List<ChatFriend> friends = [];
  List<ChatGroup> groups = [];
  List<AgentTemplate> agents = [];
  List<AIProvider> providers = [];
  Map<String, String> config = {};

  // Appearance live values (derived from config, bubble-only)
  double bubbleRadius = 16;
  double chatFontScale = 14.5;
  String chatBgKey = 'default';
  String themeColor = 'blue';

  final ActiveFriendNotifier activeFriend = ActiveFriendNotifier();
  ChatGroup? activeGroup;

  String toast = '';
  Timer? _toastTimer;

  void showToast(String msg) {
    toast = msg;
    notifyListeners();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      toast = '';
      notifyListeners();
    });
  }

  /// 启动：刷新全部列表
  void bootstrap() {
    try {
      coreInfo = AmoreBridge.coreVersion().toString();
      refreshAll();
    } catch (e) {
      coreInfo = 'bridge error: $e';
    }
  }

  /// 最近一次 Core 错误的文字（UI 可展示；单次失败不再拖垮整个 App）
  String lastCoreError = '';

  T _safeLoad<T>(T Function() load, T fallback) {
    try {
      return load();
    } catch (e) {
      lastCoreError = e.toString().replaceFirst('AmoreCoreError(', 'Core(');
      return fallback;
    }
  }

  void refreshAll() {
    lastCoreError = '';
    friends = _safeLoad(
        () => AmoreStore.listFriends()
          ..sort((a, b) => a.sort.compareTo(b.sort)),
        <ChatFriend>[]);
    groups = _safeLoad(
        () => AmoreStore.listGroups()..sort((a, b) => a.sort.compareTo(b.sort)),
        <ChatGroup>[]);
    agents = _safeLoad(
        () => AmoreStore.listAgents()..sort((a, b) => a.sort.compareTo(b.sort)),
        <AgentTemplate>[]);
    providers = _safeLoad(() => AmoreStore.listProviders(), <AIProvider>[]);
    config = _safeLoad(() => AmoreStore.allConfig(), <String, String>{});
    bubbleRadius = double.tryParse(config['bubble_radius'] ?? '') ?? 16;
    chatFontScale = double.tryParse(config['font_scale'] ?? '') ?? 14.5;
    chatBgKey = config['chat_bg'] ?? 'default';
    themeColor = config['theme_color'] ?? 'blue';
    notifyListeners();
  }

  void refreshSocial() {
    friends = _safeLoad(
        () => AmoreStore.listFriends()
          ..sort((a, b) => a.sort.compareTo(b.sort)),
        <ChatFriend>[]);
    groups = _safeLoad(
        () => AmoreStore.listGroups()..sort((a, b) => a.sort.compareTo(b.sort)),
        <ChatGroup>[]);
    notifyListeners();
  }

  void refreshProviders() {
    providers = _safeLoad(() => AmoreStore.listProviders(), <AIProvider>[]);
    config = _safeLoad(() => AmoreStore.allConfig(), <String, String>{});
    notifyListeners();
  }

  void refreshAgents() {
    agents = _safeLoad(
        () => AmoreStore.listAgents()..sort((a, b) => a.sort.compareTo(b.sort)),
        <AgentTemplate>[]);
    notifyListeners();
  }

  void setActiveFriend(ChatFriend? f) {
    activeFriend.value = f;
    notifyListeners();
  }

  void setActiveGroup(ChatGroup? g) {
    activeGroup = g;
    notifyListeners();
  }

  // ---- 常用配置便捷读写 ----

  /// 夜间免打扰（23:00-08:00，build 83 打扰分寸）
  bool dndEnabled() => config['dnd_enabled'] == '1';

  void setDnd(bool v) {
    AmoreStore.setConfig('dnd_enabled', v ? '1' : '0');
    config['dnd_enabled'] = v ? '1' : '0';
    notifyListeners();
  }

  /// 每日主动消息预算：0=不限 / 10 / 20 / 50
  int dailyBudget() => int.tryParse(config['daily_budget'] ?? '10') ?? 10;

  void setDailyBudget(int v) {
    AmoreStore.setConfig('daily_budget', '$v');
    config['daily_budget'] = '$v';
    notifyListeners();
  }

  /// 全局语音引擎
  String globalVoiceEngine() => config['voice_engine'] ?? 'server';

  void setGlobalVoiceEngine(String v) {
    AmoreStore.setConfig('voice_engine', v);
    config['voice_engine'] = v;
    notifyListeners();
  }

  /// 深色模式（CM8 后本地持久化；themeMode 由 main 响应）
  bool get darkMode => AmoreStore.getConfig('ui.dark') == '1';

  void setDarkMode(bool v) {
    AmoreStore.setConfig('ui.dark', v ? '1' : '0');
    config['ui.dark'] = v ? '1' : '0';
    notifyListeners();
  }

  /// 只刷新外观派生值（气泡圆角/字号/背景），不影响全局布局
  void refreshAppearance() {
    config = AmoreStore.allConfig();
    bubbleRadius = double.tryParse(config['bubble_radius'] ?? '') ?? 16;
    chatFontScale = double.tryParse(config['font_scale'] ?? '') ?? 14.5;
    chatBgKey = config['chat_bg'] ?? 'default';
    themeColor = config['theme_color'] ?? 'blue';
    notifyListeners();
  }

  /// 页面请求切换底部 Tab（-1 = 无请求；MainShell 消费后重置）
  int pendingTab = -1;

  void requestTab(int i) {
    pendingTab = i;
    notifyListeners();
  }
}
