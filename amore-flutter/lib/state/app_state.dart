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

  void refreshAll() {
    friends = AmoreStore.listFriends()..sort((a, b) => a.sort.compareTo(b.sort));
    groups = AmoreStore.listGroups()..sort((a, b) => a.sort.compareTo(b.sort));
    agents = AmoreStore.listAgents()..sort((a, b) => a.sort.compareTo(b.sort));
    providers = AmoreStore.listProviders();
    config = AmoreStore.allConfig();
    notifyListeners();
  }

  void refreshSocial() {
    friends = AmoreStore.listFriends()..sort((a, b) => a.sort.compareTo(b.sort));
    groups = AmoreStore.listGroups()..sort((a, b) => a.sort.compareTo(b.sort));
    notifyListeners();
  }

  void refreshProviders() {
    providers = AmoreStore.listProviders();
    config = AmoreStore.allConfig();
    notifyListeners();
  }

  void refreshAgents() {
    agents = AmoreStore.listAgents()..sort((a, b) => a.sort.compareTo(b.sort));
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

  String serverUrl() => config['server_url'] ?? 'http://154.12.16.204:8080';

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

  /// 页面请求切换底部 Tab（-1 = 无请求；MainShell 消费后重置）
  int pendingTab = -1;

  void requestTab(int i) {
    pendingTab = i;
    notifyListeners();
  }
}
