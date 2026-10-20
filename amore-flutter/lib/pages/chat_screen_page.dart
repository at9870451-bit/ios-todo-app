// 对应 Swift：ChatScreen.swift —— Tab1 当前好友聊天（核心页）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/chat_engine.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/bubble.dart';
import '../widgets/call_view.dart';
import '../widgets/red_packet.dart';

class ChatScreenPage extends StatefulWidget {
  const ChatScreenPage({super.key});

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _sending = false;
  String _toolHint = '';
  Timer? _pendingTimer;
  String _messagesKey = '';

  ChatFriend? get _friend => context.watch<AppState>().activeFriend.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    final f = _friend;
    setState(() {
      _messages = f == null ? [] : AmoreStore.loadHistory('friend.${f.id}');
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

  Future<void> _send(String text) async {
    final f = _friend;
    if (f == null || _sending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _inputCtl.clear();

    setState(() => _sending = true);
    try {
      final result = await ChatEngine.send(
        friend: f,
        userText: trimmed,
        onToolCall: (tool) {
            setState(() => _toolHint = tool);
          },
      );
      if (result.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AmoreTheme.danger.withOpacity(0.85),
              content: Text(result.error!)));
        }
      } else if (result.tools.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 1200),
            content: Text('🔧 调用了工具：${result.tools.map((t) => t.name).join('、')}')));
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

  /// 发红包（本地消息：[红包:金额|祝福]）
  void _sendRedPacket(double amount, String blessing) {
    final f = _friend;
    if (f == null) return;
    final amt = amount % 1 == 0 ? amount.toInt().toString() : amount.toString();
    final content = '[红包:$amt|$blessing]';
    AmoreStore.appendHistory('friend.${f.id}', 'user', content);
    f.lastMessage = content;
    f.lastAt = DateTime.now().millisecondsSinceEpoch / 1000;
    AmoreStore.saveFriend(f);
    _reload();
    context.read<AppState>().refreshSocial();
  }

  /// 定时消息：分钟后发送（夜间免打扰则顺延到 08:00，对齐 build 83 打扰分寸）
  void _scheduleMessage() {
    final f = _friend;
    if (f == null) return;
    final ctl = TextEditingController(text: '在吗？');
    int minutes = 5;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('定时消息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(controller: ctl, maxLines: 2, decoration: const InputDecoration(hintText: '要说的话')),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setSheet) => Wrap(
                spacing: 8,
                children: [1, 5, 15, 30, 60].map((m) => ChoiceChip(
                      label: Text('$m 分钟'),
                      selected: minutes == m,
                      onSelected: (_) => setSheet(() => minutes = m),
                    )).toList(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final text = ctl.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(sheetCtx);
                  var delay = Duration(minutes: minutes);
                  final now = DateTime.now();
                  final fireAt = now.add(delay);
                  // 夜间免打扰：23:00-08:00 跨午夜判断
                  if (context.read<AppState>().dndEnabled()) {
                    final hour = fireAt.hour;
                    final inDnd = hour >= 23 || hour < 8;
                    if (inDnd) {
                      final morning = DateTime(fireAt.year, fireAt.month, fireAt.day, 8, 0);
                      delay = morning.difference(now);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('已开启夜间免打扰：消息将顺延至早上 8:00 发送')));
                    }
                  }
                  final target = text;
                  _pendingTimer?.cancel();
                  _pendingTimer = Timer(delay, () async {
                    if (!mounted) return;
                    await _send(target);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('将在 ${delay.inMinutes} 分钟后发送')));
                },
                child: const Text('设定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _menu() {
    final f = _friend;
    if (f == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFE8613C)),
              title: const Text('发红包'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => RedPacketComposeSheet(onSend: _sendRedPacket),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('定时消息'),
              subtitle: const Text('到点自动发送（夜间免打扰生效）'),
              onTap: () {
                Navigator.pop(context);
                _scheduleMessage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_rounded, color: AmoreTheme.success),
              title: const Text('语音通话'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CallView(friend: f)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('编辑好友资料'),
              onTap: () {
                Navigator.pop(context);
                _editFriend(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: AmoreTheme.danger),
              title: const Text('清空聊天记录', style: TextStyle(color: AmoreTheme.danger)),
              onTap: () {
                Navigator.pop(context);
                AmoreStore.clearHistory('friend.${f.id}');
                _reload();
                context.read<AppState>().refreshSocial();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editFriend(ChatFriend f) {
    final personaCtl = TextEditingController(text: f.persona);
    final memoryCtl = TextEditingController(text: f.memory.join('\n'));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑 ${f.name}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              const Text('人设提示词', style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(controller: personaCtl, maxLines: 4),
              const SizedBox(height: 12),
              const Text('TA 记住的关于我的事（长期记忆，每行一条）',
                  style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              TextField(controller: memoryCtl, maxLines: 4),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    f.persona = personaCtl.text.trim();
                    f.memory = memoryCtl.text
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    AmoreStore.saveFriend(f);
                    context.read<AppState>().refreshSocial();
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已保存')));
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _friend;
    // 切换好友时刷新
    if (f != null && _messagesKey != 'friend.${f.id}') {
      _messagesKey = 'friend.${f.id}';
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f?.name ?? '对话',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              f == null
                  ? '从「聊天」选择好友'
                  : (_sending
                      ? '对方正在输入…'
                      : '${f.genderText}${f.age.isEmpty ? '' : ' · ${f.age}岁'}'),
              style: const TextStyle(fontSize: 11.5, color: AmoreTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          if (f != null)
            IconButton(onPressed: _menu, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: f == null
              ? _noFriend()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollCtl,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _messages.length) {
                            return _typingBubble();
                          }
                          final m = _messages[i];
                          return MessageBubble(
                            msg: m,
                            mine: m.role == 'user',
                            friend: f,
                            onChanged: _reload,
                          );
                        },
                      ),
                    ),
                    if (_toolHint.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.handyman_rounded,
                                size: 13, color: AmoreTheme.warn),
                            const SizedBox(width: 5),
                            Text('🔧 调用工具：$_toolHint',
                                style: const TextStyle(
                                    fontSize: 11.5, color: AmoreTheme.warn)),
                          ],
                        ),
                      ),
                    _inputBar(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          AmoreTheme.avatar(_friend?.name ?? '?', size: 34),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AmoreTheme.bubbleOther,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AmoreTheme.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: AmoreTheme.accent.withOpacity(0.4 + 0.3 * (i % 2)),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AmoreTheme.tabBg,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _menu,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AmoreTheme.accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: AmoreTheme.accent),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputCtl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: '说点什么…',
                fillColor: const Color(0xFF0C111C),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
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
                gradient: LinearGradient(colors: [AmoreTheme.bubbleMe, AmoreTheme.accent2]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noFriend() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_rounded, size: 60, color: AmoreTheme.textFaint.withOpacity(0.5)),
          const SizedBox(height: 14),
          const Text('还没有选择好友',
              style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('去「聊天」页选择或添加一位好友',
              style: TextStyle(color: AmoreTheme.textFaint, fontSize: 12.5)),
        ],
      ),
    );
  }
}
