// 好友头像：有自定义头像文件时显示图片，否则回退字母头像
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/theme.dart';

class FriendAvatar extends StatelessWidget {
  final String name;
  final String avatarFile;
  final double size;

  const FriendAvatar({
    super.key,
    required this.name,
    this.avatarFile = '',
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final path = AmoreStore.filePath(avatarFile);
    if (path.isEmpty) return AmoreTheme.avatar(name, size: size);
    return ClipOval(
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => AmoreTheme.avatar(name, size: size),
      ),
    );
  }
}