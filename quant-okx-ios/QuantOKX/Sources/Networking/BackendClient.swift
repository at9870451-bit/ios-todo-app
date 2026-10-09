import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    case badURL(String)
    case http(Int, String)
    case api(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未配置后台地址，请到「设置」填写"
        case .badURL(let s): return "地址无效：\(s)"
        case .http(let c, let m): return "网络错误 HTTP \(c)\(m.isEmpty ? "" : "：\(m)")"
        case .api(let c, let m): return "后台返回错误 \(c)：\(m)"
        case .decoding(let m): return "数据解析失败：\(m)"
        case .transport(let m): return "连接失败：\(m)"
        }
    }
}

/// 与 Java 后台通信的客户端。所有业务请求都过这里。
actor BackendClient {

    private var base = ""
    private var token = ""
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    func configure(baseURL: String, authToken: String) {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // 容错：用户可能只填了 IP
        if !b.lowercased().hasPrefix("http") {
            b = "http://" + b
        }
        if b.hasSuffix("/") { b.removeLast() }
        self.base = b
        self.token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool { !base.isEmpty }

    // MARK: - 底层请求

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Encodable? = nil,
        as type: T.Type,
        auth: Bool = true
    ) async throws -> T {

        guard !base.isEmpty else { throw BackendError.notConfigured }

        var comps = URLComponents(string: base + path)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw BackendError.badURL(base + path) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth && !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let enc = JSONEncoder()
            req.httpBody = try enc.encode(AnyEncodable(body))
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw BackendError.transport("无响应")
        }
        if http.statusCode == 401 {
            throw BackendError.api(401, "鉴权失败，请检查「设置」里的访问令牌")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw BackendError.http(http.statusCode, String(snippet))
        }

        do {
            let env = try JSONDecoder().decode(ApiEnvelope<T>.self, from: data)
            guard env.code == 0 else { throw BackendError.api(env.code, env.msg) }
            guard let d = env.data else { throw BackendError.decoding("data 为空") }
            return d
        } catch let e as BackendError {
            throw e
        } catch {
            throw BackendError.decoding(error.localizedDescription)
        }
    }

    /// 泛型擦除容器，方便把任意 Encodable 塞进方法参数
    private struct AnyEncodable: Encodable {
        let value: Encodable
        init(_ v: Encodable) { value = v }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    // MARK: - 系统

    func health() async throws -> HealthResp {
        try await send("GET", "/api/health", as: HealthResp.self, auth: false)
    }

    func status() async throws -> StatusResp {
        try await send("GET", "/api/status", as: StatusResp.self)
    }

    func startEngine() async throws {
        struct R: Decodable { let running: Bool }
        let _: R = try await send("POST", "/api/engine/start", as: R.self)
    }

    func stopEngine() async throws {
        struct R: Decodable { let running: Bool }
        let _: R = try await send("POST", "/api/engine/stop", as: R.self)
    }

    // MARK: - 配置

    func getConfig() async throws -> ConfigDTO {
        try await send("GET", "/api/config", as: ConfigDTO.self)
    }

    func updateConfig(_ body: ConfigUpdate) async throws -> ConfigDTO {
        try await send("PUT", "/api/config", body: body, as: ConfigDTO.self)
    }

    struct TestResult: Decodable {
        let ok: Bool
        let message: String
        let instId: String?
        let lastPrice: String?
        let balanceUSDT: String?
    }

    func testConnection() async throws -> TestResult {
        try await send("POST", "/api/config/test", as: TestResult.self)
    }

    // MARK: - 行情

    func ticker(_ instId: String) async throws -> TickerDTO {
        try await send("GET", "/api/market/ticker", query: ["instId": instId], as: TickerDTO.self)
    }

    func candles(_ instId: String, bar: String, limit: Int = 120) async throws -> [CandleDTO] {
        try await send("GET", "/api/market/candles",
                       query: ["instId": instId, "bar": bar, "limit": "\(limit)"],
                       as: [CandleDTO].self)
    }

    // MARK: - 交易

    func positions() async throws -> [PositionDTO] {
        try await send("GET", "/api/positions", as: [PositionDTO].self)
    }

    func logs(limit: Int = 200) async throws -> [LogDTO] {
        try await send("GET", "/api/logs", query: ["limit": "\(limit)"], as: [LogDTO].self)
    }

    struct ClearResult: Decodable { let cleared: Int }

    func clearLogs() async throws -> Int {
        let r: ClearResult = try await send("DELETE", "/api/logs", as: ClearResult.self)
        return r.cleared
    }

    struct CloseAllResult: Decodable {
        let closed: Int
        let message: String?
    }

    func closeAll() async throws -> CloseAllResult {
        try await send("POST", "/api/trade/close-all", as: CloseAllResult.self)
    }

    func strategies() async throws -> [StrategyDTO] {
        try await send("GET", "/api/strategies", as: [StrategyDTO].self)
    }
}
