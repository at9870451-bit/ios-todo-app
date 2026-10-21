// DollStudio3D — AudioService：音效 / 背景音乐 / AI 语音播放，独立音量控制
// 隐私：不录音、不采集麦克风；仅播放。
import AVFoundation
import UIKit

enum AppSound: String {
    case tap      = "tap"
    case dress    = "dress"
    case success  = "success"
}

@MainActor
final class AudioService: ObservableObject {
    static let shared = AudioService()

    // 三路独立音量（0...1）
    @Published var sfxVolume: Double {
        didSet { UserDefaults.standard.set(sfxVolume, forKey: "audio.sfxVolume") }
    }
    @Published var bgmVolume: Double {
        didSet {
            UserDefaults.standard.set(bgmVolume, forKey: "audio.bgmVolume")
            bgmPlayer?.volume = Float(bgmVolume) * (bgmOn ? 1 : 0)
        }
    }
    @Published var voiceVolume: Double {
        didSet {
            UserDefaults.standard.set(voiceVolume, forKey: "audio.voiceVolume")
            voicePlayer?.volume = Float(voiceVolume)
        }
    }
    @Published var sfxOn: Bool {
        didSet { UserDefaults.standard.set(sfxOn, forKey: "audio.sfxOn") }
    }
    @Published var bgmOn: Bool {
        didSet {
            UserDefaults.standard.set(bgmOn, forKey: "audio.bgmOn")
            if bgmOn { startBGM() } else { pauseBGM() }
        }
    }
    @Published var isBGMPlaying = false
    @Published var isVoicePlaying = false

    private var bgmPlayer: AVAudioPlayer?
    private var voicePlayer: AVAudioPlayer?

    private init() {
        let d = UserDefaults.standard
        sfxVolume = d.object(forKey: "audio.sfxVolume") as? Double ?? 0.8
        bgmVolume = d.object(forKey: "audio.bgmVolume") as? Double ?? 0.4
        voiceVolume = d.object(forKey: "audio.voiceVolume") as? Double ?? 0.9
        sfxOn = d.object(forKey: "audio.sfxOn") as? Bool ?? true
        bgmOn = d.object(forKey: "audio.bgmOn") as? Bool ?? false
        setupSession()
    }

    /// ambient 类别：跟随系统静音键，不打断其它 App 音频，也不录音
    private func setupSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: 音效（系统短音，音量跟随系统；sfxOn 开关控制）

    private var systemSoundIDs: [AppSound: SystemSoundID] = [
        .tap: 1104,       // keyboard tap
        .dress: 1103,     // tick
        .success: 1025,   // new mail
    ]

    func play(_ sound: AppSound) {
        guard sfxOn, sfxVolume > 0.01, let id = systemSoundIDs[sound] else { return }
        AudioServicesPlaySystemSound(id)
    }

    // MARK: 背景音乐（用户在 Documents 放入 bgm.mp3 即启用；无文件时开关置灰提示）

    var bgmAvailable: Bool {
        Self.bgmURL != nil
    }

    static var bgmURL: URL? {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        for name in ["bgm.mp3", "bgm.m4a", "bgm.wav"] {
            let u = doc?.appendingPathComponent(name)
            if u != nil, FileManager.default.fileExists(atPath: u!.path) { return u }
        }
        return nil
    }

    func startBGM() {
        guard bgmAvailable else { return }
        if bgmPlayer == nil, let url = Self.bgmURL {
            bgmPlayer = try? AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1
        }
        bgmPlayer?.volume = Float(bgmVolume)
        bgmPlayer?.play()
        isBGMPlaying = true
    }

    func pauseBGM() {
        bgmPlayer?.pause()
        isBGMPlaying = false
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        isBGMPlaying = false
    }

    // MARK: AI 语音播放（播放后端 TTS 返回的音频数据）

    func playVoice(data: Data) {
        voicePlayer = try? AVAudioPlayer(data: data)
        voicePlayer?.volume = Float(voiceVolume)
        voicePlayer?.play()
        isVoicePlaying = true
        Task { @MainActor in
            while let p = voicePlayer, p.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            self.isVoicePlaying = false
        }
    }

    func stopVoice() {
        voicePlayer?.stop()
        isVoicePlaying = false
    }
}
