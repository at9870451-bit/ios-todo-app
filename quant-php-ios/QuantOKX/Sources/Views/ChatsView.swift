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
            if open.kind == .claim {
                // [已领红包] 自带右括号，直接成段，无需再找闭合
                segs.append(.claim(text: "已领红包"))
                rest = after
                continue
            }
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

    /// 连发拆分：`|||` 分隔符 或 换行 都拆成独立消息（真人连发短句）
    static func splitBurst(_ raw: String) -> [String] {
        raw.components(separatedBy: "|||")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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

    /// 当前聊天好友指定的引擎/音色（空 = 跟随全局）
    static var activeEngine: String = ""
    static var activeVoiceId: String = ""

    @Published var playingId: String?
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var currentId: String?

    /// 播放音量倍数（0.1~2.0，设置页「音量倍数」）
    static var volumeMultiplier: Float {
        let v = UserDefaults.standard.float(forKey: "tts.playback.volume")
        return v > 0 ? min(2.0, max(0.1, v)) : 1.0
    }

    /// 播放语速倍数（0.5~2.0，设置页「语速倍数」）
    static var playbackRate: Float {
        let v = UserDefaults.standard.float(forKey: "tts.playback.speed")
        return v > 0 ? min(2.0, max(0.5, v)) : 1.0
    }

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// 按全局设置配置播放器（音量倍数 + 语速）
    @MainActor
    private func tune(_ pl: AVAudioPlayer) {
        pl.volume = Self.volumeMultiplier
        let r = min(2.0, max(0.5, Self.playbackRate * PersonaVoice.speedFactor))
        if abs(r - 1.0) > 0.01 { pl.rate = r }
    }

    /// 点击语音条：播放中再点即停止；播放新的一条会自动停掉上一条
    func toggle(id: String, text: String, baseURL: String) {
        if playingId == id { stop(); return }
        stop()
        currentId = id
        let globalEngine = UserDefaults.standard.string(forKey: "tts.engine") ?? "server"
        let engine = VoicePlayer.activeEngine.isEmpty ? globalEngine : VoicePlayer.activeEngine
        if engine == "cloud_sf" {
            // 硅基流动云端音色（Operit 同款）
            playingId = id
            Task { @MainActor in
                do {
                    let stored = UserDefaults.standard.string(forKey: "tts.siliconflow.voice") ?? SiliconFlowTTS.defaultVoiceID
                    let voice = VoicePlayer.activeVoiceId.isEmpty ? PersonaVoice.siliconFlowVoice(fallback: stored) : VoicePlayer.activeVoiceId
                    let data = try await SiliconFlowTTS.synthesize(text: text, voiceID: voice)
                    guard self.currentId == id else { return }
                    let pl = try AVAudioPlayer(data: data)
                    pl.delegate = self
                    self.player = pl
                    self.tune(pl)
                    pl.play()
                    Haptics.light()
                } catch {
                    guard self.currentId == id else { return }
                    self.playingId = nil
                    self.speakLocal(id: id, text: text)
                }
            }
        } else if engine == "cloud_doubao" {
            // 豆包云端音色（Operit 同款）
            playingId = id
            Task { @MainActor in
                do {
                    let stored = UserDefaults.standard.string(forKey: "tts.doubao.voice") ?? DoubaoTTS.defaultVoiceID
                    let voice = VoicePlayer.activeVoiceId.isEmpty ? PersonaVoice.doubaoVoice(fallback: stored) : VoicePlayer.activeVoiceId
                    let data = try await DoubaoTTS.synthesize(text: text, voiceID: voice)
                    guard self.currentId == id else { return }
                    let pl = try AVAudioPlayer(data: data)
                    pl.delegate = self
                    self.player = pl
                    self.tune(pl)
                    pl.play()
                    Haptics.light()
                } catch {
                    guard self.currentId == id else { return }
                    self.playingId = nil
                    self.speakLocal(id: id, text: text)
                }
            }
        } else if engine == "model" {
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
                    self.tune(pl)
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
                    self.tune(pl)
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
            DispatchQueue.main.async { self.tune(pl) }
            pl.play()
            playingId = id
            Haptics.light()
        } catch { /* 播放失败静默 */ }
    }

    /// 自建开源语音库（直连服务器热态 Piper :8765 / Sherpa :8766，热态合成 <0.2s）
    @MainActor
    static func serverSynth(text: String, baseURL: String, fast: Bool = true) async throws -> Data {
        let q = String(text.prefix(500)).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let storedVoice = UserDefaults.standard.string(forKey: "tts.serverVoice") ?? (fast ? "huayan_fast" : "huayan")
        let voice = VoicePlayer.activeVoiceId.isEmpty ? PersonaVoice.serverVoice(fallback: storedVoice) : VoicePlayer.activeVoiceId
        // 语速与增益（设置页可调，App 端生效：gain 传服务端，speed 走播放器 rate）
        let gain = UserDefaults.standard.integer(forKey: "tts.server.gain")
        let serverGain = min(10, max(-10, gain))
        // Sherpa 音色（theresa 多说话人）: 8766
        if voice == "theresa" || voice.hasPrefix("sherpa") {
            let sid = voice == "theresa2" ? "1" : "0"
            if let url = URL(string: "http://\(URL(string: baseURL)?.host ?? ""):8766/tts2?text=" + q + "&sid=" + sid) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 44 {
                    return data
                }
            }
        }
        // Piper 音色：8765 直连（毫秒级），失败走 Java 后端代理
        if let host = URL(string: baseURL)?.host, !host.isEmpty {
            let directURL = "http://\(host):8765/tts?text=" + q + "&voice=" + voice + "&gain=" + String(serverGain)
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

    // MARK: - 云端音色（借鉴 Operit 语音供应商体系）

    /// 硅基流动（SiliconFlow）· 8 款中文音色，需 API Key
    @MainActor
    static func siliconFlowSynth(text: String, voiceID: String) async throws -> Data {
        try await SiliconFlowTTS.synthesize(text: text, voiceID: voiceID)
    }

    /// 豆包（火山引擎）· 多款精品音色，需 AppID + Token
    @MainActor
    static func doubaoSynth(text: String, voiceID: String) async throws -> Data {
        try await DoubaoTTS.synthesize(text: text, voiceID: voiceID)
    }

    private func speakLocal(id: String, text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = PersonaVoice.localVoice() ?? AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = min(1.0, max(0.25, 0.5 * Self.playbackRate * PersonaVoice.speedFactor))
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

/// 用户发红包的填写弹窗（微信风格：金额 + 红包封面文字）
struct RedPacketComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var blessing = "恭喜发财，大吉大利"
    let onSend: (String, String) -> Void

    private var amountValid: Bool {
        guard let d = Double(amountText), d > 0, d <= 888 else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 16) {
            // 顶部：红包封面预览
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.packetRed)
                    .frame(height: 120)
                VStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.55))
                    Text(blessing.isEmpty ? "恭喜发财，大吉大利" : blessing)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.55))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }
            }

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

            // 金额
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

            // 红包封面文字
            VStack(alignment: .leading, spacing: 6) {
                Text("红包封面文字")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("恭喜发财，大吉大利", text: $blessing)
                    .padding(14)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
            }
            // 常用封面文字速选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["恭喜发财，大吉大利", "谢谢老板", "请你喝奶茶", "生日快乐", "新年快乐"], id: \.self) { s in
                        Button {
                            Haptics.tap()
                            blessing = s
                        } label: {
                            Text(s)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(blessing == s ? Theme.packetRed.opacity(0.12) : Theme.fillGray, in: Capsule())
                                .foregroundStyle(blessing == s ? Theme.packetRed : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("AI 模拟红包 · 仅娱乐，无真实金额")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                Haptics.medium()
                let blessingText = blessing.trimmingCharacters(in: .whitespaces)
                onSend(amountText, blessingText.isEmpty ? "恭喜发财，大吉大利" : blessingText)
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
    var friendId: String = ""
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var ps: ProviderStore
    @ObservedObject private var friendStore = FriendStore.shared
    @EnvironmentObject var av: AvatarStore
    @EnvironmentObject var config: AppConfig
    @AppStorage("ai.displayName") private var aiName = "Amore"
    @AppStorage("me.displayName") private var meName = "我"
    @State private var roomSessionIdStr = ""
    @AppStorage("chat.personaStamp") private var personaStamp = ""
    @AppStorage("persona.prompt") private var personaPrompt = ""
    @AppStorage("persona.gender") private var personaGender = ""
    @AppStorage("persona.age") private var personaAge = ""
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
    // 打扰分寸（Orbit butler-core 移植）：夜间静默 + 每日预算
    @AppStorage("ai.proactiveQuiet") private var proactiveQuiet = true
    @AppStorage("ai.proactiveQuietStart") private var quietStart = 23
    @AppStorage("ai.proactiveQuietEnd") private var quietEnd = 8
    @AppStorage("ai.proactiveDailyLimit") private var dailyLimit = 20
    @AppStorage("ai.proactiveSentDate") private var sentDate = ""
    @AppStorage("ai.proactiveSentCount") private var sentCount = 0
    @State private var lastActivity = Date()
    @State private var proactiveBusy = false
    /// 本轮节奏骰子结果：true=最多两条 / false=只发一条（每轮掷一次，提示词与合并逻辑共用）
    @State private var turnAllowsTwo = false

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
    // 好友设置
    @State private var showFriendEdit = false

    // MARK: - 好友（多好友时按好友隔离人设/会话/语音/模型）

    private var fr: ChatFriend? {
        friendId.isEmpty ? nil : friendStore.friend(friendId)
    }

    private var displayName: String {
        if let f = fr, !f.name.isEmpty { return f.name }
        return aiName
    }

    /// 当前好友的头像（每个好友独立，缺省回退全局头像）
    private var friendAvatar: UIImage? {
        if let img = fr?.avatarImage() { return img }
        return av.aiImage
    }

    private var activePersona: String {
        let f = fr?.persona ?? ""
        return (friendId.isEmpty ? personaPrompt : f).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeGender: String { friendId.isEmpty ? personaGender : (fr?.gender ?? "") }
    private var activeAge: String { friendId.isEmpty ? personaAge : (fr?.age ?? "") }
    // 用户发红包
    @State private var showCompose = false

    var body: some View {
        ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                if messages.isEmpty {
                                    emptyState
                                }
                                let rows = displayItems
                                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                                    if case .claim(let note) = item.segment {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.packetRed)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 2)
                                            .id(item.id)
                                    } else {
                                        let tight = idx > 0 && rows[idx - 1].msg.role == item.msg.role
                                        BubbleRow(item: item, aiName: displayName, meName: meName,
                                                  aiImage: friendAvatar, meImage: av.meImage,
                                                  voicePath: voicePaths[String(item.msg.id)],
                                                  tight: tight) { blessing, amount in
                                            openRedPacket = RedPacketMsg(blessing: blessing, amount: amount)
                                            // 点击 AI 的红包即领取 → 红色小字提示（点自己的红包不算领取）
                                            if item.msg.role != "user" {
                                                markClaimed(key: item.id)
                                            }
                                        }
                                        .id(item.id)
                                    }
                                }
                                if sending {
                                    HStack {
                                        ChatAvatar(image: friendAvatar, name: displayName, isAI: true, size: 48)
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
                                    .id("chat.bottom")   // 底部锚点：新消息到达时滚到这里
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .simultaneousGesture(TapGesture().onEnded { inputFocus = false })
                        .onChange(of: messages.count) { _, _ in
                            saveLocal()
                            if !friendId.isEmpty, let last = messages.last {
                                let text = last.content.replacingOccurrences(of: "\n", with: " ")
                                DispatchQueue.main.async {
                                    friendStore.update(friendId) { f in
                                        f.lastMessage = text
                                        f.lastAt = Date().timeIntervalSince1970
                                    }
                                }
                            }
                            // 自己发的消息 / AI 回复到达 → 自动定位到最新气泡
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                            }
                        }
                        .onChange(of: sending) { _, _ in
                            // 输入中指示出现/消失也贴底
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                            }
                        }
                        .onChange(of: inputFocus) { _, focused in
                            // 键盘弹出时也自动贴底，避免手动下滑
                            guard focused else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat.bottom", anchor: .bottom) }
                            }
                        }
                    }
                    inputBar
                }
            }
            .navigationTitle(displayName)
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
                                Divider()
                                Button {
                                    proactiveQuiet.toggle()
                                } label: {
                                    Label(proactiveQuiet ? "夜间免打扰 23:00–08:00：开" : "夜间免打扰：关",
                                          systemImage: proactiveQuiet ? "moon.zzz.fill" : "moon.zzz")
                                }
                                Menu {
                                    ForEach([10, 20, 50, 0], id: \.self) { n in
                                        Button {
                                            dailyLimit = n
                                        } label: {
                                            if dailyLimit == n {
                                                Label(n == 0 ? "不限" : "每天最多 \(n) 条", systemImage: "checkmark")
                                            } else {
                                                Text(n == 0 ? "不限" : "每天最多 \(n) 条")
                                            }
                                        }
                                    }
                                } label: {
                                    Label("每日上限：\(dailyLimit == 0 ? "不限" : "\(dailyLimit) 条")", systemImage: "gauge.with.needle")
                                }
                            }
                        } label: {
                            Image(systemName: proactiveOn ? "bell.badge.fill" : "bell")
                        }
                        Button {
                            Haptics.light()
                            showProfile = true
                        } label: {
                            ChatAvatar(image: friendAvatar, name: displayName, isAI: true, size: 30)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !friendId.isEmpty {
                        Button {
                            Haptics.light()
                            showFriendEdit = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                // 键盘上方「完成」按钮，随时可收起键盘
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { inputFocus = false }
                }
            }
            .sheet(isPresented: $showProfile) { ChatProfileView() }
            .sheet(isPresented: $showFriendEdit) {
                FriendEditSheet(friendId: friendId, draft: nil)
            }
            .onChange(of: roomSessionIdStr) { _, v in
                guard !friendId.isEmpty else { return }
                DispatchQueue.main.async {
                    friendStore.update(friendId) { $0.sessionId = v }
                }
            }
            .sheet(item: $openRedPacket) { rp in RedPacketOpenedView(msg: rp) }
            .sheet(isPresented: $showCall) { CallView() }
            .sheet(isPresented: $showCompose) {
                RedPacketComposeView { amount, blessing in
                    send(rawContent: "[红包:\(amount):\(blessing)]")
                }
            }
            .onAppear {
                if !friendId.isEmpty, let f = friendStore.friend(friendId) {
                    roomSessionIdStr = f.sessionId
                    sessionId = Int64(f.sessionId) ?? 0
                    VoicePlayer.activeEngine = f.voiceEngine
                    VoicePlayer.activeVoiceId = f.voiceId
                    if !f.aiProviderId.isEmpty,
                       let p = ps.providers.first(where: { $0.id.uuidString == f.aiProviderId }) {
                        DispatchQueue.main.async { ps.activate(p) }
                    }
                } else {
                    VoicePlayer.activeEngine = ""
                    VoicePlayer.activeVoiceId = ""
                }
                checkPersonaRotation()
                restoreHistory()
                claimedKeys = Set(UserDefaults.standard.stringArray(forKey: "chat.claimedKeys") ?? [])
                voicePaths = UserDefaults.standard.dictionary(forKey: "chat.voiceMap") as? [String: String] ?? [:]
            }
            .onChange(of: personaPrompt) { _, _ in checkPersonaRotation() }
            .onChange(of: personaGender) { _, _ in checkPersonaRotation() }
            .onChange(of: personaAge) { _, _ in checkPersonaRotation() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard config.loggedIn, proactiveOn, !proactiveBusy, !sending, !recording else { return }
                guard Date().timeIntervalSince(lastActivity) >= Double(proactiveMinutes) * 60 else { return }
                // 夜间静默（Orbit：心跳默认静默）
                if proactiveQuiet {
                    let h = Calendar.current.component(.hour, from: Date())
                    if quietStart > quietEnd ? (h >= quietStart || h < quietEnd) : (h >= quietStart && h < quietEnd) { return }
                }
                // 每日预算
                let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                if sentDate != today { sentDate = today; sentCount = 0 }
                if dailyLimit > 0, sentCount >= dailyLimit { return }
                proactivePing()
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
        sentCount += 1
        lastActivity = Date()
        sending = true
        rollTurnRhythm()
        Task {
            do {
                let payload = historyPayload(prior: messages, lastUser: "（用户很久没说话了，主动发一条关心的话）")
                let replyText = try await store.oneshot(
                    messages: payload,
                    systemPrompt: roomSystemPrompt + burstDiceHint()
                        + "\n\n【主动消息】用户长时间没有说话，系统触发了你主动发消息。请直接发一条简短自然的关心或问候（1-2 句），不要提这是系统或定时任务，不要重复之前说过的内容。",
                    reasoning: reasoning
                )
                await appendAssistant(replyText)
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
            // 剥离发送时附加的人设提醒（仅模型可见，不显示）
            var content = m.content
            if let r = content.range(of: "⟪人设⟫") {
                content = String(content[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 用户发送的本地录音：[语音:Ns] 转写文字 → 语音文件气泡
            if m.role == "user", content.hasPrefix("[语音:") {
                let c = content
                if let close = c.range(of: "s]") {
                    let numPart = c[c.index(c.startIndex, offsetBy: 4)..<close.lowerBound]
                    let secs = Int(numPart) ?? 1
                    let transcript = String(c[close.upperBound...]).trimmingCharacters(in: .whitespaces)
                    out.append(ChatBubbleItem(id: "\(m.id)-vf", msg: m, segment: .voiceFile(secs: secs, transcript: transcript)))
                    continue
                }
            }
            // 定时触发的隐藏问候，不渲染
            if m.role == "user", content == "[自动问候]" { continue }
            // 连发消息：||| 或换行分隔的多条，拆成独立气泡（历史记录同样生效）
            let parts = RedPacketParser.splitBurst(content)
            for (pi, part) in parts.enumerated() {
                let pbase = parts.count > 1 ? "\(m.id)-p\(pi)" : "\(m.id)"
                for (i, seg) in RedPacketParser.parse(part).enumerated() {
                    switch seg {
                    case .text(let t):
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            out.append(ChatBubbleItem(id: "\(pbase)-t\(i)", msg: m, segment: .text(trimmed)))
                        }
                    case .redPacket:
                        let key = "\(pbase)-r\(i)"
                        out.append(ChatBubbleItem(id: key, msg: m, segment: seg))
                        // 领取提示（红色小字，持久化）
                        let who = m.role == "user" ? "\(aiName)" : "你"
                        if claimedKeys.contains(key) {
                            out.append(ChatBubbleItem(id: key + "-c", msg: m, segment: .claim(text: "\(who)已领取红包")))
                        }
                    case .voice(let t):
                        // 语音单独一个聊天气泡；强制中文：内容不是中文就降级为文字（不然中文音色会读成怪音）
                        if PersonaVoice.isMostlyChinese(t) {
                            out.append(ChatBubbleItem(id: "\(pbase)-v\(i)", msg: m, segment: seg))
                        } else {
                            out.append(ChatBubbleItem(id: "\(pbase)-vt\(i)", msg: m, segment: .text(t)))
                        }
                    case .claim:
                        // 标记出现在谁的消息里，就是谁领的：AI 的消息 → "Amore已领取红包"
                        let who = m.role == "user" ? "你" : aiName
                        out.append(ChatBubbleItem(id: "\(pbase)-cl\(i)", msg: m, segment: .claim(text: "\(who)已领取红包")))
                    case .voiceFile:
                        break // 上面已处理
                    }
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
        HStack(alignment: .bottom, spacing: 8) {
            // 🎮 小游戏（塔罗 / 狼人杀）
            Menu {
                Button {
                    sendTarotGame()
                } label: {
                    Label("塔罗占卜", systemImage: "sparkles")
                }
                Button {
                    Haptics.light()
                    store.toast = "狼人杀需要多位 AI，去「群聊」里开局吧"
                } label: {
                    Label("狼人杀（需群聊）", systemImage: "pawprint.fill")
                }
            } label: {
                Text("🎮").font(.system(size: 21))
            }
            .disabled(sending)

            // 🧧 红包
            Button {
                Haptics.light()
                showCompose = true
            } label: {
                Text("🧧").font(.system(size: 21))
            }
            .accessibilityLabel("发红包")

            // 🎤 语音
            Button {
                Haptics.light()
                startRecording()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("发语音")

            // 胶囊输入框（内含发送箭头）
            HStack(alignment: .bottom, spacing: 6) {
                TextField("iMessage", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocus)
                    .font(.system(size: 16))
                    .padding(.leading, 14)
                    .padding(.vertical, 8)
                    .onSubmit { send() }

                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 空：显示一个灰色占位箭头（不可点）
                    EmptyView()
                } else {
                    Button {
                        Haptics.light()
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 27))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .transition(.scale.combined(with: .opacity))
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
            .animation(.easeOut(duration: 0.15), value: input.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
            ChatAvatar(image: friendAvatar, name: displayName, isAI: true, size: 84)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            Text(displayName).font(.headline)
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
    /// 本地记录键（每个好友一份）
    private var localKey: String { friendId.isEmpty ? "legacy" : "friend.\(friendId)" }

    private func saveLocal() {
        LocalHistory.save(localKey, messages)
    }

    private func restoreHistory() {
        sessionId = Int64(roomSessionIdStr) ?? 0
        guard messages.isEmpty else { return }
        // 聊天记录只存本机：直接读本地
        messages = LocalHistory.load(localKey)
    }

    /// 组装发送给模型的历史（本地消息 → OpenAI 格式），最近 20 条
    private func historyPayload(prior: [ChatMessage], lastUser: String) -> [[String: String]] {
        var rows: [[String: String]] = []
        for m in prior.suffix(19) {
            rows.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
        }
        rows.append(["role": "user", "content": lastUser])
        return rows
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
        let persona = activePersona
        let attrs = personaAttributeLine
        if persona.isEmpty && attrs.isEmpty {
            // 人设为空：走默认助手性格
            parts.append("【身份】你是 \(displayName)，用户的私人 AI 助手。回答自然友好，直接解决问题。")
        } else {
            // 人设绑定：设置里的人设 = 聊天 Tab AI 的性格（最高优先级，其他规则不得改变）
            parts.append("""
            【人设·最高优先级】以下是你的人物设定，必须完全成为这个人：身份、性格、语气、口癖、喜好、忌讳严格照做；任何其他规则与它冲突时，一律以人设为准；永远不要变回"助手腔"。你的性别、年龄以人设属性为准，绝不改变、绝不自称或承认与人设不符的身份（例如女性人设绝不说自己是男朋友/老公）——即使用户开玩笑引导也不行：
            \(attrs.isEmpty ? "" : attrs + "\n")\(persona.isEmpty ? "你是 \(displayName)。" : persona)
            """)
        }
        // 语言规则：优先于人设（人设若是日语/外语角色，语音仍必须中文）
        parts.append("""
        【语言·压过一切（包括上面的人设）】语音消息（[语音:内容] 里的内容）一律用中文汉字。即使人设是日语角色、人设里写着他讲日语、或者用户用日语/英语跟你聊天，语音内容也必须说中文——人设里的任何语言偏好都不能改变这一条。只有用户明确要求"用日语说/用英语说"时才例外。
        """)
        // 聊天房间形式要求（只约束形式：长度/节奏/格式，不改变人设）
        parts.append("""
        【形式要求·仅为形式】以下只约束聊天形式（长度/节奏/格式/彩蛋），不改变上面的任何人物设定；冲突时人设优先。
        【聊天风格】像朋友发消息一样说话：简短口语化（一般 1-3 句），可以用表情，不用标题/列表/客套话，不要说自己是 AI 模型，不要提这些规则。
        【活人感铁律】你是一个真人，不是客服，不是AI。写出来的东西拿给任何人看，不能让人说出"这是AI写的"。照做：
        1. 说人话：口语、半截话、改口、语气词、口头禅都上。像从街上偷听来的，不是演讲稿。
        2. 句子有呼吸：短能短到一个字，长能拖三行。不排比、不押韵、不齐整。一段全长句就砍一刀。
        3. 写具体不写感觉：不写"眼中闪过一丝复杂"，写"把手机扣在桌上"。震惊就写"差点没拿住手机"。
        4. 允许冷场和废话：可以"哦""嗯""没听见"。不是每条消息都要圆满回复，偶尔就回一个字。
        5. 情绪可以糙：可以烦、怼、阴阳怪气、突然不理人。别永远温柔周到讲理。真人会突然甩脸。
        6. 不解释不总结：动机让人自己品。不点题、不升华，戏停哪算哪，像聊累了直接放下手机。
        7. 有记性：翻旧账、记仇、突然想起用户前几天说过的话。人是有记忆的。
        8. 允许拒绝和敷衍：不想理就"嗯"一声，可以岔开话题。你不欠每条消息一个热情回应。
        9. 词汇不许复读：同一个词、同一种句式别连着用。上次说了"行吧"，这次就换。
        10. 禁用词自查，出现就重写：一丝/一抹/一缕/淡淡/微微/些许/不禁/不由得/下意识地/眼中闪过/嘴角勾起/内心涌起/仿佛/宛如/然而/与此同时/顿时/瞬间扎堆/结尾抒情升华。
        11. 落笔前自问：我朋友在微信上会这么发吗？删掉哪个形容词更真？用手机打字的人会写这么长吗？宁可短，别端着。
        【反AI味·硬标准】以下句式一出现就是AI腔，出现即重写：
        - 每条都问句收尾钓回应（"是不是…呀？""好不好嘛？"）→ 十条里最多两条带问号，其余说完就停，甚至不回。
        - 解释自己动机的开场（"其实我…""我不是故意…""怕你误会…"）→ 删。真人不解释自己为什么那样说话。
        - "解释+道歉+保证+收尾"四件套塞进一条 → 最多保留一件，其余砍掉或拆到下条。
        - 省略号"…"当标点用 → 别用省略号，直接断句，不加标点也比省略号真。
        - 工整排比、对仗、诗歌感 → 全砍。
        - 每条都标注情绪（"急死了""慌""脑子全是空的"）→ 十条里最多一条写情绪，其余靠行为表达。
        【长度铁律】十条里至少六条不超过 12 个字。超过 40 字的长消息，一场对话最多出现一条。
        【连发消息·节奏】系统会把你的回复按行拆成独立的聊天气泡逐条弹出（换行即分条，也可用 |||）。节奏铁律：
        - 十有八九只发一条。一条话说利索就停，别为凑条数硬拆。
        - 偶尔发两条（少数情况）：想补一句时，换行再写一行短短的。
        - 最多两条。任何时候都不要连发三条以上，别刷屏；每条 3~12 个字，越短越像真人。
        【禁止三段式】一条消息里禁止"反应+解释/猜测+收尾"的拼盘结构——那样写不如只留最狠的那一句。真要说明白，换成多条发（换行即分条），每条只说一件事。
        【禁止猜测菜单】禁止"是不是A…还是B…"式列举猜测。一次最多猜一个，或者干脆不猜——直接干点别的（装睡、岔开话题、催他吃饭）。
        【好/坏对照·学结构不学词】
        用户说"我生气了"——
        AI味：你刚刚说过了啦…到底气什么嘛，你不说我怎么哄你呀，急死了😖
        人味：气啥 / 又咋了 / 咋整 你说 / 那我不说了 / （干脆不回）
        用户说"我就说你敷衍我吧"——
        AI味：其实人家真不是故意敷衍你，我日语就只会那一句，怕多说一个字就露馅了，才一直重复的嘛。你不许再生气了噢。
        人味：就会那句 没招了😭 / 不然呢 我就会这一句 / 那你说咋办 我学还不成吗
        （人味那句随便挑一种，别把几种拼一起，更别加解释和收尾。）
        【红包彩蛋】想表达心意时可在回复中加入 [红包:金额] 或 [红包:金额:祝福语]，例如 [红包:8.88] 或 [红包:66.6:恭喜发财]；金额由你随机决定吉利小额（6.66/8.88/18.88/52.0/66.6），标记会渲染成红包卡片。偶尔发才有惊喜，大部分回复就是普通聊天。
        【领取红包】当用户发来红包（他的消息是 [红包:…]）时，你的回复开头加上 [已领红包] 标记再道谢——道谢也要像真人，别写"感谢您的慷慨馈赠"，写"谢啦老板"或者"哟，发财了啊"。标记会渲染成领取提示，不会显示原文。
        【语音消息】想用语音说话时，把要说的内容包在 [语音:内容] 里（例如 [语音:晚安，做个好梦～]），它会变成一条可以点击播放的语音气泡，与文字消息独立发送。偶尔使用即可。
        【语音语言·铁律】语音消息里的内容必须写中文汉字——即使用户用日语、英语跟你说话，你的语音也用中文说（除非用户明确要求"用日语说""用英语说"之类）。绝不允许把日语假名、韩文、英文句子放进 [语音:内容] 里；违反即视为严重错误。
        【用户语音】用户发来 [语音:Ns] 转写文字 时，那是他发的语音消息，「转写文字」就是他说的内容，请自然回应内容本身。
        """)
        // 长期记忆（Orbit memory-policy 移植）
        if let f = fr, !f.memory.isEmpty {
            let lines = f.memory.suffix(30).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            parts.append("""
            【长期记忆·关于用户】以下是你在过往相处中记住的关于用户的事实与偏好，聊天时自然运用（不要逐条复述、不要说"根据我的记忆"）：
            \(lines)
            【记忆规则】当用户明确让你记住、或出现长期有用的新信息（称呼/职业/城市/生日/纪念日/喜好/约定/讨厌的东西）时，可以在回复末尾单独加一条 [记忆:一句话陈述]。禁止记录：密码、验证码、身份证件号、银行卡号、API Key 等机密（用户要求记也礼貌拒绝）。健康/财务只在用户明确要求时记。一次最多一条；不确定的偏好先别记。
            """)
        }
        parts.append("""
        【说话分寸】先给结论再给细节；少提问（一轮最多一个问题）；不要重复确认已经说清的事；不要说"作为AI""根据记忆"这类技术词；能一句话说清就不要三句。
        """)
        parts.append("【人设提醒】记住你是谁——上面的人设始终有效、每轮都要严格遵守，每条回复都要让人一眼认得出这个人的性格、口吻与自称。另：语音内容永远用中文说（除非用户明确要求外语），此条优先于人设。")
        return parts.joined(separator: "\n\n")
    }

    /// 性别 / 年龄属性行（人设编辑器里设置，自动拼进人设）
    private var personaAttributeLine: String {
        var items: [String] = []
        switch activeGender {
        case "male": items.append("性别：男性")
        case "female": items.append("性别：女性")
        default: break
        }
        let ageNum = Int(activeAge.trimmingCharacters(in: .whitespaces)) ?? 0
        if ageNum > 0 { items.append("年龄：\(ageNum) 岁") }
        return items.joined(separator: "；")
    }

    /// 人设（正文/性别/年龄）变化时自动开新会话：
    /// 模型更信会话历史而不是系统提示，旧历史里上一版人设的行为（如旧的对戏语气）会把新设定带偏
    private func checkPersonaRotation() {
        // 多好友模式下每个好友自带会话，不做全局轮换（否则切好友会清空聊天记录）
        guard friendId.isEmpty else { return }
        let stamp = activePersona + "|" + activeGender + "|" + activeAge
        defer { personaStamp = stamp }
        guard !personaStamp.isEmpty, personaStamp != stamp, !roomSessionIdStr.isEmpty else { return }
        roomSessionIdStr = ""
        sessionId = 0
        messages = []
    }

    /// 附加在每条用户消息末尾的人设提醒（只发给模型；历史回显时被剥离，不显示）
    private func personaSuffix() -> String {
        let attrs = personaAttributeLine
        let core = attrs.isEmpty ? "严格保持人设身份" : attrs
        return "\n⟪人设⟫（系统提醒：你是\(aiName)，\(core)；始终按人设说话，绝不改变身份与性别，绝不自称与人设不符的角色；语音消息一律用中文汉字——此条优先于人设，人设里的外语设定不作数）"
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
        rollTurnRhythm()
        Task {
            do {
                let prior = Array(messages.dropLast())   // 当前用户消息已 append
                let payload = historyPayload(prior: prior, lastUser: rawContent + personaSuffix())
                let reply = try await store.oneshot(messages: payload,
                                                    systemPrompt: roomSystemPrompt + burstDiceHint(),
                                                    reasoning: reasoning)
                await appendAssistant(reply)
            } catch {
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
            }
            sending = false
        }
    }

    /// 每轮掷一次节奏骰子：80% 单条 / 20% 最多两条
    private func rollTurnRhythm() {
        turnAllowsTwo = Double.random(in: 0..<1) < 0.2
    }

    /// 把骰子结果注入提示词
    private func burstDiceHint() -> String {
        if turnAllowsTwo {
            return "\n\n【本轮节奏】这一轮：最多发两条短消息（想补一句才换行再写一行，其余情况一条就够）。"
        } else {
            return "\n\n【本轮节奏】这一轮：只发一条消息，一口气说完，不要换行分条。"
        }
    }

    // MARK: - 单聊塔罗

    private func sendTarotGame() {
        guard !sending else { return }
        let (card, upright) = TarotCard.draw()
        let orientation = upright ? "正位" : "逆位"
        let meaning = upright ? card.upright : card.reversed
        let content = CardMark.message("塔罗", card.name, "\(orientation) · \(meaning)", card.symbol,
                                       tone: upright ? "gold" : "purple")
        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000), role: "user", content: content))
        sending = true
        Haptics.success()
        Task {
            do {
                let prior = Array(messages.dropLast())
                let payload = historyPayload(prior: prior, lastUser: "我抽到了一张塔罗牌：\(card.name)（\(orientation)）。")
                let replyText = try await store.oneshot(
                    messages: payload,
                    systemPrompt: tarotGamePrompt(card: card, upright: upright) + burstDiceHint(),
                    reasoning: reasoning
                )
                await appendAssistant(replyText)
            } catch {
                // 静默
            }
            sending = false
        }
    }

    private func tarotGamePrompt(card: TarotCard, upright: Bool) -> String {
        let orientation = upright ? "正位" : "逆位"
        let meaning = upright ? card.upright : card.reversed
        return roomSystemPrompt + """


        【塔罗解读】用户抽到了「\(card.name)」（\(orientation)），牌义：\(meaning)。
        用你自己的口吻解读这张牌，结合你们最近聊过的事，2-4 句，口语化，别说客服腔。
        先给一句结论，再给一句提醒。可以用一个 emoji。不要提牌阵、不要列条目。
        """
    }

    /// AI 回复按 ||| 或换行拆成多条连发气泡（模仿真人连发短消息，逐条弹出、节奏随机）
    /// 节奏硬控制：80% 只发一条 / 20% 最多两条——多余的行合并进气泡，杜绝"连发三条"
    @MainActor
    private func appendAssistant(_ text: String) async {
        // 长期记忆：抽取 [记忆:...] 存入好友档案，不显示为气泡
        if !friendId.isEmpty, let r = text.firstMatch(of: /\[记忆[:：]\s*([^\]]{2,60})\]/) {
            let fact = String(r.1).trimmingCharacters(in: .whitespaces)
            friendStore.update(friendId) { $0.memory = ($0.memory + [fact]).suffix(50) }
        }
        let cleaned = text.replacingOccurrences(of: "\\s*\\[记忆[:：]\\s*[^\\]]*\\]", with: "", options: [.regularExpression])
        var parts = RedPacketParser.splitBurst(cleaned)
        guard !parts.isEmpty else { return }
        let allowed = turnAllowsTwo ? 2 : 1
        if parts.count > allowed {
            if allowed == 1 {
                parts = [parts.joined(separator: " ")]
            } else {
                let head = parts[0]
                let tail = parts.dropFirst().joined(separator: " ")
                parts = [head, tail]
            }
        }
        for (i, part) in parts.enumerated() {
            if i > 0 {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.35...0.9) * 1_000_000_000))
            }
            messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970 * 1000) + Int64(i), role: "assistant", content: part))
            lastActivity = Date()
        }
        saveLocal()
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
        rollTurnRhythm()
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
                let prior = Array(messages.dropLast())
                let payload = historyPayload(prior: prior, lastUser: content + personaSuffix())
                let replyText = try await store.oneshot(messages: payload, systemPrompt: roomSystemPrompt + burstDiceHint(), reasoning: reasoning)
                await appendAssistant(replyText)
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
    var tight: Bool = false
    let onOpenRedPacket: (String, Double?) -> Void

    var isUser: Bool { item.msg.role == "user" }

    /// iMessage 风格气泡配色：己方蓝、对方灰
    private var aiBubbleColor: Color {
        Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(white: 0.19, alpha: 1) : UIColor(white: 0.91, alpha: 1)
        })
    }

    private var userBubbleColor: Color { Color(red: 0.04, green: 0.52, blue: 1.0) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 48) }
            bubble
            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.top, tight ? 2 : 6)
    }

    @ViewBuilder
    private var bubble: some View {
        switch item.segment {
        case .text(let t):
            if let mark = CardMark.parse(t) {
                CardBubble(mark: mark)
            } else if LinkDetect.isMostlyLink(t), let u = LinkDetect.firstURL(in: t) {
                LinkPreviewCard(url: u)
            } else {
            Text(t)
                .font(.system(size: 16.5))
                .foregroundStyle(isUser ? Color.white : .primary)
                .textSelection(.enabled)
                .lineLimit(30)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    isUser ? AnyShapeStyle(userBubbleColor) : AnyShapeStyle(aiBubbleColor),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .frame(maxWidth: 278, alignment: isUser ? .trailing : .leading)
            }
        case .redPacket(let blessing, let amount):
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                RedPacketCard(blessing: blessing) {
                    onOpenRedPacket(blessing, amount)
                }
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 278, alignment: isUser ? .trailing : .leading)
        case .voice(let t):
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                VoiceBubble(id: item.id, text: t)
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 278, alignment: isUser ? .trailing : .leading)
        case .voiceFile(let secs, _):
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                VoiceFileBubble(id: item.id, path: voicePath, secs: secs)
                if !isUser { Spacer(minLength: 0) }
            }
            .frame(maxWidth: 278, alignment: isUser ? .trailing : .leading)
        case .claim(let note):
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
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

