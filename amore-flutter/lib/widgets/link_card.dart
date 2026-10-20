// 对应 Swift：LinkCard.swift —— 链接检测与卡片
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
  return _urlRe.hasMatch(t) &&
      t.replaceAll(_urlRe, '').trim().isEmpty;
}

/// 链接预览卡片（Safari 风格：图标 + 域名 + URL + 操作）
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
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AmoreTheme.accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.public_rounded, color: AmoreTheme.accent, size: 19),
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
                        fontSize: 13, fontWeight: FontWeight.w600, color: AmoreTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AmoreTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制'), duration: Duration(milliseconds: 1200)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AmoreTheme.accent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('复制',
                  style: TextStyle(fontSize: 12, color: AmoreTheme.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 富文本消息段：URL 部分高亮
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
            color: AmoreTheme.accent, decoration: TextDecoration.underline)));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return SelectableText.rich(TextSpan(children: spans));
}
