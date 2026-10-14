# iOS App 接口调用示例（Swift / SwiftUI）

> 对应后端：`/api/ios/**`（Amore 后端 v2.0）
> 认证：`QBSESSID` Cookie（HttpOnly）+ 写操作 `X-CSRF-TOKEN` 头
> 最低 iOS 17 / Swift 5.9

---

## 1. 通用响应包

```swift
struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

// 后端 code 为 0 表示成功；非 0 时 message 为错误说明
extension ApiResponse {
    var isOK: Bool { code == 0 }
}
```

## 2. 数据模型

```swift
struct UserProfile: Codable, Identifiable {
    let id: Int
    let username: String
    let nickname: String
    let email: String
    let role: String
    let membershipLevel: String
    let liveTradingEnabled: Bool
    let createdAt: String?
    let lastLoginAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, role
        case membershipLevel   = "membership_level"
        case liveTradingEnabled = "live_trading_enabled"
        case createdAt          = "created_at"
        case lastLoginAt        = "last_login_at"
    }
}

/// login / register 的 data
struct AuthPayload: Codable {
    let user: AuthUser
    let csrfToken: String
    enum CodingKeys: String, CodingKey {
        case user
        case csrfToken = "csrf_token"
    }
}

struct AuthUser: Codable {
    let id: Int
    let username: String
    let nickname: String
    let email: String
    let role: String
    let membershipLevel: String
    let liveTradingEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, role
        case membershipLevel   = "membership_level"
        case liveTradingEnabled = "live_trading_enabled"
    }
}

struct PingData: Codable {
    let app: String
    let version: String
    let csrfToken: String
    enum CodingKeys: String, CodingKey {
        case app, version
        case csrfToken = "csrf_token"
    }
}

struct Announcement: Codable {
    let id: Int
    let title: String
    let content: String
    let type: String
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, title, content, type
        case updatedAt = "updated_at"
    }
}

struct ClientConfig: Codable {
    let registerEnabled: String
    let registerNeedEmail: String
    let maintainMode: String
    let siteName: String
    let announcement: String
    let latestVersion: String
    let minVersion: String
    let forceUpdate: Bool
    let downloadUrl: String
    enum CodingKeys: String, CodingKey {
        case registerEnabled   = "register_enabled"
        case registerNeedEmail = "register_need_email"
        case maintainMode      = "maintain_mode"
        case siteName          = "site_name"
        case announcement
        case latestVersion     = "latest_version"
        case minVersion        = "min_version"
        case forceUpdate       = "force_update"
        case downloadUrl       = "download_url"
    }
}
```

## 3. APIClient（URLSession + async/await）

`QBSESSID` 由 URLSession 的 `HTTPCookieStorage` 自动保存与携带；写操作需手动附加 `X-CSRF-TOKEN`。

```swift
enum APIError: LocalizedError {
    case server(code: Int, message: String)
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .server(_, let m): return m
        case .http(let c):      return "网络错误（HTTP \(c)）"
        case .decoding:         return "数据解析失败"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    /// 服务器地址（默认与 App 内置一致）
    var baseURL = URL(string: "http://154.12.16.204:8080")!

    /// 当前 CSRF token（来自 ping / login / register 响应）
    private(set) var csrfToken: String = ""

    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared          // 自动管理 QBSESSID
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: cfg)
    }

    // MARK: - 核心请求

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> T? {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !csrfToken.isEmpty, method != "GET" {
            req.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        let decoded: ApiResponse<T>
        do { decoded = try JSONDecoder().decode(ApiResponse<T>.self, from: data) }
        catch { throw APIError.decoding(error) }

        // 写操作成功时同步刷新 csrf_token
        if let payload = decoded.data as? AuthPayload { csrfToken = payload.csrfToken }
        if let ping = decoded.data as? PingData, !ping.csrfToken.isEmpty { csrfToken = ping.csrfToken }

        guard decoded.code == 0 else {
            throw APIError.server(code: decoded.code, message: decoded.message)
        }
        return decoded.data
    }

    // MARK: - 接口

    /// 获取会话与 CSRF
    @discardableResult
    func ping() async throws -> PingData? {
        try await request("GET", "/api/ios/ping")
    }

    func register(username: String, password: String, email: String) async throws -> AuthPayload? {
        try await request("POST", "/api/ios/register", body: [
            "username": username,
            "password": password,
            "email": email,
            "device": deviceInfo()
        ])
    }

    func login(username: String, password: String) async throws -> AuthPayload? {
        try await request("POST", "/api/ios/login", body: [
            "username": username,
            "password": password,
            "device": deviceInfo()
        ])
    }

    func profile() async throws -> UserProfile? {
        struct Wrapper: Decodable { let user: UserProfile }
        let w: Wrapper? = try await request("GET", "/api/ios/profile")
        return w?.user
    }

    func updateProfile(nickname: String?, email: String?) async throws -> UserProfile? {
        struct Wrapper: Decodable { let user: UserProfile }
        var body: [String: Any] = [:]
        if let nickname { body["nickname"] = nickname }
        if let email { body["email"] = email }
        let w: Wrapper? = try await request("POST", "/api/ios/profile", body: body)
        return w?.user
    }

    func announcement() async throws -> Announcement? {
        try await request("GET", "/api/ios/announcement")
    }

    func clientConfig() async throws -> ClientConfig? {
        try await request("GET", "/api/ios/config")
    }

    func logout() async throws {
        _ = try await request("POST", "/api/ios/logout") as EmptyData?
    }

    // MARK: - 设备信息

    private func deviceInfo() -> [String: String] {
        let device = UIDevice.current
        return [
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "device_model": device.model,
            "os_version": "iOS \(device.systemVersion)",
            "app_version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        ]
    }
}

/// 用于 data 为 null 的接口
struct EmptyData: Decodable {}
```

## 4. SwiftUI 调用示例

```swift
import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: UserProfile?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let api = APIClient.shared

    /// App 启动时调用一次
    func bootstrap() async {
        do {
            try await api.ping()
            if let ann = try await api.announcement() {
                print("公告：\(ann.title)")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login(username: String, password: String) async {
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await api.login(username: username, password: password)
            user = try await api.profile()
        } catch { handle(error) }
    }

    func register(username: String, password: String, email: String) async {
        isLoading = true; defer { isLoading = false }
        do {
            _ = try await api.register(username: username, password: password, email: email)
            user = try await api.profile()
        } catch { handle(error) }
    }

    func updateNickname(_ nickname: String) async {
        do { user = try await api.updateProfile(nickname: nickname, email: nil) }
        catch { handle(error) }
    }

    func logout() async {
        try? await api.logout()
        user = nil
    }

    // MARK: - 错误处理建议

    private func handle(_ error: Error) {
        if case APIError.server(let code, let message) = error {
            switch code {
            case 401:
                user = nil                     // 会话过期 → 跳转登录页
                errorMessage = "登录已过期，请重新登录"
            case 403:
                // 封禁提示（后端 message 已含原因，如「账号已被封禁：违规」）
                errorMessage = message
            case 422:
                errorMessage = message         // 参数错误，直接展示
            default:
                errorMessage = message
            }
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
```

```swift
struct LoginView: View {
    @StateObject private var session = SessionStore()
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("用户名", text: $username).textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password).textFieldStyle(.roundedBorder)
            Button("登录") {
                Task { await session.login(username: username, password: password) }
            }
            .disabled(session.isLoading)

            if let err = session.errorMessage {
                Text(err).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding()
        .task { await session.bootstrap() }
    }
}
```

## 5. 关键注意事项

1. **Cookie 自动管理**：`QBSESSID` 为 HttpOnly，只能由 `HTTPCookieStorage` 保存，请勿手动读写；`APIClient` 已配置 `httpShouldSetCookies = true`。
2. **CSRF**：所有 `POST/PUT/DELETE` 必须带 `X-CSRF-TOKEN`，token 来自 `ping` 或 `login/register` 响应；本示例在每次成功响应后自动刷新。
3. **首次请求顺序**：先 `ping()` 建立会话，再调用其它接口。
4. **封禁处理**：登录返回 403 且 `message` 含封禁原因，直接展示给用户。
5. **登出**：`POST /api/ios/logout` 后服务端销毁会话，客户端应清空本地登录态。
6. **设备信息**：注册/登录时可选携带 `device`，会写入后台「设备信息」与「登录记录」，便于风控与运营分析。
