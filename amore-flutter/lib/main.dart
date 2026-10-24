import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import 'core/bridge.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'core/theme_prefs.dart';
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
      // 只订阅外观字段：toast / 列表刷新等其它通知不再重建整棵 MaterialApp
      child: const _AppMaterial(),
    );
  }
}

/// 外观选择器：themeColor / darkMode 变化才重建 MaterialApp
class _AppMaterial extends StatelessWidget {
  const _AppMaterial({super.key});

  /// 外观指纹：任何外观配置变化 → 重建 MaterialApp
  String _fingerprint() {
    return [
      '${AmoreStore.getConfig('theme_color')}',
      '${AmoreStore.getConfig('ui.dark')}',
      '${AmoreStore.getConfig('operit.theme_mode')}',
      '${AmoreStore.getConfig('operit.custom_colors')}',
      '${AmoreStore.getConfig('operit.custom_primary')}',
      '${AmoreStore.getConfig('operit.font_family')}',
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, s) => _fingerprint(),
      builder: (context, key, _) {
        // Appearance theme color（Operit2 前置：自定义主色 > 预设）
        const themeColors = {
          'purple': Color(0xFFAF52DE),
          'pink': Color(0xFFF472B6),
          'green': Color(0xFF34C759),
          'orange': Color(0xFFFB923C),
          'mono': Color(0xFF86868B),
        };
        final acc = ThemePrefs.useCustomColors
            ? ThemePrefs.customPrimary
            : (themeColors[ThemePrefs.themeColor] ?? AmoreBrand.accent);
        // Operit2 字体族（system / serif / sans-serif / monospace / cursive）
        final family = switch (ThemePrefs.fontFamily) {
          'serif' => 'serif',
          'sans-serif' => 'sans-serif',
          'monospace' => 'monospace',
          'cursive' => 'cursive',
          _ => null,
        };
        final light = AmoreTheme.lightWith(acc);
        final dark = AmoreTheme.darkWith(acc);
        return MaterialApp(
          title: 'Amore',
          debugShowCheckedModeBanner: false,
          theme: family == null
              ? light
              : light.copyWith(
                  textTheme: light.textTheme.apply(fontFamily: family)),
          darkTheme: family == null
              ? dark
              : dark.copyWith(
                  textTheme: dark.textTheme.apply(fontFamily: family)),
          themeMode: ThemePrefs.effectiveThemeMode,
          // 点击屏幕空白处自动收起键盘
          builder: (context, child) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: child,
          ),
          home: const RootGate(),
        );
      },
    );
  }
}

/// 底部导航栏：贴底全宽 Liquid Glass（无悬浮留白）
class _SlideTabBar extends StatelessWidget {
  final List<(IconData, IconData, String)> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _SlideTabBar(
      {required this.items, required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AmoreTheme.pal(context);
    final light = p.brightness == Brightness.light;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withOpacity(0.80)
                : const Color(0xFF101725).withOpacity(0.86),
            border: Border(
                top: BorderSide(
                    color: light
                        ? Colors.white.withOpacity(0.75)
                        : Colors.white.withOpacity(0.08),
                    width: 0.6)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(light ? 0.05 : 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, -3)),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTap(i);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 3),
                              decoration: BoxDecoration(
                                color: i == selectedIndex
                                    ? AmoreBrand.accent.withOpacity(0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                i == selectedIndex ? items[i].$2 : items[i].$1,
                                size: 22,
                                color: i == selectedIndex
                                    ? AmoreBrand.accent
                                    : p.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              items[i].$3,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: i == selectedIndex
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: i == selectedIndex
                                    ? AmoreBrand.accent
                                    : p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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

/// 懒加载 Tab 栈：只有访问过的 tab 才构建；一旦构建则保留状态。
/// 相比 IndexedStack 全量常驻，动画组件（TiltReflectCard/StaggerItem 等）
/// 不会在未访问的 tab 上持续运行 —— 流畅性与启动速度都有提升。
class _LazyTabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _LazyTabStack({required this.index, required this.children});

  @override
  State<_LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<_LazyTabStack> {
  final Set<int> _built = {0};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _built.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
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
      body: _LazyTabStack(index: _tab, children: _pages),
      bottomNavigationBar: _SlideTabBar(
        items: _items,
        selectedIndex: _tab,
        onTap: (i) {
          final st = context.read<AppState>();
          if (i == 1 &&
              st.activeFriend.value == null &&
              st.friends.isNotEmpty) {
            st.setActiveFriend(st.friends.first);
          }
          st.pendingTab = -1;
          setState(() => _tab = i);
        },
      ),
    );
  }
}

/// 底部导航栏：选中项展开显示文字标签，背景块滑到选中位置，其余项只保留图标
