// DollStudio3D — APIClient：RESTful 通信（登录/目录/穿搭/AI/配置），错误分类，重试
import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .http(let code, let msg): return "服务错误 \(code)：\(msg)"
        case .decoding(let m): return "响应解析失败：\(m)"
        case .network(let m): return "网络异常：\(m)"
        }
    }
}

struct AIOutfitResponse: Codable {
    struct Plan: Codable {
        var category: String
        var cloth_id: String
    }
    var items: [Plan]
    var reason: String?
    var source: String?      // "server-ai" / "local-rules"
}

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession
    var timeout: TimeInterval = 12
    var maxRetries = 2

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// 通用 GET，泛型解码（支持裸数组或 { data: [...] } 信封）
    func get<T: Decodable>(_ urlString: String, token: String?) async throws -> T {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await send(req)
        try check(resp, data: data)
        return try decode(data)
    }

    func post<T: Decodable>(_ urlString: String, token: String?, body: [String: Any]) async throws -> T {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await send(req)
        try check(resp, data: data)
        return try decode(data)
    }

    func delete(_ urlString: String, token: String?) async throws {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await send(req)
        try check(resp, data: Data())
    }

    private func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error = APIError.network("unknown")
        for attempt in 0...maxRetries {
            do {
                return try await session.data(for: req)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
                }
            }
        }
        throw APIError.network(lastError.localizedDescription)
    }

    private func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
        }
    }

    /// 兼容两种响应：裸数组 / { data: [...] }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            struct Envelope<T: Decodable>: Decodable { let data: T }
            if let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) {
                return env.data
            }
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - 业务方法

    /// 登录（POST /api/auth/login）
    func login(base: String, username: String, password: String) async throws -> String {
        struct LoginResp: Decodable { var token: String }
        let r: LoginResp = try await post(base + "/api/auth/login", token: nil,
                                          body: ["username": username, "password": password])
        return r.token
    }

    /// AI 搭配（POST /api/ai/outfits）
    func aiOutfit(base: String, token: String?, gender: DollGender,
                  prompt: String, catalog: [ClothItem]) async throws -> AIOutfitResponse {
        struct ClothBrief: Codable {
            let id: String; let name: String; let category: String
        }
        let briefs = catalog.map { ClothBrief(id: $0.id, name: $0.name, category: $0.category) }
        return try await post(base + "/api/ai/outfits", token: token, body: [
            "gender": gender.rawValue,
            "prompt": prompt,
            "catalog": briefs,
        ])
    }
}
