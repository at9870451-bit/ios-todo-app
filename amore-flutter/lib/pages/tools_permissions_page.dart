// 工具与权限页：系统授权 / 高级设置 / 当前运行环境（对齐 Operit 工具与权限）
import 'package:flutter/material.dart';

import '../core/permissions.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../core/tools_config.dart';

class ToolsPermissionsPage extends StatefulWidget {
  const ToolsPermissionsPage({super.key});

  @override
  State<ToolsPermissionsPage> createState() => _ToolsPermissionsPageState();
}

class _ToolsPermissionsPageState extends State<ToolsPermissionsPage> {
  void _editNumber(
      String title, int current, String hint, void Function(int) onSave) {
    final ctl = TextEditingController(text: '$current');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v != null && v > 0) onSave(v);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grantedCount = Permissions.keys
            .where((k) => Permissions.allow(k))
            .length +
        (ToolsConfig.notifyGranted ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具与权限',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 系统授权
              section('系统授权'),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('通知',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('AI 回复完成或工具等待批准时发送系统通知',
                      style: TextStyle(fontSize: 12)),
                  value: ToolsConfig.notifyGranted,
                  onChanged: (v) => setState(() => ToolsConfig.setNotifyGranted(v)),
                ),
              ),
              if (ToolsConfig.notifyGranted)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text('已授予',
                      style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF34C759),
                          fontWeight: FontWeight.w600)),
                ),

              // 高级设置
              const SizedBox(height: 20),
              section('高级设置'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('应用运行隔离',
                        style:
                            TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('HostIsolation.osAppSandbox',
                        style: TextStyle(
                            fontSize: 12, color: AmoreTheme.textSecondary)),
                    const SizedBox(height: 2),
                    const Text('系统授权 · iOS / HostPlatform.ios',
                        style: TextStyle(
                            fontSize: 11.5, color: AmoreTheme.textFaint)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI 能力限制',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: Text(
                      ToolsConfig.fullAccess
                          ? '完整权限：AI 可以读写当前工作区，并关闭应用内沙盒'
                          : '受限：AI 仅可访问已授权数据',
                      style: const TextStyle(fontSize: 12)),
                  value: ToolsConfig.fullAccess,
                  onChanged: (v) => setState(() => ToolsConfig.setFullAccess(v)),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: AmoreTheme.cardBox(),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('工具调用确认',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('开启后按 AI 直接调用的工具执行审批',
                      style: TextStyle(fontSize: 12)),
                  value: ToolsConfig.toolConfirm,
                  onChanged: (v) => setState(() => ToolsConfig.setToolConfirm(v)),
                ),
              ),
              const SizedBox(height: 8),
              _timeoutRow('MCP 启动超时', '管理 MCP 配置，当前启动等待',
                  ToolsConfig.mcpTimeout, (v) => ToolsConfig.setMcpTimeout(v)),
              const SizedBox(height: 8),
              _timeoutRow('ToolPkg 前置 Hook 超时', '每条 ToolPkg 前置 Hook 链总计最多执行',
                  ToolsConfig.hookTimeout, (v) => ToolsConfig.setHookTimeout(v)),

              // 当前运行环境
              const SizedBox(height: 20),
              section('当前运行环境'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AmoreTheme.cardBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _envRow('平台', 'ios · HostPlatform.ios'),
                    const Divider(height: 18),
                    _envRow('外层隔离', 'HostIsolation.osAppSandbox'),
                    const Divider(height: 18),
                    _envRow('文件能力', '已注册'),
                    const Divider(height: 18),
                    _envRow('终端能力', '已注册'),
                    const Divider(height: 18),
                    _envRow('授权项', '$grantedCount 项'),
                    const Divider(height: 18),
                    _envRow('结构化能力', '6 项'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '结构化能力 = 本机工具：时间 / 好友 / 聊天记录 / 计算 / 设备信息 / 随机数',
                style: const TextStyle(
                    fontSize: 11.5, color: AmoreTheme.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeoutRow(
      String title, String desc, int value, void Function(int) onSave) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: AmoreTheme.cardBox(),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14.5)),
        subtitle: Text('$desc $value 秒', style: const TextStyle(fontSize: 12)),
        trailing: TextButton(
          onPressed: () => _editNumber(title, value, '秒数（1-300）', onSave),
          child: const Text('编辑'),
        ),
      ),
    );
  }

  Widget _envRow(String k, String v) => Row(
        children: [
          Text(k,
              style: const TextStyle(
                  fontSize: 13, color: AmoreTheme.textSecondary)),
          const Spacer(),
          Text(v, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: AmoreTheme.sectionLabel()),
      );
}
