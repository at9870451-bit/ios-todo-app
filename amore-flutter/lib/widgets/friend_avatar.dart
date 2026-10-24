// 好友头像：有自定义头像文件时显示图片，否则回退字母头像
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../core/theme_prefs.dart';

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
    // Operit2 头像形状：circle（默认）/ square
    final square = ThemePrefs.avatarShape == 'square';
    final img = Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => AmoreTheme.avatar(name, size: size),
    );
    if (square) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: img,
      );
    }
    return ClipOval(child: img);
  }
}