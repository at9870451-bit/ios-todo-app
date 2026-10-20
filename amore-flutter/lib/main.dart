import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import 'core/bridge.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'state/app_state.dart';
import 'pages/chat_list_page.dart';
import 'pages/chat_screen_page.dart';
import 'pages/doll_studio_page.dart';
import 'pages/profile_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AmoreApp());
}

class AmoreApp extends StatelessWidget {
  const AmoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..bootstrap(),
      child: MaterialApp(
        title: 'Amore',
        debugShowCheckedModeBanner: false,
        theme: AmoreTheme.dark(),
        home: const RootGate(),
      ),
    );
  }
}

/// 启动门：先完成 Rust Core 初始化，再进主框架
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  String? _error;
  String? _coreVersion;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final dir = await getApplicationSupportDirectory();
      AmoreStore.init(dir.path);
      final v = AmoreBridge.coreVersion();
      if (!mounted) return;
      setState(() {
        _coreVersion = 'Rust Core v${v['version']}';
        _ready = true;
      });
      // Core 就绪后刷新全局列表（此前 store 调用都是空数据兜底）
      Future.microtask(() {
        if (mounted) context.read<AppState>().refreshAll();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _ready = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const MainShell();
    }
    return Scaffold(
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AmoreTheme.accent),
            const SizedBox(height: 18),
            Text(
              _error ?? '正在启动 Rust Core…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AmoreTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主框架：4 Tab —— 聊天 / 对话 / 玩偶 / 我的
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _pages = [
    ChatListPage(),
    ChatScreenPage(),
    DollStudioPage(),
    ProfilePage(),
  ];

  static const _items = [
    BottomNavigationBarItem(
        icon: Icon(Icons.forum_outlined),
        activeIcon: Icon(Icons.forum_rounded),
        label: '聊天'),
    BottomNavigationBarItem(
        icon: Icon(Icons.chat_bubble_outline_rounded),
        activeIcon: Icon(Icons.chat_bubble_rounded),
        label: '对话'),
    BottomNavigationBarItem(
        icon: Icon(Icons.pets_outlined),
        activeIcon: Icon(Icons.pets_rounded),
        label: '玩偶'),
    BottomNavigationBarItem(
        icon: Icon(Icons.person_outline_rounded),
        activeIcon: Icon(Icons.person_rounded),
        label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    // 响应页面级 tab 切换请求（如会话列表点击 → 对话页）
    final state = context.watch<AppState>();
    if (state.pendingTab >= 0 && state.pendingTab != _tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _tab = state.pendingTab);
          state.pendingTab = -1;
        }
      });
    }
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AmoreTheme.tabBg,
          indicatorColor: AmoreTheme.accent.withOpacity(0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 11.5,
                color: s.contains(WidgetState.selected)
                    ? AmoreTheme.accent
                    : AmoreTheme.textFaint,
              )),
          height: 62,
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            final state = context.read<AppState>();
            if (i == 1 &&
                state.activeFriend.value == null &&
                state.friends.isNotEmpty) {
              state.setActiveFriend(state.friends.first);
            }
            state.pendingTab = -1;
            setState(() => _tab = i);
          },
          destinations: _items
              .map((e) => NavigationDestination(
                    icon: e.icon!,
                    selectedIcon: e.activeIcon,
                    label: e.label!,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
