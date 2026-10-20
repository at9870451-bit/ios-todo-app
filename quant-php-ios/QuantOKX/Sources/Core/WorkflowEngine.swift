import Foundation

/// Codex 风格的本地工作流引擎（纯 App 端，无外部 agent 依赖）
/// 目标 → 模型拆解步骤 → 逐步执行（可请求本地工具）→ 汇总报告
@MainActor
final class WorkflowEngine: ObservableObject {

    enum StepStatus: String, Codable { case pending, running, done, failed }

    struct Step: Identifiable, Codable {
        var id = UUID()
        var title: String
        var status: StepStatus = .pending
        var output: String = ""
    }

    struct Run: Codable, Identifiable {
        var id = UUID()
        var goal: String
        var persona: String
        var steps: [Step]
        var summary: String = ""
        var createdAt: Date = Date()
        var ok: Bool = false
    }

    @Published var running = false
    @Published var current: Run?
    @Published var history: [Run] = []

    private let histKey = "app.workflow.history.v1"
    /// 取消标志（UI 可置 true）
    @Published var cancelRequested = false

    init() {
        if let data = UserDefaults.standard.data(forKey: histKey),
           let list = try? JSONDecoder().decode([Run].self, from: data) {
            history = list
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(Array(history.prefix(10))) {
            UserDefaults.standard.set(data, forKey: histKey)
        }
    }

    // MARK: - 工具（本地执行）

    private static let tools = [
        "time    —— 获取当前日期时间",
        "ls history —— 查看本机聊天记录概况",
        "ls friends —— 查看好友列表概况",
        "calc <算式> —— 四则运算（如 calc 12*(3+4)）",
    ]

    /// 解析模型输出中的 [工具:...]，执行后返回 (剩余文本, 工具结果报告)
    private func runTools(in text: String) -> (String, [String]) {
        var results: [String] = []
        var cleaned = text
        while let r = cleaned.firstMatch(of: /\[工具[:：]\s*([^\]]{1,80})\]/) {
            let call = String(r.1).trimmingCharacters(in: .whitespaces)
            cleaned = cleaned.replacingOccurrences(of: r.0, with: "")
            results.append("工具「\(call)」→ \(execTool(call))")
        }
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), results)
    }

    private func execTool(_ call: String) -> String {
        let parts = call.split(separator: " ").map(String.init)
        switch parts.first {
        case "time":
            return DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        case "ls":
            if parts.count > 1, parts[1] == "history" {
                var out: [String] = []
                for f in FriendStore.shared.friends {
                    let n = LocalHistory.count("friend.\(f.id)")
                    if n > 0 { out.append("\(f.name): \(n) 条") }
                }
                for g in GroupStore.shared.groups {
                    let n = LocalHistory.count("group.\(g.id)")
                    if n > 0 { out.append("\(g.name)(群): \(n) 条") }
                }
                return out.isEmpty ? "本机暂无聊天记录" : out.joined(separator: "；")
            }
            if parts.count > 1, parts[1] == "friends" {
                let fs = FriendStore.shared.friends
                return fs.isEmpty ? "本机暂无好友" : fs.map { "\($0.name)(\($0.genderText)\($0.age.isEmpty ? "" : " \($0.age)岁"))" }.joined(separator: "、")
            }
            return "ls 可用: history / friends"
        case "calc":
            let expr = call.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let n = evalArithmetic(expr) { return "\(expr) = \(n)" }
            return "算式无法解析"
        default:
            return "未知工具。可用：" + Self.tools.joined(separator: "；")
        }
    }

    private func evalArithmetic(_ expr: String) -> Double? {
        guard expr.allSatisfy({ "+-*/(). 0123456789".contains($0) }), !expr.isEmpty else { return nil }
        let exp = NSExpression(format: expr)
        let v = exp.expressionValue(with: nil, context: nil) as? Double
        return v
    }

    // MARK: - 主循环

    /// 运行一个目标。每步都走现有 oneshot 链路（本地配置/直连规则照旧）。
    func run(goal: String, persona: String, store: BackendStore, reasoning: String) async {
        guard !running else { return }
        running = true
        cancelRequested = false
        var run = Run(goal: goal, persona: persona, steps: [])
        current = run

        let sys = """
        你是用户的本地智能体工作流引擎（类 Codex）。人设：\(persona.isEmpty ? "高效可靠的助手" : persona)
        规则：先结论后细节；输出精炼；不要说"作为AI"。若需要本机信息，可单独输出一行 [工具:命令] 请求工具，可用命令：
        \(Self.tools.joined(separator: "\n"))
        """

        do {
            // 1) 计划：拆解为 3-6 步
            var planMsgs: [[String: String]] = [
                ["role": "user", "content": """
                目标：\(goal)
                请把这个目标拆解为 3~6 个可执行步骤，直接输出 JSON 字符串数组（不要解释不要代码块），例如：
                ["梳理需求要点","分析可选方案","给出结论与建议"]
                """]
            ]
            var planRaw = try await store.oneshot(messages: planMsgs, systemPrompt: sys + "\n本次只输出 JSON 数组。", reasoning: reasoning)
            var (_, toolRes) = runTools(in: planRaw)
            if !toolRes.isEmpty {
                planMsgs.append(["role": "user", "content": "工具结果：\n" + toolRes.joined(separator: "\n") + "\n请基于以上结果输出 JSON 步骤数组。"])
                planRaw = try await store.oneshot(messages: planMsgs, systemPrompt: sys, reasoning: reasoning)
            }
            var titles = Self.parseSteps(planRaw)
            if titles.isEmpty { titles = ["分析目标：\(goal)", "给出结论"] }
            run.steps = titles.map { Step(title: $0) }
            current = run

            // 2) 逐步执行
            var digest: [String] = []
            for i in run.steps.indices {
                if cancelRequested { run.steps[i].status = .pending; break }
                run.steps[i].status = .running
                current = run

                var msgs: [[String: String]] = []
                if !digest.isEmpty {
                    msgs.append(["role": "user", "content": "已完成步骤的结论：\n" + digest.joined(separator: "\n")])
                }
                var ask = """
                目标：\(goal)
                请执行第 \(i + 1)/\(run.steps.count) 步：「\(run.steps[i].title)」。
                输出该步骤的成果（简洁、可直接用于最终汇总）。如需本机信息用 [工具:命令]。
                """
                msgs.append(["role": "user", "content": ask])
                _ = ask
                var out = try await store.oneshot(messages: msgs, systemPrompt: sys, reasoning: reasoning)
                var (clean, tres) = runTools(in: out)
                var loop = 0
                while !tres.isEmpty && loop < 3 {
                    msgs.append(["role": "user", "content": "工具结果：\n" + tres.joined(separator: "\n") + "\n请继续完成本步骤的成果。"])
                    out = try await store.oneshot(messages: msgs, systemPrompt: sys, reasoning: reasoning)
                    (clean, tres) = runTools(in: out)
                    loop += 1
                }
                run.steps[i].status = .done
                run.steps[i].output = clean
                digest.append("【\(run.steps[i].title)】" + clean.prefix(400))
                current = run
            }

            // 3) 汇总
            if !cancelRequested {
                let ask = """
                目标：\(goal)
                各步骤成果：
                \(digest.joined(separator: "\n\n"))
                请给出最终报告：结论先行，分点简洁，控制在 300 字内。
                """
                let final = try await store.oneshot(messages: [["role": "user", "content": ask]], systemPrompt: sys, reasoning: reasoning)
                run.summary = final
                run.ok = true
            }
        } catch {
            run.summary = "⚠️ 工作流中断：\(error.localizedDescription)"
        }

        running = false
        current = run
        if !history.contains(where: { $0.id == run.id }) {
            history.insert(run, at: 0)
        } else {
            if let i = history.firstIndex(where: { $0.id == run.id }) { history[i] = run }
        }
        saveHistory()
    }

    /// 从模型输出解析 JSON 步骤数组（容错：截取首个 [ ... ] 块）
    static func parseSteps(_ raw: String) -> [String] {
        guard let s = raw.firstIndex(of: "["), let e = raw.lastIndex(of: "]"), s < e else { return [] }
        let json = String(raw[s...e])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr.filter { !$0.isEmpty }.prefix(6).map { $0 }
    }
}
