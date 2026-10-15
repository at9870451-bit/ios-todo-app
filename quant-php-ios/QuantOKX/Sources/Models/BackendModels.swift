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

// MARK: - 会员

struct MembershipPlansData: Decodable {
    let plans: [MembershipPlanRow]
    let badge: BadgeInfo?
    let limits: MembershipLimits?
    let usage: MembershipUsage?
    let payment: PaymentInfo?

    enum CodingKeys: String, CodingKey {
        case plans, badge, limits, usage, payment
    }
    /* 注意：后端 periods 是对象数组 [{"months":1,"label":"1 个月","discount":""}]，
       UI 未使用该字段，故不解码（此前声明成 [String:[Int]] 导致整个套餐响应解码失败）。 */
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

/// /api/member/status 的 data
struct MemberStatusData: Decodable {
    let badge: BadgeInfo
    let limits: MembershipLimits
    let usage: MembershipUsage?
    let payment: PaymentInfo?
}

// MARK: - 管理端（iOS 管理功能）

struct AdminStats: Decodable {
    let userTotal: Int
    let userToday: Int
    let orderTotal: Int
    let orderPaid: Int
    let orderPending: Int
    let incomeTotal: String
    let incomeToday: String

    enum CodingKeys: String, CodingKey {
        case userTotal = "user_total"
        case userToday = "user_today"
        case orderTotal = "order_total"
        case orderPaid = "order_paid"
        case orderPending = "order_pending"
        case incomeTotal = "income_total"
        case incomeToday = "income_today"
    }
}

struct AdminUsersData: Decodable {
    let items: [AdminUserRow]
    let total: Int
    let page: Int
    let size: Int
}

struct AdminUserRow: Decodable, Identifiable {
    let id: Int
    let username: String
    let nickname: String
    let email: String?
    let role: String
    let status: Int
    let membershipLevel: String
    let membershipName: String
    let membershipExpireAt: String?
    let daysLeft: Int?
    let liveTradingEnabled: Int?
    let lastLoginAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, role, status
        case membershipLevel = "membership_level"
        case membershipName = "membership_name"
        case membershipExpireAt = "membership_expire_at"
        case daysLeft = "days_left"
        case liveTradingEnabled = "live_trading_enabled"
        case lastLoginAt = "last_login_at"
        case createdAt = "created_at"
    }
}

struct AdminOrdersData: Decodable {
    let items: [AdminOrderRow]
    let total: Int
    let page: Int
    let size: Int
}

struct AdminOrderRow: Decodable, Identifiable {
    let id: Int
    let tradeNo: String
    let userId: Int
    let username: String
    let level: String
    let levelName: String
    let months: Int
    let amount: FlexString
    let channel: String
    let status: String
    let paidAt: String?
    let paidSource: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, level, months, amount, channel, status
        case tradeNo = "trade_no"
        case userId = "user_id"
        case levelName = "level_name"
        case paidAt = "paid_at"
        case paidSource = "paid_source"
        case createdAt = "created_at"
    }
}

struct AdminPlansData: Decodable {
    let plans: [AdminPlanRow]
    let levelNames: [String: String]?

    enum CodingKeys: String, CodingKey {
        case plans
        case levelNames = "level_names"
    }
}

struct AdminPlanRow: Decodable, Identifiable {
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
    let backtestDaily: Int
    let aiDaily: Int
    let multiSymbolLimit: Int
    let autoTrade: Int
    let liveTrade: Int
    let features: String?
    let sort: Int
    let enabled: Int

    enum CodingKeys: String, CodingKey {
        case level, name, features, sort, enabled
        case priceMonth = "price_month"
        case priceQuarter = "price_quarter"
        case priceYear = "price_year"
        case strategyLimit = "strategy_limit"
        case aiConfigLimit = "ai_config_limit"
        case accountLimit = "account_limit"
        case maxLeverage = "max_leverage"
        case backtestDaily = "backtest_daily"
        case aiDaily = "ai_daily"
        case multiSymbolLimit = "multi_symbol_limit"
        case autoTrade = "auto_trade"
        case liveTrade = "live_trade"
    }
}

struct FreeAiData: Decodable {
    let config: FreeAiConfig
    let configured: Bool
}

struct FreeAiConfig: Decodable {
    let name: String
    let providerType: String?
    let model: String?
    let apiUrl: String?
    let temperature: Double?
    let maxTokens: Int?
    let strategyNote: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name, model, enabled, temperature
        case providerType = "provider_type"
        case apiUrl = "api_url"
        case maxTokens = "max_tokens"
        case strategyNote = "strategy_note"
    }
}

struct PaymentConfigData: Decodable {
    let config: PaymentConfig
    let channels: [String: String]?
    let configured: Bool
}

struct PaymentConfig: Decodable {
    let apiUrl: String?
    let pid: String?
    let key: String?
    let enabled: Int
    let channels: [String]?
    let siteName: String?
    let notifyBase: String?

    enum CodingKeys: String, CodingKey {
        case pid, enabled, channels, key
        case apiUrl = "api_url"
        case siteName = "site_name"
        case notifyBase = "notify_base"
    }
}

struct SiteSettingsData: Decodable {
    let site: SiteSettings
}

struct SiteSettings: Decodable {
    let registerEnabled: Int
    let registerNeedEmail: Int
    let siteName: String
    let announcement: String

    enum CodingKeys: String, CodingKey {
        case announcement
        case registerEnabled = "register_enabled"
        case registerNeedEmail = "register_need_email"
        case siteName = "site_name"
    }
}

// MARK: - AI 配置详情（用于编辑）

struct AiConfigDetail: Decodable {
    let id: Int
    let name: String
    let providerType: String?
    let apiStyle: String?
    let apiUrl: String?
    let model: String?
    let temperature: Double?
    let maxTokens: Int?
    let mode: String
    let enabled: Bool
    let tradeMode: String?
    let leverage: Int?
    let autoSymbol: String?
    let autoSymbols: String?
    let autoMarketType: String?
    let directionMode: String?
    let autoInterval: String?
    let autoPeriodSeconds: Int?
    let autoQuantity: String?
    let autoPositionPercent: Double?
    let capitalUsdt: Double?
    let minConfidence: Double?
    let testStatus: String?
    let testMessage: String?
    let strategyNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, model, mode, enabled, leverage
        case providerType = "provider_type"
        case apiStyle = "api_style"
        case apiUrl = "api_url"
        case temperature
        case maxTokens = "max_tokens"
        case tradeMode = "trade_mode"
        case autoSymbol = "auto_symbol"
        case autoSymbols = "auto_symbols"
        case autoMarketType = "auto_market_type"
        case directionMode = "direction_mode"
        case autoInterval = "auto_interval"
        case autoPeriodSeconds = "auto_period_seconds"
        case autoQuantity = "auto_quantity"
        case autoPositionPercent = "auto_position_percent"
        case capitalUsdt = "capital_usdt"
        case minConfidence = "min_confidence"
        case testStatus = "test_status"
        case testMessage = "test_message"
        case strategyNote = "strategy_note"
    }
}
