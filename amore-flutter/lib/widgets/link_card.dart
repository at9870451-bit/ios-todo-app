// 对应 Swift：LinkCard.swift —— 链接检测与卡片（Apple 白卡样式）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

final RegExp _urlRe = RegExp(r'https?://[^\s<>"，。）)]+', caseSensitive: false);

/// 从文本中提取 URL 列表
List<String> extractUrls(String text) =>
    _urlRe.allMatches(text).map((m) => m.group(0)!).toList();

/// 文本主体是否就是一个链接
bool isPureLink(String text) {
  final t = text.trim();
  return _urlRe.hasMatch(t) && t.replaceAll(_urlRe, '').trim().isEmpty;
}

/// 链接预览卡片（自带浅灰底，在渐变/白色气泡上均可读）
class LinkPreviewCard extends StatelessWidget {
  final String url;
  const LinkPreviewCard({super.key, required this.url});

  String get _host {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E3E8)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AmoreGradients.clear,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.public_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D1D1F))),
                const SizedBox(height: 2),
                Text(url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF86868B))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制'),
                    duration: Duration(milliseconds: 1200)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AmoreBrand.orangeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('复制',
                  style: TextStyle(fontSize: 12, color: AmoreBrand.orangeDeep)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 富文本消息段：URL 部分加粗下划线（颜色继承气泡文字色，保证两种气泡上都可读）
Widget messageTextWithLinks(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final m in _urlRe.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start), style: baseStyle));
    }
    spans.add(TextSpan(
        text: m.group(0),
        style: baseStyle.copyWith(
            fontWeight: FontWeight.w600, decoration: TextDecoration.underline)));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return SelectableText.rich(TextSpan(children: spans));
}
