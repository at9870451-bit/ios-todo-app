import SwiftUI

/// Codex 风格工作台：输入目标 → 自动拆解 → 逐步执行 → 汇总
struct WorkflowView: View {
    @EnvironmentObject var store: BackendStore
    @AppStorage("chat.reasoning") private var reasoning = "medium"
    @StateObject private var engine = WorkflowEngine()

    @State private var goal = ""
    @State private var persona = ""
    @State private var expanded: Set<UUID> = []

    private let presets: [(String, String, String)] = [
        ("📋 本地数据体检", "检查本机的聊天记录、好友和存储情况，给出清理与整理建议", "冷静高效的助手"),
        ("🔍 深度分析", "把一个问题拆开逐项分析，给出结论与行动建议", "理性助手"),
        ("✍️ 长文起草", "先列大纲，再逐段成稿，最后统一润色", "温柔姐姐"),
        ("🗓 生活规划", "结合当前时间做一份可执行的计划", "理性助手"),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    goalCard
                    if engine.running, let run = engine.current { progressCard(run) }
                    if !engine.running, let run = engine.current { resultCard(run) }
                    if !engine.history.isEmpty { historyCard }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle("工作流")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("给智能体一个目标").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            TextEditor(text: $goal)
                .frame(minHeight: 76)
                .font(.subheadline)
                .padding(8)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 快捷预设
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { p in
                        Button {
                            goal = p.1
                            persona = p.2
                        } label: {
                            Text(p.0)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("智能体人设（可留空）", text: $persona)
                .font(.caption)
                .padding(10)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Button {
                    start()
                } label: {
                    Label(engine.running ? "运行中…" : "开始执行", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(engine.running || goal.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.25) : Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(engine.running || goal.trimmingCharacters(in: .whitespaces).isEmpty)
                if engine.running {
                    Button {
                        engine.cancelRequested = true
                    } label: {
                        Label("取消", systemImage: "stop.circle")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(Theme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("执行链：拆解目标 → 逐步完成（可用本地工具）→ 汇总报告 · 全程在本机编排")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassPanel(18)
    }

    private func progressCard(_ run: WorkflowEngine.Run) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("执行中").font(.subheadline.weight(.semibold))
                Spacer()
                ProgressView()
            }
            ForEach(run.steps) { s in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(s.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color(s.status))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.subheadline)
                        if !s.output.isEmpty {
                            Text(s.output).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassPanel(18)
    }

    private func resultCard(_ run: WorkflowEngine.Run) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: run.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(run.ok ? Theme.ok : Theme.danger)
                Text(run.ok ? "执行完成" : "已中断").font(.subheadline.weight(.semibold))
                Spacer()
                Text(run.createdAt, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
            if !run.summary.isEmpty {
                Text(run.summary).font(.subheadline).lineLimit(14)
            }
            ForEach(run.steps) { s in
                Button {
                    toggle(s.id)
                } label: {
                    HStack {
                        Image(systemName: "checkmark").font(.caption2).foregroundStyle(Theme.ok)
                        Text(s.title).font(.caption).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        Image(systemName: expanded.contains(s.id) ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                if expanded.contains(s.id), !s.output.isEmpty {
                    Text(s.output).font(.caption).foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .glassPanel(18)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史（最近 10 次）").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(engine.history) { run in
                Button {
                    goal = run.goal
                    engine.current = run
                } label: {
                    HStack {
                        Image(systemName: run.ok ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(run.ok ? Theme.ok : Theme.danger)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.goal).font(.caption).foregroundStyle(.primary).lineLimit(1)
                            Text(run.createdAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassPanel(18)
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func start() {
        expanded = []
        Task {
            await engine.run(goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                             persona: persona.trimmingCharacters(in: .whitespacesAndNewlines),
                             store: store, reasoning: reasoning)
        }
    }

    private func icon(_ s: WorkflowEngine.StepStatus) -> String {
        switch s {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func color(_ s: WorkflowEngine.StepStatus) -> Color {
        switch s {
        case .pending: return Color.secondary
        case .running: return Theme.accent
        case .done: return Theme.ok
        case .failed: return Theme.danger
        }
    }
}
