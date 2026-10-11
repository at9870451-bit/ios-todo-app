import Foundation

/// 数字/字符串混合解码辅助
struct FlexString: Decodable, CustomStringConvertible {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let d = try? c.decode(Double.self) {
            value = d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
            return
        }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        value = ""
    }
    var description: String { value }
    var doubleValue: Double { Double(value) ?? 0 }
}

// MARK: - Dashboard

struct DashboardSummary: Decodable {
    let okx: [String: OkxAccountBrief]
    let orders: [OrderRow]
    let positions: [LocalPositionRow]
    let pnl: PnlBrief
    let strategyCount: Int
    let aiRunning: Int
    let emergencyStop: Bool
    let liveTradingEnabled: Bool
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case okx, orders, positions, pnl
        case strategyCount = "strategy_count"
        case aiRunning = "ai_running"
        case emergencyStop = "emergency_stop"
        case liveTradingEnabled = "live_trading_enabled"
        case serverTime = "server_time"
    }
}

struct OkxAccountBrief: Decodable {
    let configured: Bool
    let totalAssets: String?
    let availableBalance: String?
    let unrealizedPnl: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case configured, error
        case totalAssets = "total_assets"
        case availableBalance = "available_balance"
        case unrealizedPnl = "unrealized_pnl"
    }
}

struct PnlBrief: Decodable {
    let today: Double
    let total30d: Double

    enum CodingKeys: String, CodingKey {
        case today
        case total30d = "total_30d"
    }
}

// MARK: - 订单

struct OrderRow: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let marketType: String
    let mode: String
    let side: String
    let positionSide: String?
    let orderType: String
    let price: FlexString
    let quantity: FlexString
    let executedQuantity: FlexString?
    let status: String
    let source: String?
    let rejectReason: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, mode, side, status, source
        case marketType = "market_type"
        case positionSide = "position_side"
        case orderType = "order_type"
        case price, quantity
        case executedQuantity = "executed_quantity"
        case rejectReason = "reject_reason"
        case createdAt = "created_at"
    }
}

// MARK: - 持仓

struct LocalPositionRow: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let marketType: String
    let positionSide: String
    let quantity: FlexString
    let entryPrice: FlexString
    let markPrice: FlexString
    let unrealizedPnl: FlexString
    let leverage: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, symbol, quantity, leverage, status
        case marketType = "market_type"
        case positionSide = "position_side"
        case entryPrice = "entry_price"
        case markPrice = "mark_price"
        case unrealizedPnl = "unrealized_pnl"
    }
}

// MARK: - 行情

struct TickerRow: Decodable {
    let symbol: String
    let lastPrice: String
    let highPrice: String
    let lowPrice: String
    let volume: String
    let priceChangePercent: String
}

struct KlineRow: Decodable {
    let time: Int
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String
}

// MARK: - 策略

struct StrategyRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let className: String
    let symbol: String
    let symbols: String?
    let marketType: String
    let directionMode: String
    let interval: String
    let mode: String
    let enabled: Bool
    let leverage: Int
    let positionPercent: Double
    let minConfidence: Double
    let status: String?
    let lastSignal: String?
    let lastRunAt: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, symbols, interval, mode, enabled, leverage, status
        case className = "class_name"
        case marketType = "market_type"
        case directionMode = "direction_mode"
        case positionPercent = "position_percent"
        case minConfidence = "min_confidence"
        case lastSignal = "last_signal"
        case lastRunAt = "last_run_at"
        case errorMessage = "error_message"
    }
}

// MARK: - AI 配置

struct AiConfigRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let providerType: String?
    let model: String?
    let enabled: Bool
    let mode: String
    let running: Bool?
    let tradeMode: String?
    let leverage: Int?
    let autoSymbol: String?
    let autoMarketType: String?
    let directionMode: String?
    let autoInterval: String?
    let autoPeriodSeconds: Int?
    let capitalUsdt: Double?
    let minConfidence: Double?
    let runCount: Int?
    let tradeCount: Int?
    let lastRunAt: String?
    let lastSignal: String?
    let errorMessage: String?
    let testStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, name, model, enabled, mode, running, leverage
        case providerType = "provider_type"
        case tradeMode = "trade_mode"
        case autoSymbol = "auto_symbol"
        case autoMarketType = "auto_market_type"
        case directionMode = "direction_mode"
        case autoInterval = "auto_interval"
        case autoPeriodSeconds = "auto_period_seconds"
        case capitalUsdt = "capital_usdt"
        case minConfidence = "min_confidence"
        case runCount = "run_count"
        case tradeCount = "trade_count"
        case lastRunAt = "last_run_at"
        case lastSignal = "last_signal"
        case errorMessage = "error_message"
        case testStatus = "test_status"
    }
}

struct AiAutoState: Decodable {
    let running: Bool
    let runningCount: Int
    let autoConfigCount: Int
    let emergencyStop: Bool
    let liveTradingEnabled: Bool
    let localTradingEnabled: Bool
    let maxLeverage: Int
    let cronUrl: String?
    let configs: [AiConfigRow]
    let recentSignals: [AiSignalRow]

    enum CodingKeys: String, CodingKey {
        case running, configs
        case runningCount = "running_count"
        case autoConfigCount = "auto_config_count"
        case emergencyStop = "emergency_stop"
        case liveTradingEnabled = "live_trading_enabled"
        case localTradingEnabled = "local_trading_enabled"
        case maxLeverage = "max_leverage"
        case cronUrl = "cron_url"
        case recentSignals = "recent_signals"
    }
}

struct AiSignalRow: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let signal: String
    let confidence: FlexString
    let entry: FlexString?
    let stopLoss: FlexString?
    let takeProfit: FlexString?
    let reason: String?
    let executed: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, signal, confidence, entry, reason, executed
        case stopLoss = "stop_loss"
        case takeProfit = "take_profit"
        case createdAt = "created_at"
    }
}

// MARK: - 台账

struct TradeRow: Decodable, Identifiable {
    let id: Int
    let symbol: String
    let side: String
    let price: FlexString
    let quantity: FlexString
    let fee: FlexString?
    let tradeTime: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, side, price, quantity, fee
        case tradeTime = "trade_time"
    }
}

struct TradeStats: Decodable {
    let total: Int
    let buyCount: Int
    let sellCount: Int
    let volume: Double
    let fee: Double

    enum CodingKeys: String, CodingKey {
        case total, volume, fee
        case buyCount = "buy_count"
        case sellCount = "sell_count"
    }
}

struct ProfitReport: Decodable {
    let days: Int
    let totalPnl: Double
    let daily: [String: Double]
    let curve: [CurvePoint]
    let assets: ProfitAssets?

    enum CodingKeys: String, CodingKey {
        case days, daily, curve, assets
        case totalPnl = "total_pnl"
    }
}

struct CurvePoint: Decodable {
    let time: String
    let value: Double
    let daily: Double?
}

struct ProfitAssets: Decodable {
    let okx: [String: OkxAccountBrief]?
}

struct TradingLogRow: Decodable, Identifiable {
    let id: Int
    let symbol: String?
    let source: String?
    let signal: String?
    let price: FlexString?
    let result: String?
    let pnl: FlexString?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, source, signal, price, result, pnl
        case createdAt = "created_at"
    }
}

struct SystemLogRow: Decodable, Identifiable {
    let id: Int
    let level: String
    let channel: String
    let message: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, level, channel, message
        case createdAt = "created_at"
    }
}

// MARK: - 风控

struct RiskConfig: Decodable {
    let singlePositionPercent: FlexString
    let maxTotalPositionPercent: FlexString
    let singleLossPercent: FlexString
    let dailyLossPercent: FlexString
    let dailyTradeLimit: FlexString
    let consecutiveLossLimit: FlexString
    let maxLeverage: FlexString
    let maxPositions: FlexString
    let emergencyStop: Int
    let liveTradingEnabled: Bool?
    let openPositions: Int?
    let todayTrades: Int?

    enum CodingKeys: String, CodingKey {
        case singlePositionPercent = "single_position_percent"
        case maxTotalPositionPercent = "max_total_position_percent"
        case singleLossPercent = "single_loss_percent"
        case dailyLossPercent = "daily_loss_percent"
        case dailyTradeLimit = "daily_trade_limit"
        case consecutiveLossLimit = "consecutive_loss_limit"
        case maxLeverage = "max_leverage"
        case maxPositions = "max_positions"
        case emergencyStop = "emergency_stop"
        case liveTradingEnabled = "live_trading_enabled"
        case openPositions = "open_positions"
        case todayTrades = "today_trades"
    }
}

// MARK: - 会员

struct MembershipPlansData: Decodable {
    let plans: [MembershipPlanRow]
    let periods: [String: [Int]]?
    let badge: BadgeInfo?
    let limits: MembershipLimits?
    let usage: MembershipUsage?
    let payment: PaymentInfo?

    enum CodingKeys: String, CodingKey {
        case plans, periods, badge, limits, usage, payment
    }
}

struct MembershipPlanRow: Decodable, Identifiable {
    var id: String { level }
    let level: String
    let name: String
    let priceMonth: FlexString
    let priceQuarter: FlexString
    let priceYear: FlexString
    let strategyLimit: Int
    let aiConfigLimit: Int
    let accountLimit: Int
    let maxLeverage: Int
    let features: String?

    enum CodingKeys: String, CodingKey {
        case level, name, features
        case priceMonth = "price_month"
        case priceQuarter = "price_quarter"
        case priceYear = "price_year"
        case strategyLimit = "strategy_limit"
        case aiConfigLimit = "ai_config_limit"
        case accountLimit = "account_limit"
        case maxLeverage = "max_leverage"
    }
}

struct MembershipLimits: Decodable {
    let level: String
    let name: String
    let strategyLimit: Int
    let aiConfigLimit: Int
    let accountLimit: Int
    let maxLeverage: Int
    let autoTrade: Bool
    let liveTrade: Bool

    enum CodingKeys: String, CodingKey {
        case level, name
        case strategyLimit = "strategy_limit"
        case aiConfigLimit = "ai_config_limit"
        case accountLimit = "account_limit"
        case maxLeverage = "max_leverage"
        case autoTrade = "auto_trade"
        case liveTrade = "live_trade"
    }
}

struct MembershipUsage: Decodable {
    let backtestToday: Int
    let aiToday: Int

    enum CodingKeys: String, CodingKey {
        case backtestToday = "backtest_today"
        case aiToday = "ai_today"
    }
}

struct PaymentInfo: Decodable {
    let configured: Bool
    let channels: [String]?
    let channelNames: [String: String]?

    enum CodingKeys: String, CodingKey {
        case configured, channels
        case channelNames = "channel_names"
    }
}

struct MemberOrderRow: Decodable, Identifiable {
    let id: Int
    let tradeNo: String
    let level: String
    let levelName: String
    let months: Int
    let amount: FlexString
    let status: String
    let payUrl: String?
    let paidAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, level, months, amount, status
        case tradeNo = "trade_no"
        case levelName = "level_name"
        case payUrl = "pay_url"
        case paidAt = "paid_at"
        case createdAt = "created_at"
    }
}

struct MemberOrdersData: Decodable {
    let items: [MemberOrderRow]
}

// MARK: - OKX 账户

struct OkxConfigData: Decodable {
    let spot: OkxConfigSlot?
    let swap: OkxConfigSlot?
    let accounts: [OkxAccountRow]

    enum CodingKeys: String, CodingKey { case spot, swap, accounts }
}

struct OkxConfigSlot: Decodable {
    let configured: Bool
    let id: Int?
    let name: String?
    let environment: String?
    let credentialsSaved: Bool?
    let proxyEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case configured, id, name, environment
        case credentialsSaved = "credentials_saved"
        case proxyEnabled = "proxy_enabled"
    }
}

struct OkxAccountRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let marketType: String
    let environment: String
    let enabled: Bool
    let credentialsSaved: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, environment, enabled
        case marketType = "market_type"
        case credentialsSaved = "credentials_saved"
    }
}

struct OkxAccountSummary: Decodable {
    let configured: Bool?
    let totalAssets: String?
    let availableBalance: String?
    let unrealizedPnl: String?
    let balances: [BalanceRow]?
    let positions: [ExchangePosition]?

    enum CodingKeys: String, CodingKey {
        case configured, balances, positions
        case totalAssets = "total_assets"
        case availableBalance = "available_balance"
        case unrealizedPnl = "unrealized_pnl"
    }
}

struct BalanceRow: Decodable, Identifiable {
    var id: String { asset }
    let asset: String
    let free: FlexString
    let locked: FlexString
    let total: FlexString
}

struct ExchangePosition: Decodable, Identifiable {
    var id: String { symbol + positionSide }
    let symbol: String
    let positionAmt: FlexString
    let entryPrice: FlexString
    let unrealizedProfit: FlexString
    let leverage: FlexString
    let positionSide: String
}

// MARK: - 自动化状态

struct AutomationStatus: Decodable {
    let strategy: AutomationLane
    let ai: AutomationLane
    let cronUrl: String?
    let activeStrategyCount: Int?
    let activeAiCount: Int?

    enum CodingKeys: String, CodingKey {
        case strategy, ai
        case cronUrl = "cron_url"
        case activeStrategyCount = "active_strategy_count"
        case activeAiCount = "active_ai_count"
    }
}

struct AutomationLane: Decodable {
    let lastRunAt: String?
    let status: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case status, source
        case lastRunAt = "last_run_at"
    }
}

// MARK: - 模拟盘

struct PaperStatus: Decodable {
    let configured: Bool
    let localTradingEnabled: Bool
    let accountName: String?
    let totalAssets: String?
    let availableBalance: String?
    let unrealizedPnl: String?
    let positions: [ExchangePosition]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case configured, positions, error
        case localTradingEnabled = "local_trading_enabled"
        case accountName = "account_name"
        case totalAssets = "total_assets"
        case availableBalance = "available_balance"
        case unrealizedPnl = "unrealized_pnl"
    }
}
