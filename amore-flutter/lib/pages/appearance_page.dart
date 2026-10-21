// 对应 Swift：AppearanceView.swift —— 外观设置（配置落 Rust config，渲染接入下一版）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  String _themeColor = 'blue';
  String _chatBg = 'gradient';
  double _bubbleRadius = 16;
  double _fontScale = 14.5;

  @override
  void initState() {
    super.initState();
    _themeColor = AmoreStore.getConfig('theme_color') ?? 'blue';
    _chatBg = AmoreStore.getConfig('chat_bg') ?? 'gradient';
    _bubbleRadius = double.tryParse(AmoreStore.getConfig('bubble_radius') ?? '') ?? 16;
    _fontScale = double.tryParse(AmoreStore.getConfig('font_scale') ?? '') ?? 14.5;
  }

  void _save(String key, String value) {
    AmoreStore.setConfig(key, value);
    context.read<AppState>().refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final colors = {
      'blue': ('星海蓝', AmoreTheme.accent),
      'purple': ('霞光紫', AmoreTheme.accent2),
      'pink': ('樱花粉', const Color(0xFFF472B6)),
      'green': ('薄荷绿', AmoreTheme.success),
      'orange': ('暖阳橙', const Color(0xFFFB923C)),
      'mono': ('极简灰白', const Color(0xFF86868B)),
    };
    final bgs = {
      'gradient': ('深空渐变', const [Color(0xFF1A2238), Color(0xFFF5F5F7)]),
      'graphite': ('石墨黑', const [Color(0xFF17191F), Color(0xFF0C0D11)]),
      'indigo': ('靛蓝夜', const [Color(0xFF1E1B4B), Color(0xFFF5F5F7)]),
      'teal': ('深海青', const [Color(0xFF134E4A), Color(0xFFF5F5F7)]),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('外观', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              section('主题色'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: colors.entries.map((e) {
                    final selected = _themeColor == e.key;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _themeColor = e.key;
                        _save('theme_color', e.key);
                      }),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: e.value.$2,
                                  border: Border.all(
                                      color: selected ? Colors.white : Colors.transparent,
                                      width: 2.5),
                                ),
                              ),
                              if (selected)
                                const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 24),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(e.value.$1,
                              style: const TextStyle(fontSize: 11, color: AmoreTheme.textSecondary)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),
              section('聊天背景'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Row(
                  children: bgs.entries.map((e) {
                    final selected = _chatBg == e.key;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _chatBg = e.key;
                          _save('chat_bg', e.key);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              Container(
                                height: 62,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: e.value.$2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: selected ? AmoreTheme.accent : Colors.transparent,
                                      width: 2),
                                ),
                                alignment: Alignment.center,
                                child: selected
                                    ? const Icon(Icons.check_rounded, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(e.value.$1,
                                  style: const TextStyle(
                                      fontSize: 10.5, color: AmoreTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),
              section('气泡圆角'),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  children: [
                    Slider(
                      value: _bubbleRadius,
                      min: 4,
                      max: 24,
                      divisions: 10,
                      label: '${_bubbleRadius.round()}',
                      onChanged: (v) => setState(() => _bubbleRadius = v),
                      onChangeEnd: (v) => _save('bubble_radius', v.round().toString()),
                    ),
                    // 预览
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AmoreTheme.accentGradient(),
                            borderRadius: BorderRadius.circular(_bubbleRadius),
                          ),
                          child: const Text('这是我的气泡',
                              style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              section('字体大小'),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  children: [
                    Slider(
                      value: _fontScale,
                      min: 13,
                      max: 20,
                      divisions: 7,
                      label: '${_fontScale.toStringAsFixed(1)}pt',
                      onChanged: (v) => setState(() => _fontScale = v),
                      onChangeEnd: (v) => _save('font_scale', v.toString()),
                    ),
                    Text('示例：你好，今天过得怎么样？',
                        style: TextStyle(fontSize: _fontScale, color: AmoreTheme.textPrimary)),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Center(
                child: Text('外观配置已保存，全局渲染接入将在下一版生效',
                    style: TextStyle(fontSize: 11, color: AmoreTheme.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget section(String t) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(t, style: AmoreTheme.sectionLabel()));
}
