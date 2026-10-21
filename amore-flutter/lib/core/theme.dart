// Amore Design Tokens v2 — Apple 白 × 橙色 × 蓝橙渐变 × Liquid Glass
// 浅色为主视觉；深色色板已定义（ThemeMode 接入下一版）
import 'dart:ui';

import 'package:flutter/material.dart';

/// ===== 品牌（亮暗通用）=====
class AmoreBrand {
  AmoreBrand._();
  // 橙色品牌系统
  static const orange = Color(0xFFFF9500);
  static const orangeVivid = Color(0xFFFF7A00);
  static const orangeDeep = Color(0xFFE87500);
  static const orangeLight = Color(0xFFFFE2C2);
  static const orangeBg = Color(0xFFFFF4E8);
  // 蓝橙渐变系统
  static const gradientBlue = Color(0xFF4DA3FF);
  static const skyBlue = Color(0xFF67C7FF);
  static const purpleBlue = Color(0xFF8C9EFF);
  static const brandBlue = Color(0xFF3478F6);
  static const brandBlueLight = Color(0xFF6CA8FF);
  static const warmOrange = Color(0xFFFF6A00);
  // 系统功能色（Apple 惯例）
  static const danger = Color(0xFFFF3B30);
  static const success = Color(0xFF34C759);
  static const warn = Color(0xFFFF9500);
}

/// ===== 渐变 =====
class AmoreGradients {
  AmoreGradients._();

  /// A. 清透蓝橙渐变（图标底 / 局部装饰）
  static const clear = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AmoreBrand.gradientBlue, AmoreBrand.skyBlue, AmoreBrand.orange],
  );

  /// B. 高级品牌渐变（主按钮 / 重点卡 / 选中态）
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AmoreBrand.brandBlue, AmoreBrand.brandBlueLight, AmoreBrand.orange],
    stops: [0.0, 0.55, 1.0],
  );

  /// C. 柔和背景渐变（页面底色）
  static const softPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEAF4FF), Colors.white, Color(0xFFFFF0DE)],
    stops: [0.0, 0.55, 1.0],
  );

  /// 红包 / 橙色强调
  static const orangePop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AmoreBrand.orangeVivid, AmoreBrand.warmOrange],
  );
}

/// ===== 语义色板（浅/深两套）=====
class APalette {
  final Brightness brightness;
  final Color bg; // 页面背景
  final Color card; // 卡片背景
  final Color cardBorder; // 分割线 / 卡片描边
  final Color textPrimary; // 主标题 #1D1D1F
  final Color textSecondary; // 次级文字 #86868B
  final Color textFaint; // 辅助文字 #AEAEB2
  final Color bubbleOther; // 对方气泡
  final Color inputBg; // 输入框填充
  final Color barBg; // 导航/底栏玻璃底色
  final Color shadow; // 阴影基色
  final Color overlayGlass; // 玻璃填充

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
    cardBorder: Color(0xFF232B40),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFF9AA3BC),
    textFaint: Color(0xFF5A647E),
    bubbleOther: Color(0xFF1C2333),
    inputBg: Color(0xFF0C111C),
    barBg: Color(0xE6101520),
    shadow: Color(0x33000000),
    overlayGlass: Color(0xB8141A29),
  );
}

/// ===== 主题入口 =====
class AmoreTheme {
  AmoreTheme._();

  // ---- 兼容旧代码的浅色常量（页面静态引用）----
  static const bg = Color(0xFFF5F5F7);
  static const card = Colors.white;
  static const cardBorder = Color(0xFFE3E3E8);
  static const textPrimary = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF86868B);
  static const textFaint = Color(0xFFAEAEB2);
  static const bubbleMe = AmoreBrand.brandBlue; // 我方气泡渐变起点
  static const bubbleMeDeep = AmoreBrand.warmOrange; // 我方气泡渐变终点
  static const bubbleOther = Color(0xFFFFFFFF);
  static const accent = AmoreBrand.orange;
  static const accent2 = AmoreBrand.brandBlue;
  static const danger = AmoreBrand.danger;
  static const success = AmoreBrand.success;
  static const warn = AmoreBrand.warn;
  static const tabBg = Color(0xF7FFFFFF);

  /// 语义色板（build 内使用，自动亮暗）
  static APalette pal(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? APalette.dark
          : APalette.light;

  // ---- 圆角 / 间距 ----
  static const rCard = 20.0; // 普通卡片 20–24
  static const rPanel = 28.0; // 大型面板 28–32
  static const rButton = 16.0; // 按钮 12–16
  static const rSmall = 12.0;
  static const gapCard = 16.0; // 卡片间距 16
  static const padH = 20.0; // 页面左右边距 20

  static ThemeData light() => _build(APalette.light);
  static ThemeData dark() => _build(APalette.dark);

  static ThemeData _build(APalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AmoreBrand.orange,
      brightness: p.brightness,
    ).copyWith(
      primary: AmoreBrand.orange,
      secondary: AmoreBrand.brandBlue,
      surface: p.card,
      surfaceContainerHighest: p.inputBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
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
                const BorderSide(color: AmoreBrand.orange, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AmoreBrand.orange,
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
                ? AmoreBrand.orange
                : p.cardBorder),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AmoreBrand.orange,
        thumbColor: Colors.white,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AmoreBrand.orange : Colors.transparent),
        side: BorderSide(color: p.cardBorder),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AmoreBrand.orange : p.textFaint),
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
          const ProgressIndicatorThemeData(color: AmoreBrand.orange),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AmoreBrand.orange.withOpacity(0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: s.contains(WidgetState.selected)
                  ? AmoreBrand.orange
                  : p.textSecondary,
            )),
        height: 62,
      ),
      chipTheme: ChipThemeData(
        selectedColor: AmoreBrand.orangeBg,
        labelStyle: TextStyle(fontSize: 13, color: p.textSecondary),
        secondaryLabelStyle: TextStyle(fontSize: 13, color: p.textSecondary),
        side: BorderSide(color: p.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  /// 页面柔和渐变背景（C 组合，亮暗自适应）
  static BoxDecoration pageGradient({Brightness? brightness}) {
    final dark = brightness == Brightness.dark;
    return BoxDecoration(
      gradient: dark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFFF2F2F7), const Color(0xFFF5F5F7)],
            )
          : AmoreGradients.softPage,
    );
  }

  /// 白色圆角卡片（柔和阴影）
  static BoxDecoration cardBox(
      {Brightness? brightness, Color? color, Color? border, double radius = rCard}) {
    final dark = brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? (dark ? APalette.dark.card : Colors.white),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
          color: border ?? (dark ? APalette.dark.cardBorder : const Color(0xFFECECF0)),
          width: 0.8),
      boxShadow: [
        BoxShadow(
            color: dark ? const Color(0x33000000) : const Color(0x0F1D1D1F),
            blurRadius: 16,
            offset: const Offset(0, 4)),
      ],
    );
  }

  /// 品牌渐变装饰（主按钮 / 重点卡）
  static BoxDecoration brandBox({double radius = rButton, List<Color>? colors}) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? const [AmoreBrand.brandBlue, AmoreBrand.brandBlueLight, AmoreBrand.orange],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: AmoreBrand.brandBlue.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      );

  static LinearGradient accentGradient(
          {Alignment begin = Alignment.topLeft, Alignment end = Alignment.bottomRight}) =>
      AmoreGradients.brand;

  static TextStyle sectionLabel() => const TextStyle(
      color: Color(0xFF86868B),
      fontSize: 12.5,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w500);

  static TextStyle title() => const TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF1D1D1F));

  /// 通用列表项卡片（白卡 + 橙色图标底）
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
    final c = iconColor ?? AmoreBrand.orange;
    final gradientIcon = iconColor == null; // 默认重点项用渐变图标底
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: cardBox(brightness: p.brightness, radius: 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: gradientIcon ? AmoreGradients.clear : null,
                color: gradientIcon ? null : c.withOpacity(0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: gradientIcon ? Colors.white : c, size: 20),
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

  /// 文字头像（彩色渐变圆）
  static Widget avatar(String name, {double size = 44}) {
    final hue = (name.hashCode.abs() % 360).toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.62, 0.58).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.65, 0.46).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
        boxShadow: [
          BoxShadow(color: c2.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3)),
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
}

/// ===== Liquid Glass 容器 =====
/// 半透明白 + 背景模糊 + 白色高光描边 + 低强度阴影。
/// 只用于导航栏 / 底栏 / 悬浮按钮 / 少量重点卡片。
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
    this.blur = 18,
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
              color: light ? Colors.white.withOpacity(0.85) : Colors.white.withOpacity(0.10),
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

/// ===== 按压缩放反馈 =====
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressScale;

  const PressableScale(
      {super.key, required this.child, this.onTap, this.pressScale = 0.97});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// ===== 主按钮（蓝橙渐变）=====
class BrandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  const BrandButton(
      {super.key, required this.label, this.onPressed, this.icon, this.height = 50});

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
}
