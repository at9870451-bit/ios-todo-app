// Amore — 分步底部弹窗：切换步骤时内容横向滑动，弹窗高度随内容平滑过渡
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/workflow_engine.dart';

class StepDetailSheet extends StatefulWidget {
  final WorkflowSession session;
  final int initialIndex;
  const StepDetailSheet({super.key, required this.session, this.initialIndex = 0});

  @override
  State<StepDetailSheet> createState() => _StepDetailSheetState();
}

class _StepDetailSheetState extends State<StepDetailSheet> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final step = s.steps[_index];
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                      color: const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 10),
              Row(children: [
                const Text('步骤详情',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_index + 1} / ${s.steps.length}',
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF86868B))),
              ]),
              const SizedBox(height: 10),
              // 横向滑动切换步骤；高度随内容平滑过渡
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                child: SizedBox(
                  height: _contentHeight(step),
                  child: PageView.builder(
                    controller: _page,
                    itemCount: s.steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) {
                      final st = s.steps[i];
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text('第 ${i + 1} 步',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AmoreBrand.orange)),
                              const SizedBox(width: 8),
                              Text(_statusText(st.status),
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: st.status ==
                                              WorkflowStepStatus.done
                                          ? const Color(0xFF34C759)
                                          : const Color(0xFF86868B))),
                            ]),
                            const SizedBox(height: 8),
                            Text(st.title,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(st.detail,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF86868B),
                                    height: 1.5)),
                            if (st.output.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF2F2F7),
                                    borderRadius:
                                        BorderRadius.circular(12)),
                                child: SelectableText(st.output,
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.55)),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < s.steps.length; i++)
                    Container(
                      width: i == _index ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AmoreBrand.orange
                            : const Color(0xFFD1D1D6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 高度随内容平滑过渡（估算：标题+详情+输出行数）
  double _contentHeight(WorkflowStep step) {
    final detailLines = (step.detail.length / 22).ceil();
    final outLines =
        step.output.isEmpty ? 0 : (step.output.length / 28).ceil();
    final h = 130.0 + detailLines * 20 + outLines * 19;
    return h.clamp(170.0, 420.0);
  }

  String _statusText(WorkflowStepStatus s) => switch (s) {
        WorkflowStepStatus.pending => '待执行',
        WorkflowStepStatus.running => '执行中',
        WorkflowStepStatus.done => '已完成',
        WorkflowStepStatus.error => '失败',
      };
}
