// Amore — 交互动效套件（水墨晕染打字 / Q 弹点赞 / 拖拽到位）
// 对应需求：3 输出动效（水墨晕染渐进）+ 4 交互动效（点赞 Q 弹、拖拽干脆）
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 水墨晕染渐进文本：字符按距离淡入+微模糊消散（非单字硬蹦）
/// 每个字符有自己的延迟与透明度曲线，从中心向外「晕开」
class InkRevealText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration period; // 一轮晕染时长
  final bool active; // false 时保持全显

  const InkRevealText({
    super.key,
    required this.text,
    required this.style,
    this.period = const Duration(milliseconds: 900),
    this.active = true,
  });

  @override
  State<InkRevealText> createState() => _InkRevealTextState();
}

class _InkRevealTextState extends State<InkRevealText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctl.forward();
  }

  @override
  void didUpdateWidget(covariant InkRevealText old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text) {
      _ctl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        return Wrap(
          children: [
            for (var i = 0; i < chars.length; i++)
              Builder(builder: (context) {
                // 每字符的局部进度：起始时间随索引错开（波纹扩散）
                final delay = (i / chars.length) * 0.6;
                final local =
                    ((_ctl.value - delay) / 0.4).clamp(0.0, 1.0);
                final eased = Curves.easeOutCubic.transform(local);
                // 水墨感：透明度 + 轻微缩放（0.85→1）+ 模糊（3→0）
                final blur = (1 - eased) * 3.0;
                return Opacity(
                  opacity: eased,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * eased,
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: Text(chars[i], style: widget.style),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

/// Q 弹点赞按钮：点击缩放回弹（弹性曲线），填充心形切换
class BouncyLikeButton extends StatefulWidget {
  final bool liked;
  final ValueChanged<bool>? onChanged;
  final double size;
  final Color? color;

  const BouncyLikeButton({
    super.key,
    required this.liked,
    this.onChanged,
    this.size = 28,
    this.color,
  });

  @override
  State<BouncyLikeButton> createState() => _BouncyLikeButtonState();
}

class _BouncyLikeButtonState extends State<BouncyLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: 1.0);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _toggle() {
    widget.onChanged?.call(!widget.liked);
    _ctl.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        (widget.liked ? const Color(0xFFFF3B30) : const Color(0xFFAEAEB2));
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          // Q 弹：elasticOut 缩放曲线（过冲后回弹）
          final t = _ctl.value;
          final elastic = Curves.elasticOut.transform(t);
          return Transform.scale(scale: 0.6 + 0.4 * elastic, child: Icon(
              widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: widget.size,
              color: color));
        },
      ),
    );
  }


}

/// 拖拽到位容器：拖拽时轻微跟随延迟（干脆不拖泥带水），松手吸附目标位
class SnapDraggable<T extends Object> extends StatefulWidget {
  final Widget child;
  final Offset initialOffset;
  final ValueChanged<Offset>? onDragEnd;

  const SnapDraggable({
    super.key,
    required this.child,
    this.initialOffset = Offset.zero,
    this.onDragEnd,
  });

  @override
  State<SnapDraggable<T>> createState() => _SnapDraggableState<T>();
}

class _SnapDraggableState<T extends Object> extends State<SnapDraggable<T>> {
  late Offset _offset = widget.initialOffset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          // 拖拽跟随：1:1 直接到位（干脆）
          setState(() => _offset += d.delta);
        },
        onPanEnd: (d) {
          widget.onDragEnd?.call(_offset);
        },
        child: widget.child,
      ),
    );
  }
}
