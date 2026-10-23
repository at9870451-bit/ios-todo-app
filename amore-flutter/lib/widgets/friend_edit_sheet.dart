// 好友（智能体）设置：头像 / 名称 / 人设 / 性别 / 年龄 / 语音 / 模型 / 长期记忆
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../pages/providers_page.dart';
import '../state/app_state.dart';
import 'friend_avatar.dart';

class FriendEditSheet extends StatefulWidget {
  final ChatFriend friend;
  final bool create;

  const FriendEditSheet({super.key, required this.friend, this.create = false});

  /// 编辑已有好友；保存成功返回 true
  static Future<bool> show(BuildContext context, ChatFriend friend) =>
      _open(context, friend, create: false);

  /// 新建好友（与「好友设置」同一套表单）
  static Future<bool> showCreate(BuildContext context, ChatFriend draft) =>
      _open(context, draft, create: true);

  static Future<bool> _open(BuildContext context, ChatFriend friend,
      {required bool create}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => FriendEditSheet(friend: friend, create: create),
    );
    return saved ?? false;
  }

  @override
  State<FriendEditSheet> createState() => _FriendEditSheetState();
}

class _FriendEditSheetState extends State<FriendEditSheet> {
  late final ChatFriend _f = widget.friend;
  late final TextEditingController _nameCtl =
      TextEditingController(text: _f.name);
  late final TextEditingController _ageCtl =
      TextEditingController(text: _f.age);
  late final TextEditingController _personaCtl =
      TextEditingController(text: _f.persona);
  late final TextEditingController _voiceIdCtl =
      TextEditingController(text: _f.voiceId);
  final TextEditingController _memoryCtl = TextEditingController();

  // 新建好友时先分配稳定 id（头像文件与保存都依赖它）
  @override
  void initState() {
    super.initState();
    if (_f.id.isEmpty) {
      final now = DateTime.now();
      _f.id = '${now.microsecondsSinceEpoch.toRadixString(36)}'
          '${(now.microsecond % 997).toRadixString(36)}';
    }
  }

  late String _gender = _f.gender;
  late String _avatarFile = _f.avatarFile;
  late String _voiceEngine = _f.voiceEngine;
  late String _providerId = _f.aiProviderId;
  late List<String> _memory = List.of(_f.memory);
  bool _pickerOpen = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _ageCtl.dispose();
    _personaCtl.dispose();
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
      final dest = '${dir.path}/${_f.id}.jpg';
      await File(picked.path).copy(dest);
      await FileImage(File(dest)).evict(); // 同一路径替换后清缓存
      if (!mounted) return;
      setState(() => _avatarFile = 'avatars/${_f.id}.jpg');
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
            if (_avatarFile.isNotEmpty)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: AmoreTheme.danger),
                title: const Text('恢复默认头像',
                    style: TextStyle(color: AmoreTheme.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _avatarFile = '');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(() => _pickerOpen = false);
  }

  void _openProviders() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ProvidersPage()))
        .then((_) {
      if (!mounted) return;
      context.read<AppState>().refreshProviders();
      setState(() {});
    });
  }

  void _save() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称不能为空')));
      return;
    }
    final providers = context.read<AppState>().providers;
    final pid =
        providers.any((p) => p.id == _providerId) ? _providerId : '';
    _f
      ..name = name
      ..age = _ageCtl.text.trim()
      ..persona = _personaCtl.text.trim()
      ..gender = _gender
      ..avatarFile = _avatarFile
      ..voiceEngine = _voiceEngine
      ..voiceId = _voiceIdCtl.text.trim()
      ..aiProviderId = pid
      ..memory = List.of(_memory);
    AmoreStore.saveFriend(_f);
    context.read<AppState>().refreshSocial();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<AppState>().providers;
    // 绑定的配置若已被删除，回落到「跟随全局」，避免下拉断言
    final modelValue =
        _providerId.isEmpty || providers.any((p) => p.id == _providerId)
            ? _providerId
            : '';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomInset),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.create ? '添加好友' : '好友设置',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                widget.create
                    ? '与「好友设置」同一套信息：头像 / 人设 / 语音 / 模型'
                    : '智能体信息与头像只保存在本机',
                style:
                    const TextStyle(fontSize: 11.5, color: AmoreTheme.textFaint)),
            const SizedBox(height: 14),
            // 头像
            Center(
              child: GestureDetector(
                onTap: _avatarMenu,
                child: Stack(
                  children: [
                    FriendAvatar(
                      name: _nameCtl.text.isEmpty ? _f.name : _nameCtl.text,
                      avatarFile: _avatarFile,
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
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _avatarMenu,
                child: const Text('更换头像', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(height: 4),
            // 名称 + 年龄
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameCtl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: '名称'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ageCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '年龄'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'female', label: Text('女')),
                  ButtonSegment(value: 'male', label: Text('男')),
                  ButtonSegment(value: '', label: Text('保密')),
                ],
                selected: {_gender},
                onSelectionChanged: (s) => setState(() => _gender = s.first),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _personaCtl,
              maxLines: 3,
              decoration:
                  const InputDecoration(hintText: '人设提示词（TA 的性格、身份、说话方式）'),
            ),
            const SizedBox(height: 12),
            // 模型绑定：选择已添加的 AI 模型配置
            DropdownButtonFormField<String>(
              initialValue: modelValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '使用模型',
                helperText: providers.isEmpty
                    ? '还没有模型配置，点右侧「去添加」'
                    : '已添加 ${providers.length} 个配置，可单独指定',
                suffixIcon: IconButton(
                  tooltip: '管理模型配置',
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  onPressed: _openProviders,
                ),
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
              onChanged: (v) => setState(() => _providerId = v ?? ''),
            ),
            const SizedBox(height: 12),
            // 语音
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _voiceEngine,
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
                    onChanged: (v) => setState(() => _voiceEngine = v ?? ''),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _voiceIdCtl,
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
                Text('${_memory.length} 条',
                    style: const TextStyle(
                        fontSize: 11.5, color: AmoreTheme.textFaint)),
              ],
            ),
            const SizedBox(height: 6),
            if (_memory.isEmpty)
              const Text('暂无。可以手动添加，聊天时也会自动积累。',
                  style: TextStyle(fontSize: 11.5, color: AmoreTheme.textFaint)),
            ...List.generate(_memory.length, (i) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_memory[i],
                          style: const TextStyle(fontSize: 12)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _memory.removeAt(i)),
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
                    decoration: const InputDecoration(hintText: '添加一条记忆，如：喜欢喝美式'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final t = _memoryCtl.text.trim();
                    if (t.isEmpty) return;
                    setState(() {
                      _memory.add(t);
                      _memoryCtl.clear();
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(widget.create ? '创建并保存' : '保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}