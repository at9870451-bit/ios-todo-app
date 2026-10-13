import Foundation
import Security

/// 应用全局配置（服务器地址持久化在 UserDefaults，敏感信息在 Keychain）
@MainActor
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "server_url") }
    }
    @Published var loggedIn: Bool = false
    @Published var username: String = ""
    @Published var nickname: String = ""
    @Published var role: String = ""
    @Published var membershipLevel: String = ""

    /// CSRF token（登录后由服务端下发，写请求需带 X-CSRF-TOKEN）
    var csrfToken: String = ""

    private init() {
        var saved = UserDefaults.standard.string(forKey: "server_url") ?? "http://154.12.16.204:8080"
        // 旧服务器已下线：自动迁移到新服务器（2404:8c80:85:8001::be / 64.83.22.85 / www.daykai.asia）
        if saved.contains("2404:8c80:85:8001") || saved.contains("64.83.22.85") || saved.contains("daykai.asia") {
            saved = "http://154.12.16.204:8080"
            UserDefaults.standard.set(saved, forKey: "server_url")
        }
        self.serverURL = saved
        if let u = Keychain.read("auth.username") { username = u; loggedIn = true }
        if let n = Keychain.read("auth.nickname") { nickname = n }
        if let r = Keychain.read("auth.role") { role = r }
        if let m = Keychain.read("auth.membership") { membershipLevel = m }
    }

    /// 登录/注册成功后写入会话
    func applyAuth(user: AuthUser, csrf: String) {
        username = user.username
        nickname = user.nickname
        role = user.role
        membershipLevel = user.membershipLevel
        csrfToken = csrf
        loggedIn = true
        Keychain.save("auth.username", user.username)
        Keychain.save("auth.nickname", user.nickname)
        Keychain.save("auth.role", user.role)
        Keychain.save("auth.membership", user.membershipLevel)
    }

    func clearAuth() {
        loggedIn = false
        username = ""
        nickname = ""
        role = ""
        membershipLevel = ""
        csrfToken = ""
        Keychain.delete("auth.username")
        Keychain.delete("auth.nickname")
        Keychain.delete("auth.role")
        Keychain.delete("auth.membership")
    }
}

/// 极简 Keychain 封装（kSecClassGenericPassword）
enum Keychain {
    static func save(_ key: String, _ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.quantokx.app",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.quantokx.app",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.quantokx.app",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
