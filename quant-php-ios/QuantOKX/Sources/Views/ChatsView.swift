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

    /// 头像形状：可在「聊天资料」里切换圆角方形 / 圆形
    @AppStorage("chat.avatarCircle") private var circleShape = false

    private var corner: CGFloat { circleShape ? size / 2 : size * 0.22 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    if circleShape {
                        Circle()
                            .fill(isAI ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.ok))
                    } else {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(isAI ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.ok))
                    }
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(circleShape ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous)))
    }
}

// MARK: - 红包标记解析（[红包:金额] 或 [红包:金额:祝福语] → 红包卡片）
// 金额由 AI 在消息中决定，客户端不本地生成

enum MsgSegment: Equatable {
    case text(String)
    case redPacket(blessing: String, amount: Double?)
    case voice(text: String)
    /// 用户录制的语音（本地文件回放；AI 收到的是转写文字）
    case voiceFile(secs: Int, transcript: String)
    /// 领取红包的红色小字提示行
    case claim(text: String)
}

enum RedPacketParser {
    private enum MarkerKind { case redPacket, voice, claim }

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
                case .claim:
                    segs.append(.claim(text: inner))
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
            (.claim, "[已领红包]"), (.claim, "［已领红包］"),
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
    func toggle(id: String, text: String, baseURL: String) {
        if playingId == id { stop(); return }
        stop()
        currentId = id
        let engine = UserDefaults.standard.string(forKey: "tts.engine") ?? "server"
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
        } else if engine == "local" {
            speakLocal(id: id, text: text)
        } else {
            // 开源语音库（server）：立即进入播放态，热态合成秒回
            playingId = id
            Task { @MainActor in
                do {
                    let data = try await VoicePlayer.serverSynth(text: text, baseURL: baseURL)
                    guard self.currentId == id else { return }
                    let pl = try AVAudioPlayer(data: data)
                    pl.delegate = self
                    self.player = pl
                    pl.play()
                    Haptics.light()
                } catch {
                    guard self.currentId == id else { return }
                    self.playingId = nil
                    self.speakLocal(id: id, text: text)
                }
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
        currentId = nil
        playingId = nil
    }

    /// 播放本地录音文件（用户发送的语音）
    func toggleFile(id: String, path: String?) {
        if playingId == id { stop(); return }
        stop()
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        currentId = id
        do {
            let pl = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            pl.delegate = self
            player = pl
            pl.play()
            playingId = id
            Haptics.light()
        } catch { /* 播放失败静默 */ }
    }

    /// 自建开源语音库（直连服务器热态 Piper 服务 :8765，热态合成 <0.2s）
    @MainActor
    static func serverSynth(text: String, baseURL: String, fast: Bool = true) async throws -> Data {
        let q = String(text.prefix(500)).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let voice = fast ? "huayan_fast" : "huayan"
        // 优先直连常驻热态服务（毫秒级），失败再走 Java 后端代理
        if let host = URL(string: baseURL)?.host, !host.isEmpty {
            let directURL = "http://\(host):8765/tts?text=" + q + "&voice=" + voice
            if let url = URL(string: directURL) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 44 {
                    return data
                }
            }
        }
        // 回退：Java 后端代理（piper CLI，约 5s）
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + "/api/tts?text=" + q + "&voice=" + voice) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 44 else {
            throw URLError(.badServerResponse)
        }
        return data
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
/// 气泡宽度随时长（即文字多少）增长，对齐微信语音条形态
struct VoiceBubble: View {
    let id: String
    let text: String
    @ObservedObject private var vp = VoicePlayer.shared
    @EnvironmentObject private var config: AppConfig

    private var secs: Int { max(1, min(99, Int((Double(text.count) / 4.0).rounded()))) }
    /// 宽度 = 基础 92 + 每秒 5pt，最长 238（配合气泡 maxWidth 268）
    private var bubbleWidth: CGFloat { min(238, 92 + CGFloat(secs) * 5) }
    private var playing: Bool { vp.playingId == id }

    var body: some View {
        Button {
            VoicePlayer.shared.toggle(id: id, text: text, baseURL: config.serverURL)
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
                            // 播放中才挂 repeatForever 动画，停止时置 nil 释放，
                            // 修复「播放完动画卡住不复位 / 无法再次互动」
                            .animation(playing ? .easeInOut(duration: 0.32).repeatForever(autoreverses: true).delay(Double(i) * 0.11) : nil, value: playing)
                    }
                }
                .frame(height: 16)
                Spacer(minLength: 8)
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
            .frame(width: bubbleWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 用户发送的本地录音气泡（蓝色，白声波）
struct VoiceFileBubble: View {
    let id: String
    let path: String?
    let secs: Int
    @ObservedObject private var vp = VoicePlayer.shared

    private var playing: Bool { vp.playingId == id }
    private var bubbleWidth: CGFloat { min(238, 92 + CGFloat(secs) * 5) }

    var body: some View {
        Button {
            VoicePlayer.shared.toggleFile(id: id, path: path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 3, height: playing ? 14 : 6)
                            .animation(playing ? .easeInOut(duration: 0.32).repeatForever(autoreverses: true).delay(Double(i) * 0.11) : nil, value: playing)
                    }
                }
                .frame(height: 16)
                Spacer(minLength: 8)
                Text("\(secs)″")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.heroBlue, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 6, style: .continuous))
            .frame(width: bubbleWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 用户发红包的填写弹窗
struct RedPacketComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var blessing = "恭喜发财"
    let onSend: (String, String) -> Void

    private var amountValid: Bool {
        guard let d = Double(amountText), d > 0, d <= 888 else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("给 \(aiTitle) 发红包")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text("¥")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.packetRed)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.packetRed)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.packetRed.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))

            TextField("祝福语", text: $blessing)
                .padding(14)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))

            Text("AI 模拟红包 · 仅娱乐，无真实金额")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                Haptics.medium()
                let blessingText = blessing.trimmingCharacters(in: .whitespaces)
                onSend(amountText, blessingText.isEmpty ? "恭喜发财" : blessingText)
                dismiss()
            } label: {
                Text("塞钱进红包")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.packetRed, in: Capsule())
                    .shadow(color: Theme.packetRed.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!amountValid)
        }
        .padding(22)
        .frame(maxWidth: 340)
    }

    private var aiTitle: String {
        UserDefaults.standard.string(forKey: "ai.displayName") ?? "AI"
    }
}

// MARK: - 聊天 Tab：仿微信好友聊天房间

struct ChatRoomView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var av: AvatarStore
    @EnvironmentObject var config: AppConfig
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

    // AI 定时主动消息
    @AppStorage("ai.proactiveOn") private var proactiveOn = false
    @AppStorage("ai.proactiveMinutes") private var proactiveMinutes = 30
    @State private var lastActivity = Date()
    @State private var proactiveBusy = false

    // 红包领取记录（持久化，本地）
    @State private var claimedKeys: Set<String> = []

    // 用户语音录制
    @State private var recording = false
    @State private var recorder: AVAudioRecorder?
    @State private var recordStart = Date()
    @State private var recordSecs = 0
    @State private var recordTimer: Timer?
    @State private var voicePaths: [String: String] = [:]

    // 打电话
    @State private var showCall = false
    // 用户发红包
    @State private var showCompose = false

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
                                    if case .claim(let note) = item.segment {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.packetRed)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 2)
                                            .id(item.id)
                                    } else {
                                        BubbleRow(item: item, aiName: aiName, meName: meName,
                                                  aiImage: av.aiImage, meImage: av.meImage,
                                                  voicePath: voicePaths[String(item.msg.id)]) { blessing, amount in
                                            openRedPacket = RedPacketMsg(blessing: blessing, amount: amount)
                                            // 点击 AI 红包即领取 → 红色小字提示
                                            markClaimed(key: item.id)
                                        }
                                        .id(item.id)
                                    }
                                }
                                if sending {
                                    HStack {
                                        ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 48)
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
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(displayItems.last?.id ?? "", anchor: .bottom) }
                        }
                        .onChange(of: inputFocus) { _, focused in
                            // 键盘弹出时也自动贴底，避免手动下滑
                            guard focused else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(displayItems.last?.id ?? "", anchor: .bottom) }
                            }
                        }
                    }
                    inputBar
                }
            }
            .navigationTitle(aiName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        // 打电话给 AI
                        Button {
                            Haptics.light()
                            showCall = true
                        } label: {
                            Image(systemName: "phone.fill")
                        }
                        // 定时消息开关与频率（右上角菜单）
                        Menu {
                            Button {
                                Haptics.light()
                                proactiveOn.toggle()
                            } label: {
                                Label(proactiveOn ? "定时消息：已开启" : "定时消息：已关闭",
                                      systemImage: proactiveOn ? "bell.badge.fill" : "bell.badge")
                            }
                            if proactiveOn {
                                ForEach([10, 30, 60, 180], id: \.self) { m in
                                    Button {
                                        proactiveMinutes = m
                                    } label: {
                                        if proactiveMinutes == m {
                                            Label(Self.freqLabel(m), systemImage: "checkmark")
                                        } else {
                                            Text(Self.freqLabel(m))
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: proactiveOn ? "bell.badge.fill" : "bell")
                        }
                        Button {
                            Haptics.light()
                            showProfile = true
                        } label: {
                            ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 30)
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfile) { ChatProfileView() }
            .sheet(item: $openRedPacket) { rp in RedPacketOpenedView(msg: rp) }
            .sheet(isPresented: $showCall) { CallView() }
            .sheet(isPresented: $showCompose) {
                RedPacketComposeView { amount, blessing in
                    send(rawContent: "[红包:\(amount):\(blessing)]")
                }
            }
            .onAppear {
                restoreHistory()
                claimedKeys = Set(UserDefaults.standard.stringArray(forKey: "chat.claimedKeys") ?? [])
                voicePaths = UserDefaults.standard.dictionary(forKey: "chat.voiceMap") as? [String: String] ?? [:]
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard config.loggedIn, proactiveOn, !proactiveBusy, !sending, !recording else { return }
                guard Date().timeIntervalSince(lastActivity) >= Double(proactiveMinutes) * 60 else { return }
                proactivePing()
            }
        }
    }

    static func freqLabel(_ m: Int) -> String {
        switch m {
        case 10: return "每 10 分钟"
        case 30: return "每 30 分钟"
        case 60: return "每 1 小时"
        default: return "每 3 小时"
        }
    }


    /// AI 主动发一条消息（右上角可配置频率）
    private func proactivePing() {
        proactiveBusy = true
        lastActivity = Date()
        sending = true
        Task {
            do {
                let reply = try await store.sendChat(
                    sessionId: sessionId,
                    content: "[自动问候]",
                    attachments: [],
                    reasoning: reasoning,
                    systemPrompt: roomSystemPrompt
                        + "\n\n【主动消息】用户长时间没有说话，系统触发了你主动发消息。请直接发一条简短自然的关心或问候（1-2 句），不要提这是系统或定时任务，不要重复之前说过的内容。"
                )
                if sessionId != reply.sessionId {
                    sessionId = reply.sessionId
                    roomSessionIdStr = String(reply.sessionId)
                }
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 2, role: "assistant", content: reply.reply))
            } catch { /* 静默 */ }
            sending = false
            proactiveBusy = false
        }
    }

    private var bubbleAIBg: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// 消息按段拆成独立气泡（红包/语音各自成行，各带头像；领取提示为红色小字）
    private var displayItems: [ChatBubbleItem] {
        var out: [ChatBubbleItem] = []
        for m in messages {
            // 用户发送的本地录音：[语音:Ns] 转写文字 → 语音文件气泡
            if m.role == "user", m.content.hasPrefix("[语音:") {
                let c = m.content
                if let close = c.range(of: "s]") {
                    let numPart = c[c.index(c.startIndex, offsetBy: 4)..<close.lowerBound]
                    let secs = Int(numPart) ?? 1
                    let transcript = String(c[close.upperBound...]).trimmingCharacters(in: .whitespaces)
                    out.append(ChatBubbleItem(id: "\(m.id)-vf", msg: m, segment: .voiceFile(secs: secs, transcript: transcript)))
                    continue
                }
            }
            // 定时触发的隐藏问候，不渲染
            if m.role == "user", m.content == "[自动问候]" { continue }
            for (i, seg) in RedPacketParser.parse(m.content).enumerated() {
                switch seg {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        out.append(ChatBubbleItem(id: "\(m.id)-t\(i)", msg: m, segment: .text(trimmed)))
                    }
                case .redPacket:
                    let key = "\(m.id)-r\(i)"
                    out.append(ChatBubbleItem(id: key, msg: m, segment: seg))
                    // 领取提示（红色小字，持久化）
                    let who = m.role == "user" ? "\(aiName)" : "你"
                    if claimedKeys.contains(key) {
                        out.append(ChatBubbleItem(id: key + "-c", msg: m, segment: .claim(text: "\(who)已领取红包")))
                    }
                case .voice:
                    // 语音单独一个聊天气泡
                    out.append(ChatBubbleItem(id: "\(m.id)-v\(i)", msg: m, segment: seg))
                case .claim:
                    let who = m.role == "user" ? aiName : "你"
                    out.append(ChatBubbleItem(id: "\(m.id)-cl\(i)", msg: m, segment: .claim(text: "\(who)已领取红包")))
                case .voiceFile:
                    break // 上面已处理
                }
            }
        }
        return out
    }

    // MARK: - 输入栏（仿微信：红包 / 语音 / 文字）

    private var inputBar: some View {
        Group {
            if recording {
                recordingBar
            } else {
                normalInputBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel(22)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var normalInputBar: some View {
        HStack(spacing: 10) {
            // 发红包
            Button {
                Haptics.light()
                showCompose = true
            } label: {
                Image(systemName: "giftcircle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.packetRed)
            }
            .accessibilityLabel("发红包")

            // 发语音
            Button {
                Haptics.light()
                startRecording()
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("发语音")

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
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.packetRed)
                .frame(width: 10, height: 10)
                .opacity(recordSecs % 2 == 0 ? 1 : 0.3)
            Text("正在录音 \(recordSecs)s")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                cancelRecording()
            } label: {
                Text("取消")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                sendRecording()
            } label: {
                Text("发送")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
        }
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

    /// 保存语音文件映射与领取记录（本地持久化）
    private func persistChatExtras() {
        UserDefaults.standard.set(Array(claimedKeys), forKey: "chat.claimedKeys")
        UserDefaults.standard.set(voicePaths, forKey: "chat.voiceMap")
    }

    /// AI 红包被点击领取 → 记录并显示红色小字
    private func markClaimed(key: String) {
        claimedKeys.insert(key)
        persistChatExtras()
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
        【领取红包】当用户发来红包（他的消息是 [红包:…]）时，你的回复开头加上 [已领红包] 标记再道谢，例如「[已领红包]谢谢老板！」。标记会渲染成领取提示，不会显示原文。
        【语音消息】想用语音说话时，把要说的内容包在 [语音:内容] 里（例如 [语音:晚安，做个好梦～]），它会变成一条可以点击播放的语音气泡，与文字消息独立发送。偶尔使用即可。
        【用户语音】用户发来 [语音:Ns] 转写文字 时，那是他发的语音消息，「转写文字」就是他说的内容，请自然回应内容本身。
        """)
        return parts.joined(separator: "\n\n")
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        send(rawContent: text)
    }

    /// 统一发送入口：文字 / 红包标记 / 语音消息都走这里
    private func send(rawContent: String) {
        guard !sending else { return }
        Haptics.light()
        inputFocus = false
        lastActivity = Date()
        let msg = ChatMessage(id: Int64(Date().timeIntervalSince1970), role: "user", content: rawContent)
        messages.append(msg)
        sending = true
        Task {
            do {
                let reply = try await store.sendChat(sessionId: sessionId, content: rawContent, attachments: [], reasoning: reasoning, systemPrompt: roomSystemPrompt)
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

    // MARK: - 语音录制（用户发给 AI）

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
                guard ok else {
                    store.toast = "需要麦克风权限才能发语音"
                    return
                }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let path = dir.appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a").path
                    let rec = try AVAudioRecorder(url: URL(fileURLWithPath: path), settings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                    ])
                    rec.record()
                    recorder = rec
                    recordStart = Date()
                    recordSecs = 0
                    recording = true
                    Haptics.light()
                    recordTimer?.invalidate()
                    recordTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        recordSecs += 1
                        if recordSecs >= 60 { sendRecording() }
                    }
                } catch {
                    store.toast = "录音启动失败"
                }
            }
        }
    }

    private func cancelRecording() {
        recorder?.stop()
        let path = recorder?.url.path
        recorder = nil
        recordTimer?.invalidate()
        recording = false
        if let path { try? FileManager.default.removeItem(atPath: path) }
        Haptics.tap()
    }

    private func sendRecording() {
        recordTimer?.invalidate()
        let secs = max(1, Int(Date().timeIntervalSince(recordStart)))
        recorder?.stop()
        let path = recorder?.url.path
        recorder = nil
        recording = false
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        let msgId = Int64(Date().timeIntervalSince1970)
        // 本地立即占位（转写完成后补内容）
        messages.append(ChatMessage(id: msgId, role: "user", content: "[语音:\(secs)s]"))
        sending = true
        Task {
            var transcript = ""
            if let data = try? await SpeechKit.transcribeFile(url: URL(fileURLWithPath: path)) {
                transcript = data
            }
            let content = "[语音:\(secs)s]" + (transcript.isEmpty ? "" : " " + transcript)
            if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                messages[idx].content = content
            }
            voicePaths["\(msgId)"] = path
            persistChatExtras()
            lastActivity = Date()
            sending = true
            do {
                let reply = try await store.sendChat(sessionId: sessionId, content: content, attachments: [], reasoning: reasoning, systemPrompt: roomSystemPrompt)
                if sessionId != reply.sessionId {
                    sessionId = reply.sessionId
                    roomSessionIdStr = String(reply.sessionId)
                }
                messages.append(ChatMessage(id: msgId + 1, role: "assistant", content: reply.reply))
            } catch {
                messages.append(ChatMessage(id: msgId + 1, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
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
    var voicePath: String? = nil
    let onOpenRedPacket: (String, Double?) -> Void

    var isUser: Bool { item.msg.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) } else { ChatAvatar(image: aiImage, name: aiName, isAI: true, size: 48) }
            bubble
            if isUser { ChatAvatar(image: meImage, name: meName, size: 48) } else { Spacer(minLength: 60) }
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
        case .voiceFile(let secs, _):
            // 用户发的本地录音（蓝色气泡）
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                VoiceFileBubble(id: item.id, path: voicePath, secs: secs)
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 268, alignment: isUser ? .trailing : .leading)
        case .claim(let note):
            Text(note)
                .font(.caption2)
                .foregroundStyle(Theme.packetRed)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - 聊天资料编辑（AI 头像昵称 + 我的头像昵称）

struct ChatProfileView: View {
    @EnvironmentObject var av: AvatarStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.displayName") private var aiName = "Amore"
    @AppStorage("me.displayName") private var meName = "我"
    /// 头像形状（与 ChatAvatar 共享）：false 圆角方形 / true 圆形
    @AppStorage("chat.avatarCircle") private var circleShape = false
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
                    HStack {
                        Text("头像形状").font(.subheadline)
                        Spacer()
                        Picker("头像形状", selection: $circleShape) {
                            Text("圆角方形").tag(false)
                            Text("圆形").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 156)
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

