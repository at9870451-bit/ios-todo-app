// Amore — 深色模式切换：新主题从开关位置圆形扩散覆盖全屏，反向切换原路收回
import 'dart:ui';

import 'package:flutter/material.dart';

/// 全屏圆形揭示遮罩：用新主题色圆从 [origin]（全局坐标）扩散；
/// forward=true 扩散（切深色），false 收缩（回浅色）。动画结束回调应用主题。
class CircularRevealOverlay extends StatefulWidget {
  final Offset origin;
  final Color revealColor;   // 新主题背景色
  final bool forward;        // true=扩散 false=收缩
  final VoidCallback onDone;

  const CircularRevealOverlay({
    super.key,
    required this.origin,
    required this.revealColor,
    required this.forward,
    required this.onDone,
  });

  @override
  State<CircularRevealOverlay> createState() => _CircularRevealOverlayState();
}

class _CircularRevealOverlayState extends State<CircularRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void initState() {
    super.initState();
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _ctl.forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxR = (size.longestSide * 1.2);
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final t = widget.forward ? _ctl.value : 1 - _ctl.value;
        final radius = maxR * Curves.easeOutCubic.transform(t);
        return Stack(children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _CircleClipper(center: widget.origin, radius: radius),
              child: Container(color: widget.revealColor),
            ),
          ),
        ]);
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  _CircleClipper({required this.center, required this.radius});

  @override
  Path getClip(Path path) {
    // 全屏矩形减去圆外区域 = 只显示圆内（forward 扩散圆内是“新主题”）
    path.addRect(Rect.largest);
    path.addOval(Rect.fromCircle(center: center, radius: radius));
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius;
}
