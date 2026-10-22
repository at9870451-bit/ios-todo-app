// 对应 Swift：SettingsView.swift —— 设置（服务端/免打扰/预算/语音引擎/数据管理）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import 'package:provider/provider.dart' as pv;
import '../state/app_state.dart';
import '../ui/dark_mode_transition.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _voiceEngine = 'server';
  String _ttsVoice = '';

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _voiceEngine = state.globalVoiceEngine();
    _ttsVoice = AmoreStore.getConfig('tts_voice') ?? '';
  }

  /// 深色模式圆形扩散切换：先插遮罩动画，动画完成时应用主题
  void _animateDarkMode(bool toDark) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(const Offset(0, 80))
        : Offset(MediaQuery.of(context).size.width - 60, 80);
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => CircularRevealOverlay(
        origin: origin,
        revealColor: toDark ? const Color(0xFF0B0E14) : const Color(0xFFF5F5F7),
        forward: toDark,
        onDone: () {
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
    // 动画中段应用主题（视觉连续性最佳：扩散到 ~60% 时切）
    Future.delayed(const Duration(milliseconds: 290), () {
      context.read<AppState>().setDarkMode(toDark);
    });
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const SizedBox(height: 20),
              section('打扰分寸（Orbit butler 移植）'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('夜间免打扰', style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('23:00 – 08:00 不主动发消息', style: TextStyle(fontSize: 12)),
                  value: state.dndEnabled(),
                  onChanged: (v) => state.setDnd(v),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每日主动消息预算', style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 4),
                    const Text('每天最多主动找你几次（0 = 不限）',
                        style: TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [10, 20, 50, 0].map((v) => ChoiceChip(
                            label: Text(v == 0 ? '不限' : '$v 条'),
                            selected: state.dailyBudget() == v,
                            onSelected: (_) => state.setDailyBudget(v),
                          )).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              section('外观'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('深色模式', style: TextStyle(fontSize: 14.5)),
                  subtitle:
                      const Text('切换时从开关位置圆形扩散', style: TextStyle(fontSize: 12)),
                  value: state.darkMode,
                  onChanged: (v) => _animateDarkMode(v),
                ),
              ),

              const SizedBox(height: 20),
              section('语音'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('全局语音引擎', style: TextStyle(fontSize: 14.5)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _voiceEngine,
                      items: const [
                        DropdownMenuItem(value: 'server', child: Text('服务端 TTS')),
                        DropdownMenuItem(value: 'cloud_sf', child: Text('硅基流动 CosyVoice')),
                        DropdownMenuItem(value: 'cloud_doubao', child: Text('豆包 TTS')),
                        DropdownMenuItem(value: 'model', child: Text('OpenAI 风格（跟随模型）')),
                        DropdownMenuItem(value: 'local', child: Text('本机系统 TTS（M5）')),
                      ],
                      onChanged: (v) => setState(() {
                        _voiceEngine = v ?? 'server';
                        state.setGlobalVoiceEngine(_voiceEngine);
                      }),
                    ),
                    const SizedBox(height: 10),
                    if (_voiceEngine == 'cloud_sf') ...[
                      TextField(
                        onChanged: (v) => AmoreStore.setConfig('sf_tts_key', v),
                        controller: TextEditingController(
                            text: AmoreStore.getConfig('sf_tts_key') ?? ''),
                        obscureText: true,
                        decoration: const InputDecoration(hintText: '硅基流动 API Key'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      onChanged: (v) {
                        _ttsVoice = v;
                        AmoreStore.setConfig('tts_voice', v);
                      },
                      controller: TextEditingController(text: _ttsVoice),
                      decoration: const InputDecoration(hintText: '默认音色 ID（好友可单独覆盖）'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              section('数据管理'),
              AmoreTheme.tile(
                context: context,
                icon: Icons.delete_sweep_rounded,
                iconColor: AmoreTheme.danger,
                title: '清空全部聊天记录',
                subtitle: '所有好友与群聊的本地消息',
                trailing: const SizedBox.shrink(),
                onTap: () => _confirm(context, '清空全部聊天记录？', '所有本地消息将被删除，无法恢复。', () {
                  final s = context.read<AppState>();
                  for (final f in s.friends) {
                    AmoreStore.clearHistory('friend.${f.id}');
                  }
                  for (final g in s.groups) {
                    AmoreStore.clearHistory('group.${g.id}');
                  }
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已清空全部聊天记录')));
                }),
              ),
              const SizedBox(height: 8),
              AmoreTheme.tile(
                context: context,
                icon: Icons.restart_alt_rounded,
                iconColor: AmoreTheme.warn,
                title: '重置模型配置',
                subtitle: '删除全部供应商并取消激活',
                trailing: const SizedBox.shrink(),
                onTap: () => _confirm(context, '重置模型配置？', '全部供应商配置将被删除。', () {
                  final s = context.read<AppState>();
                  for (final p in s.providers) {
                    AmoreStore.deleteProvider(p.id);
                  }
                  AmoreStore.setActiveProvider('');
                  s.refreshProviders();
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('模型配置已重置')));
                }),
              ),

              const SizedBox(height: 20),
              section('关于'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amore 4.0.0', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text('Flutter UI + Rust Core（C FFI JSON 总线）',
                        style: TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
                    Text('厂商/模型目录：Operit-iOS（AGPL-3.0）',
                        style: TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
                  ],
                ),
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

  void _confirm(BuildContext context, String title, String body, VoidCallback onOk) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AmoreTheme.danger),
            onPressed: () {
              Navigator.pop(ctx);
              onOk();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}
