import Foundation

/// 豆包（字节火山引擎）TTS —— 借鉴 Operit DoubaoVoiceProvider
/// POST openspeech.bytedance.com/api/v1/tts，JSON 里 data 字段 base64 mp3
/// 需要用户在设置里填 AppID + Access Token（火山引擎控制台开通语音合成）
enum DoubaoTTS {

    static let apiURL = "https://openspeech.bytedance.com/api/v1/tts"
    static let defaultCluster = "volcano_tts"

    struct Voice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// 火山引擎常用中文音色
    static let voices: [Voice] = [
        Voice(id: "BV700_V2_streaming", name: "灿灿 · 通用女声"),
        Voice(id: "BV701_streaming", name: "炀炀 · 甜美女声"),
        Voice(id: "BV002_streaming", name: "通用女声"),
        Voice(id: "BV001_streaming", name: "通用男声"),
        Voice(id: "BV120_streaming", name: "阳光青年"),
        Voice(id: "BV705_streaming", name: "爽快思乡 · 男声"),
    ]

    static let defaultVoiceID = "BV700_V2_streaming"

    enum Error: LocalizedError {
        case noKey
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "请先在设置里配置豆包 AppID 和 Access Token"
            case .badResponse(let m): return "豆包合成失败：\(m)"
            }
        }
    }

    static var savedAppID: String {
        (UserDefaults.standard.string(forKey: "tts.doubao.appid") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var savedToken: String {
        (UserDefaults.standard.string(forKey: "tts.doubao.token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool { !savedAppID.isEmpty && !savedToken.isEmpty }

    /// 语速 / 音调 / 音量倍数与增益（火山接口标准参数），设置页可调
    static var speedRatio: Double {
        let v = UserDefaults.standard.double(forKey: "tts.doubao.speed")
        return v > 0 ? min(2.0, max(0.2, v)) : 1.0
    }
    static var pitchRatio: Double {
        let v = UserDefaults.standard.double(forKey: "tts.doubao.pitch")
        return v > 0 ? min(2.0, max(0.5, v)) : 1.0
    }
    static var volumeRatio: Double {
        let v = UserDefaults.standard.double(forKey: "tts.doubao.volume")
        return v > 0 ? min(2.0, max(0.1, v)) : 1.0
    }
    static var gainDb: Int {
        let v = UserDefaults.standard.integer(forKey: "tts.doubao.gain")
        return min(10, max(-10, v))
    }

    /// 合成 → mp3 Data
    static func synthesize(text: String, voiceID: String) async throws -> Data {
        guard isConfigured else { throw Error.noKey }

        var req = URLRequest(url: URL(string: apiURL)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer;\(savedToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "app": ["appid": savedAppID, "token": "access_token", "cluster": defaultCluster],
            "user": ["uid": "amore-ios"],
            "audio": [
                "voice_type": voiceID,
                "encoding": "mp3",
                "speed_ratio": DoubaoTTS.speedRatio,
                "pitch_ratio": DoubaoTTS.pitchRatio,
                "volume_ratio": DoubaoTTS.volumeRatio,
                "gain_db": DoubaoTTS.gainDb,
            ],
            "request": [
                "reqid": UUID().uuidString,
                "text": String(text.prefix(500)),
                "operation": "query",
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw Error.badResponse("HTTP \(code)")
        }
        // 响应：{"data": "<base64 mp3>", ...}
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b64 = obj["data"] as? String,
              let mp3 = Data(base64Encoded: b64), mp3.count > 100 else {
            let msg = String(data: data.prefix(200), encoding: .utf8) ?? "解析失败"
            throw Error.badResponse(msg)
        }
        return mp3
    }
}
