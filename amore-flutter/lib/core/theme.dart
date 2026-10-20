import 'package:flutter/material.dart';

/// Amore 视觉常量（对齐 SwiftUI 版 Liquid Glass 深色风格）
class AmoreTheme {
  AmoreTheme._();

  static const bg = Color(0xFF0B0E14);
  static const bgGradientTop = Color(0xFF161D30);
  static const card = Color(0xFF141A29);
  static const cardBorder = Color(0xFF232B40);
  static const bubbleMe = Color(0xFF3D5AFE); // 我方气泡
  static const bubbleMeDeep = Color(0xFF2A3EB1);
  static const bubbleOther = Color(0xFF1C2333); // 对方气泡
  static const accent = Color(0xFF6C8CFF);
  static const accent2 = Color(0xFFA78BFA);
  static const textPrimary = Color(0xFFF2F4FA);
  static const textSecondary = Color(0xFF9AA3BC);
  static const textFaint = Color(0xFF5A647E);
  static const danger = Color(0xFFF87171);
  static const success = Color(0xFF4ADE80);
  static const warn = Color(0xFFFFC44D);
  static const tabBg = Color(0xFF0E121C);

  static ThemeData dark() {
    const seed = accent;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textPrimary,
        centerTitle: false,
      ),
      dividerColor: Colors.white.withOpacity(0.06),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF10151F),
        hintStyle: const TextStyle(color: textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : textFaint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : const Color(0xFF2A3147)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        thumbColor: Colors.white,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF121826),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF161C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1D2537),
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// 页面级渐变背景
  static BoxDecoration pageGradient() => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -1.0),
          radius: 1.4,
          colors: [bgGradientTop, bg],
        ),
      );

  /// 卡片容器
  static BoxDecoration cardBox({Color? color, Color? border, double radius = 16}) =>
      BoxDecoration(
        color: color ?? card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? cardBorder, width: 0.8),
      );

  static LinearGradient accentGradient({Alignment begin = Alignment.topLeft, Alignment end = Alignment.bottomRight}) =>
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bubbleMe, accent2],
      );

  /// 段落小标题
  static TextStyle sectionLabel() => const TextStyle(
        color: textSecondary,
        fontSize: 12.5,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      );

  static TextStyle title() => const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: textPrimary,
      );

  /// 通用列表项卡片
  static Widget tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final c = iconColor ?? accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: cardBox(radius: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary)),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: textSecondary)),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else
                const Icon(Icons.chevron_right_rounded, color: textFaint),
            ],
          ),
        ),
      ),
    );
  }

  /// 头像（文字头像，圆形渐变）
  static Widget avatar(String name, {double size = 44}) {
    final hue = (name.hashCode.abs() % 360).toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.42).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
