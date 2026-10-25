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
      _seedDemoData();
      refreshAll();
    } catch (e) {
      coreInfo = 'bridge error: $e';
    }
  }

  /// 首次启动预置模拟会话（iMessage 风格即时通讯演示数据；seed_done=1 后不再生成）
  void _seedDemoData() {
    if (AmoreStore.getConfig('seed_done') == '1') return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    // 写入会话历史；最后一条自己发出的消息按需标记已读
    void hist(String key, List<(bool, String, int, bool)> msgs) {
      for (final (mine, text, ago, read) in msgs) {
        AmoreStore.appendHistory(key, mine ? 'user' : 'assistant', text);
      }
      final all = AmoreStore.loadHistory(key);
      for (final m in all.reversed) {
        if (m.role == 'user') {
          m.read = msgs.last.$4;
          break;
        }
      }
      AmoreStore.replaceHistory(key, all);
    }

    // 好友：林小满
    AmoreStore.saveFriend(ChatFriend(
      id: 'f_xiaoman', name: '林小满', gender: 'female', age: '26',
      desc: '产品经理 · 喜欢咖啡和猫',
      persona: '你叫林小满，28岁产品经理，说话温柔带点俏皮，喜欢分享生活细节。',
      sort: 0,
    ));
    hist('friend.f_xiaoman', [
      (false, '在忙吗？晚上一起吃饭？', 4200, true),
      (true, '好呀，老地方？', 4100, true),
      (false, '嗯！七点见～今天想喝那家新开的粥铺', 4050, true),
      (true, '没问题，我定位置', 4000, true),
      (false, '对了，明天方案评审你帮我看看吗', 800, true),
      (true, '发我，晚上帮你看', 600, true),
      (false, '谢谢你！😊 那明天见', 300, true),
    ]);

    // 好友：陈一诺
    AmoreStore.saveFriend(ChatFriend(
      id: 'f_yinuo', name: '陈一诺', gender: 'female', age: '24',
      desc: '设计师 · 追星女孩',
      persona: '你叫陈一诺，24岁平面设计师，活泼爱分享，偶尔追剧追星。',
      sort: 1,
    ));
    hist('friend.f_yinuo', [
      (false, '新头像好看！哪拍的呀', 9000, true),
      (true, '上周去海边拍的嘿嘿', 8900, true),
      (false, '好羡慕，我也想去看海了', 8600, true),
      (true, '下次一起！', 8500, true),
      (false, '周末有空吗，陪我看展', 200, false),
    ]);

    // 好友：李哲
    AmoreStore.saveFriend(ChatFriend(
      id: 'f_lizhe', name: '李哲', gender: 'male', age: '29',
      desc: '后端工程师 · 夜猫子',
      persona: '你叫李哲，29岁后端工程师，理性简洁，偶尔吐槽需求。',
      sort: 2,
    ));
    hist('friend.f_lizhe', [
      (false, '接口文档我更新了，记得看', 15000, true),
      (true, '收到，晚点看', 14800, true),
      (false, '今晚发版，有问题随时叫我', 7200, true),
      (true, '辛苦了', 7000, true),
    ]);

    // 群聊：周末爬山小分队
    AmoreStore.saveGroup(ChatGroup(
      id: 'g_hike', name: '周末爬山小分队', sort: 0,
      memberIds: ['f_xiaoman', 'f_yinuo', 'f_lizhe'],
      lastMessage: '周六早上八点北门集合！',
      lastAt: now - 600,
    ));
    hist('group.g_hike', [
      (false, '这周六去爬香山吗', 6000, true),
      (true, '去去去！好久没运动了', 5900, true),
      (false, '我也去，带点水果', 5800, true),
      (true, '好，那周六早上八点北门集合！', 600, true),
    ]);

    // 未读标记：聊天列表红点依据 lastAt + config（简化：无未读实现，仅数据）
    AmoreStore.setConfig('seed_done', '1');
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
    // Operit2 外观体系：字号优先读 operit.font_scale（兼容旧 font_scale）
    chatFontScale = double.tryParse(
            config['operit.font_scale'] ?? config['font_scale'] ?? '') ??
        14.5;
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
