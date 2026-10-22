import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import 'core/bridge.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'state/app_state.dart';
import 'pages/chat_list_page.dart';
import 'pages/chat_screen_page.dart';
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
        // Apple 白为主视觉（浅色先行）；darkTheme 已就绪，全页面 palette 化后开启 system
        theme: AmoreTheme.light(),
        darkTheme: AmoreTheme.dark(),
        themeMode: ThemeMode.light,
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
            Container(
              width: 64,
              height: 64,
              decoration: AmoreTheme.brandBox(radius: 18),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: AmoreBrand.orange),
            const SizedBox(height: 18),
            Text(
              _error ?? '正在启动 Rust Core…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF86868B), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主框架：3 Tab —— 聊天 / 对话 / 我的
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
    ProfilePage(),
  ];

  static const _items = [
    (Icons.forum_outlined, Icons.forum_rounded, '聊天'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, '对话'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
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
      bottomNavigationBar: GlassContainer(
        radius: 24,
        blur: 22,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: AmoreBrand.orange.withOpacity(0.14),
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
                  color: s.contains(WidgetState.selected)
                      ? AmoreBrand.orange
                      : const Color(0xFF86868B),
                )),
            height: 60,
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              final st = context.read<AppState>();
              if (i == 1 &&
                  st.activeFriend.value == null &&
                  st.friends.isNotEmpty) {
                st.setActiveFriend(st.friends.first);
              }
              st.pendingTab = -1;
              setState(() => _tab = i);
            },
            destinations: _items
                .map((e) => NavigationDestination(
                      icon: Icon(e.$1,
                          color: const Color(0xFF86868B), size: 24),
                      selectedIcon: Icon(e.$2, color: AmoreBrand.orange, size: 24),
                      label: e.$3,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
