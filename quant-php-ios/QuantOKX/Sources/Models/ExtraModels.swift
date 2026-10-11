import Foundation

// MARK: - AI 连接诊断（/api/ai/diagnose）

struct AiDiagnoseStep: Decodable {
    let name: String
    let status: String        // passed / failed
    let message: String
}

struct AiDiagnoseResult: Decodable {
    let success: Bool
    let configId: Int
    let steps: [AiDiagnoseStep]
    let modelOutput: String?

    enum CodingKeys: String, CodingKey {
        case success, steps
        case configId = "config_id"
        case modelOutput = "model_output"
    }
}

// MARK: - AI 交易复盘（/api/ai/reviews）

struct AiReviewRow: Decodable, Identifiable {
    let id: Int
    let symbol: FlexString
    let marketType: FlexString
    let positionSide: FlexString?
    let entryPrice: FlexString?
    let exitPrice: FlexString?
    let quantity: FlexString?
    let leverage: Int?
    let pnl: FlexString?
    let pnlPercent: FlexString?
    let status: String
    let reviewText: String?
    let errorMessage: String?
    let reviewedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, status, leverage, pnl, quantity
        case marketType = "market_type"
        case positionSide = "position_side"
        case entryPrice = "entry_price"
        case exitPrice = "exit_price"
        case pnlPercent = "pnl_percent"
        case reviewText = "review_text"
        case errorMessage = "error_message"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
    }
}

// MARK: - 策略运行监控（/api/strategy/monitor）

struct StrategyMonitorRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let symbol: FlexString
    let symbols: FlexString
    let marketType: String
    let directionMode: String
    let interval: String
    let mode: String
    let enabled: Bool
    let leverage: Int
    let positionPercent: FlexString
    let minConfidence: FlexString
    let status: String
    let lastSignal: String?
    let lastRunAt: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, symbols, mode, enabled, leverage, status
        case marketType = "market_type"
        case directionMode = "direction_mode"
        case interval
        case positionPercent = "position_percent"
        case minConfidence = "min_confidence"
        case lastSignal = "last_signal"
        case lastRunAt = "last_run_at"
        case errorMessage = "error_message"
    }
}

// MARK: - OKX 持仓模式（/api/okx/position-mode）

struct PositionModeData: Decodable {
    let configured: Bool
    let posMode: String?
    let hedged: Bool
    let acctLv: String?
    let accountName: String?

    enum CodingKeys: String, CodingKey {
        case configured, hedged
        case posMode = "pos_mode"
        case acctLv = "acct_lv"
        case accountName = "account_name"
    }
}
