// Amore 微交互组件库（8 项交互落地）
// 1 TimerBar  2 StepSheet  3 深色圆形扩散  4 滑动背景块底栏  5 滚动感知 FAB
// 6 CopyButton  7 ErrorTextField  8 CenterDropdown
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

// ============ 1. 顶部计时小条 ============
/// 收起：横向小胶囊显示 mm:ss；离开页面（拖出/失去焦点）撑开显示剩余时间；
/// 点击展开操作卡片；数秒无操作自动收回。
class TimerBar extends StatefulWidget {
  final Duration remaining;
  final VoidCallback? onCancel;
  final VoidCallback? onOpen; // 展开操作卡片回调
  final bool running;

  const TimerBar({
    super.key,
    required this.remaining,
    required this.running,
    this.onCancel,
    this.onOpen,
  });

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar> {
  bool _expanded = false;

  String get _mmss {
    final s = widget.remaining.inSeconds.clamp(0, 359999);
    final m = s ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.running) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE3E3E8)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _expanded
              ? Row(
                  key: const ValueKey('exp'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 15, color: AmoreBrand.orange),
                    const SizedBox(width: 6),
                    Text('剩余 $_mmss',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 8),
                    TextButton(
                        onPressed: () {
                          setState(() => _expanded = false);
                          widget.onOpen?.call();
                        },
                        child: const Text('详情',
                            style: TextStyle(fontSize: 12))),
                    TextButton(
                        onPressed: () {
                          setState(() => _expanded = false);
                          widget.onCancel?.call();
                        },
                        child: const Text('取消',
                            style:
                                TextStyle(fontSize: 12, color: Color(0xFFFF3B30))),
                      ),
                  ],
                )
              : Row(
                  key: const ValueKey('col'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.timer_outlined,
                        size: 14, color: AmoreBrand.orange),
                    const SizedBox(width: 5),
                    Text(_mmss,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 10),
                  ],
                ),
        ),
      ),
    );
  }
}

// ============ 6. 复制按钮 ============
/// 点击图标翻转成对勾 + 「已复制」提示，1 秒后自动复原
class CopyButton extends StatefulWidget {
  final String text;
  final Color? color;
  final double size;

  const CopyButton({super.key, required this.text, this.color, this.size = 18});

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  bool _copied = false;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    HapticFeedback.selectionClick();
    _flip.forward();
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已复制'),
        duration: const Duration(milliseconds: 800)));
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _copied = false);
      _flip.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final angle = _flip.value * 3.14159; // π 翻转
          final showCheck = _flip.value > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(angle)
              ..setEntry(3, 2, -0.001), // 透视
            child: showCheck
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(3.14159),
                    child: Icon(Icons.check_rounded,
                        size: widget.size, color: const Color(0xFF34C759)),
                  )
                : Icon(Icons.copy_rounded,
                    size: widget.size,
                    color: widget.color ?? const Color(0xFF86868B)),
          );
        },
      ),
    );
  }
}

// ============ 7. 表单错误输入框 ============
/// 出错时轻晃 + 边框变红 + 提示从下方滑入；修正后收起
class ErrorTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? errorText; // 非空 = 出错
  final ValueChanged<String>? onChanged;
  final int maxLines;

  const ErrorTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.errorText,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<ErrorTextField> createState() => _ErrorTextFieldState();
}

class ErrorTextFieldState extends State<ErrorTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));
  bool _hasError = false;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void triggerError() {
    _shake.forward(from: 0);
    setState(() => _hasError = true);
  }

  void clearError() {
    if (_hasError) setState(() => _hasError = false);
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            // 衰减正弦轻晃
            final t = _shake.value;
            final decay = (1 - t) * 8;             // 衰减幅度
            final dx = decay * _shakeSignal(t);    // 左右交替
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: TextField(
            controller: widget.controller,
            maxLines: widget.maxLines,
            onChanged: (v) {
              widget.onChanged?.call(v);
              if (v.trim().isNotEmpty) clearError();
            },
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.hint,
              filled: true,
              fillColor: const Color(0xFFF2F2F7),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: _hasError
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFFE3E3E8),
                      width: _hasError ? 1.4 : 1)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: _hasError
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFFE3E3E8))),
            ),
          ),
        ),
        // 错误提示从下方滑入
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: (err != null && err.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.only(left: 4, top: 5),
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, 0.4), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: _shake, curve: Curves.easeOut)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 13, color: Color(0xFFFF3B30)),
                      const SizedBox(width: 4),
                      Text(err,
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFFFF3B30))),
                    ]),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  double _shakeSignal(double t) {
    // 前 60% 时间左右交替 4 次，之后归零
    if (t > 0.6) return 0;
    return (t * 13.3).floor() % 2 == 0 ? -1.0 : 1.0;
  }
}

// ============ 8. 以选中项为中心的下拉选择框 ============
/// 展开时自动滚动到当前选中项（居中），选中后收回更新文字
class CenterDropdown extends StatefulWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final String hint;
  final double height;

  const CenterDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.hint = '',
    this.height = 46,
  });

  @override
  State<CenterDropdown> createState() => _CenterDropdownState();
}

class _CenterDropdownState extends State<CenterDropdown> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  late String _value = widget.value;

  void _toggle() {
    if (_controller.isShowing) {
      _controller.hide();
    } else {
      _controller.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) {
        final box = context.findRenderObject() as RenderBox;
        final pos = box.localToGlobal(Offset.zero);
        final menuHeight = (widget.options.length * 44.0 + 12)
            .clamp(120.0, 280.0);
        // 以当前选中项为中心对齐：优先在下方展开，空间不足时向上
        final below = MediaQuery.of(context).size.height - pos.dy - box.size.height;
        final openUp = below < menuHeight + 12;
        return Stack(children: [
          // 点击遮罩关闭
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: Container(color: Colors.black.withOpacity(0.01)),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
              child: _MenuList(
                options: widget.options,
                value: _value,
                menuHeight: menuHeight,
                onSelected: (v) {
                  setState(() => _value = v);
                  _controller.hide();
                  widget.onSelected(v);
                },
              ),
            ),
          ),
        ]);
      },
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          onTap: () {
            _value = widget.value;
            _toggle();
          },
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.value.isEmpty ? widget.hint : widget.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                AnimatedRotation(
                  turns: _controller.isShowing ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.expand_more_rounded,
                      size: 18, color: Color(0xFF86868B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuList extends StatelessWidget {
  final List<String> options;
  final String value;
  final double menuHeight;
  final ValueChanged<String> onSelected;

  const _MenuList(
      {required this.options,
      required this.value,
      required this.menuHeight,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final controller = ScrollController(
        initialScrollOffset: _initialOffset(options, value));
    return SizedBox(
      width: 260,
      height: menuHeight,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: options.length,
        itemBuilder: (_, i) {
          final selected = options[i] == value;
          return InkWell(
            onTap: () => onSelected(options[i]),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              color: selected ? AmoreBrand.orangeBg : Colors.transparent,
              child: Row(children: [
                Expanded(
                    child: Text(options[i],
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? AmoreBrand.orangeDeep
                                : const Color(0xFF1D1D1F)))),
                if (selected)
                  const Icon(Icons.check_rounded,
                      size: 16, color: AmoreBrand.orange),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// 选中项滚动到列表中心
  double _initialOffset(List<String> options, String value) {
    final idx = options.indexOf(value);
    if (idx < 0) return 0;
    final itemH = 42.0;
    final viewport = menuHeight - 12;
    final target = idx * itemH + itemH / 2 - viewport / 2;
    return target.clamp(0.0, options.length * itemH);
  }
}

// ============ 5. 滚动感知悬浮按钮 ============
/// 向下滚动收缩成圆形图标，向上滚动展开带文字胶囊
class ExpandableFAB extends StatefulWidget {
  final ScrollController scrollController;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const ExpandableFAB({
    super.key,
    required this.scrollController,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<ExpandableFAB> createState() => _ExpandableFABState();
}

class _ExpandableFABState extends State<ExpandableFAB> {
  bool _expanded = true;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final off = widget.scrollController.offset;
    if (off > _lastOffset + 4 && _expanded) {
      setState(() => _expanded = false); // 下滑收缩
    } else if (off < _lastOffset - 4 && !_expanded) {
      setState(() => _expanded = true); // 上滑展开
    }
    _lastOffset = off;
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: _expanded ? 18 : 0),
        decoration: BoxDecoration(
          color: AmoreBrand.orange,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
                color: AmoreBrand.orange.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            Icon(widget.icon, color: Colors.white, size: 22),
            // 文字宽度动画展开/收起
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(widget.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
