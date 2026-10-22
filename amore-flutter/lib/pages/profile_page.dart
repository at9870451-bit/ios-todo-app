// 对应 Swift：ProfileView.swift —— Tab3 我的主页
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'agent_list_page.dart';
import 'appearance_page.dart';
import 'console_page.dart';
import 'conversations_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('我的', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 用户卡片
              Container(
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
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(state.serverUrl(),
                              style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AmoreTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('免费版',
                          style: TextStyle(fontSize: 11.5, color: AmoreTheme.accent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              section('AI 与模型'),
              AmoreTheme.tile(
                context: context,
                icon: Icons.dns_rounded,
                title: '模型配置',
                subtitle: '${state.providers.length} 个配置 · 厂商目录 34 家 / 505 模型',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProvidersPage())),
              ),
              gap(),
              AmoreTheme.tile(
                context: context,
                icon: Icons.smart_toy_rounded,
                title: '智能体',
                subtitle: '${state.agents.length} 个模板 · 一键导入成好友',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgentListPage())),
              ),

              const SizedBox(height: 20),
              section('数据与工具'),
              AmoreTheme.tile(
                context: context,
                icon: Icons.history_rounded,
                title: '历史会话',
                subtitle: '服务端同步的会话列表',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ConversationsPage())),
              ),
              gap(),
              AmoreTheme.tile(
                context: context,
                icon: Icons.terminal_rounded,
                title: '本地终端',
                subtitle: '沙盒数据命令台',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ConsolePage())),
              ),
              gap(),
              AmoreTheme.tile(
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

              const SizedBox(height: 20),
              section('个性化'),
              AmoreTheme.tile(
                context: context,
                icon: Icons.palette_rounded,
                title: '外观',
                subtitle: '主题色 / 聊天背景 / 字体',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppearancePage())),
              ),

              const SizedBox(height: 20),
              section('服务'),
              AmoreTheme.tile(
                context: context,
                icon: Icons.workspace_premium_rounded,
                title: '会员中心',
                subtitle: '等级 / 权益 / 套餐',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MembershipPage())),
              ),
              gap(),
              AmoreTheme.tile(
                context: context,
                icon: Icons.settings_rounded,
                title: '设置',
                subtitle: '服务端 / 免打扰 / 语音引擎',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),

              const SizedBox(height: 24),
              Center(
                child: Text('Amore 4.0 Flutter · ${state.coreInfo.isEmpty ? "Rust Core 0.1.0" : ""}',
                    style: const TextStyle(fontSize: 11, color: AmoreTheme.textFaint)),
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
