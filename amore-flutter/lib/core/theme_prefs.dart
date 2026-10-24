// Operit2 外观偏好模型（对齐 Operit2 ThemePreferenceSnapshot；存 config operit.*）
import 'package:flutter/material.dart';

import 'store.dart';

class ThemePrefs {
  // ---- 主题模式 ----
  static ThemeMode get themeMode {
    final v = AmoreStore.getConfig('operit.theme_mode') ?? 'system';
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static void setThemeMode(ThemeMode m) => AmoreStore.setConfig(
      'operit.theme_mode',
      switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      });

  /// 生效模式：优先 operit.theme_mode；未设置时兼容旧 ui.dark 开关
  static ThemeMode get effectiveThemeMode {
    final raw = AmoreStore.getConfig('operit.theme_mode');
    if (raw == null || raw.isEmpty) {
      return (AmoreStore.getConfig('ui.dark') ?? '0') == '1'
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    return themeMode;
  }

  // ---- 自定义主色 ----
  static bool get useCustomColors =>
      (AmoreStore.getConfig('operit.custom_colors') ?? '0') == '1';

  static void setUseCustomColors(bool v) =>
      AmoreStore.setConfig('operit.custom_colors', v ? '1' : '0');

  static Color get customPrimary =>
      _colorOf('operit.custom_primary', const Color(0xFF007AFF));

  static void setCustomPrimary(Color c) =>
      AmoreStore.setConfig('operit.custom_primary', _colorToStr(c));

  static String get themeColor =>
      AmoreStore.getConfig('theme_color') ?? 'blue';

  // ---- 聊天背景 ----
  static bool get useBackgroundImage =>
      (AmoreStore.getConfig('operit.bg_image_enabled') ?? '0') == '1';

  static void setUseBackgroundImage(bool v) =>
      AmoreStore.setConfig('operit.bg_image_enabled', v ? '1' : '0');

  static String get backgroundImagePath =>
      AmoreStore.getConfig('operit.bg_image') ?? '';

  static void setBackgroundImagePath(String p) =>
      AmoreStore.setConfig('operit.bg_image', p);

  static double get backgroundOpacity =>
      double.tryParse(AmoreStore.getConfig('operit.bg_opacity') ?? '') ?? 0.3;

  static void setBackgroundOpacity(double v) =>
      AmoreStore.setConfig('operit.bg_opacity', '$v');

  static bool get useBackgroundBlur =>
      (AmoreStore.getConfig('operit.bg_blur') ?? '0') == '1';

  static void setUseBackgroundBlur(bool v) =>
      AmoreStore.setConfig('operit.bg_blur', v ? '1' : '0');

  static double get backgroundBlurRadius =>
      double.tryParse(AmoreStore.getConfig('operit.bg_blur_radius') ?? '') ?? 12;

  static void setBackgroundBlurRadius(double v) =>
      AmoreStore.setConfig('operit.bg_blur_radius', '$v');

  // ---- 聊天气泡样式 ----
  static String get chatStyle =>
      AmoreStore.getConfig('operit.chat_style') ?? 'bubble'; // bubble / cursor

  static void setChatStyle(String v) =>
      AmoreStore.setConfig('operit.chat_style', v);

  // ---- 输入栏 ----
  static bool get chatInputFloating =>
      (AmoreStore.getConfig('operit.input_floating') ?? '0') == '1';

  static void setChatInputFloating(bool v) =>
      AmoreStore.setConfig('operit.input_floating', v ? '1' : '0');

  static String get inputStyle =>
      AmoreStore.getConfig('operit.input_style') ?? 'agent'; // classic / agent

  static void setInputStyle(String v) =>
      AmoreStore.setConfig('operit.input_style', v);

  static bool get inputRoundedCorners =>
      (AmoreStore.getConfig('operit.input_rounded') ?? '1') != '0';

  static void setInputRoundedCorners(bool v) =>
      AmoreStore.setConfig('operit.input_rounded', v ? '1' : '0');

  // ---- 头像形状 ----
  static String get avatarShape =>
      AmoreStore.getConfig('operit.avatar_shape') ?? 'circle'; // circle / square

  static void setAvatarShape(String v) =>
      AmoreStore.setConfig('operit.avatar_shape', v);

  // ---- 字体 ----
  static String get fontFamily =>
      AmoreStore.getConfig('operit.font_family') ?? 'system'; // system/serif/sans-serif/monospace/cursive

  static void setFontFamily(String v) =>
      AmoreStore.setConfig('operit.font_family', v);

  static double get chatFontScale =>
      double.tryParse(AmoreStore.getConfig('operit.font_scale') ?? '') ?? 14.5;

  static void setChatFontScale(double v) =>
      AmoreStore.setConfig('operit.font_scale', '$v');

  // ---- 透明表面 ----
  static bool get transparentSurface =>
      (AmoreStore.getConfig('operit.transparent_surface') ?? '0') == '1';

  static void setTransparentSurface(bool v) =>
      AmoreStore.setConfig('operit.transparent_surface', v ? '1' : '0');

  // ---- 工具 ----
  static Color _colorOf(String key, Color fallback) {
    final raw = AmoreStore.getConfig(key) ?? '';
    if (raw.isEmpty) return fallback;
    final v = int.tryParse(raw);
    if (v == null) return fallback;
    return Color(v);
  }

  static String _colorToStr(Color c) =>
      '${(c.toARGB32() & 0xFFFFFFFF)}';
}
