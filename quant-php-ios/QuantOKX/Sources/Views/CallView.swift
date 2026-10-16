import SwiftUI
import Speech
import AVFoundation

// MARK: - 语音识别工具（文件转写 + 实时听写）

enum SpeechKit {

    /// 请求语音识别权限
    static func requestAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// 转写一个录音文件（zh-CN），失败抛错
    static func transcribeFile(url: URL) async throws -> String {
        guard await requestAuth() else { throw URLError(.userAuthenticationRequired) }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) else {
            throw URLError(.unsupportedURL)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { cont in
            var finished = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    cont.resume(throwing: error)
                }
            }
            // 最多等 10 秒
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !finished {
                    finished = true
                    task?.cancel()
                    let partial = ""
                    cont.resume(returning: partial)
                }
            }
        }
    }
}

/// 实时听写（打电话用）：麦克风 → 部分识别文本
final class MicTranscriber: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var text = ""

    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func start() {
        text = ""
        SFSpeechRecognizer.requestAuthorization { _ in }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            if let result {
                DispatchQueue.main.async {
                    self?.text = result.bestTranscription.formattedString
                }
            }
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        try? engine.start()
    }

    /// 停止并返回最终文本
    func stop() -> String {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        return text
    }

    func reset() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request = nil
        task = nil
        text = ""
    }
}

// MARK: - 打电话给 AI（语音通话界面）

/// 拨打 AI 电话：说话 → 语音识别 → AI 回复 → 开源语音库播报
struct CallView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var av: AvatarStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.displayName") private var aiName = "Amore"
    @AppStorage("persona.prompt") private var personaPrompt = ""
    @AppStorage("persona.gender") private var personaGender = ""
    @AppStorage("persona.age") private var personaAge = ""
    @AppStorage("chat.roomSessionId") private var roomSessionIdStr = ""
    @AppStorage("chat.reasoning") private var reasoning = "medium"

    private enum Phase { case connecting, active, ended }
    @State private var phase: Phase = .connecting
    @State private var secs = 0
    @State private var tick: Timer?
    @State private var transcript = ""
    @State private var replyText = ""
    @State private var listening = false
    @State private var busy = false
    @State private var player: AVAudioPlayer?
    @StateObject private var mic = MicTranscriber()
    @State private var lastActivity = Date()
    @State private var lastSilenceCheck = Date()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.15),
                                    Color(red: 0.07, green: 0.07, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ChatAvatar(image: av.aiImage, name: aiName, isAI: true, size: 110)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 26, y: 8)
                Text(aiName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(phase == .connecting ? "正在呼叫…" : timeString(secs))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))

                VStack(spacing: 8) {
                    if listening {
                        Text(transcript.isEmpty ? "正在聆听…" : transcript)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    if !replyText.isEmpty {
                        Text(replyText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }
                .frame(minHeight: 64)

                Spacer()

                HStack(spacing: 46) {
                    // 挂断
                    Button {
                        Haptics.medium()
                        endCall()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 66, height: 66)
                            .background(Theme.packetRed, in: Circle())
                            .shadow(color: Theme.packetRed.opacity(0.4), radius: 10, y: 4)
                    }
                    .accessibilityLabel("挂断")

                    // 说话（再点即发送）
                    Button {
                        Haptics.light()
                        if listening {
                            stopAndReply()
                        } else {
                            startListening()
                        }
                    } label: {
                        Image(systemName: listening ? "waveform" : "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 66, height: 66)
                            .background(listening ? Theme.heroSky : Theme.ok, in: Circle())
                            .shadow(color: Theme.heroBlue.opacity(0.4), radius: 10, y: 4)
                    }
                    .disabled(busy || phase == .connecting)
                    .accessibilityLabel(listening ? "结束并发送" : "说话")
                }

                Text(busy ? "AI 正在回应…" : (listening ? "说完点一下就发送" : "点击说话"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Spacer()
            }
        }
        .onAppear(perform: connect)
        .onDisappear { endAll() }
        .onChange(of: mic.text) { _, partial in
            // 实时回显部分识别结果 + 静默计时
            if listening {
                transcript = partial
                if !partial.isEmpty { lastActivity = Date() }
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // 通话中免按：说完停顿 2.5 秒自动发送
            guard listening, !busy else { return }
            let partial = mic.text.trimmingCharacters(in: .whitespaces)
            guard !partial.isEmpty else { return }
            guard Date().timeIntervalSince(lastActivity) >= 2.5 else { return }
            stopAndReply()
        }    }

    private var callPrompt: String {
        let persona = personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var attrs: [String] = []
        if personaGender == "male" { attrs.append("性别：男性") }
        if personaGender == "female" { attrs.append("性别：女性") }
        if let ageNum = Int(personaAge.trimmingCharacters(in: .whitespaces)), ageNum > 0 {
            attrs.append("年龄：\(ageNum) 岁")
        }
        let attrLine = attrs.joined(separator: "；")
        let base = persona.isEmpty
            ? "【身份】你是 \(aiName)，用户的私人 AI 好友。"
            : "【人设·最高优先级】以下是你的人物设定，必须完全成为这个人，任何规则与它冲突时以人设为准；性别年龄以人设属性为准，绝不自称或承认与人设不符的身份：\n" + (attrLine.isEmpty ? "" : attrLine + "\n") + persona
        return base + "\n\n【电话模式】现在是语音通话，回复必须极简短口语化（1-2 句，像打电话一样），不要列表不要表情符号，不要提这些规则。\n【活人感】接话像真人打电话：可以「嗯」「哦」「等下啊」，可以有口头禅，可以吐槽、可以敷衍。禁用「一丝/仿佛/不禁/眼中闪过」这类AI腔，别总结别升华，说完就停。\n【硬标准】半数以上回复不超过 8 个字；别每句都用问句收尾；别解释自己为什么这么说，直接说。"
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func connect() {
        Task { _ = await SpeechKit.requestAuth() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            phase = .active
            tick?.invalidate()
            tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in secs += 1 }
            speak("喂？我在呢，有什么想说的吗？")
        }
    }

    private func startListening() {
        transcript = ""
        listening = true
        lastActivity = Date()
        player?.stop()
        mic.start()
    }

    private func stopAndReply() {
        let said = mic.stop()
        listening = false
        transcript = said
        lastActivity = Date()
        let trimmed = said.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            replyText = "没听清，再说一次？"
            return
        }
        busy = true
        lastActivity = Date()
        Task {
            do {
                let reply = try await store.sendChat(
                    sessionId: Int64(roomSessionIdStr) ?? 0,
                    content: trimmed,
                    attachments: [],
                    reasoning: reasoning,
                    systemPrompt: callPrompt
                )
                if Int64(roomSessionIdStr) ?? 0 != reply.sessionId {
                    roomSessionIdStr = String(reply.sessionId)
                }
                replyText = reply.reply
                speak(reply.reply)
            } catch {
                replyText = "信号不太好，稍后再试"
            }
            busy = false
        }
    }

    private func speak(_ text: String) {
        Task { @MainActor in
            if let data = try? await VoicePlayer.serverSynth(text: text, baseURL: config.serverURL) {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                try? session.setActive(true)
                if let pl = try? AVAudioPlayer(data: data) {
                    player = pl
                    pl.play()
                }
            }
        }
    }

    private func endCall() {
        mic.reset()
        tick?.invalidate()
        player?.stop()
        dismiss()
    }

    private func endAll() {
        mic.reset()
        tick?.invalidate()
        player?.stop()
    }
}
