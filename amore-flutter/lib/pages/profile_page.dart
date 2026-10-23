// 对应 Swift：ProfileView.swift —— Tab3 我的主页
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../ui/effects.dart';
import '../state/app_state.dart';
import 'agent_list_page.dart';
import 'appearance_page.dart';
import 'console_page.dart';
import 'membership_page.dart';
import 'providers_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  String _exportJson(AppState state) {
    final obj = {
      'exported_at': DateTime.now().toIso8601String(),
      'friends': state.friends.map((f) => f.toJson()).toList(),
      'groups': state.groups.map((g) => g.toJson()).toList(),
      'providers': state.providers.map((p) => p.toJson()).toList(),
      'agents': state.agents.map((a) => a.toJson()).toList(),
      'config': state.config,
    };
    return obj.toString().replaceAllMapped(RegExp(r'([,{])(\s*)([A-Za-z_][A-Za-z0-9_]*):'), (m) => '${m[1]}${m[2]}"${m[3]}":');
  }

  Future<void> _coreSelfTest(BuildContext context) async {
    String text;
    try {
      final data = AmoreBridge.call('core.selftest');
      final results = (data['results'] as List?) ?? const [];
      text = results.map((r) {
        final m = (r as Map)['method']?.toString() ?? '?';
        final ok = r['ok'] == true;
        final d = r['detail']?.toString() ?? '';
        return '${ok ? '✓' : '✗'} $m${ok || d.isEmpty ? '' : '\n   $d'}';
      }).join('\n');
      if (text.isEmpty) text = '没有返回结果';
    } catch (e) {
      text = '自检调用失败：${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rust Core 自检'),
        content: SingleChildScrollView(
            child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: const AmoreAppBar(centerTitle: false, title: '我的'),
      body: Container(
        decoration: AmoreTheme.pageBg(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 用户卡片（#1 TiltReflectCard：3D 触摸倾斜 + 反射流光）
              TiltReflectCard(
                radius: const BorderRadius.all(Radius.circular(20)),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AmoreTheme.cardBox(),
                  child: Row(
                    children: [
                      AmoreTheme.avatar('我', size: 62),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('QuantOKX 用户',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text('本地模式 · 数据存储在本机',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AmoreTheme.textSecondary)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AmoreTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('免费版',
                            style: TextStyle(
                                fontSize: 11.5, color: AmoreTheme.accent)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 近 7 日消息活跃度（#4 SnapLineChart：磁吸 + 滚动计数器）
              _ActivityCard(state),
              const SizedBox(height: 20),

              section('AI 与模型'),
              StaggerItem(
                index: 0,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.dns_rounded,
                  title: '模型配置',
                  subtitle: '${state.providers.length} 个配置 · 厂商目录 34 家 / 505 模型',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProvidersPage())),
                ),
              ),
              gap(),
              StaggerItem(
                index: 1,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.smart_toy_rounded,
                  title: '智能体',
                  subtitle: '${state.agents.length} 个模板 · 一键导入成好友',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AgentListPage())),
                ),
              ),
const SizedBox(height: 20),
              section('数据与工具'),
              gap(),
              StaggerItem(
                index: 2,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.terminal_rounded,
                  title: '本地终端',
                  subtitle: '沙盒数据命令台',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ConsolePage())),
                ),
              ),
              gap(),
              StaggerItem(
                index: 3,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.health_and_safety_rounded,
                  title: '核心自检',
                  subtitle: '逐项检测 Rust Core 方法是否正常',
                  onTap: () => _coreSelfTest(context),
                ),
              ),
              gap(),
              StaggerItem(
                index: 4,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.ios_share_rounded,
                  title: '数据导出',
                  subtitle: '好友/群组/配置 JSON 复制到剪贴板',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _exportJson(state)));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已导出到剪贴板')));
                  },
                ),
              ),

              const SizedBox(height: 20),
              section('个性化'),
              StaggerItem(
                index: 4,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.palette_rounded,
                  title: '外观',
                  subtitle: '主题色 / 聊天背景 / 字体',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppearancePage())),
                ),
              ),

              const SizedBox(height: 20),
              section('服务'),
              StaggerItem(
                index: 5,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.workspace_premium_rounded,
                  title: '会员中心',
                  subtitle: '等级 / 权益 / 套餐',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MembershipPage())),
                ),
              ),
              gap(),
              StaggerItem(
                index: 6,
                child: AmoreTheme.tile(
                  context: context,
                  icon: Icons.settings_rounded,
                  title: '设置',
                  subtitle: '服务端 / 免打扰 / 语音引擎',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage())),
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: Text(
                    'Amore 4.0 Flutter · ${state.coreInfo.isEmpty ? "Rust Core 0.1.0" : ""}',
                    style: const TextStyle(
                        fontSize: 11, color: AmoreTheme.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: AmoreTheme.sectionLabel()),
      );

  Widget gap() => const SizedBox(height: 8);
}

/// 近 7 日消息活跃度卡片：真实历史消息按天聚合 → 磁吸折线图
class _ActivityCard extends StatefulWidget {
  final AppState state;
  const _ActivityCard(this.state);

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  late Future<List<double>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadWeek();
  }

  Future<List<double>> _loadWeek() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(7, 0);
    try {
      final keys = <String>[
        ...widget.state.friends.map((f) => f.id),
        ...widget.state.groups.map((g) => g.id),
      ];
      for (final k in keys) {
        for (final m in AmoreStore.loadHistory(k)) {
          final d = DateTime.fromMillisecondsSinceEpoch((m.ts * 1000).round());
          final day = DateTime(d.year, d.month, d.day);
          final diff = today.difference(day).inDays;
          if (diff >= 0 && diff < 7) counts[6 - diff]++;
        }
      }
    } catch (_) {}
    return counts.map((e) => e.toDouble()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: AmoreTheme.cardBox(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AmoreBrand.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.insights_rounded,
                    color: AmoreBrand.accent, size: 17),
              ),
              const SizedBox(width: 10),
              const Text('近 7 日消息活跃',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('滑动查看',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: FutureBuilder<List<double>>(
              future: _future,
              builder: (context, snap) {
                final data = snap.data;
                if (data == null || data.every((v) => v == 0)) {
                  return const Center(
                    child: Text('还没有消息记录，去和好友聊聊天吧',
                        style:
                            TextStyle(fontSize: 12, color: AmoreTheme.textFaint)),
                  );
                }
                return SnapLineChart(
                  values: data,
                  labels: const ['一', '二', '三', '四', '五', '六', '日'],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}