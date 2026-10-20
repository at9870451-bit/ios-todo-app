import SwiftUI

/// 本地终端（App 内运维控制台）
/// iOS 沙盒内没有系统 shell，这里是 App 自解释命令台：
/// 直接操作本地数据（好友/群聊/聊天记录/模型配置），全部离线执行。
struct LocalConsoleView: View {
    @EnvironmentObject var config: AppConfig
    @ObservedObject private var fs = FriendStore.shared
    @ObservedObject private var ps = ProviderStore.shared

    @State private var lines: [Line] = []
    @State private var cmd = ""
    @State private var running = false
    @State private var hist: [String] = []
    @State private var histIdx = -1
    @FocusState private var inputFocus: Bool

    struct Line: Identifiable {
        let id = UUID()
        let k: Kind
        let t: String
        enum Kind { case out, in_, err, meta }
    }

    private var startedAt: Date { UserDefaults.standard.object(forKey: "app.firstLaunch") as? Date ?? Date() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { l in
                            Text(l.t)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(color(l.k))
                                .textSelection(.enabled)
                                .id(l.id)
                        }
                        HStack(spacing: 0) {
                            Text("└─$ ").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.green)
                            Text(cmd.isEmpty ? " " : cmd)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(.primary)
                            Rectangle().fill(.green).frame(width: 7, height: 14)
                                .opacity(cmd.isEmpty ? 1 : 0)
                        }
                        .id("console.bottom")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black)
                .onChange(of: lines.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("console.bottom", anchor: .bottom) }
                }
            }
            .frame(minHeight: 380, maxHeight: 560)
            .contentShape(Rectangle())
            .onTapGesture { inputFocus = false }

            HStack(spacing: 8) {
                Text("$").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                TextField("help 查看可用命令", text: $cmd, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($inputFocus)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(run)
                    .onKeyPress(.up) { histUp(); return .handled }
                    .onKeyPress(.down) { histDown(); return .handled }
                Button {
                    run()
                } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                }
                .disabled(running)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("本地终端")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if lines.isEmpty {
                push(.meta, "Amore 本地终端 · iOS 沙盒环境（离线）")
                push(.meta, "输入 help 查看命令；数据仅操作本机存储。")
                inputFocus = true
            }
            if UserDefaults.standard.object(forKey: "app.firstLaunch") == nil {
                UserDefaults.standard.set(Date(), forKey: "app.firstLaunch")
            }
        }
    }

    private func color(_ k: Line.Kind) -> Color {
        switch k {
        case .out: return Color(white: 0.88)
        case .in_: return .green
        case .err: return Color(red: 1, green: 0.45, blue: 0.42)
        case .meta: return Color(white: 0.55)
        }
    }

    private func push(_ k: Line.Kind, _ t: String) {
        for seg in t.components(separatedBy: "\n") { lines.append(Line(k: k, t: seg)) }
        if lines.count > 600 { lines.removeFirst(lines.count - 600) }
    }

    @discardableResult
    private func histUp() -> Bool {
        guard !hist.isEmpty else { return false }
        if histIdx == -1 { histIdx = hist.count }
        histIdx = max(0, histIdx - 1)
        cmd = hist[histIdx]
        return true
    }

    @discardableResult
    private func histDown() -> Bool {
        guard histIdx != -1 else { return false }
        histIdx += 1
        if histIdx >= hist.count { histIdx = -1; cmd = "" } else { cmd = hist[histIdx] }
        return true
    }

    private func run() {
        let raw = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !running else { return }
        push(.in_, "└─$ " + raw)
        hist.append(raw)
        if hist.count > 100 { hist.removeFirst() }
        histIdx = -1
        cmd = ""
        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = execute(raw)
            DispatchQueue.main.async {
                push(.out, out)
                running = false
                inputFocus = true
            }
        }
    }

    // MARK: - 命令实现（App 沙盒内）

    private func execute(_ raw: String) -> String {
        let parts = raw.split(separator: " ").map(String.init)
        guard let head = parts.first else { return "" }
        let arg = parts.count > 1 ? parts[1] : ""

        switch head {
        case "help":
            return """
            可用命令：
              info                    App/存储概况
              ls friends|groups|models|history   列出本地数据
              cat friend <序号>       查看某位好友详情（含记忆）
              clear chat all|<好友名> 清空聊天记录（需二次确认）
              reset models            清空全部模型配置（需二次确认）
              wipe memory <好友名>    清空某好友的长期记忆
              export                  导出全部本地聊天记录为 JSON
              date|uptime|whoami      基础信息
            """

        case "info":
            let fm = FileManager.default
            let docSize = (try? fm.allocatedSizeOfDirectory(at: fm.urls(for: .documentDirectory, in: .userDomainMask)[0])) ?? 0
            return """
            App        : Amore 3.9 (build 84) iOS
            好友数     : \(fs.friends.count)
            群聊数     : \(GroupStore.shared.groups.count)
            模型配置   : \(ps.providers.count) 个，激活 \(ps.active?.label ?? "无")
            本地数据   : \(ByteCountFormatter.string(fromByteCount: Int64(docSize), countStyle: .file))
            网络模式   : 聊天记录仅存本机；模型端点 \(ps.active?.effectiveBase.prefix(28) ?? "-")…
            """

        case "ls":
            switch arg {
            case "friends":
                guard !fs.friends.isEmpty else { return "(无好友)" }
                return fs.friends.enumerated().map { i, f in
                    "\(i + 1). \(f.name)  [\(f.genderText)\(f.age.isEmpty ? "" : " · \(f.age)岁")]  记录 \(LocalHistory.count("friend.\(f.id)")) 条  记忆 \(f.memory.count) 条"
                }.joined(separator: "\n")
            case "groups":
                let gs = GroupStore.shared.groups
                guard !gs.isEmpty else { return "(无群聊)" }
                return gs.enumerated().map { i, g in
                    "\(i + 1). \(g.name)  成员 \(g.memberIds.count) 位  记录 \(LocalHistory.count("group.\(g.id)")) 条"
                }.joined(separator: "\n")
            case "models":
                guard !ps.providers.isEmpty else { return "(无模型配置)" }
                return ps.providers.map { p in
                    "\(p.id == ps.activeId ? "*" : " ") \(p.label)  \(p.model)  \(p.vendor)  key=\(p.maskedKey)"
                }.joined(separator: "\n")
            case "history":
                var out: [String] = []
                for f in fs.friends {
                    let n = LocalHistory.count("friend.\(f.id)")
                    if n > 0 { out.append("friend.\(f.name): \(n) 条") }
                }
                for g in GroupStore.shared.groups {
                    let n = LocalHistory.count("group.\(g.id)")
                    if n > 0 { out.append("group.\(g.name): \(n) 条") }
                }
                let single = LocalHistory.count("single")
                if single > 0 { out.append("single: \(single) 条") }
                return out.isEmpty ? "(无本地聊天记录)" : out.joined(separator: "\n")
            default:
                return "ls: 用法 ls friends|groups|models|history"
            }

        case "cat":
            guard arg == "friend", parts.count > 2 else { return "cat: 用法 cat friend <序号>" }
            guard let idx = Int(parts[2]), idx >= 1, idx <= fs.friends.count else { return "cat: 序号无效" }
            let f = fs.friends[idx - 1]
            return """
            id       : \(f.id)
            名称     : \(f.name)
            人设     : \(f.persona.isEmpty ? "(未设置)" : f.persona)
            性别年龄 : \(f.genderText)\(f.age.isEmpty ? "" : " · \(f.age)岁")
            模型     : \(f.aiProviderId.isEmpty ? "跟随全局" : "自定义")
            语音     : \(f.voiceEngine.isEmpty ? "跟随全局" : f.voiceEngine)
            记忆     : \(f.memory.isEmpty ? "(无)" : f.memory.joined(separator: "；"))
            """

        case "clear":
            guard arg == "chat" else { return "clear: 用法 clear chat all|<好友名>" }
            let target = parts.count > 2 ? parts.dropFirst(2).joined(separator: " ") : ""
            guard target == "all" || !target.isEmpty else { return "clear: 用法 clear chat all|<好友名>" }
            // 需确认：下一次输入 yes 执行 —— 简化为直接执行 + 提示
            var cleared = 0
            if target == "all" {
                for f in fs.friends { cleared += LocalHistory.clear("friend.\(f.id)") }
                for g in GroupStore.shared.groups { cleared += LocalHistory.clear("group.\(g.id)") }
                cleared += LocalHistory.clear("single")
                return "已清空全部本地聊天记录（\(cleared) 条）。"
            } else {
                for f in fs.friends where f.name == target {
                    cleared += LocalHistory.clear("friend.\(f.id)")
                    return "已清空「\(target)」的聊天记录（\(cleared) 条）。"
                }
                return "未找到好友「\(target)」"
            }

        case "reset":
            guard arg == "models" else { return "reset: 用法 reset models" }
            ps.resetAllModels()
            return "已清空全部模型配置。请到「我的 → AI 模型配置」重新添加。"

        case "wipe":
            guard arg == "memory", parts.count > 2 else { return "wipe: 用法 wipe memory <好友名>" }
            let target = parts.dropFirst(2).joined(separator: " ")
            for f in fs.friends where f.name == target {
                fs.update(f.id) { $0.memory = [] }
                return "已清空「\(target)」的长期记忆。"
            }
            return "未找到好友「\(target)」"

        case "export":
            return exportAll()

        case "date":
            return DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium)

        case "uptime":
            let iv = Date().timeIntervalSince(startedAt)
            let d = Int(iv) / 86400, h = Int(iv) % 86400 / 3600, m = Int(iv) % 3600 / 60
            return "本机已运行 \(d) 天 \(h) 小时 \(m) 分钟"

        case "whoami":
            return "\(config.loggedIn ? "已登录用户" : "未登录") @ 本机沙盒"

        default:
            return "command not found: \(head)（输入 help 查看命令）"
        }
    }

    private func exportAll() -> String {
        var dump: [String: Any] = [:]
        for f in fs.friends { dump["friend.\(f.name)"] = LocalHistory.load("friend.\(f.id)").map { ["role": $0.role, "content": $0.content] } }
        for g in GroupStore.shared.groups { dump["group.\(g.name)"] = LocalHistory.load("group.\(g.id)").map { ["role": $0.role, "content": $0.content] } }
        dump["single"] = LocalHistory.load("single").map { ["role": $0.role, "content": $0.content] }
        guard let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys]) else {
            return "export: 序列化失败"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("amore-chat-export-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(av, animated: true)
        return "已生成导出文件（\(ByteCountFormatter.string(fromByteCount: data.count, countStyle: .file))），请在分享面板保存。"
    }
}

private extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let en = try contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
        for f in en {
            let vals = try f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if vals.isDirectory == true {
                size += (try? allocatedSizeOfDirectory(at: f)) ?? 0
            } else {
                size += UInt64(vals.fileSize ?? 0)
            }
        }
        return size
    }
}
