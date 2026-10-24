// 聊天背景：Operit2 风格——纯色 / 图片背景（透明度 + 可选模糊）
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/theme_prefs.dart';

class ChatBackground extends StatelessWidget {
  final Widget child;
  final String bgKey; // 默认纯色背景 key（chat_bg）

  const ChatBackground({super.key, required this.child, this.bgKey = 'default'});

  @override
  Widget build(BuildContext context) {
    final useImg = ThemePrefs.useBackgroundImage &&
        ThemePrefs.backgroundImagePath.isNotEmpty &&
        File(ThemePrefs.backgroundImagePath).existsSync();

    if (!useImg) {
      return Container(
        color: AmoreTheme.chatBgColor(bgKey),
        child: child,
      );
    }

    final opacity = ThemePrefs.backgroundOpacity.clamp(0.05, 1.0);
    final blur = ThemePrefs.useBackgroundBlur;
    final radius = ThemePrefs.backgroundBlurRadius.clamp(0.0, 40.0);
    final path = ThemePrefs.backgroundImagePath;

    final image = Positioned.fill(
      child: Opacity(
        opacity: opacity,
        child: blur
            ? ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: radius, sigmaY: radius),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        // 底色兜底（图片透明处透出主题背景）
        Container(color: AmoreTheme.chatBgColor(bgKey)),
        child,
      ],
    );
  }
}
