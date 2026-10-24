import 'dart:async';
// Amore — 工作流对话页（与聊天界面分开：目标输入 → 分步执行 → 总结 → 历史回看）
import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/theme.dart';
import '../core/workflow_engine.dart';
import '../ui/effects.dart';
import '../ui/micro.dart';
import '../widgets/step_detail_sheet.dart';

class WorkflowPage extends StatefulWidget {
  final WorkflowSession? viewSession; // null = 新建运行模式
  final String? initialGoal; // 工作包预设目标（预填输入框）
  const WorkflowPage({super.key, this.viewSession, this.initialGoal});

  @override
  State<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends State<WorkflowPage> {
  final _goalCtl = TextEditingController(
      text: '帮我做一次本地数据体检');
  late final WorkflowEngine _engine;
  Timer? _tickTimer;
  Duration _remaining = const Duration(minutes: 5);

  static const _presets = [
    '本地数据体检',
    '深度分析我的聊天记录',
    '起草一篇长文',
    '制定一周生活规划',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialGoal != null && widget.initialGoal!.isNotEmpty) {
      _goalCtl.text = widget.initialGoal!;
    }
    _engine = WorkflowEngine();
    if (widget.viewSession != null) {
      // 回看模式：展示历史
      _engine.current = widget.viewSession;
    }
    _engine.addListener(_onEngineChange);
  }

  void _onEngineChange() {
    if (_engine.running && _tickTimer == null) {
      _remaining = const Duration(minutes: 5);
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!_engine.running) {
          t.cancel();
          _tickTimer = null;
          if (mounted) setState(() {});
          return;
        }
        setState(() {
          _remaining -= const Duration(seconds: 1);
          if (_remaining.inSeconds <= 0) _remaining = const Duration(minutes: 5);
        });
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _engine.removeListener(_onEngineChange);
    super.dispose();
  }

  bool get _viewOnly => widget.viewSession != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_viewOnly ? '工作流 · 回看' : '工作流对话',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部计时小条（运行中显示；点击展开操作卡片；离开此页自动收起）
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 4),
                  child: TimerBar(
                    running: _engine.running,
                    remaining: _remaining,
                    onCancel: () => _engine.cancel(),
                    onOpen: () => _showStepSheet(),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _engine,
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: _viewOnly ? _viewBody() : _runBody(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: 新建运行模式

  List<Widget> _runBody() {
    final s = _engine.current;
    return [
      // 目标输入
      Container(
        padding: const EdgeInsets.all(14),
        decoration: AmoreTheme.cardBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('工作流目标',
                style: TextStyle(
                    color: Color(0xFF86868B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _goalCtl,
              maxLines: 2,
              enabled: !_engine.running,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                  hintText: '例如：帮我做一次本地数据体检',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in _presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p, style: const TextStyle(fontSize: 12.5)),
                        selected: _goalCtl.text == p,
                        onSelected: (_) => setState(() => _goalCtl.text = p),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // 运行按钮
      if (!_engine.running && (s == null || s.steps.isEmpty))
        BrandButton(
          label: '开始执行工作流',
          icon: Icons.play_arrow_rounded,
          onPressed: () {
            final goal = _goalCtl.text.trim();
            if (goal.isEmpty) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('请输入目标')));
              return;
            }
            _engine.run(goal: goal);
          },
        ),
      if (_engine.running)
        Center(
          child: TextButton.icon(
            onPressed: () => _engine.cancel(),
            icon: const Icon(Icons.stop_circle_outlined,
                color: Color(0xFFFF3B30)),
            label:
                const Text('取消执行', style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ),

      if (_engine.error != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12)),
          child: Text(_engine.error!,
              style:
                  const TextStyle(fontSize: 12.5, color: Color(0xFFFF3B30))),
        ),

      // 步骤
      if (s != null) ...[
        const SizedBox(height: 8),
        for (final step in s.steps) _stepCard(step, s),
        if (s.summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          _summaryCard(s.summary),
        ],
        if (s.finished && !s.summary.contains('已取消'))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Text('已保存到工作流历史',
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.grey.withOpacity(0.6))),
            ),
          ),
      ],
    ];
  }

  void _showStepSheet() {
    final session = _engine.current;
    if (session == null || session.steps.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      builder: (_) => StepDetailSheet(session: session),
    );
  }

  Widget _stepCard(WorkflowStep step, WorkflowSession session) {
    final (icon, color) = switch (step.status) {
      WorkflowStepStatus.pending => (
          Icons.radio_button_unchecked_rounded,
          const Color(0xFFAEAEB2)
        ),
      WorkflowStepStatus.running => (
          Icons.sync_rounded,
          const Color(0xFFFF9500)
        ),
      WorkflowStepStatus.done => (
          Icons.check_circle_rounded,
          const Color(0xFF34C759)
        ),
      WorkflowStepStatus.error => (
          Icons.error_rounded,
          const Color(0xFFFF3B30)
        ),
    };
    final idx = session.steps.indexOf(step) + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: AmoreTheme.cardBox(radius: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet(
            context: context,
            builder: (_) => StepDetailSheet(
                session: session, initialIndex: idx - 1)),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              if (step.status == WorkflowStepStatus.running)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('第 $idx 步 · ${step.title}',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(step.detail,
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF86868B))),
          if (step.output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10)),
                child: SelectableText(step.output,
                    style: const TextStyle(fontSize: 12.5, height: 1.5)),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _summaryCard(String summary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AmoreBrand.orange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.summarize_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('最终报告',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            CopyButton(text: summary, color: Colors.white),
          ]),
          const SizedBox(height: 8),
          SelectableText(summary,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13.5, height: 1.55)),
        ],
      ),
    );
  }

  // MARK: 回看模式

  List<Widget> _viewBody() {
    final s = _engine.current!;
    return [
      SharedHero(
        tag: 'wf-${s.id}',
        isDetail: true,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AmoreTheme.cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.goal,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('完成于 ${s.createdAt.toString().substring(0, 19)}',
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFFAEAEB2))),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      ...s.steps.map((st) => _stepCard(st, s)),
      if (s.summary.isNotEmpty) ...[
        const SizedBox(height: 12),
        _summaryCard(s.summary),
      ],
    ];
  }
}
