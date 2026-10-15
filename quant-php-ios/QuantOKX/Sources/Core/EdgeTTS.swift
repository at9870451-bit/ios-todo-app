import Foundation
import CryptoKit

/// 微软 Edge 神经语音（开源 edge-tts 协议）
/// 免费在线合成、无需 API Key，内置多款中文普通话 / 粤语神经音色。
/// 协议：WSS speech.platform.bing.com，SSML 下发，二进制分片回传 mp3。
enum EdgeTTS {

    struct Voice: Identifiable, Hashable {
        let id: String   // e.g. zh-CN-XiaoxiaoNeural
        let name: String // 显示名
    }

    /// 内置中文音色
    static let voices: [Voice] = [
        Voice(id: "zh-CN-XiaoxiaoNeural", name: "晓晓 · 女 · 温柔"),
        Voice(id: "zh-CN-XiaoyiNeural", name: "晓伊 · 女 · 甜美"),
        Voice(id: "zh-CN-YunxiNeural", name: "云希 · 男 · 阳光"),
        Voice(id: "zh-CN-YunjianNeural", name: "云健 · 男 · 浑厚"),
        Voice(id: "zh-CN-YunyangNeural", name: "云扬 · 男 · 播音"),
        Voice(id: "zh-HK-HiuMaanNeural", name: "曉曼 · 粤语 · 女"),
        Voice(id: "zh-HK-WanLungNeural", name: "雲龍 · 粤语 · 男"),
    ]

    static var defaultVoiceID: String { voices[0].id }

    enum EdgeTTSError: LocalizedError {
        case emptyAudio
        var errorDescription: String? {
            switch self {
            case .emptyAudio: return "Edge 语音未返回音频"
            }
        }
    }

    private static let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let secGecVersion = "1-130.0.2849.68"
    private static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"

    /// 合成单条语音，返回 mp3 数据；超长文本自动截断（前 1200 字）
    static func synthesize(text: String, voiceID: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EdgeTTSError.emptyAudio }
        let content = String(trimmed.prefix(1200))

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: makeRequest(voiceID: voiceID))
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        // 1) 服务端下发 speech.config 响应
        _ = try await receive(task)

        // 2) 合成配置
        let config = "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{"
            + "\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},"
            + "\"outputFormat\":\"\(outputFormat)\"}}}}"
        try await task.send(.string(
            "X-Timestamp:\(dateString())\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n" + config
        ))

        // 3) SSML
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let lang = voiceID.hasPrefix("zh-HK") ? "zh-HK" : "zh-CN"
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(lang)'>"
            + "<voice name='\(voiceID)'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(xmlEscape(content))</prosody>"
            + "</voice></speak>"
        try await task.send(.string(
            "X-RequestId:\(requestId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(dateString())Z\r\nPath:ssml\r\n\r\n" + ssml
        ))

        // 4) 收音频分片，直到 turn.end
        var audio = Data()
        while true {
            let msg = try await receive(task)
            switch msg {
            case .data(let d):
                let bytes = [UInt8](d)
                guard bytes.count > 2 else { continue }
                let headerLen = Int(bytes[0]) << 8 | Int(bytes[1])
                guard bytes.count > headerLen + 2 else { continue }
                let header = String(decoding: bytes[2..<(2 + headerLen)], as: UTF8.self)
                if header.contains("Path:audio") {
                    audio.append(contentsOf: bytes[(2 + headerLen)...])
                }
            case .string(let s):
                if s.contains("Path:turn.end") {
                    if !audio.isEmpty { return audio }
                    throw EdgeTTSError.emptyAudio
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - 协议细节

    private static func makeRequest(voiceID: String) -> URLRequest {
        var comps = URLComponents(string: "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1")!
        comps.queryItems = [
            URLQueryItem(name: "TrustedClientToken", value: trustedToken),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: secGecVersion),
            URLQueryItem(name: "Sec-MS-GEC", value: secMsGec()),
            URLQueryItem(name: "ConnectionId", value: UUID().uuidString.replacingOccurrences(of: "-", with: "")),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.2849.68", forHTTPHeaderField: "User-Agent")
        req.setValue("chrome-extension://jdiccldimpahbcfhbmnnjbclgnbnkgof", forHTTPHeaderField: "Origin")
        return req
    }

    /// DRM 令牌：Windows 文件时间（1601 纪元秒）按 5 分钟窗取整 + TrustedToken，SHA256 大写
    private static func secMsGec() -> String {
        var ticks = Int(Date().timeIntervalSince1970) + 11_644_473_600
        ticks -= ticks % 300
        return SHA256.hash(data: Data("\(ticks)\(trustedToken)".utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }

    private static func receive(_ task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { cont in
            task.receive { result in
                switch result {
                case .success(let m): cont.resume(returning: m)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
    }

    private static func xmlEscape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&" + "amp;"
            case "<": out += "&" + "lt;"
            case ">": out += "&" + "gt;"
            case "\"": out += "&" + "quot;"
            case "'": out += "&" + "#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return f.string(from: Date())
    }
}
