import Foundation

// MARK: - 通用信封

struct ApiEnvelope<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?
}

/// 后端返回的数字有时是字符串有时是数字，统一容错解析
@propertyWrapper
struct FlexDouble: Decodable {
    var wrappedValue: Double

    init(wrappedValue: Double = 0) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { wrappedValue = d; return }
        if let s = try? c.decode(String.self) { wrappedValue = Double(s) ?? 0; return }
        if let i = try? c.decode(Int.self) { wrappedValue = Double(i); return }
        wrappedValue = 0
    }
}

// MARK: - 系统状态

struct HealthResp: Decodable {
    let status: String
    let version: String?
    let serverTime: String?
    let javaVersion: String?
}

struct StatusResp: Decodable {
    let running: Bool
    let demoTrading: Bool
    let instId: String
    let bar: String
    let activeStrategy: String
    let tickCount: Int
    let lastTickAt: String?
    let errorMessage: String?
    @FlexDouble var balanceUSDT: Double
    let uptimeSeconds: Int?
    let ticker: TickerDTO?
    let positions: [PositionDTO]?
    let lastSignal: SignalDTO?
    let lastAIReply: String?
}

struct TickerDTO: Decodable {
    let instId: String
    let last: String
    let open24h: String?
    let high24h: String?
    let low24h: String?
    let vol24h: String?
    @FlexDouble var changePct: Double

    var lastDouble: Double { Double(last) ?? 0 }
}

struct PositionDTO: Decodable, Identifiable {
    var id: String { "\(instId)-\(posSide)" }
    let instId: String
    let posSide: String
    let pos: String
    let avgPx: String
    let upl: String
    let uplRatio: String
    let lever: String
    let mgnMode: String?

    var posDouble: Double { Double(pos) ?? 0 }
    var avgDouble: Double { Double(avgPx) ?? 0 }
    var uplDouble: Double { Double(upl) ?? 0 }
    var uplRatioPct: Double { (Double(uplRatio) ?? 0) * 100 }
    var isLong: Bool { posSide == "long" || (posSide == "net" && posDouble > 0) }
}

struct SignalDTO: Decodable {
    let action: String
    let reason: String
    @FlexDouble var confidence: Double
    let strategy: String?
    @FlexDouble var price: Double
    let at: String?

    var actionLabel: String {
        switch action {
        case "buy": return "开多"
        case "sell": return "开空"
        case "closeLong": return "平多"
        case "closeShort": return "平空"
        default: return "观望"
        }
    }
}

// MARK: - 行情

struct CandleDTO: Decodable, Identifiable {
    var id: Int64 { ts }
    let ts: Int64
    @FlexDouble var open: Double
    @FlexDouble var high: Double
    @FlexDouble var low: Double
    @FlexDouble var close: Double
    @FlexDouble var vol: Double

    var date: Date { Date(timeIntervalSince1970: Double(ts) / 1000) }
}

// MARK: - 日志

struct LogDTO: Decodable, Identifiable {
    let id: String
    let time: String
    let instId: String?
    let action: String
    @FlexDouble var price: Double
    @FlexDouble var size: Double
    let note: String
    let success: Bool

    var date: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: time) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: time) ?? Date()
    }
}

// MARK: - 配置

struct ConfigDTO: Decodable {
    let okxConfigured: Bool
    let okxApiKeyMasked: String?
    let demoTrading: Bool
    let instId: String
    let bar: String
    let activeStrategy: String
    @FlexDouble var tradeSizeUSDT: Double
    let leverage: Int
    let pollSeconds: Int
    @FlexDouble var stopLossPct: Double
    @FlexDouble var takeProfitPct: Double
    @FlexDouble var maxPositionUSDT: Double
    let maxTradesPerHour: Int
    let aiEnabled: Bool
    let aiBaseURL: String?
    let aiModel: String?
    let aiKeyConfigured: Bool
}

/// PUT /api/config 的请求体。密钥字段用 nil 表示「不改」。
struct ConfigUpdate: Encodable {
    var okxApiKey: String?
    var okxApiSecret: String?
    var okxPassphrase: String?
    var demoTrading: Bool?
    var instId: String?
    var bar: String?
    var activeStrategy: String?
    var tradeSizeUSDT: Double?
    var leverage: Int?
    var pollSeconds: Int?
    var stopLossPct: Double?
    var takeProfitPct: Double?
    var maxPositionUSDT: Double?
    var maxTradesPerHour: Int?
    var aiEnabled: Bool?
    var aiBaseURL: String?
    var aiModel: String?
    var aiKey: String?
}

struct StrategyDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let detail: String

    var kind: StrategyKind { StrategyKind(rawValue: id) ?? .maCross }
}

// MARK: - 策略枚举（与后端 id 对应）

enum StrategyKind: String, CaseIterable, Identifiable {
    case grid, maCross, rsi, breakout, ai
    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "网格交易"
        case .maCross: return "均线交叉"
        case .rsi: return "RSI 反转"
        case .breakout: return "通道突破"
        case .ai: return "AI 自主决策"
        }
    }
    var detail: String {
        switch self {
        case .grid: return "在区间内低买高卖，震荡行情收益稳定"
        case .maCross: return "快线上穿慢线开多，下穿开空，适合趋势"
        case .rsi: return "RSI < 30 超卖买入，> 70 超买卖出"
        case .breakout: return "突破 N 周期高点做多，跌破低点做空"
        case .ai: return "把行情和技术指标交给 AI，由它决定买卖"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .maCross: return "chart.line.uptrend.xyaxis"
        case .rsi: return "gauge.with.dots.needle.67percent"
        case .breakout: return "arrow.up.forward.square.fill"
        case .ai: return "brain.head.profile"
        }
    }
}

// MARK: - 常用交易对

enum Market {
    static let pairs = [
        "BTC-USDT", "ETH-USDT", "SOL-USDT", "BNB-USDT",
        "XRP-USDT", "DOGE-USDT", "ADA-USDT", "AVAX-USDT",
        "LINK-USDT", "TON-USDT",
    ]
    static var all: [String] { pairs + pairs.map { $0 + "-SWAP" } }
    static let bars = [
        ("1m", "1分钟"), ("5m", "5分钟"), ("15m", "15分钟"),
        ("30m", "30分钟"), ("1H", "1小时"), ("4H", "4小时"), ("1D", "日线"),
    ]
}
