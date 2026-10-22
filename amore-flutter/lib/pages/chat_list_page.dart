// 对应 Swift：ChatListView.swift —— Tab0 好友/群组会话列表
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/workflow_engine.dart';
import '../core/theme.dart';
import 'workflow_page.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'group_chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  bool _workflowMode = false;
  final WorkflowEngine _workflowEngine = WorkflowEngine();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshSocial();
    });
  }

  String _timeText(double ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return DateFormat('HH:mm').format(d);
    }
    return DateFormat('MM/dd').format(d);
  }

  void _openFriend(ChatFriend f) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatRoomPage(friend: f)));
  }

  void _openGroup(ChatGroup g) {
    final state = context.read<AppState>();
    state.setActiveGroup(g);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupChatPage(group: g)));
  }

  void _longPressFriend(ChatFriend f) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AmoreTheme.danger),
              title: const Text('删除好友', style: TextStyle(color: AmoreTheme.danger)),
              subtitle: Text('同时删除与 ${f.name} 的全部聊天记录'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('删除 ${f.name}？'),
                    content: const Text('聊天记录将一并清除，无法恢复。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AmoreTheme.danger),
                        onPressed: () {
                          AmoreStore.deleteFriend(f.id);
                          AmoreStore.clearHistory('friend.${f.id}');
                          context.read<AppState>().refreshSocial();
                          Navigator.pop(ctx);
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _longPressGroup(ChatGroup g) {
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
                _showMembers(g);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AmoreTheme.danger),
              title: const Text('解散群聊', style: TextStyle(color: AmoreTheme.danger)),
              onTap: () {
                Navigator.pop(context);
                AmoreStore.deleteGroup(g.id);
                AmoreStore.clearHistory('group.${g.id}');
                context.read<AppState>().refreshSocial();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMembers(ChatGroup g) {
    final state = context.read<AppState>();
    final members = state.friends.where((f) => g.memberIds.contains(f.id)).toList();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('${g.name} · ${members.length} 位成员',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...members.map((m) => ListTile(
                  leading: AmoreTheme.avatar(m.name, size: 38),
                  title: Text(m.name),
                  subtitle: Text('${m.genderText}${m.age.isEmpty ? '' : ' · ${m.age}岁'}'),
                )),
          ],
        ),
      ),
    );
  }

  // ---- 添加好友 ----
  void _addFriendSheet() {
    final nameCtl = TextEditingController();
    final ageCtl = TextEditingController();
    final personaCtl = TextEditingController();
    String gender = 'female';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('添加好友', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(controller: nameCtl, decoration: const InputDecoration(hintText: '昵称')),
            const SizedBox(height: 10),
            Row(
              children: [
                StatefulBuilder(builder: (context, setSheet) => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'female', label: Text('女')),
                    ButtonSegment(value: 'male', label: Text('男')),
                    ButtonSegment(value: '', label: Text('保密')),
                  ],
                  selected: {gender},
                  onSelectionChanged: (s) => setSheet(() => gender = s.first),
                )),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: ageCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '年龄')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
                controller: personaCtl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: '人设提示词（TA 是什么样的人）')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (nameCtl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入昵称')));
                    return;
                  }
                  final f = ChatFriend(
                    name: nameCtl.text.trim(),
                    gender: gender,
                    age: ageCtl.text.trim(),
                    persona: personaCtl.text.trim(),
                    sort: context.read<AppState>().friends.length,
                  );
                  AmoreStore.saveFriend(f);
                  context.read<AppState>().refreshSocial();
                  Navigator.pop(context);
                },
                child: const Text('添加'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 新建群聊 ----
  void _createGroupSheet() {
    final nameCtl = TextEditingController(text: '新群聊');
    final selected = <String>{};
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('新建群聊', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(controller: nameCtl, decoration: const InputDecoration(hintText: '群名称')),
              const SizedBox(height: 10),
              const Text('选择成员', style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              ...state.friends.map((f) => CheckboxListTile(
                    dense: true,
                    value: selected.contains(f.id),
                    onChanged: (v) => setSheet(() =>
                        v == true ? selected.add(f.id) : selected.remove(f.id)),
                    title: Text(f.name),
                    secondary: AmoreTheme.avatar(f.name, size: 32),
                  )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (selected.isEmpty) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('至少选择一位成员')));
                      return;
                    }
                    final g = ChatGroup(
                      name: nameCtl.text.trim().isEmpty ? '新群聊' : nameCtl.text.trim(),
                      memberIds: selected.toList(),
                      sort: state.groups.length,
                    );
                    AmoreStore.saveGroup(g);
                    state.refreshSocial();
                    Navigator.pop(context);
                  },
                  child: const Text('创建'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // 合并会话（好友 + 群），按 lastAt 排序
    final rows = <_SessionRow>[
      ...state.friends.map((f) => _SessionRow(
            avatar: AmoreTheme.avatar(f.name),
            name: f.name,
            last: f.lastMessage,
            ts: f.lastAt,
            onTap: () => _openFriend(f),
            onLongPress: () => _longPressFriend(f),
          )),
      ...state.groups.map((g) => _SessionRow(
            avatar: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AmoreTheme.accentGradient(),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_rounded, color: Colors.white, size: 22),
            ),
            name: g.name,
            last: g.lastMessage,
            ts: g.lastAt,
            onTap: () => _openGroup(g),
            onLongPress: () => _longPressGroup(g),
          )),
    ]..sort((a, b) => b.ts.compareTo(a.ts));

    return Scaffold(
      floatingActionButton: _workflowMode
          ? FloatingActionButton.extended(
              backgroundColor: AmoreTheme.accent,
              onPressed: () {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WorkflowPage()));
              },
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('新建工作流', style: TextStyle(color: Colors.white)),
            )
          : null,
      appBar: AppBar(
        title: const Text('聊天', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        actions: [
          if (!_workflowMode) ...[
            IconButton(
                onPressed: _addFriendSheet,
                icon: const Icon(Icons.person_add_alt_rounded),
                tooltip: '添加好友'),
            IconButton(
                onPressed: _createGroupSheet,
                icon: const Icon(Icons.group_add_rounded),
                tooltip: '新建群聊'),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: Column(
            children: [
              // 会话类型分段：聊天 / 工作流
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('聊天'), icon: Icon(Icons.forum_outlined, size: 16)),
                      ButtonSegment(value: true, label: Text('工作流'), icon: Icon(Icons.account_tree_outlined, size: 16)),
                    ],
                    selected: {_workflowMode},
                    onSelectionChanged: (s) => setState(() => _workflowMode = s.first),
                  ),
                ),
              ),
              Expanded(
                child: _workflowMode ? _workflowList() : _chatList(rows),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatList(List<_SessionRow> rows) {
    if (rows.isEmpty) return _empty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final r = rows[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: r.onTap,
            onLongPress: r.onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  r.avatar,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name,
                            style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: AmoreTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(r.last.isEmpty ? '打个招呼吧～' : r.last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: AmoreTheme.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_timeText(r.ts),
                      style: const TextStyle(fontSize: 11, color: AmoreTheme.textFaint)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 工作流会话列表（与聊天分开）
  Widget _workflowList() {
    final sessions = _workflowEngine.sessions;
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree_outlined, size: 60, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 14),
            const Text('还没有工作流对话',
                style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('工作流会把目标拆解为多个步骤逐步执行，与聊天分开',
                textAlign: TextAlign.center,
                style: TextStyle(color: AmoreTheme.textFaint, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = sessions[i];
        return AmoreTheme.tile(
          context: context,
          icon: Icons.account_tree_rounded,
          iconColor: AmoreBrand.orange,
          title: s.goal,
          subtitle: s.finished
              ? '已完成 · ${s.steps.length} 步 · ${_timeText(s.createdAt.millisecondsSinceEpoch / 1000)}'
              : '进行中',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkflowPage(viewSession: s)));
          },
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') {
                setState(() => _workflowEngine.deleteSession(s.id));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Color(0xFFFF3B30)))),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 64, color: AmoreTheme.textFaint.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('还没有好友或群聊',
              style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('点右上角添加好友，或从「智能体」一键导入',
              style: TextStyle(color: AmoreTheme.textFaint, fontSize: 12.5)),
          const SizedBox(height: 20),
          FilledButton(onPressed: _addFriendSheet, child: const Text('添加第一位好友')),
        ],
      ),
    );
  }
}

class _SessionRow {
  final Widget avatar;
  final String name;
  final String last;
  final double ts;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  _SessionRow({
    required this.avatar,
    required this.name,
    required this.last,
    required this.ts,
    required this.onTap,
    required this.onLongPress,
  });
}
