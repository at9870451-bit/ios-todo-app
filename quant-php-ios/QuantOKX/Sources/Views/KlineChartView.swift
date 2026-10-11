import SwiftUI

/// K 线图（Canvas 绘制，对齐网页版 kline.js 的视觉风格）
struct KlineChartView: View {
    let candles: [KlineRow]

    private let upColor = Color(red: 0.16, green: 0.78, blue: 0.51)
    private let downColor = Color(red: 1.0, green: 0.35, blue: 0.42)

    var body: some View {
        Canvas { context, size in
            guard candles.count > 1 else { return }

            let n = min(candles.count, 80)
            let data = Array(candles.suffix(n))

            var highs: [Double] = []
            var lows: [Double] = []
            for c in data {
                highs.append(Double(c.high) ?? 0)
                lows.append(Double(c.low) ?? 0)
            }
            guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }

            let topPad: CGFloat = 8
            let bottomPad: CGFloat = 8
            let chartH = size.height - topPad - bottomPad
            func yFor(_ price: Double) -> CGFloat {
                let ratio = (price - minLow) / (maxHigh - minLow)
                return topPad + chartH * (1 - CGFloat(ratio))
            }

            let slot = size.width / CGFloat(data.count)
            let bodyW = max(1.5, slot * 0.62)

            // 网格线（4 条横线）
            var grid = Path()
            for i in 1...3 {
                let y = topPad + chartH * CGFloat(i) / 4
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)

            // 蜡烛
            for (i, c) in data.enumerated() {
                guard let o = Double(c.open), let cl = Double(c.close),
                      let h = Double(c.high), let l = Double(c.low) else { continue }
                let cx = slot * CGFloat(i) + slot / 2
                let color = cl >= o ? upColor : downColor
                let yHigh = yFor(h)
                let yLow = yFor(l)
                let yOpen = yFor(o)
                let yClose = yFor(cl)

                // 影线
                var wick = Path()
                wick.move(to: CGPoint(x: cx, y: yHigh))
                wick.addLine(to: CGPoint(x: cx, y: yLow))
                context.stroke(wick, with: .color(color.opacity(0.9)), lineWidth: 1)

                // 实体
                let bodyTop = min(yOpen, yClose)
                let bodyBottom = max(yOpen, yClose)
                let rect = CGRect(x: cx - bodyW / 2, y: bodyTop,
                                  width: bodyW, height: max(1, bodyBottom - bodyTop))
                context.fill(Path(rect), with: .color(color))
            }

            // 最新价横线
            if let last = data.last, let lastClose = Double(last.close) {
                let y = yFor(lastClose)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color(red: 0.29, green: 0.56, blue: 1.0).opacity(0.7)),
                               style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            }
        }
        .frame(height: 190)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

/// K 线区块：周期选择 + 图表 + 加载
struct KlineSection: View {
    @EnvironmentObject var store: BackendStore

    let symbol: String
    let market: String

    @State private var interval = "15m"
    @State private var candles: [KlineRow] = []
    @State private var loading = false

    private let intervals = ["1m", "5m", "15m", "1h", "4h", "1d"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("K 线走势").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if loading { ProgressView().controlSize(.small).tint(.white.opacity(0.5)) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(intervals, id: \.self) { i in
                        Button {
                            interval = i
                            Task { await load() }
                        } label: {
                            Text(i)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(interval == i ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(interval == i ? Color.blue.opacity(0.6) : Color.white.opacity(0.07),
                                            in: Capsule())
                        }
                    }
                }
            }
            KlineChartView(candles: candles)
            if candles.isEmpty && !loading {
                Text("暂无 K 线数据").font(.caption).foregroundStyle(.white.opacity(0.35))
            }
        }
        .task { await load() }
        .onChange(of: symbol) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            candles = try await BackendClient.shared.get("/api/okx/kline", query: [
                "symbol": symbol, "market_type": market, "interval": interval, "limit": "120",
            ], as: [KlineRow].self)
        } catch {
            store.handle(error)
        }
    }
}

/// 策略信号分析（strategy/analyze）
struct StrategyAnalyzeView: View {
    @EnvironmentObject var store: BackendStore

    @State private var symbol = "BTC-USDT-SWAP"
    @State private var strategy = "ma"
    @State private var interval = "15m"
    @State private var result: AnalyzeResult?
    @State private var running = false
    @State private var errorMsg = ""

    struct AnalyzeResult: Decodable {
        let signal: String
        let confidence: Double
        let price: FlexString?
        let reason: String?
    }

    private let strategies = ["ma", "ema", "macd", "rsi", "boll", "kdj", "atr", "donchian", "supertrend"]
    private let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]

    var body: some View {
        PageScaffold(title: "信号分析", subtitle: "对当前行情运行策略，输出即时的买卖信号") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    FieldRow(icon: "bitcoinsign.circle", placeholder: "交易对", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 5) {
                        Text("策略类型").font(.caption).foregroundStyle(.white.opacity(0.5))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(strategies, id: \.self) { s in
                                    Button {
                                        strategy = s
                                    } label: {
                                        Text(s.uppercased())
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(strategy == s ? .white : .white.opacity(0.5))
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(strategy == s ? Color.blue.opacity(0.6) : Color.white.opacity(0.07),
                                                        in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("K 线周期").font(.caption).foregroundStyle(.white.opacity(0.5))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(intervals, id: \.self) { i in
                                    Button {
                                        interval = i
                                    } label: {
                                        Text(i)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(interval == i ? .white : .white.opacity(0.5))
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(interval == i ? Color.blue.opacity(0.6) : Color.white.opacity(0.07),
                                                        in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    PrimaryButton(title: running ? "分析中…" : "开始分析", icon: "waveform.path.ecg", disabled: running) {
                        Task { await analyze() }
                    }
                }
            }

            if !errorMsg.isEmpty {
                Card(padding: 12) {
                    Text(errorMsg).font(.caption).foregroundStyle(.orange)
                }
            }

            if let r = result {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("信号结果").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            StatusBadge(text: r.signal,
                                        color: r.signal == "BUY" ? .green : (r.signal == "SELL" ? .red : .gray))
                        }
                        HStack(spacing: 10) {
                            StatTile(title: "置信度", value: String(format: "%.0f%%", r.confidence * 100))
                            StatTile(title: "当前价", value: Fmt.price(r.price?.value))
                        }
                        if let reason = r.reason, !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("信号分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func analyze() async {
        running = true
        defer { running = false }
        errorMsg = ""
        do {
            result = try await BackendClient.shared.post("/api/strategy/analyze", body: [
                "symbol": symbol.uppercased(),
                "strategy": strategy,
                "interval": interval,
            ], as: AnalyzeResult.self)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
