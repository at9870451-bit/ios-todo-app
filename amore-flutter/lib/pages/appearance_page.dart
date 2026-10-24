// 外观设置（Operit2 外观体系移植）：主题模式/自定义色/背景图/气泡样式/输入样式/头像/字体
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../core/theme_prefs.dart';
import '../state/app_state.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  void _save() {
    // 只刷新外观派生值（气泡/字号/背景），不影响其他 tab 布局
    context.read<AppState>().refreshAppearance();
  }

  Future<void> _pickBackgroundImage() async {
    final XFile? img =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img == null) return;
    try {
      final dir = AmoreStore.dataDir;
      final target = '$dir/backgrounds/bg_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(img.path).copy(target);
      ThemePrefs.setBackgroundImagePath(target);
      setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = {
      'blue': ('星海蓝', AmoreTheme.accent),
      'purple': ('霞光紫', const Color(0xFFAF52DE)),
      'pink': ('樱花粉', const Color(0xFFF472B6)),
      'green': ('薄荷绿', AmoreTheme.success),
      'orange': ('暖阳橙', const Color(0xFFFB923C)),
      'mono': ('极简灰白', const Color(0xFF86868B)),
    };
    final bgs = {
      'default': ('经典浅灰', const Color(0xFFF5F5F7)),
      'graphite': ('石墨黑', const Color(0xFF17191F)),
      'indigo': ('靛蓝夜', const Color(0xFF1E1B4B)),
      'teal': ('深海青', const Color(0xFF134E4A)),
    };

    return Scaffold(
      appBar: const AmoreAppBar(title: '外观'),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ---- 主题模式 ----
              section('主题'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('主题模式',
                        style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                        ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                      ],
                      selected: {ThemePrefs.themeMode},
                      onSelectionChanged: (sel) => setState(() {
                        ThemePrefs.setThemeMode(sel.first);
                        _save();
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('自定义主色',
                            style: TextStyle(fontSize: 14.5)),
                        const Spacer(),
                        Switch(
                          value: ThemePrefs.useCustomColors,
                          onChanged: (v) => setState(() {
                            ThemePrefs.setUseCustomColors(v);
                            _save();
                          }),
                        ),
                      ],
                    ),
                    if (ThemePrefs.useCustomColors) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final c in const [
                            Color(0xFF007AFF),
                            Color(0xFFAF52DE),
                            Color(0xFFF472B6),
                            Color(0xFF34C759),
                            Color(0xFFFB923C),
                            Color(0xFFFF3B30),
                            Color(0xFF5E5CE6),
                            Color(0xFF86868B),
                          ])
                            GestureDetector(
                              onTap: () {
                                ThemePrefs.setCustomPrimary(c);
                                ThemePrefs.setUseCustomColors(true);
                                setState(() => _save());
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ThemePrefs.customPrimary == c
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                        color: c.withOpacity(0.4),
                                        blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ---- 聊天背景 ----
              const SizedBox(height: 16),
              section('聊天背景'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('背景图片',
                            style: TextStyle(fontSize: 14.5)),
                        const Spacer(),
                        Switch(
                          value: ThemePrefs.useBackgroundImage,
                          onChanged: (v) => setState(() {
                            ThemePrefs.setUseBackgroundImage(v);
                            _save();
                          }),
                        ),
                      ],
                    ),
                    if (ThemePrefs.useBackgroundImage) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _pickBackgroundImage,
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(ThemePrefs.backgroundImagePath.isEmpty
                            ? '选择背景图片'
                            : '更换背景图片'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('透明度',
                              style: TextStyle(fontSize: 12.5)),
                          Expanded(
                            child: Slider(
                              value: ThemePrefs.backgroundOpacity
                                  .clamp(0.05, 1.0),
                              onChanged: (v) => setState(() {
                                ThemePrefs.setBackgroundOpacity(v);
                                _save();
                              }),
                            ),
                          ),
                          Text('${(ThemePrefs.backgroundOpacity * 100).round()}%',
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('模糊',
                              style: TextStyle(fontSize: 12.5)),
                          const SizedBox(width: 8),
                          Switch(
                            value: ThemePrefs.useBackgroundBlur,
                            onChanged: (v) => setState(() {
                              ThemePrefs.setUseBackgroundBlur(v);
                              _save();
                            }),
                          ),
                          if (ThemePrefs.useBackgroundBlur)
                            Expanded(
                              child: Slider(
                                value: ThemePrefs.backgroundBlurRadius
                                    .clamp(2.0, 30.0),
                                onChanged: (v) => setState(() {
                                  ThemePrefs.setBackgroundBlurRadius(v);
                                  _save();
                                }),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('纯色背景',
                        style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (k, (label, color)) in bgs.entries)
                          ChoiceChip(
                            label: Text(label,
                                style: const TextStyle(fontSize: 12)),
                            selected:
                                (AmoreStore.getConfig('chat_bg') ?? 'default') == k,
                            onSelected: (_) => setState(() {
                              AmoreStore.setConfig('chat_bg', k);
                              _save();
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---- 聊天气泡 ----
              const SizedBox(height: 16),
              section('聊天气泡'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('消息样式',
                        style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'bubble', label: Text('气泡')),
                        ButtonSegment(value: 'cursor', label: Text('光标式')),
                      ],
                      selected: {ThemePrefs.chatStyle},
                      onSelectionChanged: (sel) => setState(() {
                        ThemePrefs.setChatStyle(sel.first);
                        _save();
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('头像形状',
                        style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'circle', label: Text('圆形')),
                        ButtonSegment(value: 'square', label: Text('方形')),
                      ],
                      selected: {ThemePrefs.avatarShape},
                      onSelectionChanged: (sel) => setState(() {
                        ThemePrefs.setAvatarShape(sel.first);
                        _save();
                      }),
                    ),
                  ],
                ),
              ),

              // ---- 输入栏 ----
              const SizedBox(height: 16),
              section('输入栏'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('输入样式',
                        style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'classic', label: Text('经典')),
                        ButtonSegment(value: 'agent', label: Text('智能体')),
                      ],
                      selected: {ThemePrefs.inputStyle},
                      onSelectionChanged: (sel) => setState(() {
                        ThemePrefs.setInputStyle(sel.first);
                        _save();
                      }),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('悬浮输入面板',
                            style: TextStyle(fontSize: 13)),
                        const Spacer(),
                        Switch(
                          value: ThemePrefs.chatInputFloating,
                          onChanged: (v) => setState(() {
                            ThemePrefs.setChatInputFloating(v);
                            _save();
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---- 字体 ----
              const SizedBox(height: 16),
              section('字体'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: ThemePrefs.fontFamily,
                      decoration: const InputDecoration(labelText: '字体'),
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('系统字体')),
                        DropdownMenuItem(value: 'serif', child: Text('衬线体 (serif)')),
                        DropdownMenuItem(value: 'sans-serif', child: Text('无衬线 (sans-serif)')),
                        DropdownMenuItem(value: 'monospace', child: Text('等宽 (monospace)')),
                        DropdownMenuItem(value: 'cursive', child: Text('手写体 (cursive)')),
                      ],
                      onChanged: (v) => setState(() {
                        ThemePrefs.setFontFamily(v ?? 'system');
                        _save();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('聊天字号',
                            style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: ThemePrefs.chatFontScale.clamp(12, 20),
                            min: 12,
                            max: 20,
                            onChanged: (v) => setState(() {
                              ThemePrefs.setChatFontScale(v);
                              _save();
                            }),
                          ),
                        ),
                        Text('${ThemePrefs.chatFontScale.round()}',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '外观体系移植自 Operit2（Material3 色板 + 主题偏好快照）',
                style: const TextStyle(
                    fontSize: 11, color: AmoreTheme.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: AmoreTheme.sectionLabel()),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: AmoreTheme.cardBox(),
        child: child,
      );
}
