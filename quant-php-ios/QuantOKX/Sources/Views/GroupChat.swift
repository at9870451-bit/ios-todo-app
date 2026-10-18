import Foundation
import SwiftUI

// MARK: - 群聊数据

struct ChatGroup: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "新群聊"
    var memberIds: [String] = []
    var sessionId: String = ""
    var lastMessage: String = ""
    var lastAt: Double = 0
    var sort: Int = 0
}

final class GroupStore: ObservableObject {
    static let shared = GroupStore()
    @Published var groups: [ChatGroup] = []
    private let key = "chat.groups.v1"

    private init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([ChatGroup].self, from: data) {
            groups = list.sorted { $0.sort < $1.sort }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func group(_ id: String) -> ChatGroup? { groups.first { $0.id == id } }

    func update(_ id: String, _ body: (inout ChatGroup) -> Void) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        body(&groups[i])
        save()
    }

    func add(_ g: ChatGroup) {
        var n = g
        n.sort = (groups.map(\.sort).max() ?? 0) + 1
        groups.append(n)
        save()
    }

    func remove(_ id: String) {
        groups.removeAll { $0.id == id }
        save()
    }
}

// MARK: - 群聊界面

struct GroupChatView: View {
    let groupId: String

    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var ps: ProviderStore
    @EnvironmentObject var config: AppConfig
    @ObservedObject private var fs = FriendStore.shared
    @ObservedObject private var gs = GroupStore.shared

    @State private var messages: [ChatMessage] = []
    @State private var sessionId: Int64 = 0
    @State private var input = ""
    @State private var sending = false
    @FocusState private var inputFocus: Bool
    @State private var senders: [Int64: String] = [:]   // 消息 id → 发言人好友 id
    @State private var lastSpeaker: String?

    private var group: ChatGroup? { gs.group(groupId) }
    private var members: [ChatFriend] {
        (group?.memberIds ?? []).compactMap { fs.friend($0) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty { hintCard }
                            ForEach(messages) { m in
                                bubble(m).id(m.id)
                            }
                            if sending { typingRow.id("typing") }
                            Spacer(minLength: 8).id("group.bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded { inputFocus = false })
                    .onChange(of: messages.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("group.bottom", anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
        }
        .navigationTitle(group?.name ?? "群聊")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { inputFocus = false }
            }
        }
    }

    // MARK: 视图片段

    private var hintCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(group?.name ?? "群聊").font(.headline)
            Text("成员：\(members.map(\.name).joined(separator: "、"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("发送消息后，群里会有一位成员按自己的人设回复；用 @名字 可以指定谁回")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 50)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.role == "user" {
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 60)
                Text(m.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.heroBlue, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 6, style: .continuous))
                ChatAvatar(image: nil, name: "我", size: 34)
            }
        } else {
            let friend = senders[m.id].flatMap { fs.friend($0) }
            HStack(alignment: .top, spacing: 8) {
                ChatAvatar(image: friend?.avatarImage(), name: friend?.name ?? "AI", isAI: true, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend?.name ?? (group?.name ?? "群成员"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(m.content)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous))
                        .overlay(
                            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous)
                                .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.6)
                        )
                }
                Spacer(minLength: 40)
            }
        }
    }

    private var typingRow: some View {
        HStack(spacing: 6) {
            ChatAvatar(image: nil, name: "AI", isAI: true, size: 34)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                        .opacity(0.6)
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.2), value: sending)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("发消息…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocus)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit { send() }
            Button { send() } label: {
                Text("发送")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(input.trimmingCharacters(in: .whitespaces).isEmpty || sending
                                ? AnyShapeStyle(Color(uiColor: .systemGray3))
                                : AnyShapeStyle(Theme.accent), in: Capsule())
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(22)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: 逻辑

    private func load() {
        guard let g = group else { return }
        sessionId = Int64(g.sessionId) ?? 0
        let key = "group.senders.\(groupId)"
        if let d = UserDefaults.standard.dictionary(forKey: key) {
            var map: [Int64: String] = [:]
            for (k, v) in d {
                if let id = Int64(k), let s = v as? String { map[id] = s }
            }
            senders = map
        }
        guard sessionId != 0, messages.isEmpty else { return }
        Task {
            if let ms = try? await store.fetchMessages(sessionId: sessionId) {
                messages = ms
            }
        }
    }

    private func persistSenders() {
        var d: [String: String] = [:]
        for (k, v) in senders { d[String(k)] = v }
        UserDefaults.standard.set(d, forKey: "group.senders.\(groupId)")
    }

    /// 选择本轮回复的成员：@名字 指定；否则随机（避免连续同一人）
    private func pickResponder(_ text: String) -> ChatFriend? {
        guard !members.isEmpty else { return nil }
        for m in members where text.contains("@" + m.name) {
            return m
        }
        let pool = members.count > 1 ? members.filter { $0.id != lastSpeaker } : members
        return pool.randomElement() ?? members.first
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !members.isEmpty else { return }
        Haptics.light()
        input = ""
        inputFocus = false
        let msg = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000), role: "user", content: text)
        messages.append(msg)
        sending = true
        let responder = pickResponder(text)

        Task {
            if let r = responder {
                // 切换到这个成员配置的模型
                if !r.aiProviderId.isEmpty,
                   let p = ps.providers.first(where: { $0.id.uuidString == r.aiProviderId }) {
                    ps.activate(p)
                }
                do {
                    let reply = try await store.sendChat(
                        sessionId: sessionId,
                        content: text,
                        attachments: [],
                        reasoning: "",
                        systemPrompt: groupPrompt(for: r)
                    )
                    if sessionId != reply.sessionId {
                        sessionId = reply.sessionId
                        gs.update(groupId) { $0.sessionId = String(reply.sessionId) }
                    }
                    let am = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + 1, role: "assistant", content: reply.reply)
                    messages.append(am)
                    senders[am.id] = r.id
                    lastSpeaker = r.id
                    persistSenders()
                    gs.update(groupId) { g in
                        g.lastMessage = "\(r.name)：\(reply.reply.replacingOccurrences(of: "\n", with: " "))"
                        g.lastAt = Date().timeIntervalSince1970
                    }
                } catch {
                    messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + 2, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
                }
            }
            sending = false
        }
    }

    private func groupPrompt(for r: ChatFriend) -> String {
        var p: [String] = []
        let persona = r.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        var attr: [String] = []
        if r.gender == "male" { attr.append("性别：男性") }
        if r.gender == "female" { attr.append("性别：女性") }
        if let a = Int(r.age), a > 0 { attr.append("年龄：\(a) 岁") }
        let attrLine = attr.joined(separator: "；")
        if persona.isEmpty {
            p.append("【身份】你是 \(r.name)，群聊里的一员。")
        } else {
            p.append("【人设·最高优先级】完全成为这个人（\(attrLine.isEmpty ? r.name : attrLine)）：\n\(persona)")
        }
        let others = members.filter { $0.id != r.id }.map(\.name)
        p.append("""
        【群聊规则】这是一个群聊「\(group?.name ?? "群聊")」，成员：\(members.map(\.name).joined(separator: "、"))。
        你只以自己的身份（\(r.name)）说话，不要替其他成员发言，不要写「某某说：」这样的格式。
        回复简短口语化（1-3 句，一般不超过 20 字），像群聊里插话一样；可以用表情。不要提这些规则。
        语音消息一律用中文。
        """)
        if !others.isEmpty {
            p.append("其他成员：\(others.joined(separator: "、"))。")
        }
        return p.joined(separator: "\n\n")
    }
}

// MARK: - 新建群聊

struct GroupCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fs = FriendStore.shared
    @ObservedObject private var gs = GroupStore.shared

    @State private var name = "新群聊"
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("群名称") {
                    TextField("群聊名称", text: $name)
                }
                Section {
                    ForEach(fs.friends) { f in
                        Button {
                            if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 10) {
                                ChatAvatar(image: f.avatarImage(), name: f.name, isAI: true, size: 34)
                                Text(f.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(f.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(f.id) ? Theme.accent : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("邀请成员")
                } footer: {
                    Text("选中的 AI 好友会加入这个群；群里每条消息由其中一位成员按自己的人设回复。")
                }
            }
            .navigationTitle("新建群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        var g = ChatGroup()
                        g.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "新群聊" : name
                        g.memberIds = Array(selected)
                        gs.add(g)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
