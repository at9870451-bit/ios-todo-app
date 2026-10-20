// 对应 Swift：AgentListView.swift + AgentEditorView —— 智能体模板
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class AgentListPage extends StatefulWidget {
  const AgentListPage({super.key});

  @override
  State<AgentListPage> createState() => _AgentListPageState();
}

class _AgentListPageState extends State<AgentListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshAgents();
    });
  }

  void _openEditor([AgentTemplate? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AgentEditorSheet(
        existing: existing,
        onSaved: () => context.read<AppState>().refreshAgents(),
      ),
    );
  }

  void _importToFriend(AgentTemplate a) {
    final nameCtl = TextEditingController(text: a.name);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('用「${a.name}」创建好友',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: nameCtl, decoration: const InputDecoration(hintText: '好友昵称')),
            const SizedBox(height: 8),
            Text('将带入：人设 / 性别 / 年龄 / 语音配置',
                style: const TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final f = ChatFriend(
                    name: nameCtl.text.trim().isEmpty ? a.name : nameCtl.text.trim(),
                    persona: a.persona,
                    gender: a.gender,
                    age: a.age,
                    voiceEngine: a.voiceEngine,
                    voiceId: a.voiceId,
                    aiProviderId: a.modelId,
                    sort: context.read<AppState>().friends.length,
                  );
                  AmoreStore.saveFriend(f);
                  context.read<AppState>().refreshSocial();
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已创建好友「${f.name}」')));
                },
                child: const Text('创建'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agents = context.watch<AppState>().agents;
    return Scaffold(
      appBar: AppBar(title: const Text('智能体', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: agents
                .map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: AmoreTheme.cardBox(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AmoreTheme.avatar(a.name, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.name,
                                        style: const TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.w600)),
                                    Text(a.desc,
                                        style: const TextStyle(
                                            fontSize: 12, color: AmoreTheme.textSecondary)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: a.enabled,
                                onChanged: (v) {
                                  a.enabled = v;
                                  AmoreStore.saveAgent(a);
                                  context.read<AppState>().refreshAgents();
                                },
                              ),
                            ],
                          ),
                          if (a.persona.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(a.persona,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: AmoreTheme.textFaint, height: 1.5)),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _openEditor(a),
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('编辑', style: TextStyle(fontSize: 12.5)),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: () => _importToFriend(a),
                                icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                                label: const Text('用到新好友', style: TextStyle(fontSize: 12.5)),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () {
                                  AmoreStore.deleteAgent(a.id);
                                  context.read<AppState>().refreshAgents();
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 16, color: AmoreTheme.danger),
                                label: const Text('删除',
                                    style: TextStyle(fontSize: 12.5, color: AmoreTheme.danger)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AmoreTheme.accent,
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('新建模板', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class AgentEditorSheet extends StatefulWidget {
  final AgentTemplate? existing;
  final VoidCallback onSaved;
  const AgentEditorSheet({super.key, this.existing, required this.onSaved});

  @override
  State<AgentEditorSheet> createState() => _AgentEditorSheetState();
}

class _AgentEditorSheetState extends State<AgentEditorSheet> {
  late final AgentTemplate _a;
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _personaCtl = TextEditingController();
  final _ageCtl = TextEditingController();
  final _voiceIdCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _a = widget.existing ?? AgentTemplate(name: '新模板', desc: '');
    _nameCtl.text = _a.name;
    _descCtl.text = _a.desc;
    _personaCtl.text = _a.persona;
    _ageCtl.text = _a.age;
    _voiceIdCtl.text = _a.voiceId;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    _personaCtl.dispose();
    _ageCtl.dispose();
    _voiceIdCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? '新建模板' : '编辑「${_a.name}」',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
                controller: _nameCtl,
                onChanged: (v) => _a.name = v,
                decoration: const InputDecoration(hintText: '名称')),
            const SizedBox(height: 10),
            TextField(
                controller: _descCtl,
                onChanged: (v) => _a.desc = v,
                decoration: const InputDecoration(hintText: '一句话描述')),
            const SizedBox(height: 10),
            TextField(
                controller: _personaCtl,
                onChanged: (v) => _a.persona = v,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '人设提示词')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'female', label: Text('女')),
                      ButtonSegment(value: 'male', label: Text('男')),
                      ButtonSegment(value: '', label: Text('保密')),
                    ],
                    selected: {_a.gender},
                    onSelectionChanged: (s) => setState(() => _a.gender = s.first),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: TextField(
                      controller: _ageCtl,
                      onChanged: (v) => _a.age = v,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '年龄')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _a.voiceEngine.isEmpty ? 'cloud_sf' : _a.voiceEngine,
              decoration: const InputDecoration(labelText: '语音引擎'),
              items: const [
                DropdownMenuItem(value: 'cloud_sf', child: Text('硅基流动 CosyVoice')),
                DropdownMenuItem(value: 'cloud_doubao', child: Text('豆包 TTS')),
                DropdownMenuItem(value: 'model', child: Text('OpenAI 风格')),
                DropdownMenuItem(value: 'server', child: Text('服务端 TTS')),
              ],
              onChanged: (v) => setState(() => _a.voiceEngine = v ?? 'cloud_sf'),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _voiceIdCtl,
                onChanged: (v) => _a.voiceId = v,
                decoration: const InputDecoration(hintText: '音色 ID（如 female-yujie）')),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  _a.name = _nameCtl.text.trim();
                  _a.desc = _descCtl.text.trim();
                  _a.persona = _personaCtl.text.trim();
                  _a.age = _ageCtl.text.trim();
                  _a.voiceId = _voiceIdCtl.text.trim();
                  AmoreStore.saveAgent(_a);
                  widget.onSaved();
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
