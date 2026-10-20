// 对应 Swift：ChatsView.swift 的 RedPacketParser / RedPacketCard / RedPacketOpenedView / RedPacketComposeView
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 消息分段类型
enum SegmentKind { text, voice, redPacket }

class MessageSegment {
  final SegmentKind kind;
  final String content;
  // 红包专用
  final double? amount;
  final String? blessing;

  MessageSegment.text(this.content)
      : kind = SegmentKind.text,
        amount = null,
        blessing = null;
  MessageSegment.voice(this.content)
      : kind = SegmentKind.voice,
        amount = null,
        blessing = null;
  MessageSegment.redPacket(this.amount, this.blessing)
      : kind = SegmentKind.redPacket,
        content = '';

  /// 解析 [红包:金额|祝福] / [语音:内容]（全角冒号/竖线容错）——对齐 RedPacketParser
  static List<MessageSegment> parse(String text) {
    final out = <MessageSegment>[];
    final re = RegExp(r'\[(红包|语音|語音)[:：]([^\]]+)\]');
    var cursor = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > cursor) {
        final plain = text.substring(cursor, m.start);
        if (plain.trim().isNotEmpty) out.add(MessageSegment.text(plain));
      }
      final tag = m.group(1)!;
      final body = m.group(2)!;
      if (tag == '红包') {
        final parts = body.split(RegExp(r'[|｜,，]'));
        final amount = double.tryParse(parts.first.trim()) ?? 0;
        final blessing = parts.length > 1 ? parts.sublist(1).join(' ') : '恭喜发财';
        out.add(MessageSegment.redPacket(amount, blessing));
      } else {
        out.add(MessageSegment.voice(body));
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      final plain = text.substring(cursor);
      if (plain.trim().isNotEmpty) out.add(MessageSegment.text(plain));
    }
    if (out.isEmpty) out.add(MessageSegment.text(text));
    return out;
  }
}

/// 红包卡片
class RedPacketCard extends StatelessWidget {
  final double amount;
  final String blessing;
  final bool mine; // 我发的样式略深

  const RedPacketCard(
      {super.key, required this.amount, required this.blessing, this.mine = false});

  String get _amountText {
    if (amount % 1 == 0) return amount.toInt().toString();
    return amount.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8613C), Color(0xFFD03A2B)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFD03A2B).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.redeem_rounded,
                      color: Color(0xFFB71C1C), size: 18),
                ),
                const SizedBox(width: 8),
                const Text('Amore 红包',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Text('¥ $_amountText',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(blessing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _RedPacketOpenedView(amount: amount, blessing: blessing),
    );
  }
}

/// 领取红包弹窗
class _RedPacketOpenedView extends StatelessWidget {
  final double amount;
  final String blessing;
  const _RedPacketOpenedView({required this.amount, required this.blessing});

  @override
  Widget build(BuildContext context) {
    final amt = amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8613C), Color(0xFFB93026)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.redeem_rounded, color: Colors.amber, size: 52),
          const SizedBox(height: 14),
          Text('¥ $amt',
              style: const TextStyle(
                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(blessing,
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('收下啦'),
          ),
        ],
      ),
    );
  }
}

/// 发红包表单（回调金额与祝福）
class RedPacketComposeSheet extends StatefulWidget {
  final void Function(double amount, String blessing) onSend;
  const RedPacketComposeSheet({super.key, required this.onSend});

  @override
  State<RedPacketComposeSheet> createState() => _RedPacketComposeSheetState();
}

class _RedPacketComposeSheetState extends State<RedPacketComposeSheet> {
  final _amountCtl = TextEditingController();
  final _blessCtl = TextEditingController(text: '恭喜发财，大吉大利');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('发红包', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                prefixText: '¥ ', hintText: '金额', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _blessCtl,
            decoration: const InputDecoration(hintText: '祝福语'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8613C)),
              onPressed: () {
                final amount = double.tryParse(_amountCtl.text.trim());
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入正确的金额')));
                  return;
                }
                Navigator.pop(context);
                widget.onSend(amount, _blessCtl.text.trim().isEmpty ? '恭喜发财' : _blessCtl.text.trim());
              },
              child: const Text('塞进红包'),
            ),
          ),
        ],
      ),
    );
  }
}
