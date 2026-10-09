import SwiftUI

struct StrategyView: View {
    @EnvironmentObject private var store: BackendStore

    // 本地编辑态，点「保存」才推到后台
    @State private var strategy: StrategyKind = .maCross
    @State private var instId = "BTC-USDT-SWAP"
    @State private var bar = "1m"
    @State private var tradeSize: Double = 10
    @State private var leverage: Int = 3
    @State private var pollSeconds: Int = 15
    @State private var stopLoss: Double = 2
    @State private var takeProfit: Double = 4
    @State private var maxPosition: Double = 100
    @State private var maxTrades: Int = 10
    @State private var demoTrading = true
    @State private var aiEnabled = false
    @State private var aiBaseURL = ""
    @State private var aiModel = ""
    @State private var aiKey = ""

    @State private var loaded = false
    @State private var showLiveConfirm = false
    @State private var pendingDemo = true

    private var dirty: Bool {
        guard let c = store.remoteConfig else { return false }
        return c.activeStrategy != strategy.rawValue
            || c.instId != instId || c.bar != bar
            || abs(c.tradeSizeUSDT - tradeSize) > 0.0001
            || c.leverage != leverage || c.pollSeconds != pollSeconds
            || abs(c.stopLossPct - stopLoss) > 0.0001
            || abs(c.takeProfitPct - takeProfit) > 0.0001
            || abs(c.maxPositionUSDT - maxPosition) > 0.0001
            || c.maxTradesPerHour != maxTrades
            || c.demoTrading != demoTrading
            || c.aiEnabled != aiEnabled
            || (c.aiBaseURL ?? "") != aiBaseURL
            || (c.aiModel ?? "") != aiModel
            || !aiKey.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.connected {
                    Section {
                        Label("后台未连接，配置无法加载", systemImage: "wifi.slash")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                strategySection
                if strategy == .ai { aiSection }
                tradingSection
                riskSection
                modeSection

                Section {
                    Button {
                        Task { await store.testOKX() }
                    } label: {
                        Label("测试 OKX 连接（由后台发起）", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(!store.connected || store.busy)
                } footer: {
                    if let mask = store.remoteConfig?.okxApiKeyMasked {
                        Text("当前密钥：\(mask)")
                    } else {
                        Text("OKX 密钥在后台服务器上配置，App 里不保存")
                    }
                }
            }
            .navigationTitle("策略与参数")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!dirty || !store.connected || store.busy)
                }
            }
            .onAppear { loadFromRemote() }
            .onChange(of: store.remoteConfig) { _, _ in
                if !dirty { loadFromRemote() }
            }
            .confirmationDialog("切换到实盘？", isPresented: $showLiveConfirm, titleVisibility: .visible) {
                Button("我明白，切到实盘", role: .destructive) {
                    demoTrading = false
                    Task { await save() }
                }
                Button("保持模拟盘", role: .cancel) {
                    demoTrading = true
                    pendingDemo = true
                }
            } message: {
                Text("实盘会用真实资金下单。请确认：\n• OKX 上的 API Key 已关闭「提币」权限\n• 每单金额和杠杆设置合理\n• 你清楚程序可能亏损")
            }
        }
    }

    // MARK: - 分区

    private var strategySection: some View {
        Section {
            ForEach(StrategyKind.allCases) { kind in
                Button {
                    strategy = kind
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(strategy == kind ? Color.blue : Color.gray.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .foregroundStyle(strategy == kind ? .white : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(kind.detail)
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if strategy == kind {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("策略")
        } footer: {
            Text("策略运行在 Java 后台，App 只负责下发配置。切换后点右上角「保存」生效。")
        }
    }

    private var aiSection: some View {
        Section {
            Toggle("启用 AI 决策", isOn: $aiEnabled)
            TextField("接口地址", text: $aiBaseURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.caption.monospaced())
            TextField("模型名", text: $aiModel)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("API Key（留空表示不修改）", text: $aiKey)
                .textInputAutocapitalization(.never)
        } header: {
            Text("AI 引擎")
        } footer: {
            Text("兼容 OpenAI Chat Completions 格式。DeepSeek 用 https://api.deepseek.com/v1/chat/completions；本地 Ollama 用 http://主机:11434/v1/chat/completions。\n\nAI 只产生信号，下单仍要过风控和频率限制，置信度低于 0.6 自动降级为观望。")
        }
    }

    private var tradingSection: some View {
        Section {
            Picker("交易对", selection: $instId) {
                ForEach(Market.all, id: \.self) { Text($0).tag($0) }
            }
            Picker("K 线周期", selection: $bar) {
                ForEach(Market.bars, id: \.0) { Text($0.1).tag($0.0) }
            }
            HStack {
                Text("每单金额")
                Spacer()
                TextField("10", value: $tradeSize, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                Text("USDT").font(.caption).foregroundStyle(.secondary)
            }
            Stepper("杠杆 \(leverage)x", value: $leverage, in: 1...20)
            Stepper("轮询间隔 \(pollSeconds) 秒", value: $pollSeconds, in: 5...300, step: 5)
        } header: {
            Text("交易参数")
        } footer: {
            Text("带 -SWAP 的是永续合约（可用杠杆、可做空）；不带的走现货（只能做多）。")
        }
    }

    private var riskSection: some View {
        Section {
            HStack {
                Text("止损")
                Spacer()
                TextField("2", value: $stopLoss, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                Text("%").foregroundStyle(.secondary)
            }
            HStack {
                Text("止盈")
                Spacer()
                TextField("4", value: $takeProfit, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                Text("%").foregroundStyle(.secondary)
            }
            HStack {
                Text("最大持仓")
                Spacer()
                TextField("100", value: $maxPosition, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                Text("USDT").font(.caption).foregroundStyle(.secondary)
            }
            Stepper("每小时最多 \(maxTrades) 笔", value: $maxTrades, in: 1...60)
        } header: {
            Text("风险控制")
        } footer: {
            Text("止盈止损每轮检查，优先级高于策略信号；最大持仓和频率限制是防止程序失控的最后一道闸。")
        }
    }

    private var modeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { demoTrading },
                set: { v in
                    if v { demoTrading = true }
                    else { pendingDemo = false; showLiveConfirm = true }
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模拟盘模式")
                    Text(demoTrading ? "使用 OKX 模拟环境，不涉及真实资金" : "⚠️ 实盘，会真实下单")
                        .font(.caption2)
                        .foregroundStyle(demoTrading ? .secondary : .red)
                }
            }
        } header: {
            Text("运行模式")
        } footer: {
            Text("模拟盘需先在 OKX 网页版开通「模拟交易」，同一套 API Key 通用。强烈建议先跑够 24 小时再切实盘。")
        }
    }

    // MARK: - 数据同步

    private func loadFromRemote() {
        guard let c = store.remoteConfig else { return }
        strategy = StrategyKind(rawValue: c.activeStrategy) ?? .maCross
        instId = c.instId
        bar = c.bar
        tradeSize = c.tradeSizeUSDT
        leverage = c.leverage
        pollSeconds = c.pollSeconds
        stopLoss = c.stopLossPct
        takeProfit = c.takeProfitPct
        maxPosition = c.maxPositionUSDT
        maxTrades = c.maxTradesPerHour
        demoTrading = c.demoTrading
        aiEnabled = c.aiEnabled
        aiBaseURL = c.aiBaseURL ?? ""
        aiModel = c.aiModel ?? ""
        aiKey = ""
        loaded = true
    }

    private func save() async {
        var u = ConfigUpdate()
        u.activeStrategy = strategy.rawValue
        u.instId = instId
        u.bar = bar
        u.tradeSizeUSDT = tradeSize
        u.leverage = leverage
        u.pollSeconds = pollSeconds
        u.stopLossPct = stopLoss
        u.takeProfitPct = takeProfit
        u.maxPositionUSDT = maxPosition
        u.maxTradesPerHour = maxTrades
        u.demoTrading = demoTrading
        u.aiEnabled = aiEnabled
        u.aiBaseURL = aiBaseURL
        u.aiModel = aiModel
        if !aiKey.isEmpty { u.aiKey = aiKey }   // 空表示不修改
        await store.updateConfig(u)
        aiKey = ""
        loadFromRemote()
    }
}
