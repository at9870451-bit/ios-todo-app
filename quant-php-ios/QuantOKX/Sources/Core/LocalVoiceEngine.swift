import Foundation
import AVFoundation

/// 本地语音引擎（完全离线，不依赖任何服务器）
/// 把系统自带的中文音色全部枚举成"语音包"；支持手动选音色、按人设匹配、语速/音调/音量调节
enum LocalVoiceEngine {

    struct Voice: Identifiable, Hashable {
        let id: String          // AVSpeechSynthesisVoice.identifier
        let name: String        // 显示名
        let locale: String
        let gender: String      // male / female / unknown
        let isPremium: Bool     // 增强音色（用户下载过的）

        var display: String {
            let g = gender == "male" ? "男" : (gender == "female" ? "女" : "未标注")
            return "\(name) · \(g)"
        }
    }

    /// 已选本地音色 identifier（空 = 自动按人设）
    static var selectedVoiceID: String {
        UserDefaults.standard.string(forKey: "tts.local.voice") ?? ""
    }

    /// 音调倍数（0.5~2.0）
    static var pitchMultiplier: Float {
        let v = UserDefaults.standard.float(forKey: "tts.local.pitch")
        return v > 0 ? min(2.0, max(0.5, v)) : 1.0
    }

    /// 全部可用中文音色（系统 + 用户下载的增强音色）
    static func allVoices() -> [Voice] {
        let raw = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("zh") }
        var out: [Voice] = []
        for v in raw {
            out等著: break
        }
        return out
    }
}