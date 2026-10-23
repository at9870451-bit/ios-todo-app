// 附件卡片：图片缩略图（点击放大）/ 视频 / 文件
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AttachmentCard extends StatelessWidget {
  final Map<String, String> att; // name / path / kind
  final bool mine;

  const AttachmentCard({super.key, required this.att, required this.mine});

  String get _kind => att['kind'] ?? 'file';
  String get _name => att['name'] ?? '附件';
  String get _path => att['path'] ?? '';
  bool get _exists => _path.isNotEmpty && File(_path).existsSync();

  @override
  Widget build(BuildContext context) {
    // 图片：缩略图
    if (_kind == 'image' && _exists) {
      return GestureDetector(
        onTap: () => _previewImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(_path),
            width: 150,
            height: 150,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final isVideo = _kind == 'video';
    final isImg = _kind == 'image';
    return Container(
      width: 168,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mine
            ? const Color(0xFF0B5ED7)
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
        border: mine ? null : Border.all(color: const Color(0xFFE3E3E8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo
                ? Icons.play_circle_fill_rounded
                : isImg
                    ? Icons.broken_image_rounded
                    : Icons.insert_drive_file_rounded,
            size: 28,
            color: mine ? Colors.white : AmoreTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: mine ? Colors.white : AmoreTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _previewImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Image.file(
            File(_path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Center(child: Text('图片不可用', style: TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }
}
