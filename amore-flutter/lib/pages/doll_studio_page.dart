// 对应 Swift：DollStudioView.swift —— 玩偶工作室（3D 渲染 M5 接入 RealityKit 替代方案，装扮配置本期完整）
import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/theme.dart';

class DollStudioPage extends StatefulWidget {
  const DollStudioPage({super.key});

  @override
  State<DollStudioPage> createState() => _DollStudioPageState();
}

class _DollStudioPageState extends State<DollStudioPage> {
  int _tab = 0;

  static const _tabs = ['发型', '表情', '服装', '配饰'];
  static const _configKeys = ['doll_hair', 'doll_face', 'doll_outfit', 'doll_acc'];

  static const Map<String, List<(String, IconData)>> _options = {
    'doll_hair': [
      ('长直发', Icons.waves_rounded),
      ('双马尾', Icons.animation_rounded),
      ('丸子头', Icons.egg_alt_rounded),
      ('短发', Icons.spa_rounded),
      ('卷发', Icons.blur_circular_rounded),
      ('侧编发', Icons.linear_scale_rounded),
      ('高马尾', Icons.thermostat_rounded),
      ('公主卷', Icons.filter_vintage_rounded),
    ],
    'doll_face': [
      ('元气笑', Icons.sentiment_very_satisfied_rounded),
      ('温柔笑', Icons.sentiment_satisfied_rounded),
      ('傲娇脸', Icons.sentiment_neutral_rounded),
      ('思考中', Icons.psychology_rounded),
      ('惊讶', Icons.sentiment_dissatisfied_rounded),
      ('困困', Icons.bedtime_rounded),
      ('星星眼', Icons.star_rounded),
      ('wink', Icons.winking_face_rounded),
    ],
    'doll_outfit': [
      ('JK 制服', Icons.school_rounded),
      ('和风浴衣', Icons.checkroom_rounded),
      ('卫仔装', Icons.sports_baseball_rounded),
      ('礼服', Icons.local_florist_rounded),
      ('居家服', Icons.nightlight_rounded),
      ('运动风', Icons.sports_soccer_rounded),
      ('哥特', Icons.dark_mode_rounded),
      ('未来感', Icons.rocket_launch_rounded),
    ],
    'doll_acc': [
      ('蝴蝶结', Icons.interesting_events_rounded),
      ('猫耳', Icons.pets_rounded),
      ('眼镜', Icons.remove_red_eye_rounded),
      ('发卡', Icons.brightness_high_rounded),
      ('项链', Icons.diamond_rounded),
      ('帽子', Icons.face_retouching_natural_rounded),
      ('耳机', Icons.headphones_rounded),
      ('无', Icons.block_rounded),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final key = _configKeys[_tab];
    final current = AmoreStore.getConfig(key) ?? _options[key]!.first.$1;
    final summary = _configKeys
        .map((k) => AmoreStore.getConfig(k) ?? _options[k]!.first.$1)
        .join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('玩偶工作室', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: Column(
            children: [
              // 3D 预览区
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                height: 250,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.4),
                    radius: 1.2,
                    colors: [Color(0xFF232B47), Color(0xFF12182A)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AmoreTheme.cardBorder),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        _options[key]!
                            .firstWhere((o) => o.$1 == current, orElse: () => _options[key]!.first)
                            .$2,
                        key: ValueKey(current),
                        size: 84,
                        color: AmoreTheme.accent2.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(summary,
                        style: const TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AmoreTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('3D 实时渲染 M5 接入（RealityKit 替代方案）',
                          style: TextStyle(fontSize: 10, color: AmoreTheme.accent)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // 页签
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: _tabs
                      .asMap()
                      .entries
                      .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                      .toList(),
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),

              // 选项网格
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: _options[key]!.length,
                  itemBuilder: (_, i) {
                    final (name, icon) = _options[key]![i];
                    final selected = current == name;
                    return GestureDetector(
                      onTap: () {
                        setState(() {});
                        _save(key, name);
                      },
                      child: Container(
                        decoration: AmoreTheme.cardBox(
                          border: selected ? AmoreTheme.accent : null,
                          radius: 13,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon,
                                size: 26,
                                color: selected ? AmoreTheme.accent : AmoreTheme.textSecondary),
                            const SizedBox(height: 6),
                            Text(name,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: selected ? AmoreTheme.accent : AmoreTheme.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save(String key, String value) {
    AmoreStore.setConfig(key, value);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text('已保存：$value')));
  }
}
