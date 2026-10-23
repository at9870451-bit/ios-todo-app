// 好友（智能体）设置 —— 与「添加好友」「智能体编辑」共用同一套人设表单
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'persona_form.dart';

class FriendEditSheet extends StatefulWidget {
  final ChatFriend friend;
  final bool create;

  const FriendEditSheet({super.key, required this.friend, this.create = false});

  /// 编辑已有好友；保存成功返回 true
  static Future<bool> show(BuildContext context, ChatFriend friend) =>
      _open(context, friend, create: false);

  /// 新建好友（与「好友设置」「智能体」同一套表单）
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
  late final PersonaDraft _draft = PersonaDraft.fromFriend(_f);

  void _save() {
    if (_draft.name.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称不能为空')));
      return;
    }
    // 模型绑定失效时回落「跟随全局」
    final providers = context.read<AppState>().providers;
    if (_draft.providerId.isNotEmpty &&
        !providers.any((p) => p.id == _draft.providerId)) {
      _draft.providerId = '';
    }
    _draft.applyToFriend(_f);
    if (_f.id.isEmpty) _f.id = _draft.id;
    AmoreStore.saveFriend(_f);
    context.read<AppState>().refreshSocial();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.create ? '添加好友' : '好友设置',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('与「添加好友」「智能体」使用同一套人设表单',
                style: TextStyle(fontSize: 11.5, color: AmoreTheme.textFaint)),
            const SizedBox(height: 14),
            PersonaFormFields(draft: _draft),
            const SizedBox(height: 16),
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