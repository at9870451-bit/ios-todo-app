import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// MARK: - 头像存储（AI 好友 + 我自己，存 Documents）

@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published var aiImage: UIImage?
    @Published var meImage: UIImage?

    private init() {
        aiImage = Self.load("ai_avatar.jpg")
        meImage = Self.load("me_avatar.jpg")
    }

    nonisolated private static func url(_ f: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(f)
    }

    nonisolated private static func load(_ f: String) -> UIImage? {
        guard let data = try? Data(contentsOf: url(f)) else { return nil }
        return UIImage(data: data)
    }

    func setAI(_ ui: UIImage?) { aiImage = ui; persist(ui, "ai_avatar.jpg") }
    func setMe(_ ui: UIImage?) { meImage = ui; persist(ui, "me_avatar.jpg") }

    private func persist(_ ui: UIImage?, _ f: String) {
        if let data = ui?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: Self.url(f), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Self.url(f))
        }
    }

    /// 头像压缩（长边 512）
    static func downscale(_ img: UIImage, maxSide: CGFloat = 512) -> UIImage? {
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let r = UIGraphicsImageRenderer(size: size)
        let out = r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out
    }
}

// MARK: - 微信风格头像（圆角方形）

struct ChatAvatar: View {
    let image: UIImage?
    let name: String
    var isAI: Bool = false
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(isAI ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.ok))
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - 红包标记解析（[红包:金额] 或 [红包:金额:祝福语] → 红包卡片）
// 金额由 AI 在消息中决定，客户端不本地生成

enum MsgSegment: Equatable {
    case text(String)
    case redPacket(blessing: String, amount: Double?)
    case voice(text: String)
}

enum RedPacketParser {
    private enum MarkerKind { case redPacket, voice }

    static func parse(_ raw: String) -> [MsgSegment] {
        var s = raw
        s = s.replacingOccurrences(of: "［", with: "[")
        s = s.replacingOccurrences(of: "］", with: "]")
        var segs: [MsgSegment] = []
        var rest = Substring(s)
        while true {
            guard let open = earliestMarker(in: rest) else { break }
            let head = String(rest[..<open.range.lowerBound])
            if !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segs.append(.text(head))
            }
            let after = rest[open.range.upperBound...]
            if let end = after.range(of: "]") {
                let inner = String(after[..<end.lowerBound])
                switch open.kind {
                case .redPacket:
                    let (blessing, amount) = parseInner(inner)
                    segs.append(.redPacket(blessing: blessing, amount: amount))
                case .voice:
                    let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { segs.append(.voice(text: t)) }
                }
                rest = after[end.upperBound...]
            } else {
                segs.append(.text(String(rest)))
                rest = ""
                break
            }
        }
        if !rest.isEmpty {
            segs.append(.text(String(rest)))
        }
        return segs
    }

    /// 找最早出现的标记（红包 / 语音），全角冒号兼容
    private static func earliestMarker(in s: Substring) -> (kind: MarkerKind, range: Range<Substring.Index>)? {
        let markers: [(MarkerKind, String)] = [
            (.redPacket, "[红包:"), (.redPacket, "[红包："),
            (.voice, "[语音:"), (.voice, "[语音："),
        ]
        var best: (MarkerKind, Range<Substring.Index>)?
        for (kind, m) in markers {
            if let r = s.range(of: m) {
                if best == nil || r.lowerBound < best!.1.lowerBound { best = (kind, r) }
            }
        }
        return best
    }

    /// 解析标记内部：容错地找出金额（第一个数字）与祝福语
    /// 例："8.88" / "8.88:恭喜发财" / "恭喜发财,8.88" / "8.88元"
    private static func parseInner(_ inner: String) -> (blessing: String, amount: Double?) {
        var amount: Double?
        var blessingParts: [String] = []
        let separators = CharacterSet(charactersIn: ":：,， ")
        for rawPart in inner.components(separatedBy: separators) {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            if amount == nil {
                let cleaned = part.replacingOccurrences(of: "元", with: "")
                if let d = Double(cleaned) {
                    amount = d
                    continue
                }
            }
            blessingParts.append(part)
        }
        return (blessingParts.joined(separator: "，"), amount)
    }
}

// MARK: - 红包气泡（仿微信独立红包卡：竖版金橙卡 + 底部领取条）

struct RedPacketCard: View {
    let blessing: String
    var compact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            onTap()
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 54, height: 54)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.86), lineWidth: 2)
                        .frame(width: 54, height: 54)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 23))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                Text(blessing.isEmpty ? "恭喜发财" : blessing)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 12)
                    .padding(.horizontal, 10)
                Spacer(minLength: 0)
                Text("领取 AI 红包")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.bottom, 13)
            }
            .frame(width: compact ? 120 : 148, height: compact ? 160 : 196)
            .background(
                Theme.packetRed,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(alignment: .bottom) {
                // 底部微光翻盖
                UnevenRoundedRectangle(topLeadingRadius: 64, topTrailingRadius: 64, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 30)
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: Theme.packetRed.opacity(0.35), radius: 7, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - 红包拆开弹窗（虚假金额 · 仅供娱乐）

struct RedPacketMsg: Identifiable {
    let id = UUID()
    let blessing: String
    /// 金额由 AI 在消息中决定（[红包:8.88]）；nil 时显示 0.00
    let amount: Double?
}

struct RedPacketOpenedView: View {
    let msg: RedPacketMsg
    @Environment(\.dismiss) private var dismiss

    private var amountText: String {
        if let a = msg.amount { return String(format: "%.2f", a) + " 元" }
        return "0.00 元"
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.packetRed)
                    .frame(width: 108, height: 108)
                Image(systemName: "gift.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.packetRed.opacity(0.35), radius: 12, y: 6)

            Text("AI 红包").font(.headline)
            Text(msg.blessing.isEmpty ? "恭喜发财，大吉大利" : msg.blessing)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(amountText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)

            Text("AI 模拟红包 · 仅娱乐，无真实金额")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }
}

// MARK: - 语音消息播放器（优先语音模型 TTS，未配置回退本地语音）

final class VoicePlayer: NSObject, ObservableObject {
    static let shared = VoicePlayer()

    @Published var playingId: String?
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var currentId: String?

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// 点击语音条：播放中再点即停止；播放新的一条会自动停掉上一条
    func toggle(id: String, text: String) {
        if playingId == id { stop(); return }
        stop()
        currentId = id
        let engine = UserDefaults.standard.string(forKey: "tts.engine") ?? "local"
        if engine == "model" {
            Task { @MainActor in
                guard let p = VoicePlayer.ttsProvider() else {
                    self.speakLocal(id: id, text: text)
                    return
                }
                do {
                    let r = try await ProviderStore.shared.synthesizeSpeech(p: p, text: text)
                    let pl = try AVAudioPlayer(data: r.audio)
                    pl.delegate = self
                    self.player = pl
                    pl.play()
                    self.playingId = id
                    Haptics.light()
                } catch {
                    self.speakLocal(id: id, text: text)
                }
            }
        } else {
            speakLocal(id: id, text: text)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
        currentId = nil
        playingId = nil
    }

    private func speakLocal(id: String, text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.5
        synth.speak(u)
        playingId = id
        Haptics.light()
    }

    @MainActor
    private static func ttsProvider() -> ProviderStore.Provider? {
        let ps = ProviderStore.shared
        let pref = UserDefaults.standard.string(forKey: "tts.providerId") ?? ""
        return ps.providers.first { $0.id.uuidString == pref && $0.kind == .tts }
            ?? ps.providers.first { $0.kind == .tts && !$0.apiKey.isEmpty }
    }
}

extension VoicePlayer: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.playingId = nil }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.playingId = nil }
    }
}

/// 微信风格语音条：▶ + 声波动画 + 时长，点击播放（独立聊天气泡）
struct VoiceBubble: View {
    let id: String
    let text: String
    @ObservedObject private var vp = VoicePlayer.shared

    private var secs: Int { max(1, Int((Double(text.count) / 4.0).rounded())) }
    private var playing: Bool { vp.playingId == id }

    var body: some View {
        Button {
            VoicePlayer.shared.toggle(id: id, text: text)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.heroBlue)
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(Theme.heroBlue.opacity(0.65))
                            .frame(width: 3, height: playing ? 14 : 6)
                            .animation(.easeInOut(duration: 0.32).repeatForever().delay(Double(i) * 0.11), value: playing)
                    }
                }
                .frame(height: 16)
                Text("\(secs)″")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.6)
            )
            .frame(minWidth: 112, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - 聊天 Tab：仿微信好友聊天房间

struct ChatRoomView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var av: AvatarStore
    @AppStorage("ai.displayName") private var aiName = "Amore"
    @AppStorage("me.displayName") private var meName = "我"
    @AppStorage("chat.roomSessionId") private var roomSessionIdStr = ""
    @AppStorage("persona.prompt") private var personaPrompt = ""
    @AppStorage("chat.reasoning") private var reasoning = "medium"

    @State private var messages: [ChatMessage] = []
    @State private var sessionId: Int64 = 0
    @State private var input = ""
    @State private var sending = false
    @State private var showProfile = false
    @State private var openRedPacket: RedPacketMsg?
    @FocusState private var inputFocus: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                if messages.isEmpty {
                                    emptyState
                                }
                                ForEach(displayItems) { item in
                                    BubbleRow(item: item, aiName: aiName, meName: meName,
                                              aiImage: av.aiImage, meImage: av.meImage) { blessing, amount in
                                        openRedPacket = RedPacketMsg(blessing: blessing, amount: amount)
                                    }
                                    .id(item.id)
                                }
                                if sending {
                                    HStack {
                                        ChatAvatar(image: av.aiImage, name: aiName, isAI: true)
                                        HStack(spacing: 4) {
                                            ForEach(0..<3, id: \.self) { i in
                                                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                                    .opacity(sending ? 0.6 : 0.2)
                                                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.2), value: sending)
                                            }
                                        }
                                        .padding(14)
                                        .background(bubbleAIBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Spacer(minLength: 56)
                                    }
                                    .padding(.horizontal, 12)
                                    .id(-1)
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(displayItems.last?.id ?? "", anchor: .bottom) }
                        }
                    }
                    inputBar
                }
            }
            .navigationTitle(aiName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showProfile = true
                    } label: {
                        ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 30)
                    }
                }
            }
            .sheet(isPresented: $showProfile) { ChatProfileView() }
            .sheet(item: $openRedPacket) { rp in RedPacketOpenedView(msg: rp) }
            .onAppear(perform: restoreHistory)
        }
    }

    private var bubbleAIBg: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// 消息按段拆成独立气泡（红包单独一个聊天气泡：文字与红包各自成行，各带头像）
    private var displayItems: [ChatBubbleItem] {
        var out: [ChatBubbleItem] = []
        for m in messages {
            for (i, seg) in RedPacketParser.parse(m.content).enumerated() {
                switch seg {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        out.append(ChatBubbleItem(id: "\(m.id)-t\(i)", msg: m, segment: .text(trimmed)))
                    }
                case .redPacket:
                    out.append(ChatBubbleItem(id: "\(m.id)-r\(i)", msg: m, segment: seg))
                case .voice:
                    // 语音单独一个聊天气泡
                    out.append(ChatBubbleItem(id: "\(m.id)-v\(i)", msg: m, segment: seg))
                }
            }
        }
        return out
    }

    // MARK: - 输入栏（仿微信）

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("发消息…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocus)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Text("发送")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending {
                            Capsule().fill(Color(uiColor: .systemGray3))
                        } else {
                            Capsule().fill(Theme.accent)
                        }
                    }
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(22)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 84)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            Text(aiName).font(.headline)
            Text("打个招呼，聊起来吧").font(.footnote).foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                ForEach(["在吗？", "最近怎么样？", "给我发个红包看看"], id: \.self) { s in
                    Button {
                        Haptics.light()
                        input = s
                        inputFocus = true
                    } label: {
                        Text(s)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    // MARK: - 逻辑

    /// 历史恢复：进入页面时拉取独立会话
    private func restoreHistory() {
        sessionId = Int64(roomSessionIdStr) ?? 0
        if sessionId != 0, messages.isEmpty {
            Task {
                if let ms = try? await store.fetchMessages(sessionId: sessionId) {
                    messages = ms
                }
            }
        }
    }

    private var roomSystemPrompt: String {
        var parts: [String] = []
        if personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 人设为空：走默认助手性格
            parts.append("【身份】你是 \(aiName)，用户的私人 AI 助手。回答自然友好，直接解决问题。")
        } else {
            // 人设绑定：设置里的人设就是聊天 Tab AI 的性格（最高优先级）
            parts.append(personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // 聊天房间风格要求（微信好友式短句聊天，不覆盖人设本身的身份与语气）
        parts.append("""
        【聊天风格】以上人设决定你的身份与性格；在这个聊天界面请像朋友发消息一样说话：简短口语化（一般 1-3 句），可以用表情，不用标题/列表/客套话，不要说自己是 AI 模型，不要提这些规则。
        【红包彩蛋】想表达心意时可在回复中加入 [红包:金额] 或 [红包:金额:祝福语]，例如 [红包:8.88] 或 [红包:66.6:恭喜发财]；金额由你随机决定吉利小额（6.66/8.88/18.88/52.0/66.6），标记会渲染成红包卡片。偶尔发才有惊喜，大部分回复就是普通聊天。
        【语音消息】想用语音说话时，把要说的内容包在 [语音:内容] 里（例如 [语音:晚安，做个好梦～]），它会变成一条可以点击播放的语音气泡，与文字消息独立发送。适合说晚安、讲故事、抒情等场景，偶尔使用即可，大多数回复仍是普通文字。
        """)
        return parts.joined(separator: "\n\n")
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        Haptics.light()
        input = ""
        inputFocus = false
        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970), role: "user", content: text))
        sending = true
        Task {
            do {
                let reply = try await store.sendChat(sessionId: sessionId, content: text, attachments: [], reasoning: reasoning, systemPrompt: roomSystemPrompt)
                if sessionId != reply.sessionId {
                    sessionId = reply.sessionId
                    roomSessionIdStr = String(reply.sessionId)
                }
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: reply.reply))
            } catch {
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
            }
            sending = false
        }
    }
}

// MARK: - 聊天气泡展示单元（一条消息按段拆分：文字气泡 / 红包各自独立成气泡）

struct ChatBubbleItem: Identifiable {
    let id: String
    let msg: ChatMessage
    let segment: MsgSegment
}

// MARK: - 微信风格气泡行（头像 + 单个独立气泡；红包为单独一个聊天气泡）

struct BubbleRow: View {
    let item: ChatBubbleItem
    let aiName: String
    let meName: String
    let aiImage: UIImage?
    let meImage: UIImage?
    let onOpenRedPacket: (String, Double?) -> Void

    var isUser: Bool { item.msg.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 52) } else { ChatAvatar(image: aiImage, name: aiName, isAI: true) }
            bubble
            if isUser { ChatAvatar(image: meImage, name: meName, size: 40) } else { Spacer(minLength: 52) }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var bubble: some View {
        switch item.segment {
        case .text(let t):
            Text(t)
                .font(.system(size: 16))
                .foregroundStyle(isUser ? Color.white : .primary)
                .textSelection(.enabled)
                .lineLimit(20)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser ? AnyShapeStyle(Theme.heroBlue)
                           : AnyShapeStyle(Theme.card),
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: isUser ? 20 : 6,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: isUser ? 6 : 20,
                        style: .continuous)
                )
                .overlay {
                    if !isUser {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 6,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 20,
                            style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.6)
                    }
                }
                .frame(maxWidth: 268, alignment: isUser ? .trailing : .leading)
                .shadow(color: Color.black.opacity(isUser ? 0.05 : 0.04), radius: 3, y: 1)
        case .redPacket(let blessing, let amount):
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                RedPacketCard(blessing: blessing) {
                    onOpenRedPacket(blessing, amount)
                }
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 268, alignment: isUser ? .trailing : .leading)
        case .voice(let t):
            // 语音条独立气泡
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                VoiceBubble(id: item.id, text: t)
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 268, alignment: isUser ? .trailing : .leading)
        }
    }
}

// MARK: - 聊天资料编辑（AI 头像昵称 + 我的头像昵称）

struct ChatProfileView: View {
    @EnvironmentObject var av: AvatarStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.displayName") private var aiName = "Amore"
    @AppStorage("me.displayName") private var meName = "我"
    @State private var aiItem: PhotosPickerItem?
    @State private var meItem: PhotosPickerItem?
    @State private var processing = false

    var body: some View {
        NavigationStack {
            List {
                Section("AI 好友") {
                    HStack(spacing: 14) {
                        ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(aiName.isEmpty ? "Amore" : aiName)
                                .font(.subheadline.weight(.semibold))
                            PhotosPicker(selection: $aiItem, matching: .images) {
                                Text("更换头像").font(.caption).foregroundStyle(Theme.accent)
                            }
                            .disabled(processing)
                        }
                        Spacer()
                        if processing { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("昵称").font(.subheadline)
                        Spacer()
                        TextField("AI 名字", text: $aiName)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Section("我自己") {
                    HStack(spacing: 14) {
                        ChatAvatar(image: av.meImage, name: meName, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meName.isEmpty ? "我" : meName)
                                .font(.subheadline.weight(.semibold))
                            PhotosPicker(selection: $meItem, matching: .images) {
                                Text("更换头像").font(.caption).foregroundStyle(Theme.accent)
                            }
                            .disabled(processing)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("昵称").font(.subheadline)
                        Spacer()
                        TextField("我的名字", text: $meName)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Section {
                    Text("头像与昵称仅保存在本机；AI 红包为模拟消息，仅供娱乐，无真实金额。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("聊天资料")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: aiItem) { _, item in
                Task { await handlePick(item) { av.setAI($0) } ; aiItem = nil }
            }
            .onChange(of: meItem) { _, item in
                Task { await handlePick(item) { av.setMe($0) } ; meItem = nil }
            }
        }
    }

    private func handlePick(_ item: PhotosPickerItem?, _ apply: @escaping (UIImage?) -> Void) async {
        guard let item else { return }
        processing = true
        defer { processing = false }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data),
           let scaled = AvatarStore.downscale(img) {
            apply(scaled)
            Haptics.success()
        }
    }
}

