// Amore — 工作流引擎（Codex 风格：plan → 逐步执行（可调本地工具）→ summarize）
// 编排纯 Dart（直连用户配置的 AI 供应商）；工具执行走 Rust Core（chat.exec_tool）。
// 历史持久化：AmoreStore config 'workflow.sessions'（最近 20 个）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'chat_engine.dart';
import 'models.dart';
import 'store.dart';

enum WorkflowStepStatus { pending, running, done, error }

class WorkflowStep {
  final String title;
  final String detail;
  WorkflowStepStatus status;
  String output;

  WorkflowStep({
    required this.title,
    required this.detail,
    this.status = WorkflowStepStatus.pending,
    this.output = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'status': status.name,
        'output': output,
      };

  factory WorkflowStep.fromJson(Map<String, dynamic> j) => WorkflowStep(
        title: (j['title'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        status: WorkflowStepStatus.values
            .firstWhere((s) => s.name == j['status'],
                orElse: () => WorkflowStepStatus.pending),
        output: (j['output'] ?? '').toString(),
      );
}

class WorkflowSession {
  String id;
  String goal;
  DateTime createdAt;
  List<WorkflowStep> steps;
  String summary;
  bool finished;

  WorkflowSession({
    required this.goal,
    String? id,
    DateTime? createdAt,
    List<WorkflowStep>? steps,
    this.summary = '',
    this.finished = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        createdAt = createdAt ?? DateTime.now(),
        steps = steps ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'steps': steps.map((s) => s.toJson()).toList(),
        'summary': summary,
        'finished': finished,
      };

  factory WorkflowSession.fromJson(Map<String, dynamic> j) => WorkflowSession(
        id: (j['id'] ?? '').toString(),
        goal: (j['goal'] ?? '').toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((j['createdAt'] as num?) ?? 0).toInt()),
        steps: ((j['steps'] ?? []) as List)
            .map((s) => WorkflowStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        summary: (j['summary'] ?? '').toString(),
        finished: j['finished'] as bool? ?? false,
      );
}

/// 状态中枢：当前运行中的工作流 + 历史列表
class WorkflowEngine extends ChangeNotifier {
  WorkflowSession? current;
  bool running = false;
  bool cancelRequested = false;
  String? error;

  List<WorkflowSession> _sessions = [];

  List<WorkflowSession> get sessions => _sessions;

  WorkflowEngine() {
    _loadSessions();
  }

  // MARK: 持久化

  void _loadSessions() {
    try {
      final raw = AmoreStore.getConfig('workflow.sessions');
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((j) => WorkflowSession.fromJson(j as Map<String, dynamic>))
            .toList();
        _sessions = list;
      }
    } catch (_) {
      _sessions = [];
    }
  }

  void _persist() {
    // 只保留最近 20 个已完成的
    final done = _sessions.where((s) => s.finished).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (done.length > 20) done.removeRange(20, done.length);
    AmoreStore.setConfig(
        'workflow.sessions', jsonEncode(done.map((s) => s.toJson()).toList()));
  }

  void saveSession(WorkflowSession s) {
    _sessions.removeWhere((x) => x.id == s.id);
    _sessions.insert(0, s);
    _persist();
    notifyListeners();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    _persist();
    notifyListeners();
  }

  // MARK: 运行

  void cancel() {
    cancelRequested = true;
  }

  /// 运行完整工作流：plan → execute（每步最多 2 轮工具）→ summarize
  Future<void> run({required String goal}) async {
    if (running) return;
    running = true;
    cancelRequested = false;
    error = null;
    current = WorkflowSession(goal: goal);
    notifyListeners();

    try {
      // ---------- PLAN ----------
      final planSystem = '你是工作流规划器。把用户目标拆解为 3~6 个可执行步骤。'
          '只输出 JSON 数组：[{"title":"步骤名","detail":"怎么做"}]，不要其它文字。';
      final planRaw = await ChatEngine.request(
        _providerOrThrow(),
        [
          {'role': 'user', 'content': goal}
        ],
        planSystem,
      );
      final steps = _parseSteps(planRaw, fallbackGoal: goal);
      current!.steps = steps;
      notifyListeners();

      // ---------- EXECUTE ----------
      final digest = <String>[];
      for (var i = 0; i < steps.length; i++) {
        if (cancelRequested) break;
        steps[i].status = WorkflowStepStatus.running;
        notifyListeners();

        final sys = '你是工作流执行器，正在执行多步骤任务「${current!.goal}」的第 ${i + 1}/${steps.length} 步。'
            '已完成步骤的结论摘要：\n${digest.isEmpty ? "（无，这是第一步）" : digest.join("\n")}\n\n'
            '输出本步骤的执行结果（结论式、精炼、中文）。${AmoreStore.toolsGuide()}';
        final user = '步骤：${steps[i].title}\n${steps[i].detail}';

        var output = '';
        var feedback = '';
        for (var round = 0; round < 2; round++) {
          final msgs = <Map<String, String>>[
            if (feedback.isNotEmpty) {'role': 'tool', 'content': feedback},
            {'role': 'user', 'content': user},
          ];
          final reply = await ChatEngine.request(_providerOrThrow(), msgs, sys);
          final parsed = AmoreStore.parseAssistant(reply);
          output = parsed.clean;

          if (parsed.feedback == null || parsed.called.isEmpty) break;
          // 本地工具执行（Rust Core）
          for (final c in parsed.called) {
            AmoreStore.execTool(c.name, c.params);
          }
          feedback = parsed.feedback!;
        }

        steps[i].status = WorkflowStepStatus.done;
        steps[i].output = output.isEmpty ? '（无输出）' : output;
        digest.add('${steps[i].title}：${_digestOf(output)}');
        notifyListeners();
      }

      // ---------- SUMMARIZE ----------
      if (!cancelRequested) {
        final sumSys = '你是工作流总结器。把以下各步骤结论汇总为 300 字内的最终报告（中文，分点）。';
        final sumUser = steps
            .map((s) => '【${s.title}】\n${s.output}')
            .join('\n\n');
        try {
          current!.summary =
              await ChatEngine.request(_providerOrThrow(), [
                {'role': 'user', 'content': sumUser}
              ], sumSys);
        } catch (_) {
          current!.summary = digest.join('\n');
        }
      } else {
        current!.summary = '（已取消）';
      }

      current!.finished = true;
      saveSession(current!);
    } catch (e) {
      error = e.toString();
      if (current != null) {
        current!.summary = '执行失败：$error';
        current!.finished = true;
        saveSession(current!);
      }
    } finally {
      running = false;
      notifyListeners();
    }
  }

  AIProvider _providerOrThrow() {
    final p = ChatEngine.providerForGlobal();
    if (p == null) {
      throw Exception('尚未配置 AI 模型：请到「我的 → 模型配置」添加并激活一个供应商。');
    }
    return p;
  }

  /// 解析 plan JSON（容错：截取 [ ... ]）
  List<WorkflowStep> _parseSteps(String raw, {required String fallbackGoal}) {
    try {
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start >= 0 && end > start) {
        final list = jsonDecode(raw.substring(start, end + 1));
        if (list is List && list.isNotEmpty) {
          return list
              .take(6)
              .map((e) {
                final m = e as Map;
                return WorkflowStep(
                  title: (m['title'] ?? m['步骤'] ?? '步骤').toString(),
                  detail: (m['detail'] ?? m['说明'] ?? '').toString(),
                );
              })
              .toList();
        }
      }
    } catch (_) {}
    // 降级：两步
    return [
      WorkflowStep(title: '分析', detail: '分析「$fallbackGoal」所需的信息与方法'),
      WorkflowStep(title: '执行与结论', detail: '执行并给出最终结论'),
    ];
  }

  String _digestOf(String output) {
    final clean = output.replaceAll('\n', ' ').trim();
    return clean.length <= 120 ? clean : '${clean.substring(0, 120)}…';
  }
}
