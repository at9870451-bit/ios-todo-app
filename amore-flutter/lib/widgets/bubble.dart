// 对应 Swift：ChatsView.swift 的 BubbleRow / Components.swift —— 消息气泡
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import 'game_card.dart';
import '../core/group_games.dart';
import 'link_card.dart';
import 'red_packet.dart';
import 'voice_bubble.dart';

/// 消息气泡（含红包/语音/链接分段渲染；长按菜单）
class MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final ChatFriend? friend; // 对方头像与语音配置
  final bool mine;
  final bool plain; // 群聊里的 AI 语音条 plain 模式
  final VoidCallback? onChanged; // 删除/记忆后通知刷新

  const MessageBubble({
    super.key,
    required this.msg,
    required this.mine,
    this.friend,
    this.plain = false,
    this.onChanged,
  });

  String get _timeText {
    final d = DateTime.fromMillisecondsSinceEpoch((msg.ts * 1000).round());
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return DateFormat('HH:mm').format(d);
    }
    return DateFormat('MM-dd HH:mm').format(d);
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制')));
              },
            ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.psychology_alt_rounded),
                title: const Text('让 TA 记住这条'),
                subtitle: const Text('加入长期记忆'),
                onTap: () {
                  final f = friend;
                  if (f != null) {
                    f.memory = [...f.memory, msg.content];
                    AmoreStore.saveFriend(f);
                  }
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已加入 TA 的长期记忆')));
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AmoreTheme.danger),
              title: const Text('删除该条',
                  style: TextStyle(color: AmoreTheme.danger)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('单条删除即将支持，可清空会话')));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        mine ? null : AmoreTheme.bubbleOther; // 我方用渐变
    final contentWidget = _renderContent();

    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              AmoreTheme.avatar(friend?.name ?? '?', size: 34),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: mine
                        ? BoxDecoration(
                            gradient: AmoreTheme.accentGradient(),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: const Radius.circular(16),
                              bottomRight: Radius.circular(
                                  _hasRichContent ? 16 : 4),
                            ),
                          )
                        : BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(_hasRichContent ? 16 : 4),
                              bottomRight: const Radius.circular(16),
                            ),
                            border: Border.all(color: AmoreTheme.cardBorder)),
                    child: contentWidget,
                  ),
                  const SizedBox(height: 3),
                  Text(_timeText,
                      style: const TextStyle(
                          fontSize: 10.5, color: AmoreTheme.textFaint)),
                ],
              ),
            ),
            if (mine) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  bool get _hasRichContent {
    final segs = MessageSegment.parse(msg.content);
    return segs.length > 1 ||
        segs.any((s) => s.kind != SegmentKind.text);
  }

  Widget _renderContent() {
    // 卡牌消息（塔罗/狼人杀文本协议）
    final mark = CardMark.parse(msg.content);
    if (mark != null) {
      return Center(child: GameCard(
        kind: mark.kind,
        title: mark.title,
        sub: mark.sub,
        symbol: mark.symbol,
        tint: mark.color,
      ));
    }
    final segs = MessageSegment.parse(msg.content);

    // 纯文本：直接富文本渲染（URL 高亮）
    if (segs.length == 1 && segs.first.kind == SegmentKind.text) {
      final text = msg.content.trim();
      if (isPureLink(text)) {
        return LinkPreviewCard(url: text.trim());
      }
      return messageTextWithLinks(
        text,
        TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: mine ? Colors.white : AmoreTheme.textPrimary),
      );
    }

    // 混合内容
    final widgets = <Widget>[];
    for (final seg in segs) {
      switch (seg.kind) {
        case SegmentKind.voice:
          widgets.add(VoiceBubble(
            content: seg.content,
            friend: friend,
            plain: plain,
            mine: mine,
          ));
        case SegmentKind.redPacket:
          widgets.add(RedPacketCard(
              amount: seg.amount ?? 0, blessing: seg.blessing ?? '', mine: mine));
        case SegmentKind.text:
          final t = seg.content.trim();
          if (t.isEmpty) continue;
          if (isPureLink(t)) {
            widgets.add(LinkPreviewCard(url: t));
          } else {
            widgets.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: messageTextWithLinks(
                  t,
                  TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: mine ? Colors.white : AmoreTheme.textPrimary)),
            ));
          }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
