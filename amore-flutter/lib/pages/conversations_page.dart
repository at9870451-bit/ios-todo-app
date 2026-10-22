// Amore — 历史会话（本地版：Rust Core 各会话历史一览；纯本地，无服务端）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'chat_room_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final List<(_Conv, int)> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final state = context.read<AppState>();
    final rows = <(_Conv, int)>[];
    // AI 对话（single）
    final nSingle = AmoreStore.countHistory('single');
    if (nSingle > 0) {
      rows.add((_Conv('AI 对话', Icons.question_answer_rounded, 'single'), nSingle));
    }
    // 好友
    for (final f in state.friends) {
      final n = AmoreStore.countHistory('friend.${f.id}');
      if (n > 0) rows.add((_Conv(f.name, Icons.person_rounded, 'friend.${f.id}', friendId: f.id), n));
    }
    // 群聊
    for (final g in state.groups) {
      final n = AmoreStore.countHistory('group.${g.id}');
      if (n > 0) rows.add((_Conv('群·${g.name}', Icons.group_rounded, 'group.${g.id}'), n));
    }
    setState(() => _rows
      ..clear()
      ..addAll(rows));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('历史会话', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: _rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.folder_open_rounded, size: 52, color: Color(0xFFAEAEB2)),
                      SizedBox(height: 14),
                      Text('本地还没有聊天记录',
                          style: TextStyle(color: Color(0xFF86868B), fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final (conv, count) = _rows[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AmoreTheme.tile(
                        context: context,
                        icon: conv.icon,
                        title: conv.title,
                        subtitle: '$count 条消息',
                        onTap: () {
                          if (conv.friendId != null) {
                            final f = context
                                .read<AppState>()
                                .friends
                                .where((x) => x.id == conv.friendId)
                                .firstOrNull;
                            if (f != null) {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ChatRoomPage(friend: f)));
                              return;
                            }
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(conv.friendId == null
                                  ? 'AI 对话与群聊记录在对应页面查看'
                                  : '好友不存在')));
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Conv {
  final String title;
  final IconData icon;
  final String key;
  final String? friendId;
  const _Conv(this.title, this.icon, this.key, {this.friendId});
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
