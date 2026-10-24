// 对应 Swift：GroupChat.swift —— 群聊页（全员回复，build 88 行为）
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../core/chat_engine.dart';
import '../core/attachments.dart';
import '../core/group_games.dart';
import '../core/group_games_runner.dart';
import '../widgets/game_card.dart';
import '../widgets/attachment_card.dart';
import '../widgets/chat_background.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../pages/rootfs_page.dart';
import '../widgets/bubble.dart';
import '../widgets/friend_avatar.dart';

class GroupChatPage extends StatefulWidget {
  final ChatGroup group;
  const GroupChatPage({super.key, required this.group});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  List<ChatMessage> _messages = [];
  List<_Attachment> _pendingAtts = [];
  bool _generatingImage = false;
  bool _sending = false;
  String _typingName = '';
  bool _gameRunning = false;

  List<ChatFriend> get _members {
    final state = context.read<AppState>();
    return state.friends.where((f) => widget.group.memberIds.contains(f.id)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    setState(() {
      _messages = AmoreStore.loadHistory('group.${widget.group.id}');
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(
          _scrollCtl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
    // 转场动画期间 maxScrollExtent 是中间态，转场完成后再校正到最新
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  /// 发送 → 全员依次回复（对齐 build 88：所有 AI 成员一起回，各自人设/模型）
  Future<void> _send(String text, [List<_Attachment>? atts]) async {
    if (_sending) return;
    final trimmed = text.trim();
    final attList = atts ?? const <_Attachment>[];
    if (trimmed.isEmpty && attList.isEmpty) return;
    _inputCtl.clear();

    final attMaps = attList
        .map((a) => {'name': a.name, 'path': a.path, 'kind': a.kind})
        .toList();
    final content = Attachments.encode(attMaps, trimmed);
    setState(() => _pendingAtts = []);

    final key = 'group.${widget.group.id}';
    AmoreStore.appendHistory(key, 'user', content);
    widget.group.lastMessage = trimmed;
    widget.group.lastAt = DateTime.now().millisecondsSinceEpoch / 1000;
    AmoreStore.saveGroup(widget.group);

    setState(() {
      _sending = true;
    });
    _reload();

    final members = _members;
    final nameList = members.map((m) => m.name).join('、');

    try {
      for (final member in members) {
        if (!mounted) return;
        setState(() => _typingName = member.name);
        final result = await ChatEngine.send(
          friend: member,
          userText: trimmed,
          attachments: attMaps,
          extraSystem: '当前是群聊「${widget.group.name}」，群成员：$nameList。'
              '以 ${member.name} 的身份自然回应，不要重复他人刚说过的话，保持简短、有个性。'
              '偶尔可以用 [语音:内容] 发一条语音（中文），别每句都发。',
        );
        if (result.error != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
                duration: const Duration(seconds: 6),
                content: Text(result.error!)));
          }
          break;
        }
        if (result.text != null && result.text!.isNotEmpty) {
          AmoreStore.appendHistory(key, 'assistant', result.text!);
          if (mounted) _reload();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
            duration: const Duration(seconds: 6),
            content:
                Text('发送失败：${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _typingName = '';
        });
        context.read<AppState>().refreshSocial();
      }
    }
  }

  // MARK: 群游戏（塔罗 / 狼人杀，移植自 SwiftUI build 89）

  GroupGamesRunner? _runner;

  GroupGamesRunner get _gamesRunner => _runner ??= GroupGamesRunner(
        groupId: widget.group.id,
        groupName: widget.group.name,
        members: _members,
        loadMessages: () => _messages,
        append: (role, content, {String? senderId}) {
          AmoreStore.appendHistory('group.${widget.group.id}', role, content);
          if (role == 'assistant') {
            widget.group.lastMessage = content;
            widget.group.lastAt = DateTime.now().millisecondsSinceEpoch / 1000;
            AmoreStore.saveGroup(widget.group);
          }
          if (mounted) _reload();
        },
        typing: (name) {
          if (mounted) setState(() => _typingName = name);
        },
      );

  Future<void> _sendTarot() async {
    if (_gameRunning) return;
    if (_members.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('群聊还没有成员')));
      return;
    }
    setState(() => _gameRunning = true);
    try {
      await _gamesRunner.sendTarot();
    } finally {
      if (mounted) {
        setState(() {
          _gameRunning = false;
          _typingName = '';
        });
        context.read<AppState>().refreshSocial();
      }
    }
  }

  Future<void> _startWerewolf() async {
    if (_gameRunning) return;
    final game = _gamesRunner.startWerewolf();
    if (game == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('狼人杀需要至少 2 位成员')));
      return;
    }
    setState(() => _gameRunning = true);
    try {
      await _gamesRunner.runWerewolf(game);
    } finally {
      if (mounted) {
        setState(() {
          _gameRunning = false;
          _typingName = '';
        });
        context.read<AppState>().refreshSocial();
      }
    }
  }

  void _groupMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_alt_rounded),
              title: const Text('查看成员'),
              onTap: () {
                Navigator.pop(context);
                _showMembers();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFC79A2E)),
              title: const Text('塔罗占卜'),
              onTap: () {
                Navigator.pop(context);
                _sendTarot();
              },
            ),
            ListTile(
              leading: const Icon(Icons.pets_rounded, color: Color(0xFFFF3B30)),
              title: const Text('狼人杀'),
              subtitle: const Text('成员至少 2 人 · 单轮体验'),
              onTap: () {
                Navigator.pop(context);
                _startWerewolf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: AmoreTheme.danger),
              title: const Text('清空群聊记录', style: TextStyle(color: AmoreTheme.danger)),
              onTap: () {
                Navigator.pop(context);
                AmoreStore.clearHistory('group.${widget.group.id}');
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMembers() {
    final members = _members;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('${widget.group.name} · ${members.length} 位成员',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...members.map((m) => ListTile(
                  leading: FriendAvatar(
                      name: m.name, avatarFile: m.avatarFile, size: 38),
                  title: Text(m.name),
                  subtitle: Text(m.persona.isEmpty ? '（无人设）' : m.persona,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              _sending
                  ? '$_typingName 正在输入…'
                  : '${_members.length} 位成员 · 全员回复',
              style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RootfsPage())),
              icon: const Icon(Icons.storage_rounded),
              tooltip: 'Rootfs 管理'),
          IconButton(onPressed: _groupMenu, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: ChatBackground(
        bgKey: context.select<AppState, String>((s) => s.chatBgKey),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  controller: _scrollCtl,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            FriendAvatar(
                                name: _typingName,
                                avatarFile: _members
                                    .where((f) => f.name == _typingName)
                                    .firstOrNull
                                    ?.avatarFile ??
                                    '',
                                size: 34),
                            const SizedBox(width: 8),
                            Text('$_typingName 正在输入…',
                                style: const TextStyle(
                                    fontSize: 12, color: AmoreTheme.textSecondary)),
                          ],
                        ),
                      );
                    }
                    final m = _messages[i];
                    // 卡牌消息（塔罗/狼人杀）→ 金边卡面
                    final mark = CardMark.parse(m.content);
                    if (mark != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Center(child: GameCard(
                          kind: mark.kind,
                          title: mark.title,
                          sub: mark.sub,
                          icon: CardMark.symbolIcon(mark.symbol),
                          tint: mark.color,
                        )),
                      );
                    }
                    // 群聊：AI 回复没有单人气泡颜色区分，语音条 plain
                    return MessageBubble(
                      msg: m,
                      mine: m.role == 'user',
                      friend: _members.isEmpty ? null : _members.first,
                      plain: true,
                      onChanged: () {
                        if (mounted) _reload();
                      },
                      historyKey: 'group.${widget.group.id}',
                    );
                  },
                ),
              ),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachMenu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: const Text('添加文件'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('选择照片'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('选择视频'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AmoreBrand.accent),
              title: const Text('AI 生成图片'),
              subtitle: const Text('用「图片」类型配置画画'),
              onTap: () => Navigator.pop(ctx, 'aigen'),
            ),
          ],
        ),
      ),
    );
    if (v == null) return;
    if (v == 'aigen') {
      await _aiGenerateImage();
      return;
    }
    if (v == 'photo') {
      final XFile? img =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (img != null) {
        final att =
            await Attachments.importFile(img.path, img.name, 'image');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? img.name,
                    path: att['path'] ?? '',
                    kind: 'image')
              ]);
        }
      }
    } else if (v == 'video') {
      final XFile? vid =
          await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (vid != null) {
        final att =
            await Attachments.importFile(vid.path, vid.name, 'video');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? vid.name,
                    path: att['path'] ?? '',
                    kind: 'video')
              ]);
        }
      }
    } else if (v == 'camera') {
      final XFile? img =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (img != null) {
        final att =
            await Attachments.importFile(img.path, img.name, 'image');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? img.name,
                    path: att['path'] ?? '',
                    kind: 'image')
              ]);
        }
      }
    } else {
      final res = await FilePicker.platform.pickFiles();
      if (res != null && res.files.single.name.isNotEmpty) {
        final f = res.files.single;
        final att =
            await Attachments.importFile(f.path ?? '', f.name, 'file');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? f.name,
                    path: att['path'] ?? '',
                    kind: 'file')
              ]);
        }
      }
    }
  }

  // AI 生成图片（OpenAI /images/generations 兼容；存沙盒进附件预览）
  Future<void> _aiGenerateImage() async {
    final provider = ChatEngine.providerForImage();
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未配置模型供应商：先到「我的 → 模型配置」添加配置')));
      return;
    }
    final ctl = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 生成图片'),
        content: TextField(
          controller: ctl,
          maxLines: 3,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: '描述你想生成的画面（可英文更准）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('生成')),
        ],
      ),
    );
    if (prompt == null || prompt.trim().isEmpty) return;
    setState(() => _generatingImage = true);
    try {
      final path = await ChatEngine.generateImage(provider, prompt.trim());
      if (!mounted) return;
      setState(() {
        _generatingImage = false;
        _pendingAtts = [
          ..._pendingAtts,
          _Attachment(name: 'AI 生成.png', path: path, kind: 'image'),
        ];
      });
      // 明确告知：图在输入框待发送区，由用户手动发送，不会自动发出
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('✓ 图片已生成，放在输入框上方待发送区，点发送发出（可点 ✕ 取消）')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
          duration: const Duration(seconds: 6),
          content: Text(
              '图片生成失败：${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  // 输入栏上方的附件预览（可删除）
  Widget _attachPreview() {
    if (_pendingAtts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 0, 0),
            child: Text('待发送（${_pendingAtts.length}）',
                style: const TextStyle(
                    fontSize: 10.5,
                    color: AmoreTheme.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        itemCount: _pendingAtts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _pendingAtts[i];
          return Stack(
            children: [
              if (a.kind == 'image' && a.path.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(a.path),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _previewFallback(a),
                  ),
                )
              else
                _previewFallback(a),
              Positioned(
                right: -4,
                top: -4,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingAtts.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A3A3C),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
        ),
      ],
    );
  }

  Widget _previewFallback(_Attachment a) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        a.kind == 'video'
            ? Icons.play_circle_fill_rounded
            : a.kind == 'file'
                ? Icons.insert_drive_file_rounded
                : Icons.image_rounded,
        size: 24,
        color: const Color(0xFF86868B),
      ),
    );
  }

  Widget _inputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _attachPreview(),
        Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AmoreTheme.tabBg,
        border: Border(top: BorderSide(color: Color(0xFFE3E3E8))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _generatingImage ? null : _attachMenu,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _generatingImage
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2))
                  : const Icon(Icons.add_circle_outline_rounded,
                      size: 24, color: Color(0xFF86868B)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _inputCtl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (t) => _send(t, _pendingAtts),
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: '发到群里…',
                fillColor: const Color(0xFFF2F2F7),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AmoreTheme.accent.withOpacity(0.5))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_inputCtl.text, _pendingAtts),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AmoreBrand.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }
}

// ---- 附件（文件/照片/视频）----
class _Attachment {
  final String name;
  final String path; // 沙盒内路径（空=占位）
  final String kind; // image / video / file
  const _Attachment({required this.name, this.path = '', required this.kind});
}
