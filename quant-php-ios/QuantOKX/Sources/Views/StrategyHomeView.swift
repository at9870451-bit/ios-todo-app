import SwiftUI

/// 策略首页：策略列表 + 启动/停止 + 回测入口
struct StrategyHomeView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.055, blue: 0.09).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("策略")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("多策略引擎 · 回测 · 运行监控")
                                .font(.footnote).foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.top, 6)

                        NavigationLink {
                            BacktestView()
                        } label: {
                            HStack(spacing: 13) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.orange.opacity(0.18)).frame(width: 40, height: 40)
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 17)).foregroundStyle(.orange)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("策略回测").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("历史数据验证策略表现").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.25))
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            StrategyAnalyzeView()
                        } label: {
                            HStack(spacing: 13) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.teal.opacity(0.18)).frame(width: 40, height: 40)
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.system(size: 17)).foregroundStyle(.teal)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("信号分析").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("对当前行情运行策略，输出即时信号").font(.caption).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.25))
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)

                        NavCard(icon: "waveform.path", title: "运行监控", desc: "每个策略最近一轮执行状态", color: .indigo) {
                            StrategyMonitorView()
                        }

                        // 运行监控
                        if let automation = store.automation {
                            Card(padding: 13) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("后台自动化").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    HStack {
                                        InfoRow(label: "策略任务", value: automation.strategy.status ?? "未运行",
                                                valueColor: automation.strategy.status == "running" ? .green : .gray)
                                        InfoRow(label: "AI 任务", value: automation.ai.status ?? "未运行",
                                                valueColor: automation.ai.status == "running" ? .green : .gray)
                                    }
                                    if let last = automation.strategy.lastRunAt {
                                        Text("策略最近执行：\(Fmt.time(last))")
                                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                            }
                        }

                        // 策略列表
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("策略列表").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text("\(store.strategies.count) 个").font(.caption).foregroundStyle(.white.opacity(0.4))
                                NavigationLink {
                                    StrategyEditView(existing: nil)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 1.0))
                                }
                            }
                            if store.strategies.isEmpty {
                                EmptyHint(icon: "chart.xyaxis.line", text: "暂无策略\n点右上角 + 创建")
                            } else {
                                ForEach(store.strategies) { s in
                                    strategyCard(s)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await store.loadStrategies()
                    await store.loadAutomation()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await store.loadStrategies()
                await store.loadAutomation()
            }
        }
    }

    private func strategyCard(_ s: StrategyRow) -> some View {
        Card(padding: 13) {
            VStack(spacing: 9) {
                HStack {
                    Text(s.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    StatusBadge(text: s.className.uppercased(), color: .blue)
                    Spacer()
                    StatusBadge(text: s.enabled ? "运行中" : "已停止",
                                color: s.enabled ? Color(red: 0.25, green: 0.85, blue: 0.5) : .gray)
                }
                HStack {
                    InfoRow(label: "交易对", value: s.symbol, mono: true)
                    InfoRow(label: "周期", value: s.interval)
                }
                HStack {
                    InfoRow(label: "市场", value: s.marketType == "spot" ? "现货" : "永续")
                    InfoRow(label: "模式", value: modeText(s.mode))
                    InfoRow(label: "杠杆", value: "\(s.leverage)x")
                }
                HStack {
                    if let sig = s.lastSignal, !sig.isEmpty {
                        StatusBadge(text: "信号 \(sig)", color: sig == "BUY" ? .green : (sig == "SELL" ? .red : .gray))
                    }
                    Text(Fmt.time(s.lastRunAt)).font(.caption2).foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    if let err = s.errorMessage, !err.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    }
                }
                HStack(spacing: 10) {
                    if s.enabled {
                        Button {
                            Task { await store.stopStrategy(s.id) }
                        } label: {
                            Text("停止")
                                .font(.caption.weight(.semibold)).foregroundStyle(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        }
                    } else {
                        Button {
                            Task { await store.startStrategy(s.id) }
                        } label: {
                            Text("启动")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.25, green: 0.85, blue: 0.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    NavigationLink {
                        StrategyEditView(existing: s)
                    } label: {
                        Text("编辑")
                            .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Button {
                        Task { await store.deleteStrategy(s.id) }
                    } label: {
                        Text("删除")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
    }

    private func modeText(_ m: String) -> String {
        switch m {
        case "paper": return "本地模拟"
        case "testnet": return "OKX 模拟盘"
        case "live": return "实盘"
        default: return m
        }
    }
}

/// 策略回测
struct BacktestView: View {
    @EnvironmentObject var store: BackendStore

    @State private var symbol = "BTC-USDT"
    @State private var strategy = "ma"
    @State private var interval = "15m"
    @State private var initialCapital = "10000"
    @State private var running = false
    @State private var result: BacktestResult?

    struct BacktestResult: Decodable {
        let symbol: String
        let finalCapital: Double
        let returnRate: Double
        let maxDrawdown: Double
        let winRate: Double
        let winCount: Int
        let lossCount: Int
        let profitFactor: Double
        let tradeCount: Int

        enum CodingKeys: String, CodingKey {
            case symbol
            case finalCapital = "final_capital"
            case returnRate = "return_rate"
            case maxDrawdown = "max_drawdown"
            case winRate = "win_rate"
            case winCount = "win_count"
            case lossCount = "loss_count"
            case profitFactor = "profit_factor"
            case tradeCount = "trade_count"
        }
    }

    private let strategies = ["ma", "macd", "rsi", "boll", "kdj", "atr", "donchian", "supertrend"]
    private let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]

    var body: some View {
        PageScaffold(title: "策略回测", subtitle: "历史数据验证策略（计入手续费与滑点）") {
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

                    FieldRow(icon: "dollarsign.circle", placeholder: "初始资金", text: $initialCapital)
                        .keyboardType(.numberPad)

                    PrimaryButton(title: running ? "回测中…" : "开始回测", icon: "play.fill", disabled: running) {
                        Task { await run() }
                    }
                }
            }

            if let r = result {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("回测结果").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        HStack(spacing: 10) {
                            StatTile(title: "收益率", value: String(format: "%+.2f%%", r.returnRate * 100),
                                     color: r.returnRate >= 0 ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.36, blue: 0.36))
                            StatTile(title: "最大回撤", value: String(format: "%.2f%%", r.maxDrawdown * 100),
                                     color: .orange)
                        }
                        HStack(spacing: 10) {
                            StatTile(title: "胜率", value: String(format: "%.1f%%", r.winRate * 100))
                            StatTile(title: "盈亏比", value: String(format: "%.2f", r.profitFactor))
                            StatTile(title: "交易数", value: "\(r.tradeCount)")
                        }
                        InfoRow(label: "最终资金", value: Fmt.money(String(r.finalCapital)), mono: true)
                        InfoRow(label: "盈利/亏损笔数", value: "\(r.winCount) / \(r.lossCount)")
                    }
                }
            }
        }
        .navigationTitle("策略回测")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            result = try await BackendClient.shared.post("/api/strategy/backtest", body: [
                "symbol": symbol.uppercased(),
                "strategy": strategy,
                "interval": interval,
                "initial_capital": initialCapital,
            ], as: BacktestResult.self)
            store.toast = "回测完成"
        } catch {
            store.handle(error)
        }
    }
}
