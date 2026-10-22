// Amore Interaction Effects — 交互动效组件库
// #1 TiltReflectCard 3D 触摸倾斜 + 径向反射流光（Spring 回正）
// #2 FluidMorph    胶囊→面板流体形态变换
// #3 SharedHero    共享元素转场（连续缩放）
// #4 SnapLineChart 折线图磁吸 + 滚动计数器
// #5 BounceSheet   阻尼橡皮筋底部抽屉（速度吸附锚点）
// #6 AuraCard      旋转渐变描边 + 呼吸弥散背光
// #7 StaggerItem   交错入场弹性上滑
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// ===== #7 交错入场：每个子项带微弱弹性向上滑入 =====
class StaggerItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration step;

  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 55),
  });

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 560));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.step * widget.index, () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_ctl.value);
        return Opacity(
          opacity: _ctl.value.clamp(0.0, 1.0),
          child: Transform.translate(
              offset: Offset(0, 26 * (1 - t)), child: child),
        );
      },
    );
  }
}

/// ===== #1 3D 触摸倾斜卡 + 径向反射流光，松手 Spring 阻尼回正 =====
class TiltReflectCard extends StatefulWidget {
  final Widget child;
  final double maxTilt;
  final BorderRadius? radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool reflect;

  const TiltReflectCard({
    super.key,
    required this.child,
    this.maxTilt = 0.20,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.reflect = true,
  });

  @override
  State<TiltReflectCard> createState() => _TiltReflectCardState();
}

class _TiltReflectCardState extends State<TiltReflectCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this)
    ..duration = const Duration(milliseconds: 480);
  late final Animation<double> _settle = _ctl.drive(TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
  ]));

  double _rx = 0, _ry = 0;
  Offset _spot = Offset.zero;
  bool _down = false;
  Size _size = Size.zero;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onMove(Offset local, {required bool down}) {
    if (_size.width <= 0) return;
    final dx = (local.dx / _size.width - 0.5) * 2;
    final dy = (local.dy / _size.height - 0.5) * 2;
    setState(() {
      _down = down;
      _rx = (down ? -dy : _rx * 0.6) * widget.maxTilt;
      _ry = (down ? dx : _ry * 0.6) * widget.maxTilt;
      _spot = Offset(dx, dy);
    });
  }

  void _release() {
    if (!_down) return;
    _ctl.forward(from: 0);
    setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (d) => _onMove(d.localPosition, down: true),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        onPanDown: (d) => _onMove(d.localPosition, down: true),
        onPanUpdate: (d) => _onMove(d.localPosition, down: true),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ctl, _settle]),
          builder: (context, child) {
            final s = _settle.value;
            final rx = _rx * (1 - s);
            final ry = _ry * (1 - s);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(rx)
                ..rotateY(ry),
              child: child,
            );
          },
          child: _buildSurface(),
        ),
      );
    });
  }

  Widget _buildSurface() {
    final r = widget.radius ?? BorderRadius.circular(AmoreTheme.rCard);
    return ClipRRect(
      borderRadius: r,
      child: Stack(
        children: [
          widget.child,
          // 环境顶光（大 blur 柔光斑模拟顶面漫反射，非渐变）
          Positioned(
            left: 14,
            top: 10,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(_down ? 0.22 : 0.10),
                    blurRadius: 34,
                    spreadRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          // 跟随手指的径向反射光斑
          if (_down)
            Positioned(
              left: _spot.dx * 40 + 10,
              top: _spot.dy * 40 + 10,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.16),
                      blurRadius: 46,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}/// ===== #2 胶囊按钮 → 弹窗面板 流体形态变换 =====
/// 高阻尼流体曲线（快起缓收），尺寸与圆角无缝过渡。
class FluidMorph extends StatefulWidget {
  final Widget collapsed;
  final Widget expanded;
  final bool expanded_;
  final VoidCallback? onCollapsedTap;
  final VoidCallback? onExpandedTap;
  final double radius;

  const FluidMorph({
    super.key,
    required this.collapsed,
    required this.expanded,
    required this.expanded_,
    this.onCollapsedTap,
    this.onExpandedTap,
    this.radius = 24,
  });

  @override
  State<FluidMorph> createState() => _FluidMorphState();
}

class _FluidMorphState extends State<FluidMorph> {
  // 高阻尼流体曲线：启动快、收尾慢
  static const _fluid = Cubic(0.30, 0.86, 0.25, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 460),
      curve: _fluid,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: _fluid,
        switchOutCurve: _fluid,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: widget.expanded_
            ? GestureDetector(
                key: const ValueKey('morph-expanded'),
                onTap: widget.onExpandedTap,
                child: widget.expanded,
              )
            : GestureDetector(
                key: const ValueKey('morph-collapsed'),
                onTap: widget.onCollapsedTap,
                child: widget.collapsed,
              ),
      ),
    );
  }
}/// ===== #6 旋转渐变描边 + 呼吸弥散背光 =====
/// 旋转描边为唯一渐变元素（用户交互建议 #6 指定，仅装饰光效）。
class AuraCard extends StatefulWidget {
  final Widget child;
  final double radius;
  final Color auraColor;
  final double borderWidth;

  const AuraCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.auraColor = const Color(0xFF007AFF),
    this.borderWidth = 1.6,
  });

  @override
  State<AuraCard> createState() => _AuraCardState();
}

class _AuraCardState extends State<AuraCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(seconds: 5))
    ..repeat();
  late final AnimationController _breathe = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _breathe]),
      builder: (context, child) {
        final breath = 0.55 + 0.45 * _breathe.value;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 呼吸弥散背光（blur 随呼吸振荡）
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r + 6),
                boxShadow: [
                  BoxShadow(
                    color: widget.auraColor.withOpacity(0.30 * breath),
                    blurRadius: 26 * breath,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: widget.auraColor.withOpacity(0.14 * breath),
                    blurRadius: 52 * breath,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            // 主体 + 旋转渐变描边
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r),
                border: Border.all(
                  color: widget.auraColor.withOpacity(0.22),
                  width: widget.borderWidth,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(r),
                child: Stack(
                  children: [
                    child,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _AuraBorderPainter(
                            radius: r,
                            progress: _spin.value,
                            color: widget.auraColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _AuraBorderPainter extends CustomPainter {
  final double radius;
  final double progress;
  final Color color;

  _AuraBorderPainter({
    required this.radius,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.clipPath(Path()..addRRect(rr));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(progress * math.pi * 2);
    canvas.translate(-size.width / 2, -size.height / 2);
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.9),
          color.withOpacity(0.0),
          color.withOpacity(0.0),
        ],
        stops: const [0.0, 0.14, 0.34, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(rr.deflate(1.5), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AuraBorderPainter old) =>
      old.progress != progress || old.color != color;
}/// ===== #5 阻尼橡皮筋回弹底部抽屉，松手按速度吸附锚点 =====
class BounceSheet extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDismiss;

  const BounceSheet({super.key, required this.child, this.onDismiss});

  static Future<void> show(BuildContext context, Widget child,
      {VoidCallback? onDismiss, Color barrierColor = const Color(0x66000000)}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: barrierColor,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, _, __) => BounceSheet(child: child, onDismiss: onDismiss),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  State<BounceSheet> createState() => _BounceSheetState();
}

class _BounceSheetState extends State<BounceSheet>
    with SingleTickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _spring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _settle = _spring.drive(
      Tween<double>(begin: 1, end: 0)
          .chain(CurveTween(curve: Curves.easeOutCubic)));

  void _onUpdate(DragUpdateDetails d) {
    final raw = _drag + d.delta.dy;
    setState(() => _drag = raw > 0 ? raw * 0.38 : raw * 0.5);
  }

  void _onEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final beyond = _drag > 0;
    if (v > 700 || (beyond && _drag > 90)) {
      _spring.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) Navigator.of(context).pop();
        widget.onDismiss?.call();
      });
    } else {
      _spring.forward(from: 0);
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onUpdate,
        onVerticalDragEnd: _onEnd,
        child: AnimatedBuilder(
          animation: _spring,
          builder: (context, child) {
            final oy = _drag * (1 - _settle.value);
            return Transform.translate(
                offset: Offset(0, oy.clamp(-400.0, 900.0)), child: child);
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 28,
                      offset: const Offset(0, -6)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D1D6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    widget.child,
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}/// ===== #4 折线图：横向滑动数据点磁吸吸附 + 顶部滚动计数器 =====
class SnapLineChart extends StatefulWidget {
  final List<double> values;
  final List<String>? labels;
  final double height;
  final Color lineColor;
  final Color dotColor;

  const SnapLineChart({
    super.key,
    required this.values,
    this.labels,
    this.height = 140,
    this.lineColor = const Color(0xFF007AFF),
    this.dotColor = const Color(0xFF007AFF),
  });

  @override
  State<SnapLineChart> createState() => _SnapLineChartState();
}class _SnapLineChartState extends State<SnapLineChart> {
  double _index = 0;
  List<double> _data = const [];

  @override
  void initState() {
    super.initState();
    _data = List.of(widget.values);
  }

  @override
  void didUpdateWidget(covariant SnapLineChart old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length) {
      _data = List.of(widget.values);
    }
  }

  void _snapTo(int i) => setState(() => _index = i.toDouble());

  @override
  Widget build(BuildContext context) {
    if (_data.length < 2) {
      return SizedBox(
          height: widget.height, child: const Center(child: Text('暂无数据')));
    }
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = widget.height;
      final n = _data.length;
      final minV = _data.reduce(math.min);
      final maxV = _data.reduce(math.max);
      final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
      final stepX = w / (n - 1);
      double px(double i) => i * stepX;
      double py(double v) => h - 24 - ((v - minV) / range) * (h - 44);

      return Column(
        children: [
          _CounterText(
              value: _data[_index.clamp(0, n - 1).round()],
              color: widget.lineColor),
          const SizedBox(height: 6),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                final dx = d.localPosition.dx;
                setState(() => _index = (dx / stepX).clamp(0, n - 1));
              },
              onHorizontalDragEnd: (_) => _snapTo(_index.round()),
              onTapDown: (d) => _snapTo(
                  (d.localPosition.dx / stepX).clamp(0, n - 1).round()),
              child: CustomPaint(
                size: Size(w, h),
                painter: _ChartPainter(
                  data: _data,
                  idx: _index,
                  px: px,
                  py: py,
                  lineColor: widget.lineColor,
                  dotColor: widget.dotColor,
                ),
              ),
            ),
          ),
          if (widget.labels != null && widget.labels!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final l in widget.labels!)
                    Text(l,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> data;
  final double idx;
  final double Function(double) px;
  final double Function(double) py;
  final Color lineColor;
  final Color dotColor;

  _ChartPainter({
    required this.data,
    required this.idx,
    required this.px,
    required this.py,
    required this.lineColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 图表填充面（数据可视化内部渐变，非 UI 装饰）
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.16), lineColor.withOpacity(0.0)],
      ).createShader(Offset.zero & size);

    final path = Path()..moveTo(px(0), py(data[0]));
    for (var i = 1; i < data.length; i++) {
      path.lineTo(px(i), py(data[i]));
    }
    final fillPath = Path.from(path)
      ..lineTo(px(data.length - 1), size.height)
      ..lineTo(px(0), size.height)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);

    final dot = Paint()..color = dotColor;
    for (var i = 0; i < data.length; i++) {
      canvas.drawCircle(
          Offset(px(i), py(data[i])), i == idx.round() ? 6 : 3.5, dot);
    }
    final ci = idx.clamp(0, data.length - 1).round();
    final cur = Offset(px(ci), py(data[ci]));
    canvas.drawCircle(cur, 9, Paint()..color = dotColor.withOpacity(0.18));
    canvas.drawCircle(cur, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(cur, 3.5, dot);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.idx != idx || old.data != data;
}

/// 滚动计数器：数值变化时滚动到目标整数
class _CounterText extends StatelessWidget {
  final int value;
  final Color color;

  const _CounterText({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        v.round().toString(),
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}/// ===== #3 共享元素转场（Card → 详情页连续缩放）=====
class SharedHero extends StatelessWidget {
  final Object tag;
  final Widget child;
  final BorderRadius radius;
  final bool isDetail;

  const SharedHero({
    super.key,
    required this.tag,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(20)),
    this.isDetail = false,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      createOverlayTween: (_, __) => _RectTween(),
      flightShuttleBuilder: (
        flightContext,
        animation,
        direction,
        fromContext,
        toContext,
      ) {
        final curved = CurvedAnimation(
            parent: animation, curve: Curves.easeInOutCubicEmphasized);
        return AnimatedBuilder(
          animation: curved,
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.lerp(radius, radius, curved.value)!,
            child: child,
          ),
          child: isDetail ? toContext.widget : fromContext.widget,
        );
      },
      child: child,
    );
  }
}

class _RectTween extends RectTween {
  _RectTween({super.begin, super.end});
  @override
  Rect? lerp(double t) {
    return Rect.lerp(begin, end, Curves.easeInOutCubic.transform(t));
  }
}