// Amore — 好友聊天室（从聊天列表推入；对齐旧 SwiftUI ChatRoomView：好友气泡/记忆注入/语音）
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/chat_engine.dart';
import '../core/group_games.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../state/app_state.dart';
import '../core/theme.dart';
import '../widgets/bubble.dart';
import '../widgets/friend_avatar.dart';
import '../widgets/friend_edit_sheet.dart';
import '../widgets/game_card.dart';

class ChatRoomPage extends StatefulWidget {
  final ChatFriend friend;
  const ChatRoomPage({super.key, required this.friend});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _sending = false;
  String _toolHint = '';

  ChatFriend get _friend => widget.friend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    setState(() => _messages = AmoreStore.loadHistory('friend.${_friend.id}'));
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(_scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
    // 转场动画期间 maxScrollExtent 是中间态，转场完成后再校正到最新
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    _inputCtl.clear();
    setState(() => _sending = true);
    try {
      final result = await ChatEngine.send(
          friend: _friend,
          userText: trimmed,
          onToolCall: (tool) {
            if (mounted) setState(() => _toolHint = tool);
          });
      if (result.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
            duration: const Duration(seconds: 6),
            content: Text(result.error!)));
      } else if (result.tools.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 1200),
            content:
                Text('🔧 调用了工具：${result.tools.map((t) => t.name).join('、')}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
            duration: const Duration(seconds: 6),
            content: Text(
                '发送失败：${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _toolHint = '';
        });
        context.read<AppState>().refreshSocial();
        _reload();
      }
    }
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('好友设置'),
              subtitle: const Text('头像 / 人设 / 模型 / 语音 / 长期记忆'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded,
                  color: Color(0xFFFF3B30)),
              title:
                  const Text('清空聊天记录', style: TextStyle(color: Color(0xFFFF3B30))),
              onTap: () {
                Navigator.pop(context);
                AmoreStore.clearHistory('friend.${_friend.id}');
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final saved = await FriendEditSheet.show(context, _friend);
    if (!mounted) return;
    if (saved) setState(() {}); // 名称/头像即时刷新
  }

  @override
  Widget build(BuildContext context) {
    // 当前生效模型（好友专属 > 全局激活 > 第一个）
    final providers = context.watch<AppState>().providers;
    AIProvider? bound;
    if (_friend.aiProviderId.isNotEmpty) {
      bound = providers.where((p) => p.id == _friend.aiProviderId).firstOrNull;
    }
    bound ??= providers
        .where((p) => p.id == AmoreStore.activeProviderId())
        .firstOrNull;
    bound ??= providers.firstOrNull;
    final modelLabel = bound == null
        ? '未配置模型'
        : (bound.model.isEmpty ? bound.label : bound.model);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            GestureDetector(
              onTap: _openSettings,
              child: FriendAvatar(
                  name: _friend.name,
                  avatarFile: _friend.avatarFile,
                  size: 34),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _openSettings,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_friend.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(modelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: AmoreTheme.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              onPressed: _menu, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AmoreTheme.chatBgColor(
              context.select<AppState, String>((s) => s.chatBgKey)),
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
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 16, top: 8),
                          child: _Typing(),
                        ),
                      );
                    }
                    final m = _messages[i];
                    final mark = CardMark.parse(m.content);
                    if (mark != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Center(
                            child: GameCard(
                                kind: mark.kind,
                                title: mark.title,
                                sub: mark.sub,
                                icon: CardMark.symbolIcon(mark.symbol),
                                tint: mark.color)),
                      );
                    }
                    return MessageBubble(
                        msg: m, mine: m.role == 'user', friend: _friend);
                  },
                ),
              ),
              if (_toolHint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.handyman_rounded,
                        size: 13, color: AmoreBrand.orange),
                    const SizedBox(width: 5),
                    Text('🔧 调用工具：$_toolHint',
                        style: const TextStyle(
                            fontSize: 11.5, color: AmoreBrand.orange)),
                  ]),
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
        color: Colors.white.withOpacity(0.9),
        border:
            const Border(top: BorderSide(color: Color(0xFFE3E3E8))),
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
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入消息...',
                fillColor: const Color(0xFFF2F2F7),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide:
                        BorderSide(color: const Color(0xFFE3E3E8))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                        color: AmoreBrand.orange.withOpacity(0.5))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_inputCtl.text),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AmoreBrand.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AmoreBrand.accent.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> {
  int _dot = 0;
  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _dot = (_dot + 1) % 3);
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF86868B)
                    .withOpacity(_dot == i ? 1 : 0.3),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
