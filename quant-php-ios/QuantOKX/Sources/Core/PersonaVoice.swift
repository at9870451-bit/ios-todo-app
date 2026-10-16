import Foundation
import AVFoundation

/// 人设音色匹配：按人设的「性别 / 年龄 / 性格」自动挑选音色与语速
/// 女性 → 女声、男性 → 男声；年龄影响年轻/成熟音色；性格微调语速（温柔更慢、活泼更快）
enum PersonaVoice {

    /// 是否启用（默认开启；设置页可关）
    static var enabled: Bool {
        if UserDefaults.standard.object(forKey: "tts.personaMatch") == nil { return true }
        return UserDefaults.standard.bool(forKey: "tts.personaMatch")
    }

    static var gender: String {
        UserDefaults.standard.string(forKey: "persona.gender") ?? ""
    }

    static var age: Int {
        Int((UserDefaults.standard.string(forKey: "persona.age") ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    static var personaText: String {
        UserDefaults.standard.string(forKey: "persona.prompt") ?? ""
    }

    private static var young: Bool { age > 0 && age < 25 }
    private static var mature: Bool { age >= 40 }

    /// 性格关键词
    private static var soft: Bool {
        let p = personaText
        return p.contains("温柔") || p.contains("软") || p.contains("慵懒") || p.contains("慢性子") || p.contains("体贴")
    }

    private static var lively: Bool {
        let p = personaText
        return p.contains("活泼") || p.contains("元气") || p.contains("开朗") || p.contains("俏皮") || p.contains("话多") || p.contains("跳脱")
    }

    private static var calm: Bool {
        let p = personaText
        return p.contains("高冷") || p.contains("沉稳") || p.contains("冷静") || p.contains("成熟") || p.contains("淡漠")
    }

    /// 语速微调系数（性格）
    static var speedFactor: Float {
        guard enabled else { return 1.0 }
        if soft { return 0.94 }
        if lively { return 1.08 }
        if calm { return 0.97 }
        return 1.0
    }

    /// 开源语音库（Piper / Sherpa 自建）
    static func serverVoice(fallback: String) -> String {
        guard enabled else { return fallback }
        switch gender {
        case "female":
            if soft { return "theresa" }      // 特蕾莎 · 柔和女声
            if mature { return "xiaoya" }     // 小雅 · 女声
            return fallback == "huayan" ? "huayan" : "huayan_fast"   // 华严 · 女声
        case "male":
            return "chaowen"                  // 沧元 · 男声
        default:
            return fallback
        }
    }

    /// 硅基流动 8 款中文音色
    static func siliconFlowVoice(fallback: String) -> String {
        guard enabled else { return fallback }
        switch gender {
        case "female":
            if lively { return "bella" }      // 激情女声
            if mature { return "anna" }       // 沉稳女声
            return "claire"                   // 温柔女声
        case "male":
            if young { return "david" }       // 青春男声
            return "charles"                  // 甜茶男声
        default:
            return fallback
        }
    }

    /// 豆包音色
    static func doubaoVoice(fallback: String) -> String {
        guard enabled else { return fallback }
        switch gender {
        case "female":
            if lively { return "BV701_streaming" }        // 炀炀 · 甜美女声
            return "BV700_V2_streaming"                    // 灿灿 · 通用女声
        case "male":
            if young { return "BV120_streaming" }          // 阳光青年
            return "BV001_streaming"                       // 通用男声
        default:
            return fallback
        }
    }

    /// 本地系统语音：按性别挑中文音色（尽力而为，找不到用默认）
    static func localVoice() -> AVSpeechSynthesisVoice? {
        guard enabled else { return AVSpeechSynthesisVoice(language: "zh-CN") }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("zh") }
        guard !voices.isEmpty else { return AVSpeechSynthesisVoice(language: "zh-CN") }
        switch gender {
        case "male":
            if let v = voices.first(where: {
                $0.name.contains("Yu-shu") || $0.name.contains("Li-mu") || $0.name.contains("云希")
            }) { return v }
            return AVSpeechSynthesisVoice(language: "zh-CN")
        case "female":
            if let v = voices.first(where: {
                $0.name.contains("Ting") || $0.name.contains("Mei-Jia") || $0.name.contains("Sin-Ji") || $0.name.contains("婷婷")
            }) { return v }
            return AVSpeechSynthesisVoice(language: "zh-CN")
        default:
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
    }
}
