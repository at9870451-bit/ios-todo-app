import Foundation

/// 统一 API 响应包装：{"code":0,"message":"...","data":{...}}
struct APIEnvelope<T: Decodable>: Decodable {
    let code: FlexibleCode
    let message: String
    let data: T?

    var success: Bool { code.value == 0 }

    enum CodingKeys: String, CodingKey { case code, message, data }
}

/// code 可能是 int 或 string（错误时为字符串）
struct FlexibleCode: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let s = try? c.decode(String.self) { value = Int(s) ?? -1; return }
        value = -1
    }
}

/// 业务错误
struct APIError: LocalizedError {
    let message: String
    let code: String
    let status: Int
    var errorDescription: String? { message }

    var isUnauthorized: Bool { status == 401 || code == "UNAUTHORIZED" }
}

/// 后端 HTTP 客户端：Cookie 会话 + CSRF token 自动注入
actor BackendClient {
    static let shared = BackendClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private var baseURL: String = ""
    private var csrfToken: String = ""

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    func configure(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    func setCSRF(_ token: String) {
        self.csrfToken = token
    }

    private func url(_ path: String, query: [String: String]? = nil) throws -> URL {
        var full = baseURL + path
        if let query, !query.isEmpty {
            var comps = URLComponents(string: full)
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            full = comps?.url?.absoluteString ?? full
        }
        guard let u = URL(string: full) else { throw APIError(message: "服务器地址无效", code: "BAD_URL", status: 0) }
        return u
    }

    /// GET 请求（自动带会话 Cookie）
    func get<T: Decodable>(_ path: String, query: [String: String]? = nil, as type: T.Type) async throws -> T {
        var req = URLRequest(url: try url(path, query: query))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(req, as: type)
    }

    /// POST 请求（JSON body + CSRF 头）
    func post<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async throws -> T {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !csrfToken.isEmpty {
            req.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(req, as: type)
    }

    /// POST 表单（部分旧接口只认 form 编码）
    func postForm<T: Decodable>(_ path: String, form: [String: String], as type: T.Type) async throws -> T {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !csrfToken.isEmpty {
            req.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        let body = form.map { "\($0.key)=\(Self.escape($0.value))" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        return try await execute(req, as: type)
    }

    /// 执行请求并解析 envelope
    private func execute<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError(message: "网络错误：\(error.localizedDescription)", code: "NETWORK", status: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // 尝试解析标准 envelope
        if let env = try? decoder.decode(APIEnvelope<T>.self, from: data) {
            if env.success, let payload = env.data {
                return payload
            }
            if env.success, T.self == EmptyData.self {
                return EmptyData() as! T
            }
            throw APIError(message: env.message, code: "\(env.code.value)", status: status)
        }

        // 非标准响应（HTML 错误页等）
        let text = String(data: data, encoding: .utf8) ?? ""
        if status == 401 || status == 419 {
            throw APIError(message: "未登录或会话已过期", code: "UNAUTHORIZED", status: status)
        }
        if text.contains("系统发生错误") {
            throw APIError(message: "服务器内部错误（请检查后端日志）", code: "SERVER_ERROR", status: status)
        }
        throw APIError(message: "响应格式异常（HTTP \(status)）", code: "BAD_RESPONSE", status: status)
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// 空数据占位（服务端 data 可能为 [] 或 {}）
struct EmptyData: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// 登录返回的用户信息
struct AuthUser: Decodable {
    let id: Int
    let username: String
    let nickname: String
    let email: String?
    let role: String
    let membershipLevel: String
    let liveTradingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, role
        case membershipLevel = "membership_level"
        case liveTradingEnabled = "live_trading_enabled"
    }
}

/// /api/ios/{login,register,me} 的 data 载荷
struct SessionPayload: Decodable {
    let user: AuthUser
    let csrfToken: String
    let badge: BadgeInfo

    enum CodingKeys: String, CodingKey {
        case user
        case csrfToken = "csrf_token"
        case badge
    }
}

struct BadgeInfo: Decodable {
    let level: String
    let name: String
    let isAdmin: Bool
    let expireAt: String?
    let daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case level, name
        case isAdmin = "is_admin"
        case expireAt = "expire_at"
        case daysLeft = "days_left"
    }
}
