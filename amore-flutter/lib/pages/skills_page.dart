// 技能中心：Skill 技能 / 插件 / 工作包 / MCP 服务
import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

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
        _importButtons(),
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
        Text('插件 = 宿主级扩展（消息钩子/行为注入）',
            style: TextStyle(
                fontSize: 11.5, color: AmoreTheme.textSecondary)),
        const SizedBox(height: 10),
        for (final p in packs) _packCard(p, enabled.contains(p.id)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addPlugin,
          icon: const Icon(Icons.extension_rounded, size: 18),
          label: const Text('本地添加插件'),
        ),
        _importButtons(),
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
        Text('工作包 = 工具/脚本/流程的打包分发（manifest 清单）',
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addWorkflow,
          icon: const Icon(Icons.add_task_rounded, size: 18),
          label: const Text('本地新建工作包'),
        ),
        _importButtons(),
      ],
    );
  }

  // 统一的导入按钮组（本地文件 / URL / 剪贴板——技能/插件/工作包共用）
  Widget _importButtons() {
    return Column(
      children: [
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _importFromFile,
              icon: const Icon(Icons.folder_open_rounded, size: 15),
              label: const Text('本地文件'),
            ),
            TextButton.icon(
              onPressed: _importFromUrl,
              icon: const Icon(Icons.link_rounded, size: 15),
              label: const Text('URL'),
            ),
            TextButton.icon(
              onPressed: _importFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 15),
              label: const Text('剪贴板'),
            ),
          ],
        ),
      ],
    );
  }

  // 剪贴板导入（统一解析：技能/插件/工作包）
  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空，请先复制 JSON')));
      return;
    }
    _importParsed(raw);
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
          if (p.category == 'skill' && p.parameters.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('参数规范（JSON Schema）：',
                style: TextStyle(
                    fontSize: 10.5, color: AmoreTheme.textFaint)),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(p.parameters,
                  style: const TextStyle(
                      fontSize: 10, fontFamily: 'monospace')),
            ),
          ],
          if (p.handler.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('执行器：${p.handler}',
                style: TextStyle(
                    fontSize: 10.5, color: AmoreTheme.textFaint)),
          ],
          if (p.category == 'plugin' && p.hook.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('宿主扩展点：recv 钩子（回复前处理）',
                style: TextStyle(
                    fontSize: 10.5, color: AmoreTheme.textFaint)),
          ],
          if (p.category == 'workflow' && p.manifest.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('manifest',
                    style: TextStyle(
                        fontSize: 10.5, color: AmoreTheme.textFaint)),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _exportPack(p),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('导出'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _importPack(p),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('导入'),
                ),
              ],
            ),
          ],
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

  // 本地添加插件（宿主级扩展：名称/描述/消息钩子/行为指令）
  void _addPlugin() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final promptCtl = TextEditingController();
    var hookSel = 'recv';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('本地添加插件'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtl,
                    decoration: const InputDecoration(labelText: '插件名称')),
                const SizedBox(height: 8),
                TextField(
                    controller: descCtl,
                    decoration: const InputDecoration(labelText: '一句话描述')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: hookSel,
                  decoration: const InputDecoration(labelText: '消息钩子'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('无（仅行为注入）')),
                    DropdownMenuItem(value: 'recv', child: Text('recv（接收后）')),
                  ],
                  onChanged: (v) => setDlg(() => hookSel = v ?? ''),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: promptCtl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: '行为指令（注入 AI 的提示词）'),
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
                  id: 'plugin_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  desc: descCtl.text.trim(),
                  category: 'plugin',
                  prompt: promptCtl.text.trim(),
                  hook: hookSel,
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
      ),
    );
  }

  // 本地新建工作包（名称/描述/步骤列表）
  void _addWorkflow() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final stepsCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本地新建工作包'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: '工作包名称')),
              const SizedBox(height: 8),
              TextField(
                  controller: descCtl,
                  decoration: const InputDecoration(labelText: '一句话描述')),
              const SizedBox(height: 8),
              TextField(
                controller: stepsCtl,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '步骤（每行一步）',
                    hintText: '第一步…\n第二步…\n第三步…'),
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
              final steps = stepsCtl.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (steps.isEmpty) return;
              final all = SkillCatalog.load();
              all.add(SkillPack(
                id: 'wf_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                desc: descCtl.text.trim(),
                category: 'workflow',
                manifest:
                    '{"name":"$name","version":"1.0.0","author":"本机","entry":"steps","kind":"workflow"}',
                steps: steps,
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

  String _handlerSel = 'prompt';

  void _addSkill() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final promptCtl = TextEditingController();
    final schemaCtl = TextEditingController();
    _handlerSel = 'prompt';
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
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '技能指令（提示词型技能用）',
                    hintText: '或留空，用下方「参数+执行器」做可调用技能'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: schemaCtl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: '参数规范（JSON Schema，可空）',
                    hintText:
                        '{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: 'prompt',
                decoration: const InputDecoration(labelText: '执行器'),
                items: const [
                  DropdownMenuItem(value: 'prompt', child: Text('提示词型（仅注入指令）')),
                  DropdownMenuItem(value: 'tool:get_time', child: Text('本地工具：时间')),
                  DropdownMenuItem(value: 'tool:calc', child: Text('本地工具：计算')),
                  DropdownMenuItem(value: 'tool:random', child: Text('本地工具：随机数')),
                ],
                onChanged: (v) => _handlerSel = v ?? 'prompt',
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
                parameters: schemaCtl.text.trim(),
                handler: _handlerSel,
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

  // 工作包导出：复制 manifest JSON 到剪贴板
  void _exportPack(SkillPack p) async {
    final m = p.manifest.isNotEmpty
        ? p.manifest
        : '{"name":"${p.name}","version":"1.0.0","author":"Amore","entry":"steps","kind":"workflow","steps":${p.steps.map((e) => '"$e"').toList()}}';
    await Clipboard.setData(ClipboardData(text: m));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ 工作包 manifest 已复制到剪贴板')));
  }

  // 工作包导入：从剪贴板解析 manifest 加入
  Future<void> _importPack([SkillPack? _]) async {
    final data = await Clipboard.getData('text/plain');
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空，请先复制 manifest JSON')));
      return;
    }
    _importParsed(raw);
  }

  // 本地文件导入（.json manifest / SkillPack 导出文件）
  Future<void> _importFromFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.single.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法读取文件内容（未获取到数据）')));
      return;
    }
    _importParsed(utf8.decode(bytes, allowMalformed: true).trim());
  }

  // URL 导入（下载 manifest JSON）
  Future<void> _importFromUrl() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL 导入'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'https://example.com/workflow.json'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('下载导入')),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final resp = await dio.get<String>(url.trim());
      _importParsed(resp.data?.trim() ?? '');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30),
          content: Text('下载失败：${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  // 统一解析导入（兼容 SkillPack 导出格式 与 工作包 manifest 格式）
  void _importParsed(String raw) {
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('内容为空，导入失败')));
      return;
    }
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) {
        throw Exception('JSON 应为对象（manifest 或 SkillPack 导出）');
      }
      final m = Map<String, dynamic>.from(obj);
      final all = SkillCatalog.load();

      // SkillPack 导出格式（含 category）
      if ((m['category'] as String?)?.isNotEmpty == true) {
        final pack = SkillPack.fromJson(m);
        if (pack.name.isEmpty) throw Exception('缺少 name');
        pack.id = '${pack.category}_${DateTime.now().millisecondsSinceEpoch}';
        pack.builtin = false; // 导入的一律视为自定义
        all.add(pack);
        SkillCatalog.saveCustom(all);
        SkillCatalog.setEnabled(pack.id, true);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✓ 「${pack.name}」已导入（${pack.category == 'plugin' ? '插件' : '技能'}）')));
        return;
      }

      // 工作包 manifest 格式（name + steps）
      final steps = (m['steps'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      if (steps.isEmpty) throw Exception('manifest 缺少 steps');
      all.add(SkillPack(
        id: 'wf_${DateTime.now().millisecondsSinceEpoch}',
        name: (m['name'] ?? '导入工作包').toString(),
        desc: (m['desc'] ?? '从文件/URL 导入').toString(),
        category: 'workflow',
        manifest: jsonEncode(m),
        steps: steps,
      ));
      SkillCatalog.saveCustom(all);
      SkillCatalog.setEnabled(all.last.id, true);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ 工作包已导入（可启用并运行）')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30),
          content: Text('导入失败：${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  void _runWorkflow(SkillPack p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkflowPage(initialGoal: p.name),
    ));
  }
}
