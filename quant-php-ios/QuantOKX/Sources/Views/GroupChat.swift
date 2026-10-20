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
    @State private var senders: [Int64: String] = [:]      // 消息 id → 发言人好友 id（本次会话）
    @State private var senderBySig: [String: String] = [:] // 内容签名 → 发言人（重进后仍能对上）
    @State private var lastSpeaker: String?
    @State private var werewolf: WerewolfGame?

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
                        LazyVStack(spacing: 4) {
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
                        saveLocal()
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
        let aiColor = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(white: 0.19, alpha: 1) : UIColor(white: 0.91, alpha: 1)
        })
        if m.role == "user" {
            HStack {
                Spacer(minLength: 48)
                bubbleContent(m.content, isUser: true, msgId: m.id)
                    .font(.system(size: 16.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.04, green: 0.52, blue: 1.0),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 278, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        } else {
            let friend = senders[m.id].flatMap { fs.friend($0) }
            HStack(alignment: .top, spacing: 8) {
                // 头像：普通发言用该 AI 头像，系统卡牌用群组图标
                if let f = friend {
                    ChatAvatar(image: f.avatarImage(), name: f.name, isAI: true, size: 34)
                } else {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.16))
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend?.name ?? (group?.name ?? "群成员"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    bubbleContent(m.content, isUser: false, msgId: m.id)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(aiColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(maxWidth: 236, alignment: .leading)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private var typingRow: some View {
        HStack(spacing: 6) {
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
        HStack(alignment: .bottom, spacing: 8) {
            // 游戏选择器：选一个游戏即开始
            Menu {
                Button {
                    sendTarot()
                } label: {
                    Label("塔罗占卜", systemImage: "sparkles")
                }
                Button {
                    startWerewolf()
                } label: {
                    Label("狼人杀", systemImage: "pawprint.fill")
                }
            } label: {
                Text("🎮").font(.system(size: 20))
            }
            .disabled(sending || members.isEmpty)
            HStack(alignment: .bottom, spacing: 6) {
                TextField("iMessage", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocus)
                    .font(.system(size: 16))
                    .padding(.leading, 14)
                    .padding(.vertical, 8)
                    .onSubmit { send() }
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { Haptics.light(); send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 27))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                }
            }
            .padding(.vertical, 1)
            .background(
                Color(uiColor: UIColor { t in
                    t.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(white: 0.93, alpha: 1)
                }),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
        if let sigs = UserDefaults.standard.dictionary(forKey: "group.sigs.\(groupId)") as? [String: String] {
            senderBySig = sigs
        }
        guard sessionId != 0, messages.isEmpty else { return }
        Task {
            let local = LocalHistory.load("group.\(groupId)")
            if !local.isEmpty { messages = local; return }
            if let ms = try? await store.fetchMessages(sessionId: sessionId) {
                var deduped: [ChatMessage] = []
                for m in ms {
                    if let last = deduped.last, last.role == "user", m.role == "user", last.content == m.content { continue }
                    deduped.append(m)
                }
                messages = deduped
                // 服务器消息 id 与本地不同：用内容签名回填发言人，保证头像/名字不丢
                var fixed = senders
                for m in deduped where m.role == "assistant" {
                    if fixed[m.id] == nil, let f = senderBySig[Self.sig(m.content)] {
                        fixed[m.id] = f
                    }
                }
                senders = fixed
            }
        }
    }

    private func saveLocal() {
        LocalHistory.save("group.\(groupId)", messages)
    }

    private func persistSenders() {
        var d: [String: String] = [:]
        for (k, v) in senders { d[String(k)] = v }
        UserDefaults.standard.set(d, forKey: "group.senders.\(groupId)")
        if senderBySig.count > 400 { senderBySig.removeAll() }
        UserDefaults.standard.set(senderBySig, forKey: "group.sigs.\(groupId)")
    }

    /// 内容签名（用于重进后把服务器消息对应回发言人）
    static func sig(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
    }

    /// 选择本轮回复的成员：@名字 指定；否则多位随机（最多 3 位）
        private func pickResponders(_ text: String) -> [ChatFriend] {
        // 全员同时回复
        return members
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
        let responders = pickResponders(text)
        guard !responders.isEmpty else { sending = false; return }

        // 多人并发回复：各自用自己的人设提示词，同一时刻各自生成
        let groupSession = sessionId
        let groupPromptByFriend: [String: String] = Dictionary(uniqueKeysWithValues: responders.map { ($0.id, groupPrompt(for: $0)) })
        var payload: [[String: String]] = []
        for m in messages.suffix(19) {
            payload.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
        }

        Task {
            await withTaskGroup(of: (String, String, Int64?).self) { tg in
                for r in responders {
                    tg.addTask { [groupPromptByFriend, payload] in
                        do {
                            var reply = try await store.oneshot(
                                messages: payload,
                                systemPrompt: groupPromptByFriend[r.id] ?? ""
                            )
                            // Operit 式工具循环（本地执行，最多 3 轮）
                            var loops = 0
                            while loops < 3 {
                                let rt = ChatTools.roundtrip(reply)
                                guard let feedback = rt.feedback else { break }
                                var next = payload
                                next.append(["role": "user", "content": feedback])
                                reply = try await store.oneshot(
                                    messages: next,
                                    systemPrompt: groupPromptByFriend[r.id] ?? ""
                                )
                                loops += 1
                            }
                            return (r.id, ChatTools.stripMarkup(reply), nil)
                        } catch {
                            return (r.id, "", nil)
                        }
                    }
                }
                for await (friendId, replyText, newSession) in tg {
                    if let sid = newSession, sessionId != sid {
                        sessionId = sid
                        gs.update(groupId) { $0.sessionId = String(sid) }
                    }
                    guard !replyText.isEmpty else { continue }
                    let am = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + Int64.random(in: 1...99),
                                         role: "assistant", content: replyText)
                    messages.append(am)
                    senders[am.id] = friendId
                    senderBySig[Self.sig(replyText)] = friendId
                    lastSpeaker = friendId
                    persistSenders()
                    let name = fs.friend(friendId)?.name ?? "AI"
                    gs.update(groupId) { g in
                        g.lastMessage = "\(name)：\(replyText.replacingOccurrences(of: "\n", with: " "))"
                        g.lastAt = Date().timeIntervalSince1970
                    }
                }
            }
            // 历史里可能有多条相同的用户消息（每位成员各存一次），本地去重
            var deduped: [ChatMessage] = []
            for m in messages {
                if let last = deduped.last, last.role == "user", m.role == "user", last.content == m.content { continue }
                deduped.append(m)
            }
            if deduped.count != messages.count { messages = deduped }
            sending = false
        }
    }


    // MARK: - 卡牌渲染

    private struct CardInfo {
        let kind: String      // 塔罗 / 角色 / 结算
        let title: String
        let sub: String
        let symbol: String
        let tone: String      // purple / red / green / gold
    }

    private func parseCard(_ text: String) -> CardInfo? {
        guard text.hasPrefix("[卡牌]") else { return nil }
        let body = String(text.dropFirst(4))
        let p = body.components(separatedBy: "|")
        guard p.count >= 5 else { return nil }
        return CardInfo(kind: p[0], title: p[1], sub: p[2], symbol: p[3], tone: p[4])
    }

    @ViewBuilder
    private func bubbleContent(_ text: String, isUser: Bool, msgId: Int64 = 0) -> some View {
        if let c = parseCard(text) {
            VStack(spacing: 6) {
                GameCardView(kind: c.kind == "塔罗" ? .tarot : (c.kind == "结算" ? .reveal : .role),
                             title: c.title,
                             subtitle: c.sub,
                             symbol: c.symbol,
                             tint: toneColor(c.tone))
            }
        } else if LinkDetect.isMostlyLink(text), let u = LinkDetect.firstURL(in: text) {
            LinkPreviewCard(url: u)
        } else {
            let segs = RedPacketParser.parse(text)
            let hasVoice = segs.contains { if case .voice = $0 { return true }; return false }
            if hasVoice {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { idx, seg in
                        switch seg {
                        case .text(let t):
                            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                Text(trimmed)
                                    .font(.system(size: 16.5))
                                    .foregroundStyle(isUser ? .white : .primary)
                            }
                        case .voice(let v):
                            VoiceBubble(id: "\(msgId)-v\(idx)", text: v)
                        default:
                            EmptyView()
                        }
                    }
                }
            } else {
                Text(text)
                    .font(.system(size: 16.5))
                    .foregroundStyle(isUser ? .white : .primary)
            }
        }
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "red": return Theme.danger
        case "green": return Theme.ok
        case "gold": return Color(red: 0.78, green: 0.60, blue: 0.18)
        case "blue": return Theme.heroBlue
        default: return Color(red: 0.36, green: 0.27, blue: 0.55)
        }
    }

    private func cardMessage(_ kind: String, _ title: String, _ sub: String, _ symbol: String, tone: String) -> String {
        "[卡牌]\(kind)|\(title)|\(sub)|\(symbol)|\(tone)"
    }

    // MARK: - 塔罗

    private func sendTarot() {
        guard !sending, !members.isEmpty else { return }
        let (card, upright) = TarotCard.draw()
        let orientation = upright ? "正位" : "逆位"
        let meaning = upright ? card.upright : card.reversed
        let msg = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000), role: "user",
                              content: cardMessage("塔罗", card.name, "\(orientation) · \(meaning)", card.symbol,
                                                   tone: upright ? "gold" : "purple"))
        messages.append(msg)
        Haptics.success()
        sending = true

        let responder = pickResponders("").first
        Task {
            if let r = responder {
                if !r.aiProviderId.isEmpty,
                   let p = ps.providers.first(where: { $0.id.uuidString == r.aiProviderId }) {
                    ps.activate(p)
                }
                do {
                    var payload: [[String: String]] = []
                    for m in messages.suffix(19) {
                        payload.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
                    }
                    let replyText = try await store.oneshot(
                        messages: payload,
                        systemPrompt: tarotPrompt(for: r, card: card, upright: upright)
                    )
                    let am = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + 1, role: "assistant", content: replyText)
                    messages.append(am)
                    senders[am.id] = r.id
                    lastSpeaker = r.id
                    persistSenders()
                    gs.update(groupId) { g in
                        g.lastMessage = "\(r.name)：(塔罗) \(replyText.prefix(20))"
                        g.lastAt = Date().timeIntervalSince1970
                    }
                } catch {
                    // 静默
                }
            }
            sending = false
        }
    }

    private func tarotPrompt(for r: ChatFriend, card: TarotCard, upright: Bool) -> String {
        let orientation = upright ? "正位" : "逆位"
        let meaning = upright ? card.upright : card.reversed
        var p: [String] = []
        let persona = r.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty {
            p.append("【人设·最高优先级】你是 \(r.name)：\n\(persona)")
        } else {
            p.append("【身份】你是 \(r.name)，群聊里的一员。")
        }
        p.append("""
        【塔罗解读】用户抽到了「\(card.name)」（\(orientation)），牌义：\(meaning)。
        用你自己的口吻解读这张牌（结合用户最近聊过的事），2-4 句，口语化，别端着，别用「亲爱的」这类客服腔。
        先给一句结论，再说一句提醒。可以用一个 emoji。不要提牌阵、不要列条目、不要重复用户原话。
        语音消息一律用中文。
        """)
        p.append(ChatTools.guide)
        return p.joined(separator: "\n\n")
    }

    // MARK: - 狼人杀（单轮体验）

    private func startWerewolf() {
        guard !sending, members.count >= 2 else { return }
        var game = WerewolfGame()
        let pool = Array(members.prefix(4))
        game.players = pool.map { ($0.name, $0.id) }
        // 分配身份：1 个狼人（2 人局）/ 1 狼 + 1 预言家（3-4 人局），其余村民
        var shuffled = pool.shuffled()
        game.roles[shuffled.removeFirst().id] = .wolf
        if pool.count >= 3, let s2 = shuffled.first { game.roles[s2.id] = .seer }
        for m in pool where game.roles[m.id] == nil { game.roles[m.id] = .villager }
        werewolf = game

        let playersText = pool.map { $0.name }.joined(separator: "、")
        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000), role: "user",
                                   content: cardMessage("角色", "狼人杀", "玩家：\(playersText) · 天黑请闭眼", "moon.stars.fill", tone: "purple")))
        Haptics.success()
        nightPhase()
    }

    private func nightPhase() {
        guard var g = werewolf else { return }
        let wolves = g.roles.filter { $0.value == .wolf }.map { $0.key }
        let victims = g.players.filter { !wolves.contains($0.memberId) }
        let victim = victims.randomElement() ?? g.players.first
        g.victim = victim?.name ?? "某人"
        g.phase = 1
        werewolf = g

        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + 1, role: "assistant",
                                   content: cardMessage("结算", "天亮了", "\(g.victim) 昨夜被袭击", "sunrise.fill", tone: "red")))
        senders[messages.last!.id] = ""
        speakWerewolf()
    }

    private func speakWerewolf() {
        guard let g = werewolf else { return }
        sending = true
        let speakers = members.prefix(3)
        Task {
            for m in speakers {
                if let role = g.roles[m.id] {
                    if !m.aiProviderId.isEmpty,
                       let p = ps.providers.first(where: { $0.id.uuidString == m.aiProviderId }) {
                        ps.activate(p)
                    }
                    let prompt = werewolfPrompt(for: m, role: role, game: g)
                    var payload: [[String: String]] = []
                    for m in messages.suffix(19) {
                        payload.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
                    }
                    payload.append(["role": "user", "content": "（白天讨论）昨晚 \(g.victim) 出局了，来说说你的看法。"])
                    if let replyText = try? await store.oneshot(messages: payload, systemPrompt: prompt) {
                        let am = ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000), role: "assistant", content: replyText)
                        messages.append(am)
                        senders[am.id] = m.id
                        persistSenders()
                    }
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            // 结算
            var g2 = g
            let wolves = g2.roles.values.filter { $0 == .wolf }.count
            let others = g2.players.count - wolves
            g2.winner = wolves >= others ? "狼人胜利" : "好人阵营胜利"
            g2.phase = 3
            werewolf = g2
            let rolesText = g2.players.map { p in
                "\(p.name)：\(g2.roles[p.memberId]?.rawValue ?? "村民")"
            }.joined(separator: " / ")
            messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + 2, role: "assistant",
                                        content: cardMessage("结算", g2.winner, rolesText, "flag.checkered", tone: "gold")))
            senders[messages.last!.id] = ""
            sending = false
        }
    }

    private func werewolfPrompt(for m: ChatFriend, role: WerewolfRole, game: WerewolfGame) -> String {
        var p: [String] = []
        let persona = m.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty {
            p.append("【人设·最高优先级】你是 \(m.name)：\n\(persona)")
        } else {
            p.append("【身份】你是 \(m.name)。")
        }
        let others = game.players.filter { $0.memberId != m.id }.map { $0.name }.joined(separator: "、")
        p.append("""
        【狼人杀·白天发言】你的隐藏身份是「\(role.rawValue)」——\(role.blurb)。
        场上玩家：\(others)；昨晚 \(game.victim) 出局。
        \(role == .wolf ? "你是狼人：要伪装成好人，带节奏把嫌疑推给别人，绝不能承认身份。" : "你是好人：基于现有信息分析，可以怀疑别人，但别报假身份。")
        要求：只以自己的身份发言，1-2 句，口语化，像群聊插话（不超过 30 字）。
        不要写「作为预言家」这类格式，不要报自己的真实身份标签（除非你是预言家且决定跳身份）。
        语音一律中文。
        """)
        return p.joined(separator: "\n\n")
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
        偶尔可以用 [语音:内容] 发一条语音（内容写中文），像在群里发语音一样；别每句都发。
        语音消息一律用中文。
        """)
        if !others.isEmpty {
            p.append("其他成员：\(others.joined(separator: "、"))。")
        }
        p.append("""
        【群聊气氛·会争风吃醋】群里这几个人都跟用户关系不错，都有点小心思：
        - 偶尔抢话、护短、酸一下别的成员（"你怎么光理他"、"行吧，你们聊"）
        - 用户夸别人时，可以不服气、吃醋、暗暗比较；用户只理别人时，可以故意刷存在感
        - 也可以接别人刚说的话，拆台或帮腔
        但要克制：一次最多一句带过，别真的吵起来，别攻击用户，别破坏人设。
        """)
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
