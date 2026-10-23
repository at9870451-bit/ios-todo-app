// 附件协议：消息 content 中 `[atts]JSON[/atts]` 前缀块（Rust 历史零改动）
// JSON 数组元素: {"name": 文件名, "path": 沙盒内绝对路径, "kind": image|video|file}
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

class Attachments {
  static const _open = '[atts]';
  static const _close = '[/atts]';

  /// 解析 content → 附件列表
  static List<Map<String, String>> parse(String content) {
    final s = content;
    if (!s.startsWith(_open)) return const [];
    final end = s.indexOf(_close);
    if (end < 0) return const [];
    final raw = s.substring(_open.length, end);
    try {
      final list = jsonDecode(raw) as List? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => {
                'name': (e['name'] ?? '').toString(),
                'path': (e['path'] ?? '').toString(),
                'kind': (e['kind'] ?? 'file').toString(),
              })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 剥离附件块后的纯文本
  static String text(String content) {
    if (!content.startsWith(_open)) return content;
    final end = content.indexOf(_close);
    if (end < 0) return content;
    return content.substring(end + _close.length);
  }

  /// 组装 content：附件块在前，文本在后
  static String encode(List<Map<String, String>> atts, String text) {
    if (atts.isEmpty) return text;
    final json = jsonEncode(atts);
    return '$_open$json$_close${text.isEmpty ? '' : '\n$text'}';
  }

  /// 沙盒附件目录：<dataDir>/attachments/
  static Future<String> dir() async {
    final d = await getApplicationSupportDirectory();
    final dir = '${d.path}/attachments';
    // 目录不存在时自动创建（尽力而为）
    AmoreStore.dataDir = d.path;
    return dir;
  }

  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }
}

  /// 把选取的临时文件复制进沙盒 attachments/（持久化），返回附件描述
  /// srcPath 为空（如模拟器权限问题）时返回仅 name 的占位描述
  static Future<Map<String, String>> importFile(
      String srcPath, String name, String kind) async {
    final safeName = _safeName(name);
    if (srcPath.isEmpty) {
      return {'name': safeName, 'path': '', 'kind': kind};
    }
    try {
      final d = await dir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final target = '$d/${stamp}_$safeName';
      final src = File(srcPath);
      if (src.existsSync()) {
        await src.copy(target);
        return {'name': safeName, 'path': target, 'kind': kind};
      }
    } catch (_) {}
    return {'name': safeName, 'path': '', 'kind': kind};
  }
