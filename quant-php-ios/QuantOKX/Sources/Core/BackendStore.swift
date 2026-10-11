import Foundation
import SwiftUI

/// 全局状态管理：登录态、数据加载、统一错误处理
@MainActor
final class BackendStore: ObservableObject {
    static let shared = BackendStore()

    let config = AppConfig.shared
    private let client = BackendClient.shared

    // 登录表单
    @Published var loginError: String = ""
    @Published var busy: Bool = false

    // 仪表盘
    @Published var dashboard: DashboardSummary?
    // OKX
    @Published var okxConfig: OkxConfigData?
    @Published var ticker: TickerRow?
    @Published var tickers: [TickerRow] = []
    @Published var accountSummary: OkxAccountSummary?
    @Published var orders: [OrderRow] = []
    @Published var positions: [LocalPositionRow] = []
    @Published var exchangePositions: [ExchangePosition] = []
    // 策略
    @Published var strategies: [StrategyRow] = []
    // AI
    @Published var aiConfigs: [AiConfigRow] = []
    @Published var aiAutoState: AiAutoState?
    // 台账
    @Published var trades: [TradeRow] = []
    @Published var tradeStats: TradeStats?
    @Published var profit: ProfitReport?
    @Published var tradingLogs: [TradingLogRow] = []
    @Published var systemLogs: [SystemLogRow] = []
    // 风控
    @Published var riskConfig: RiskConfig?
    // 会员
    @Published var memberPlans: MembershipPlansData?
    @Published var memberOrders: [MemberOrderRow] = []
    // 自动化
    @Published var automation: AutomationStatus?
    // 模拟盘
    @Published var paperStatus: PaperStatus?

    @Published var lastError: String = ""
    @Published var toast: String = ""

    private init() {
        Task { await client.configure(baseURL: config.serverURL) }
    }

    // MARK: - 会话

    /// 启动时恢复会话：配置地址并校验登录态
    func bootstrap() async {
        await client.configure(baseURL: config.serverURL)
        guard config.loggedIn else { return }
        do {
            let payload: SessionPayload = try await client.get("/api/ios/me", as: SessionPayload.self)
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
        } catch {
            // 会话失效：清空登录态（网络错误除外，保留以便重试）
            if let apiErr = error as? APIError, apiErr.isUnauthorized {
                config.clearAuth()
            }
        }
    }

    func login(username: String, password: String) async {
        busy = true
        loginError = ""
        defer { busy = false }
        do {
            await client.configure(baseURL: config.serverURL)
            let payload: SessionPayload = try await client.post(
                "/api/ios/login",
                body: ["username": username, "password": password],
                as: SessionPayload.self
            )
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
            toast = "欢迎回来，\(payload.user.nickname)"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func register(username: String, password: String, confirm: String, email: String) async {
        busy = true
        loginError = ""
        defer { busy = false }
        do {
            await client.configure(baseURL: config.serverURL)
            var body: [String: Any] = [
                "username": username,
                "password": password,
                "password_confirmation": confirm,
            ]
            if !email.isEmpty { body["email"] = email }
            let payload: SessionPayload = try await client.post("/api/ios/register", body: body, as: SessionPayload.self)
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
            toast = "注册成功"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() async {
        _ = try? await client.post("/api/ios/logout", body: [:], as: EmptyData.self)
        config.clearAuth()
    }

    /// 连通性测试（登录页用）
    func testConnection(url: String) async -> (ok: Bool, message: String) {
        await client.configure(baseURL: url)
        do {
            struct PingData: Decodable { let app: String; let version: String; let csrfToken: String?
                enum CodingKeys: String, CodingKey { case app, version; case csrfToken = "csrf_token" }
            }
            let data: PingData = try await client.get("/api/ios/ping", as: PingData.self)
            if let token = data.csrfToken { await client.setCSRF(token) }
            return (true, "\(data.app) \(data.version) 连接正常")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 通用请求包装（统一 401 处理）

    func handle(_ error: Error) {
        if let apiErr = error as? APIError {
            if apiErr.isUnauthorized {
                config.clearAuth()
            }
            lastError = apiErr.message
            toast = apiErr.message
        } else {
            lastError = error.localizedDescription
            toast = error.localizedDescription
        }
    }

    // MARK: - 数据加载

    func refreshDashboard() async {
        do { dashboard = try await client.get("/api/dashboard", as: DashboardSummary.self) }
        catch { handle(error) }
    }

    func loadOkxConfig() async {
        do { okxConfig = try await client.get("/api/okx/config", as: OkxConfigData.self) }
        catch { handle(error) }
    }

    func loadTicker(symbol: String, market: String) async {
        do {
            ticker = try await client.get("/api/okx/ticker", query: ["symbol": symbol, "market_type": market], as: TickerRow.self)
        } catch { handle(error) }
    }

    func loadTickers(market: String, keyword: String = "") async {
        do {
            var q = ["market_type": market, "limit": "50"]
            if !keyword.isEmpty { q["keyword"] = keyword }
            tickers = try await client.get("/api/okx/tickers", query: q, as: [TickerRow].self)
        } catch { handle(error) }
    }

    func loadAccount(market: String) async {
        do { accountSummary = try await client.get("/api/okx/account", query: ["market_type": market], as: OkxAccountSummary.self) }
        catch { handle(error) }
    }

    func loadOrders(remote: Bool = false) async {
        struct OrdersData: Decodable { let local: [OrderRow]; let remote: [OrderRow]? }
        do {
            orders = try await client.get("/api/okx/orders", query: remote ? ["remote": "1"] : nil, as: OrdersData.self).local
        } catch { handle(error) }
    }

    func loadPositions(market: String = "swap", source: String = "local") async {
        do {
            positions = try await client.get("/api/positions/local", query: ["market_type": market, "status": "OPEN"], as: [LocalPositionRow].self)
            if source == "exchange" {
                exchangePositions = try await client.get("/api/okx/positions", query: ["market_type": market], as: [ExchangePosition].self)
            }
        } catch { handle(error) }
    }

    func loadStrategies() async {
        do { strategies = try await client.get("/api/strategies", as: [StrategyRow].self) }
        catch { handle(error) }
    }

    func loadAiConfigs() async {
        do { aiConfigs = try await client.get("/api/ai/list", as: [AiConfigRow].self) }
        catch { handle(error) }
    }

    func loadAiAutoState() async {
        do { aiAutoState = try await client.get("/api/ai/auto/status", as: AiAutoState.self) }
        catch { handle(error) }
    }

    func loadTrades(symbol: String = "") async {
        do {
            var q: [String: String] = ["limit": "100"]
            if !symbol.isEmpty { q["symbol"] = symbol }
            trades = try await client.get("/api/trades", query: q, as: [TradeRow].self)
        } catch { handle(error) }
    }

    func loadTradeStats() async {
        do { tradeStats = try await client.get("/api/trades/stats", as: TradeStats.self) }
        catch { handle(error) }
    }

    func loadProfit(days: Int = 30) async {
        do { profit = try await client.get("/api/profit", query: ["days": "\(days)"], as: ProfitReport.self) }
        catch { handle(error) }
    }

    func loadTradingLogs() async {
        do { tradingLogs = try await client.get("/api/logs/trading", query: ["limit": "200"], as: [TradingLogRow].self) }
        catch { handle(error) }
    }

    func loadSystemLogs() async {
        do { systemLogs = try await client.get("/api/logs/system", query: ["limit": "200"], as: [SystemLogRow].self) }
        catch { handle(error) }
    }

    func loadRiskConfig() async {
        do { riskConfig = try await client.get("/api/risk/config", as: RiskConfig.self) }
        catch { handle(error) }
    }

    func loadMemberPlans() async {
        do { memberPlans = try await client.get("/api/member/plans", as: MembershipPlansData.self) }
        catch { handle(error) }
    }

    func loadMemberOrders() async {
        do { memberOrders = try await client.get("/api/member/orders", as: MemberOrdersData.self).items }
        catch { handle(error) }
    }

    func loadAutomation() async {
        do { automation = try await client.get("/api/system/automation/status", as: AutomationStatus.self) }
        catch { handle(error) }
    }

    func loadPaperStatus(market: String = "swap") async {
        do { paperStatus = try await client.get("/api/paper/status", query: ["market_type": market], as: PaperStatus.self) }
        catch { handle(error) }
    }

    // MARK: - 写操作

    func emergencyStop(_ enabled: Bool) async {
        struct Resp: Decodable { let emergencyStop: Bool
            enum CodingKeys: String, CodingKey { case emergencyStop = "emergency_stop" }
        }
        do {
            let r: Resp = try await client.post("/api/system/emergency-stop", body: ["enabled": enabled], as: Resp.self)
            toast = r.emergencyStop ? "已开启紧急停止" : "已解除紧急停止"
            await refreshDashboard()
        } catch { handle(error) }
    }

    func toggleLiveTrading(_ enabled: Bool) async {
        struct Resp: Decodable { let liveTradingEnabled: Bool
            enum CodingKeys: String, CodingKey { case liveTradingEnabled = "live_trading_enabled" }
        }
        do {
            var body: [String: Any] = ["enabled": enabled]
            if enabled { body["confirm_text"] = "ENABLE_LIVE" }
            let r: Resp = try await client.post("/api/system/live-trading", body: body, as: Resp.self)
            toast = r.liveTradingEnabled ? "实盘交易已开启" : "实盘交易已关闭"
            await refreshDashboard()
        } catch { handle(error) }
    }

    func startStrategy(_ id: Int) async {
        do {
            _ = try await client.post("/api/strategy/start", body: ["id": id], as: EmptyData.self)
            toast = "策略已启动"
            await loadStrategies()
        } catch { handle(error) }
    }

    func stopStrategy(_ id: Int) async {
        do {
            _ = try await client.post("/api/strategy/stop", body: ["id": id], as: EmptyData.self)
            toast = "策略已停止"
            await loadStrategies()
        } catch { handle(error) }
    }

    func deleteStrategy(_ id: Int) async {
        do {
            _ = try await client.post("/api/strategy/delete", body: ["id": id], as: EmptyData.self)
            toast = "策略已删除"
            await loadStrategies()
        } catch { handle(error) }
    }

    func startAi(_ id: Int) async {
        do {
            _ = try await client.post("/api/ai/auto/start", body: ["id": id], as: EmptyData.self)
            toast = "AI 自动交易已启动"
            await loadAiAutoState()
        } catch { handle(error) }
    }

    func stopAi(_ id: Int) async {
        do {
            _ = try await client.post("/api/ai/auto/stop", body: ["id": id], as: EmptyData.self)
            toast = "AI 自动交易已停止"
            await loadAiAutoState()
        } catch { handle(error) }
    }

    func runAiOnce(_ id: Int) async {
        do {
            _ = try await client.post("/api/ai/auto/run", body: id > 0 ? ["id": id] : [:], as: EmptyData.self)
            toast = "已执行一轮 AI 交易"
            await loadAiAutoState()
        } catch { handle(error) }
    }

    func saveRisk(_ fields: [String: String]) async {
        do {
            var body: [String: Any] = [:]
            for (k, v) in fields { body[k] = v }
            _ = try await client.post("/api/risk/config", body: body, as: EmptyData.self)
            toast = "风控参数已保存"
            await loadRiskConfig()
        } catch { handle(error) }
    }

    func saveOkxAccount(name: String, marketType: String, apiKey: String, apiSecret: String, passphrase: String, environment: String) async {
        do {
            var body: [String: Any] = [
                "name": name,
                "market_type": marketType,
                "environment": environment,
            ]
            if !apiKey.isEmpty { body["api_key"] = apiKey }
            if !apiSecret.isEmpty { body["api_secret"] = apiSecret }
            if !passphrase.isEmpty { body["passphrase"] = passphrase }
            _ = try await client.post("/api/okx/account/save", body: body, as: EmptyData.self)
            toast = "OKX 账号已保存"
            await loadOkxConfig()
        } catch { handle(error) }
    }

    func testOkx(marketType: String) async -> String {
        do {
            struct TestData: Decodable { let success: Bool?; let authenticated: Bool?; let environment: String? }
            let r: TestData = try await client.post("/api/okx/test", body: ["market_type": marketType], as: TestData.self)
            return "连接成功（\(r.environment ?? "?")）"
        } catch {
            if let apiErr = error as? APIError { return apiErr.message }
            return error.localizedDescription
        }
    }

    func placeOrder(symbol: String, marketType: String, mode: String, side: String, orderType: String,
                    quantity: String, price: String, leverage: Int?, stopLoss: String, takeProfit: String) async -> Bool {
        do {
            var body: [String: Any] = [
                "symbol": symbol,
                "market_type": marketType,
                "mode": mode,
                "side": side,
                "order_type": orderType,
                "quantity": quantity,
            ]
            if !price.isEmpty { body["price"] = price }
            if let leverage, marketType == "swap" { body["leverage"] = leverage }
            if !stopLoss.isEmpty { body["stop_loss"] = stopLoss }
            if !takeProfit.isEmpty { body["take_profit"] = takeProfit }
            _ = try await client.post("/api/order/create", body: body, as: EmptyData.self)
            toast = "订单已提交"
            await loadOrders()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func cancelOrder(_ id: Int) async {
        do {
            _ = try await client.post("/api/order/cancel", body: ["id": id], as: EmptyData.self)
            toast = "订单已撤销"
            await loadOrders()
        } catch { handle(error) }
    }

    func closePosition(symbol: String, marketType: String) async {
        do {
            _ = try await client.post("/api/position/close", body: ["symbol": symbol, "market_type": marketType], as: EmptyData.self)
            toast = "持仓已平仓"
            await loadPositions()
        } catch { handle(error) }
    }

    func refreshServer() async {
        do {
            _ = try await client.post("/api/system/refresh", body: [:], as: EmptyData.self)
            toast = "服务器已刷新"
        } catch { handle(error) }
    }

    func subscribe(level: String, months: Int, channel: String) async -> String? {
        do {
            struct PayData: Decodable { let tradeNo: String; let amount: String; let payUrl: String
                enum CodingKeys: String, CodingKey { case tradeNo = "trade_no"; case amount; case payUrl = "pay_url" }
            }
            let r: PayData = try await client.post("/api/member/pay", body: ["level": level, "months": months, "channel": channel], as: PayData.self)
            await loadMemberOrders()
            return r.payUrl
        } catch {
            handle(error)
            return nil
        }
    }
}
