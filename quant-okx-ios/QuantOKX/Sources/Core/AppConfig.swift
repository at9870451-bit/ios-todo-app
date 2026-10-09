import Foundation
import Combine

/// 全局配置。后台地址 + 访问令牌走 Keychain（令牌算凭据），其余走 UserDefaults。
@MainActor
final class AppConfig: ObservableObject {

    // MARK: - 后台连接
    @Published var backendURL: String = ""
    @Published var authToken: String = ""

    /// 本地缓存的远端配置（由 BackendStore 同步回来）
    @Published var demo: Bool = true
    @Published var instId: String = "BTC-USDT-SWAP"
    @Published var bar: String = "1m"
    @Published var strategy: StrategyKind = .maCross
    @Published var aiEnabled: Bool = false

    private let defaults = UserDefaults.standard

    init() {
        load()
        if backendURL.isEmpty {
            // 首次使用给个提示性默认值，方便用户在设置页看到格式
            backendURL = ""
        }
    }

    var isConfigured: Bool { !backendURL.isEmpty }

    var maskedURL: String {
        guard !backendURL.isEmpty else { return "未配置" }
        return backendURL
    }

    // MARK: - 读写

    func load() {
        backendURL = defaults.string(forKey: "backendURL") ?? ""
        authToken = Keychain.get("backend.token") ?? ""
        demo = defaults.object(forKey: "demo") as? Bool ?? true
        instId = defaults.string(forKey: "instId") ?? instId
        bar = defaults.string(forKey: "bar") ?? bar
        aiEnabled = defaults.bool(forKey: "aiEnabled")
        if let raw = defaults.string(forKey: "strategy"),
           let s = StrategyKind(rawValue: raw) { strategy = s }
    }

    func save() {
        defaults.set(backendURL, forKey: "backendURL")
        Keychain.set(authToken, for: "backend.token")
        defaults.set(demo, forKey: "demo")
        defaults.set(instId, forKey: "instId")
        defaults.set(bar, forKey: "bar")
        defaults.set(aiEnabled, forKey: "aiEnabled")
        defaults.set(strategy.rawValue, forKey: "strategy")
    }

    /// 用后台返回的配置覆盖本地缓存
    func apply(_ c: ConfigDTO) {
        demo = c.demoTrading
        instId = c.instId
        bar = c.bar
        if let s = StrategyKind(rawValue: c.activeStrategy) { strategy = s }
        aiEnabled = c.aiEnabled
        save()
    }

    func clearToken() {
        authToken = ""
        Keychain.delete("backend.token")
    }
}
