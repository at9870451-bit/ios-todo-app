// 统一人设表单：添加好友 / 好友设置 / 智能体编辑 三处共用同一套字段与顺序
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'friend_avatar.dart';

/// 表单数据（好友与智能体互相映射）
class PersonaDraft {
  String id;
  String name;
  String desc;
  String persona;
  String gender;
  String age;
  String voiceEngine;
  String voiceId;
  String providerId;
  String avatarFile;
  List<String> memory;

  PersonaDraft({
    this.id = '',
    this.name = '',
    this.desc = '',
    this.persona = '',
    this.gender = 'female',
    this.age = '',
    this.voiceEngine = '',
    this.voiceId = '',
    this.providerId = '',
    this.avatarFile = '',
    List<String>? memory,
  }) : memory = memory ?? [];

  factory PersonaDraft.fromFriend(ChatFriend f) => PersonaDraft(
        id: f.id,
        name: f.name,
        desc: f.desc,
        persona: f.persona,
        gender: f.gender,
        age: f.age,
        voiceEngine: f.voiceEngine,
        voiceId: f.voiceId,
        providerId: f.aiProviderId,
        avatarFile: f.avatarFile,
        memory: List.of(f.memory),
      );

  factory PersonaDraft.fromAgent(AgentTemplate a) => PersonaDraft(
        id: a.id,
        name: a.name,
        desc: a.desc,
        persona: a.persona,
        gender: a.gender,
        age: a.age,
        voiceEngine: a.voiceEngine,
        voiceId: a.voiceId,
        providerId: a.modelId,
        avatarFile: a.avatarFile,
        memory: List.of(a.memory),
      );

  void applyToFriend(ChatFriend f) {
    f
      ..name = name.trim()
      ..desc = desc.trim()
      ..persona = persona.trim()
      ..gender = gender
      ..age = age.trim()
      ..voiceEngine = voiceEngine
      ..voiceId = voiceId.trim()
      ..aiProviderId = providerId
      ..avatarFile = avatarFile
      ..memory = List.of(memory);
  }

  void applyToAgent(AgentTemplate a) {
    a
      ..name = name.trim()
      ..desc = desc.trim()
      ..persona = persona.trim()
      ..gender = gender
      ..age = age.trim()
      ..voiceEngine = voiceEngine
      ..voiceId = voiceId.trim()
      ..modelId = providerId
      ..avatarFile = avatarFile
      ..memory = List.of(memory);
  }
}

/// 三处共用的表单控件（内部持有输入状态，实时写回 draft）
class PersonaFormFields extends StatefulWidget {
  final PersonaDraft draft;

  const PersonaFormFields({super.key, required this.draft});

  @override
  State<PersonaFormFields> createState() => PersonaFormFieldsState();
}

class PersonaFormFieldsState extends State<PersonaFormFields> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.draft.name);
  late final TextEditingController _descCtl =
      TextEditingController(text: widget.draft.desc);
  late final TextEditingController _personaCtl =
      TextEditingController(text: widget.draft.persona);
  late final TextEditingController _ageCtl =
      TextEditingController(text: widget.draft.age);
  late final TextEditingController _voiceIdCtl =
      TextEditingController(text: widget.draft.voiceId);
  final TextEditingController _memoryCtl = TextEditingController();
  bool _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    // 新建时分配稳定 id（头像文件与保存都依赖它）
    if (widget.draft.id.isEmpty) {
      final now = DateTime.now();
      widget.draft.id = '${now.microsecondsSinceEpoch.toRadixString(36)}'
          '${(now.microsecond % 997).toRadixString(36)}';
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    _personaCtl.dispose();
    _ageCtl.dispose();
    _voiceIdCtl.dispose();
    _memoryCtl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
          source: source, maxWidth: 640, maxHeight: 640, imageQuality: 88);
      if (picked == null) return;
      final dir = Directory('${AmoreStore.dataDir}/avatars');
      await dir.create(recursive: true);
      final dest = '${dir.path}/${widget.draft.id}.jpg';
      await File(picked.path).copy(dest);
      await FileImage(File(dest)).evict();
      if (!mounted) return;
      setState(() => widget.draft.avatarFile = 'avatars/${widget.draft.id}.jpg');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('头像保存失败：$e')));
    }
  }

  void _avatarMenu() {
    if (_pickerOpen) return;
    _pickerOpen = true;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            if (widget.draft.avatarFile.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AmoreTheme.danger),
                title: const Text('恢复默认头像',
                    style: TextStyle(color: AmoreTheme.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => widget.draft.avatarFile = '');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(() => _pickerOpen = false);
  }
  @override
  Widget build(BuildContext context) {
    final providers = context.watch<AppState>().providers;
    final ids = providers.map((p) => p.id).toSet();
    final modelValue =
        widget.draft.providerId.isEmpty || ids.contains(widget.draft.providerId)
            ? widget.draft.providerId
            : '';
    if (modelValue != widget.draft.providerId) {
      widget.draft.providerId = modelValue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头像
        Center(
          child: GestureDetector(
            onTap: _avatarMenu,
            child: Stack(
              children: [
                FriendAvatar(
                  name: widget.draft.name.isEmpty ? '?' : widget.draft.name,
                  avatarFile: widget.draft.avatarFile,
                  size: 86,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AmoreBrand.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _avatarMenu,
            child: const Text('更换头像', style: TextStyle(fontSize: 12.5)),
          ),
        ),
        const SizedBox(height: 2),
        // 名称 + 年龄
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _nameCtl,
                onChanged: (v) {
                  widget.draft.name = v;
                  setState(() {});
                },
                decoration: const InputDecoration(hintText: '名称'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ageCtl,
                keyboardType: TextInputType.number,
                onChanged: (v) => widget.draft.age = v,
                decoration: const InputDecoration(hintText: '年龄'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 一句话简介
        TextField(
          controller: _descCtl,
          onChanged: (v) => widget.draft.desc = v,
          decoration: const InputDecoration(hintText: '一句话简介（列表里展示）'),
        ),
        const SizedBox(height: 10),
        // 性别
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'female', label: Text('女')),
              ButtonSegment(value: 'male', label: Text('男')),
              ButtonSegment(value: '', label: Text('保密')),
            ],
            selected: {widget.draft.gender},
            onSelectionChanged: (s) =>
                setState(() => widget.draft.gender = s.first),
          ),
        ),
        const SizedBox(height: 10),
        // 人设
        TextField(
          controller: _personaCtl,
          maxLines: 3,
          onChanged: (v) => widget.draft.persona = v,
          decoration:
              const InputDecoration(hintText: '人设提示词（性格、身份、说话方式）'),
        ),
        const SizedBox(height: 12),
        // 使用模型
        DropdownButtonFormField<String>(
          key: ValueKey('model_$modelValue'),
          initialValue: modelValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '使用模型',
            helperText: providers.isEmpty
                ? '还没有模型配置，点右侧齿轮去添加'
                : '已添加 ${providers.length} 个配置，可单独指定',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('跟随全局模型')),
            ...providers.map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.label}${p.model.isEmpty ? '' : ' · ${p.model}'}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                )),
          ],
          onChanged: (v) => setState(() => widget.draft.providerId = v ?? ''),
        ),
        const SizedBox(height: 12),
        // 语音引擎 + 音色
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('voice_${widget.draft.voiceEngine}'),
                initialValue: widget.draft.voiceEngine,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '语音引擎'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('跟随默认')),
                  DropdownMenuItem(value: 'local', child: Text('本地朗读')),
                  DropdownMenuItem(value: 'server', child: Text('服务端')),
                  DropdownMenuItem(value: 'cloud_sf', child: Text('硅基流动')),
                  DropdownMenuItem(value: 'cloud_doubao', child: Text('豆包')),
                  DropdownMenuItem(value: 'model', child: Text('模型音色')),
                ],
                onChanged: (v) =>
                    setState(() => widget.draft.voiceEngine = v ?? ''),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _voiceIdCtl,
                onChanged: (v) => widget.draft.voiceId = v,
                decoration: const InputDecoration(hintText: '音色 ID（可空）'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 长期记忆
        Row(
          children: [
            const Text('长期记忆',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('${widget.draft.memory.length} 条',
                style: const TextStyle(
                    fontSize: 11.5, color: AmoreTheme.textFaint)),
          ],
        ),
        const SizedBox(height: 6),
        if (widget.draft.memory.isEmpty)
          const Text('暂无。可以手动添加，聊天时也会自动积累。',
              style: TextStyle(fontSize: 11.5, color: AmoreTheme.textFaint)),
        ...List.generate(widget.draft.memory.length, (i) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.draft.memory[i],
                      style: const TextStyle(fontSize: 12)),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => widget.draft.memory.removeAt(i)),
                  child: const Icon(Icons.close_rounded,
                      size: 15, color: AmoreTheme.textFaint),
                ),
              ],
            ),
          );
        }),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _memoryCtl,
                decoration: const InputDecoration(
                    hintText: '添加一条记忆，如：喜欢喝美式'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final t = _memoryCtl.text.trim();
                if (t.isEmpty) return;
                setState(() {
                  widget.draft.memory.add(t);
                  _memoryCtl.clear();
                });
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
      ],
    );
  }
}