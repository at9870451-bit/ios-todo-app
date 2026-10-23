// 对应 Swift：GroupChat.swift —— 群聊页（全员回复，build 88 行为）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/chat_engine.dart';
import '../core/group_games.dart';
import '../core/group_games_runner.dart';
import '../widgets/game_card.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
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
  }

  /// 发送 → 全员依次回复（对齐 build 88：所有 AI 成员一起回，各自人设/模型）
  Future<void> _send(String text) async {
    if (_sending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _inputCtl.clear();

    final key = 'group.${widget.group.id}';
    AmoreStore.appendHistory(key, 'user', trimmed);
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
          IconButton(onPressed: _groupMenu, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AmoreTheme.chatBgColor(
              context.watch<AppState>().chatBgKey),
        ),
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

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AmoreTheme.tabBg,
        border: Border(top: BorderSide(color: Color(0xFFE3E3E8))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
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
            onTap: () => _send(_inputCtl.text),
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
    );
  }
}
