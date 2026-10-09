import Foundation
import Combine

/// App 与 Java 后台之间的唯一桥梁。
/// 交易逻辑全在后台，这里只做：拉状态、下发指令、维护 UI 数据。
@MainActor
final class BackendStore: ObservableObject {

    // MARK: - 连接
    @Published private(set) var connected = false
    @Published private(set) var lastError: String?
    @Published private(set) var serverVersion: String?
    @Published private(set) var lastRefresh: Date?

    // MARK: - 引擎状态
    @Published private(set) var running = false
    @Published private(set) var tickCount = 0
    @Published private(set) var balanceUSDT: Double = 0
    @Published private(set) var uptimeSeconds: Int = 0
    @Published private(set) var engineError: String?
    @Published private(set) var ticker: TickerDTO?
    @Published private(set) var positions: [PositionDTO] = []
    @Published private(set) var lastSignal: SignalDTO?
    @Published private(set) var lastAIReply: String = ""
    @Published private(set) var demoTrading = true

    // MARK: - 配置与数据
    @Published private(set) var remoteConfig: ConfigDTO?
    @Published private(set) var logs: [LogDTO] = []
    @Published private(set) var strategies: [StrategyDTO] = []
    @Published private(set) var candles: [CandleDTO] = []

    // MARK: - 交互
    @Published private(set) var busy = false
    @Published var toast: String?

    private let client = BackendClient()
    private var pollTask: Task<Void, Never>?
    private weak var appConfig: AppConfig?

    init(appConfig: AppConfig) {
        self.appConfig = appConfig
    }

    func attach(_ cfg: AppConfig) {
        self.appConfig = cfg
        Task { await syncClient() }
    }

    private func syncClient() async {
        guard let appConfig else { return }
        await client.configure(baseURL: appConfig.backendURL, authToken: appConfig.authToken)
    }

    var isReady: Bool { appConfig?.isConfigured ?? false }

    // MARK: - 轮询

    func startPolling(interval: TimeInterval = 5) {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll()
                let wait = self.connected ? interval : 15
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 刷新

    func refreshAll() async {
        await syncClient()

        guard let appConfig, appConfig.isConfigured else {
            connected = false
            lastError = "未配置后台地址，请到「设置」填写"
            return
        }

        // 主状态：失败就整体标记离线
        do {
            let s = try await client.status()
            applyStatus(s)
            connected = true
            lastError = nil
            lastRefresh = Date()
        } catch {
            connected = false
            lastError = describe(error)
            return
        }

        // 次要数据：失败不影响主状态
        if let c = try? await client.getConfig() {
            remoteConfig = c
            appConfig.apply(c)
        }
        if let l = try? await client.logs(limit: 200) { logs = l }
        if let s = try? await client.strategies() { strategies = s }
    }

    private func applyStatus(_ s: StatusResp) {
        running = s.running
        tickCount = s.tickCount
        balanceUSDT = s.balanceUSDT
        uptimeSeconds = s.uptimeSeconds ?? 0
        engineError = s.errorMessage
        ticker = s.ticker
        positions = s.positions ?? []
        lastSignal = s.lastSignal
        lastAIReply = s.lastAIReply ?? ""
        demoTrading = s.demoTrading
    }

    func refreshCandles() async {
        await syncClient()
        guard let appConfig, appConfig.isConfigured else { return }
        if let c = try? await client.candles(appConfig.instId, bar: appConfig.bar, limit: 120) {
            candles = c
        }
    }

    // MARK: - 指令

    func startEngine() async {
        await perform { try await self.client.startEngine(); self.toast = "✅ 引擎已启动" }
    }

    func stopEngine() async {
        await perform { try await self.client.stopEngine(); self.toast = "⏹ 引擎已停止" }
    }

    func closeAll() async {
        await perform {
            let r = try await self.client.closeAll()
            self.toast = "✅ \(r.message ?? "已平仓 \(r.closed) 个")"
        }
    }

    func clearLogs() async {
        await perform {
            let n = try await self.client.clearLogs()
            self.logs = []
            self.toast = "✅ 已清空 \(n) 条日志"
        }
    }

    func updateConfig(_ body: ConfigUpdate) async {
        await perform {
            let c = try await self.client.updateConfig(body)
            self.remoteConfig = c
            self.appConfig?.apply(c)
            self.toast = "✅ 配置已保存"
        }
    }

    func testOKX() async {
        busy = true
        defer { busy = false }
        await syncClient()
        do {
            let r = try await client.testConnection()
            if r.ok {
                var msg = "✅ \(r.message)"
                if let p = r.lastPrice { msg += " · 现价 \(p)" }
                if let b = r.balanceUSDT { msg += " · 余额 \(b)" }
                toast = msg
            } else {
                toast = "❌ \(r.message)"
            }
        } catch {
            toast = "❌ \(describe(error))"
        }
    }

    func pingBackend() async -> String {
        await syncClient()
        do {
            let h = try await client.health()
            serverVersion = h.version
            return "✅ 后台在线 · v\(h.version ?? "?") · Java \(h.javaVersion ?? "?")"
        } catch {
            return "❌ \(describe(error))"
        }
    }

    /// 统一处理「发指令 → 刷新」流程
    private func perform(_ block: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        await syncClient()
        do {
            try await block()
            lastError = nil
            await refreshAll()
        } catch {
            lastError = describe(error)
            toast = "❌ \(lastError ?? "")"
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - 派生显示

    var uptimeText: String {
        let h = uptimeSeconds / 3600, m = (uptimeSeconds % 3600) / 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        if m > 0 { return "\(m) 分钟" }
        return "\(uptimeSeconds) 秒"
    }

    var lastRefreshText: String {
        guard let d = lastRefresh else { return "尚未刷新" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s) 秒前" }
        return "\(s / 60) 分钟前"
    }

    var activeStrategyTitle: String {
        guard let id = remoteConfig?.activeStrategy,
              let k = StrategyKind(rawValue: id) else {
            return appConfig?.strategy.title ?? "—"
        }
        return k.title
    }
}
