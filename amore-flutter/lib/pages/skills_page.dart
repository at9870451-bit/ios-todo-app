// 技能中心：Skill 技能 / 插件 / 工作包 / MCP 服务
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/mcp_client.dart';
import '../core/skill_pack.dart';
import '../core/store.dart';
import '../core/theme.dart';
import 'workflow_page.dart';

class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  String _tab = 'skill';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('技能中心',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'skill', label: Text('技能')),
                    ButtonSegment(value: 'plugin', label: Text('插件')),
                    ButtonSegment(value: 'workflow', label: Text('工作包')),
                    ButtonSegment(value: 'mcp', label: Text('MCP 服务')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (sel) =>
                      setState(() => _tab = sel.first),
                ),
              ),
              Expanded(
                child: switch (_tab) {
                  'plugin' => _pluginTab(),
                  'workflow' => _workflowTab(),
                  'mcp' => _mcpTab(),
                  _ => _skillTab(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 技能 tab ----
  Widget _skillTab() {
    final packs = SkillCatalog.load()
        .where((p) => p.category == 'skill')
        .toList();
    final enabled = SkillCatalog.enabledIds();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('启用后，AI 好友对话时自动按技能工作（提示词注入）',
            style: TextStyle(
                fontSize: 11.5, color: AmoreTheme.textSecondary)),
        const SizedBox(height: 10),
        for (final p in packs) _packCard(p, enabled.contains(p.id)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addSkill,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('自定义技能'),
        ),
      ],
    );
  }

  // ---- 插件 tab ----
  Widget _pluginTab() {
    final packs = SkillCatalog.load()
        .where((p) => p.category == 'plugin')
        .toList();
    final enabled = SkillCatalog.enabledIds();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('插件 = 能力扩展包：启用后 AI 行为更强',
            style: TextStyle(
                fontSize: 11.5, color: AmoreTheme.textSecondary)),
        const SizedBox(height: 10),
        for (final p in packs) _packCard(p, enabled.contains(p.id)),
      ],
    );
  }

  // ---- 工作包 tab ----
  Widget _workflowTab() {
    final packs = SkillCatalog.load()
        .where((p) => p.category == 'workflow')
        .toList();
    final enabled = SkillCatalog.enabledIds();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('工作包 = 预设流程模板：一键生成目标并开始分步执行',
            style: TextStyle(
                fontSize: 11.5, color: AmoreTheme.textSecondary)),
        const SizedBox(height: 10),
        for (final p in packs)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AmoreTheme.cardBox(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    Switch(
                      value: enabled.contains(p.id),
                      onChanged: (v) => setState(() {
                        SkillCatalog.setEnabled(p.id, v);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(p.desc,
                    style: TextStyle(
                        fontSize: 12, color: AmoreTheme.textSecondary)),
                if (p.steps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final st in p.steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('· ',
                              style: TextStyle(color: AmoreTheme.accent)),
                          Expanded(
                            child: Text(st,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AmoreTheme.accent),
                  onPressed: () => _runWorkflow(p),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('运行'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- MCP tab ----
  Widget _mcpTab() {
    final services = mcpServices();
    return Column(
      children: [
        Expanded(
          child: services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hub_outlined,
                          size: 56,
                          color: AmoreTheme.textFaint.withOpacity(0.6)),
                      const SizedBox(height: 12),
                      const Text('还没有 MCP 服务',
                          style: TextStyle(color: AmoreTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('添加一个 HTTP JSON-RPC 的 MCP 服务器',
                          style: TextStyle(
                              fontSize: 12, color: AmoreTheme.textFaint)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: services.length,
                  itemBuilder: (_, i) => _mcpCard(services[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _addMcp,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('添加 MCP 服务'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mcpCard(McpService s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AmoreTheme.cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.name.isEmpty ? '未命名服务' : s.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: s.enabled,
                onChanged: (v) => setState(() {
                  s.enabled = v;
                  _saveMcp(services: null, target: s);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.url,
              style: TextStyle(
                  fontSize: 11.5,
                  color: AmoreTheme.textFaint,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => _testMcp(s),
                icon: const Icon(Icons.cloud_done_outlined, size: 15),
                label: const Text('测试连接'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: AmoreTheme.danger,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _deleteMcp(s),
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 通用卡片（技能/插件）----
  Widget _packCard(SkillPack p, bool enabled) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AmoreTheme.cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (!p.builtin)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deletePack(p),
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 17, color: AmoreTheme.danger),
                ),
              Switch(
                value: enabled,
                onChanged: (v) => setState(() {
                  SkillCatalog.setEnabled(p.id, v);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(p.desc,
              style:
                  TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
        ],
      ),
    );
  }

  // ---- 动作 ----

  void _saveMcp({List<McpService>? services, McpService? target}) {
    final list = services ?? mcpServices();
    saveMcpServices(list);
    setState(() {});
  }

  void _addMcp() {
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final tokCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 MCP 服务'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                    labelText: '服务名称', hintText: '如 文件系统 / 数据库'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlCtl,
                decoration: const InputDecoration(
                    labelText: '服务器 URL',
                    hintText: 'http://127.0.0.1:8000/mcp（HTTP JSON-RPC）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tokCtl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Token（可选）', hintText: 'Bearer 令牌'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              final url = urlCtl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              final list = mcpServices();
              list.add(McpService(name: name, url: url, token: tokCtl.text.trim()));
              _saveMcp(services: list);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _testMcp(McpService s) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final tools = await McpClient(s).listTools();
      final names = tools.map((t) => t.name).take(8).join('、');
      msg.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF34C759),
          duration: const Duration(seconds: 5),
          content: Text('✓ 连接成功，${tools.length} 个工具：${names.isEmpty ? '（空）' : names}${tools.length > 8 ? '…' : ''}')));
    } catch (e) {
      msg.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30),
          duration: const Duration(seconds: 6),
          content: Text('✗ 连接失败：${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  void _deleteMcp(McpService s) {
    final list = mcpServices()..removeWhere((x) => x.id == s.id);
    _saveMcp(services: list);
  }

  void _addSkill() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final promptCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义技能'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: '技能名称')),
              const SizedBox(height: 8),
              TextField(
                  controller: descCtl,
                  decoration: const InputDecoration(labelText: '一句话描述')),
              const SizedBox(height: 8),
              TextField(
                controller: promptCtl,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: '技能指令（注入 AI 的提示词）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final all = SkillCatalog.load();
              all.add(SkillPack(
                id: 'skill_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                desc: descCtl.text.trim(),
                category: 'skill',
                prompt: promptCtl.text.trim(),
              ));
              SkillCatalog.saveCustom(all);
              SkillCatalog.setEnabled(all.last.id, true);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deletePack(SkillPack p) {
    final all = SkillCatalog.load()..removeWhere((x) => x.id == p.id);
    SkillCatalog.saveCustom(all);
    SkillCatalog.setEnabled(p.id, false);
    setState(() {});
  }

  void _runWorkflow(SkillPack p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkflowPage(initialGoal: p.name),
    ));
  }
}
