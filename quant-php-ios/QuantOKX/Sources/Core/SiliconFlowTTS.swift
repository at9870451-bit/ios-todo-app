import Foundation

/// SiliconFlow（硅基流动）TTS 供应商 —— 借鉴 Operit SiliconFlowVoiceProvider
/// OpenAI 兼容 /v1/audio/speech 协议；系统预置音色需 "model:voice" 格式
/// 需要用户在设置里填 API Key（有免费额度）
enum SiliconFlowTTS {

    static let apiURL = "https://api.siliconflow.cn/v1/audio/speech"
    static let defaultModel = "FunAudioLLM/CosyVoice2-0.5B"

    struct Voice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// 中文音色（参考 Operit：预置音色 4 男 4 女）
    static let voices: [Voice] = [
        Voice(id: "alex", name: "Alex · 沉稳男声"),
        Voice(id: "benjamin", name: "Benjamin · 磁性男声"),
        Voice(id: "charles", name: "Charles · 甜茶男声"),
        Voice(id: "david", name: "David · 青春男声"),
        Voice(id: "anna", name: "Anna · 沉稳女声"),
        Voice(id: "bella", name: "Bella · 激情女声"),
        Voice(id: "claire", name: "Claire · 温柔女声"),
        Voice(id: "diana", name: "Diana · 干练女声"),
    ]

    static let defaultVoiceID = "anna"

    enum Error: LocalizedError {
        case noKey
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "请先在设置里配置硅基流动 API Key"
            case .badResponse(let m): return "硅基流动合成失败：\(m)"
            }
        }
    }

    /// 读取本机保存的 Key（设置页写入 UserDefaults）
    static var savedKey: String {
        let s = UserDefaults.standard.string(forKey: "tts.siliconflow.key") ?? ""
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 合成 → mp3 Data
    static func synthesize(text: String, voiceID: String) async throws -> Data {
        let key = savedKey
        guard !key.isEmpty else { throw Error.noKey }
        let cleanVoice = voiceID.trimmingCharacters(in: .whitespaces)
        // 预置音色需要 "model:voice" 前缀（对齐 Operit 逻辑）
        let voiceValue: String
        if cleanVoice.hasPrefix("speech:") || cleanVoice.contains(":") {
            voiceValue = cleanVoice
        } else {
            voiceValue = "\(defaultModel):\(cleanVoice)"
        }

        var req = URLRequest(url: URL(string: apiURL)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable {
            let model: String
            let input: String
            let voice: String
            let response_format: String
            let sample_rate: Int
            let speed: Double
            let gain: Int
        }
        req.httpBody = try JSONEncoder().encode(
            Body(model: defaultModel,
                 input: String(text.prefix(500)),
                 voice: voiceValue,
                 response_format: "mp3",
                 sample_rate: 32000,
                 speed: 1.0,
                 gain: 0)
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200, data.count > 100 else {
            let msg = String(data: data.prefix(200), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Error.badResponse(msg)
        }
        return data
    }
}
