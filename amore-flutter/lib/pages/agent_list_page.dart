// 对应 Swift：AgentListView.swift + AgentEditorView —— 智能体模板
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/friend_avatar.dart';
import '../widgets/persona_form.dart';

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
                    desc: a.desc,
                    gender: a.gender,
                    age: a.age,
                    voiceEngine: a.voiceEngine,
                    voiceId: a.voiceId,
                    aiProviderId: a.modelId,
                    avatarFile: a.avatarFile,
                    memory: List.of(a.memory),
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
      appBar: const AmoreAppBar(title: '智能体'),
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
                              FriendAvatar(name: a.name, avatarFile: a.avatarFile, size: 40),
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
  late final AgentTemplate _a =
      widget.existing ?? AgentTemplate(name: '新模板', desc: '');
  late final PersonaDraft _draft = PersonaDraft.fromAgent(_a);

  void _save() {
    if (_draft.name.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称不能为空')));
      return;
    }
    final providers = context.read<AppState>().providers;
    if (_draft.providerId.isNotEmpty &&
        !providers.any((p) => p.id == _draft.providerId)) {
      _draft.providerId = '';
    }
    _draft.applyToAgent(_a);
    if (_a.id.isEmpty) _a.id = _draft.id;
    AmoreStore.saveAgent(_a);
    widget.onSaved();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? '新建智能体' : '编辑「${_a.name}」',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('与「添加好友」「好友设置」使用同一套人设表单',
                style: TextStyle(fontSize: 11.5, color: AmoreTheme.textFaint)),
            const SizedBox(height: 14),
            PersonaFormFields(draft: _draft),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
