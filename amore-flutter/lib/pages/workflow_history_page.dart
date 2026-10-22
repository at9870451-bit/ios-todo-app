// Amore — 工作流历史列表（从对话 Tab 进入；ExpandableFAB 新建工作流）
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/workflow_engine.dart';
import '../ui/effects.dart';
import '../ui/micro.dart';
import 'workflow_page.dart';

class WorkflowHistoryPage extends StatefulWidget {
  const WorkflowHistoryPage({super.key});

  @override
  State<WorkflowHistoryPage> createState() => _WorkflowHistoryPageState();
}

class _WorkflowHistoryPageState extends State<WorkflowHistoryPage> {
  final _engine = WorkflowEngine();
  final _scroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    final sessions = _engine.sessions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流对话',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.account_tree_outlined,
                          size: 60, color: Color(0xFFAEAEB2)),
                      SizedBox(height: 14),
                      Text('还没有工作流对话',
                          style:
                              TextStyle(color: Color(0xFF86868B), fontSize: 15)),
                      SizedBox(height: 6),
                      Text('工作流会把目标拆解为多个步骤逐步执行',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFFAEAEB2), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    return StaggerItem(
                      index: i,
                      child: SharedHero(
                        tag: 'wf-${s.id}',
                        child: AmoreTheme.tile(
                          context: context,
                          icon: Icons.account_tree_rounded,
                          iconColor: AmoreBrand.orange,
                          title: s.goal,
                          subtitle: s.finished
                              ? '已完成 · ${s.steps.length} 步'
                              : '进行中',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      WorkflowPage(viewSession: s))),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19, color: Color(0xFFFF3B30)),
                            onPressed: () => setState(
                                () => _engine.deleteSession(s.id)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: ExpandableFAB(
        scrollController: _scroll,
        icon: Icons.add_rounded,
        label: '新建工作流',
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const WorkflowPage())),
      ),
    );
  }
}
