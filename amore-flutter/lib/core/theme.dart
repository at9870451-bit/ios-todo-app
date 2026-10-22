// Amore Design Tokens v3 — Apple White × Liquid Glass × 苹果蓝 #007AFF
// 纯色 / 半透明玻璃 / 自然阴影；零渐变（背景、按钮、阴影一律纯色）
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ===== 品牌（Apple 系统蓝 #007AFF 单一强调色）=====
class AmoreBrand {
  AmoreBrand._();

  // Apple 系统蓝
  static const accent = Color(0xFF007AFF);
  static const accentLight = Color(0xFF4DA3FF);
  static const accentDeep = Color(0xFF0062CC);
  static const accentBg = Color(0xFFF0F7FF);
  static const accentTint = Color(0xFFE5F1FF);

  // ---- 兼容别名：旧渐变体系常量名保留，值统一映射到苹果蓝系 ----
  static const orange = accent;
  static const orangeVivid = accent;
  static const orangeDeep = accentDeep;
  static const orangeLight = accentTint;
  static const orangeBg = accentBg;
  static const gradientBlue = accentLight;
  static const skyBlue = accentLight;
  static const purpleBlue = accent;
  static const brandBlue = accent;
  static const brandBlueLight = accentLight;
  static const warmOrange = accentDeep;

  // 系统功能色（Apple 惯例）
  static const danger = Color(0xFFFF3B30);
  static const success = Color(0xFF34C759);
  static const warn = Color(0xFFFF9500);
}

/// ===== 渐变（已移除：全部改为纯色/玻璃）=====
/// 保留类名以兼容旧代码，但不再定义渐变常量，业务零引用。
class AmoreGradients {
  AmoreGradients._();
}/// ===== 语义色板（浅/深两套）=====
class APalette {
  final Brightness brightness;
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;
  final Color bubbleOther;
  final Color inputBg;
  final Color barBg;
  final Color shadow;
  final Color overlayGlass;

  const APalette({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.bubbleOther,
    required this.inputBg,
    required this.barBg,
    required this.shadow,
    required this.overlayGlass,
  });

  static const light = APalette(
    brightness: Brightness.light,
    bg: Color(0xFFF5F5F7),
    card: Colors.white,
    cardBorder: Color(0xFFE3E3E8),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF86868B),
    textFaint: Color(0xFFAEAEB2),
    bubbleOther: Colors.white,
    inputBg: Color(0xFFF2F2F7),
    barBg: Color(0xF7FFFFFF),
    shadow: Color(0x141D1D1F),
    overlayGlass: Color(0xB8FFFFFF),
  );

  static const dark = APalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0E14),
    card: Color(0xFF141A29),
    cardBorder: Color(0xFF1B2233),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFF9AA3BC),
    textFaint: Color(0xFF5A647E),
    bubbleOther: Color(0xFF1C2333),
    inputBg: Color(0xFF0C111C),
    barBg: Color(0xE6101520),
    shadow: Color(0x33000000),
    overlayGlass: Color(0xB8141A29),
  );
}/// ===== 主题入口 =====
class AmoreTheme {
  AmoreTheme._();

  static const bg = Color(0xFFF5F5F7);
  static const card = Colors.white;
  static const cardBorder = Color(0xFFE3E3E8);
  static const textPrimary = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF86868B);
  static const textFaint = Color(0xFFAEAEB2);
  static const bubbleMe = AmoreBrand.accent;
  static const bubbleMeDeep = AmoreBrand.accentDeep;
  static const bubbleOther = Color(0xFFFFFFFF);
  static const accent = AmoreBrand.accent;
  static const accent2 = AmoreBrand.accent;
  static const danger = AmoreBrand.danger;
  static const success = AmoreBrand.success;
  static const warn = AmoreBrand.warn;
  static const tabBg = Color(0xF7FFFFFF);

  static APalette pal(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? APalette.dark
          : APalette.light;

  static const rCard = 20.0;
  static const rPanel = 28.0;
  static const rButton = 16.0;
  static const rSmall = 12.0;
  static const gapCard = 12.0;
  static const padH = 20.0;

  static ThemeData light() => _build(APalette.light);
  static ThemeData dark() => _build(APalette.dark);

  static ThemeData _build(APalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AmoreBrand.accent,
      brightness: p.brightness,
    ).copyWith(
      primary: AmoreBrand.accent,
      secondary: AmoreBrand.accent,
      surface: p.card,
      surfaceContainerHighest: p.inputBg,
    );

    final isDark = p.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      textTheme: Typography.material2021(platform: TargetPlatform.iOS)
          .black
          .apply(
            bodyColor: p.textPrimary,
            displayColor: p.textPrimary,
            fontFamilyFallback: const ['.SF Pro', 'SF Pro'],
          )
          .merge(TextTheme(
            bodyLarge: TextStyle(fontWeight: isDark ? FontWeight.w300 : FontWeight.w400),
            bodyMedium: TextStyle(
                fontWeight: isDark ? FontWeight.w300 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()]),
            bodySmall: TextStyle(fontWeight: isDark ? FontWeight.w300 : FontWeight.w400),
          )),
      scaffoldBackgroundColor: p.bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: p.textPrimary,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
            letterSpacing: 0.2),
      ),
      dividerColor: p.cardBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.inputBg,
        hintStyle: TextStyle(color: p.textFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rSmall),
            borderSide: BorderSide(color: p.cardBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rSmall),
            borderSide: BorderSide(color: p.cardBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rSmall),
            borderSide:
                const BorderSide(color: AmoreBrand.accent, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AmoreBrand.accent,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(rButton)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.cardBorder),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(rButton)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : p.textFaint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AmoreBrand.accent
                : p.cardBorder),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AmoreBrand.accent,
        thumbColor: Colors.white,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AmoreBrand.accent : Colors.transparent),
        side: BorderSide(color: p.cardBorder),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AmoreBrand.accent : p.textFaint),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rPanel)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.brightness == Brightness.light
            ? const Color(0xFF1D1D1F)
            : const Color(0xFF1D2537),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AmoreBrand.accent),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AmoreBrand.accent.withOpacity(0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected)
                  ? AmoreBrand.accent
                  : p.textSecondary,
            )),
        height: 62,
      ),
      chipTheme: ChipThemeData(
        selectedColor: AmoreBrand.accentBg,
        labelStyle: TextStyle(fontSize: 13, color: p.textSecondary),
        secondaryLabelStyle: TextStyle(fontSize: 13, color: p.textSecondary),
        side: BorderSide(color: p.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }/// 页面纯色背景（#F5F5F7；零渐变）
  static BoxDecoration pageBg({Brightness? brightness}) {
    final dark = brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? APalette.dark.bg : const Color(0xFFF5F5F7),
    );
  }

  /// 兼容别名：旧 pageGradient 名保留（指向纯色背景）
  static BoxDecoration pageGradient({Brightness? brightness}) =>
      pageBg(brightness: brightness);

  /// 白色圆角卡片（柔和阴影）
  static BoxDecoration cardBox(
      {Brightness? brightness, Color? color, Color? border, double radius = rCard}) {
    final dark = brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? (dark ? APalette.dark.card : Colors.white),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
          color: border ??
              (dark ? Colors.white.withOpacity(0.015) : const Color(0xFFF0F0F3)),
          width: dark ? 0 : 0.8),
      boxShadow: [
        BoxShadow(
            color: dark ? const Color(0x40000000) : const Color(0x0D1D1D1F),
            blurRadius: 16,
            offset: const Offset(0, 6)),
      ],
    );
  }

  /// 品牌强调块：苹果蓝纯色 + 同色系自然阴影（零渐变）
  static BoxDecoration brandBox({double radius = rButton, List<Color>? colors}) =>
      BoxDecoration(
        color: AmoreBrand.accent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: AmoreBrand.accent.withOpacity(0.26),
              blurRadius: 16,
              offset: const Offset(0, 5)),
        ],
      );

  static BoxDecoration accentSolid({double radius = rButton}) =>
      BoxDecoration(
        color: AmoreBrand.accent,
        borderRadius: BorderRadius.circular(radius),
      );

  static BoxDecoration accentBlue({double radius = rButton}) =>
      BoxDecoration(
        color: AmoreBrand.accent,
        borderRadius: BorderRadius.circular(radius),
      );

  static TextStyle sectionLabel() => const TextStyle(
      color: Color(0xFF86868B),
      fontSize: 12.5,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w500);

  static TextStyle title() => const TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF1D1D1F));  /// 通用列表项卡片（白卡 + 苹果蓝图标底）
  static Widget tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final p = pal(context);
    final c = iconColor ?? AmoreBrand.accent;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardBox(brightness: p.brightness, radius: 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(Icons.chevron_right_rounded, color: p.textFaint.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }

  /// 文字头像（苹果蓝纯色圆；零渐变）
  static Widget avatar(String name, {double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AmoreBrand.accent,
        boxShadow: [
          BoxShadow(color: AmoreBrand.accent.withOpacity(0.22),
              blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(
            color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600),
      ),
    );
  }
}/// ===== Liquid Glass 容器 =====
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = AmoreTheme.rCard,
    this.padding,
    this.blur = 20,
  });

  @override
  Widget build(BuildContext context) {
    final p = AmoreTheme.pal(context);
    final light = p.brightness == Brightness.light;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: p.overlayGlass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: light ? Colors.white.withOpacity(0.8)
                  : Colors.white.withOpacity(0.10),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ===== 按压缩放反馈（#8：0.96 弹性压缩 + 深度内阴影，释放轻微超调回弹）=====
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressScale;

  const PressableScale(
      {super.key, required this.child, this.onTap, this.pressScale = 0.96});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _t =
      CurvedAnimation(parent: _ctl, curve: Curves.linear);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onTap == null) return;
    HapticFeedback.selectionClick();
    _ctl.forward(from: 0);
  }

  /// 分段曲线：按下压缩(0-26%) → 保持(26-36%) → 反弹超调(36-70%) → 回正(70-100%)
  double _segment(double t) {
    final p = widget.pressScale;
    if (t < 0.26) {
      final k = Curves.easeOutCubic.transform(t / 0.26);
      return 1.0 + (p - 1.0) * k;
    }
    if (t < 0.36) return p;
    if (t < 0.70) {
      final k = Curves.easeOutCubic.transform((t - 0.36) / 0.34);
      return p + (1.06 - p) * k;
    }
    final k = Curves.easeOutBack.transform((t - 0.70) / 0.30);
    return 1.06 + (1.0 - 1.06) * k;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapCancel: () => _ctl.forward(from: 0.36),
      onTapUp: (_) => _ctl.forward(from: 0.36),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) {
          final s = _segment(_t.value);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 深度内阴影层（按压时下沉压入纸面）
              if (s < 0.985)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.20 * (1 - s) * 8),
                            blurRadius: 12,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                  ),
                ),
              Transform.scale(scale: s, child: child),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}/// ===== 主按钮（苹果蓝纯色）=====
class BrandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  const BrandButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1.0,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: AmoreTheme.brandBox(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}/// ===== 玻璃导航栏 =====
class AmoreAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final bool centerTitle;

  const AmoreAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AppBar(
          backgroundColor: Colors.white.withOpacity(0.65),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          shape: Border(
              bottom: BorderSide(
                  color: Colors.white.withOpacity(0.6), width: 0.8)),
          centerTitle: centerTitle,
          title: Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F))),
          leading: leading,
          actions: actions,
        ),
      ),
    );
  }
}

/// ===== 悬浮玻璃圆钮 =====
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final double size;
  final VoidCallback? onTap;
  final String? tooltip;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.iconColor = const Color(0xFF1D1D1F),
    this.size = 40,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withOpacity(0.9), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Icon(icon, size: size * 0.5, color: iconColor),
        ),
      ),
    );
    return tooltip != null
        ? Tooltip(message: tooltip!, child: GestureDetector(onTap: onTap, child: btn))
        : GestureDetector(onTap: onTap, child: btn);
  }
}