import SwiftUI

/// 更多：模拟盘、台账、风控、日志、会员、设置
struct MoreView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @State private var showLiveConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.055, blue: 0.09).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("更多")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("台账 · 风控 · 会员 · 设置")
                                .font(.footnote).foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.top, 6)

                        // 全局控制
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("全局控制").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                HStack(spacing: 10) {
                                    Button {
                                        Task { await store.emergencyStop(!(store.dashboard?.emergencyStop ?? false)) }
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: "stop.circle.fill").font(.system(size: 22))
                                            Text((store.dashboard?.emergencyStop ?? false) ? "解除停止" : "紧急停止")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.red)
                                    }
                                    Button {
                                        if store.dashboard?.liveTradingEnabled == true {
                                            Task { await store.toggleLiveTrading(false) }
                                        } else {
                                            showLiveConfirm = true
                                        }
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: "bolt.fill").font(.system(size: 22))
                                            Text((store.dashboard?.liveTradingEnabled ?? false) ? "关闭实盘" : "开启实盘")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.orange)
                                    }
                                }
                                Text("紧急停止会禁止所有非模拟盘新订单；开启实盘需要二次确认。")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        // 功能导航
                        VStack(spacing: 10) {
                            NavCard(icon: "shield.lefthalf.filled", title: "风控参数", desc: "仓位 / 止损 / 杠杆 / 交易次数限制", color: Color(red: 0.4, green: 0.8, blue: 0.8)) {
                                RiskView()
                            }
                            NavCard(icon: "clock.arrow.circlepath", title: "收益统计", desc: "已实现盈亏曲线与资产快照", color: Color(red: 0.25, green: 0.85, blue: 0.5)) {
                                ProfitView()
                            }
                            NavCard(icon: "list.clipboard.fill", title: "交易历史", desc: "成交明细与统计", color: Color(red: 0.55, green: 0.75, blue: 1.0)) {
                                TradeHistoryView()
                            }
                            NavCard(icon: "doc.text.magnifyingglass", title: "交易日志", desc: "引擎运行记录", color: Color(red: 0.75, green: 0.65, blue: 1.0)) {
                                TradingLogView()
                            }
                            NavCard(icon: "doc.plaintext", title: "系统日志", desc: "服务端系统事件", color: .gray) {
                                SystemLogView()
                            }
                            NavCard(icon: "crown.fill", title: "会员中心", desc: "套餐权益 · 在线购买", color: Color(red: 1.0, green: 0.78, blue: 0.25)) {
                                MembershipView()
                            }
                            // 管理端（仅管理员可见）
                            if config.role == "admin" {
                                NavCard(icon: "person.badge.key.fill", title: "管理端", desc: "用户 · 订单 · 套餐 · 支付 · 站点设置", color: Color(red: 0.9, green: 0.4, blue: 0.5)) {
                                    AdminHomeView()
                                }
                            }
                            NavCard(icon: "gearshape.fill", title: "设置", desc: "服务器地址 · 账号 · 关于", color: .gray) {
                                SettingsView()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshDashboard() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.refreshDashboard() }
            .alert("开启实盘交易？", isPresented: $showLiveConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认开启", role: .destructive) {
                    Task { await store.toggleLiveTrading(true) }
                }
            } message: {
                Text("实盘交易将使用真实资金下单，请确认已充分测试策略并理解风险。")
            }
        }
    }
}

/// 风控参数
struct RiskView: View {
    @EnvironmentObject var store: BackendStore
    @State private var singlePosition = ""
    @State private var maxTotal = ""
    @State private var singleLoss = ""
    @State private var dailyLoss = ""
    @State private var dailyLimit = ""
    @State private var consecLimit = ""
    @State private var maxLeverage = ""
    @State private var maxPositions = ""

    var body: some View {
        PageScaffold(title: "风控参数", subtitle: "服务端强制执行，保存后立即生效") {
            if let r = store.riskConfig {
                Card(padding: 13) {
                    HStack {
                        InfoRow(label: "当前持仓数", value: "\(r.openPositions ?? 0)")
                        InfoRow(label: "今日交易", value: "\(r.todayTrades ?? 0)")
                        InfoRow(label: "紧急停止", value: r.emergencyStop == 1 ? "已开启" : "关闭",
                                valueColor: r.emergencyStop == 1 ? .red : .green)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("参数设置").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    FieldRow(icon: "1.circle", placeholder: "单笔仓位上限 %（0.1-100）", text: $singlePosition).keyboardType(.decimalPad)
                    FieldRow(icon: "2.circle", placeholder: "总仓位上限 %（0.1-100）", text: $maxTotal).keyboardType(.decimalPad)
                    FieldRow(icon: "3.circle", placeholder: "单笔止损 %（0.1-50）", text: $singleLoss).keyboardType(.decimalPad)
                    FieldRow(icon: "4.circle", placeholder: "每日止损 %（0.1-100）", text: $dailyLoss).keyboardType(.decimalPad)
                    FieldRow(icon: "5.circle", placeholder: "每日交易次数（1-1000）", text: $dailyLimit).keyboardType(.numberPad)
                    FieldRow(icon: "6.circle", placeholder: "连续亏损限制（1-100）", text: $consecLimit).keyboardType(.numberPad)
                    FieldRow(icon: "7.circle", placeholder: "杠杆上限（1-125）", text: $maxLeverage).keyboardType(.numberPad)
                    FieldRow(icon: "8.circle", placeholder: "最大持仓数（1-100）", text: $maxPositions).keyboardType(.numberPad)

                    PrimaryButton(title: "保存风控参数", icon: "checkmark.circle.fill") {
                        Task {
                            await store.saveRisk([
                                "single_position_percent": singlePosition,
                                "max_total_position_percent": maxTotal,
                                "single_loss_percent": singleLoss,
                                "daily_loss_percent": dailyLoss,
                                "daily_trade_limit": dailyLimit,
                                "consecutive_loss_limit": consecLimit,
                                "max_leverage": maxLeverage,
                                "max_positions": maxPositions,
                            ])
                        }
                    }
                }
            }
        }
        .navigationTitle("风控参数")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadRiskConfig()
            fill()
        }
    }

    private func fill() {
        guard let r = store.riskConfig else { return }
        singlePosition = r.singlePositionPercent.value
        maxTotal = r.maxTotalPositionPercent.value
        singleLoss = r.singleLossPercent.value
        dailyLoss = r.dailyLossPercent.value
        dailyLimit = r.dailyTradeLimit.value
        consecLimit = r.consecutiveLossLimit.value
        maxLeverage = r.maxLeverage.value
        maxPositions = r.maxPositions.value
    }
}

/// 收益统计
struct ProfitView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "收益统计", subtitle: "已实现盈亏与资产快照") {
            if let p = store.profit {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("近 \(p.days) 天累计盈亏").font(.footnote).foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "%+.4f", p.totalPnl))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(p.totalPnl >= 0 ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.36, blue: 0.36))
                    }
                }

                // 每日盈亏列表
                VStack(alignment: .leading, spacing: 8) {
                    Text("每日盈亏").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    if p.curve.isEmpty {
                        EmptyHint(icon: "chart.bar", text: "暂无盈亏数据")
                    } else {
                        ForEach(p.curve.reversed(), id: \.time) { pt in
                            Card(padding: 11) {
                                HStack {
                                    Text(pt.time).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                    Text(String(format: "%+.4f", pt.daily ?? 0))
                                        .font(.caption.monospaced())
                                        .foregroundStyle((pt.daily ?? 0) >= 0 ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.36, blue: 0.36))
                                    Text("累计 \(String(format: "%.2f", pt.value))")
                                        .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.35))
                                }
                            }
                        }
                    }
                }

                // 资产快照
                if let assets = p.assets?.okx {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("资产快照").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        ForEach(Array(assets.keys.sorted()), id: \.self) { key in
                            if let a = assets[key] {
                                Card(padding: 12) {
                                    HStack {
                                        Text(key == "spot" ? "现货" : "永续")
                                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        Spacer()
                                        if a.configured {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("总资产 \(Fmt.money(a.totalAssets))").font(.caption.monospaced()).foregroundStyle(.white)
                                                Text("可用 \(Fmt.money(a.availableBalance))").font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.4))
                                            }
                                        } else {
                                            Text("未配置").font(.caption).foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingHint()
            }
        }
        .navigationTitle("收益统计")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProfit() }
    }
}

/// 交易历史
struct TradeHistoryView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "交易历史", subtitle: "OKX 成交明细") {
            if let stats = store.tradeStats {
                HStack(spacing: 10) {
                    StatTile(title: "总成交", value: "\(stats.total)")
                    StatTile(title: "买入", value: "\(stats.buyCount)", color: Color(red: 0.25, green: 0.85, blue: 0.5))
                    StatTile(title: "卖出", value: "\(stats.sellCount)", color: Color(red: 1.0, green: 0.36, blue: 0.36))
                }
                HStack(spacing: 10) {
                    StatTile(title: "成交额", value: Fmt.money(String(stats.volume)))
                    StatTile(title: "手续费", value: String(format: "%.6f", stats.fee))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("成交明细").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                if store.trades.isEmpty {
                    EmptyHint(icon: "list.clipboard", text: "暂无成交记录")
                } else {
                    ForEach(store.trades) { t in
                        Card(padding: 11) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(t.symbol).font(.subheadline.monospaced()).foregroundStyle(.white)
                                        StatusBadge(text: t.side, color: t.side == "BUY" ? .green : .red)
                                    }
                                    Text(Fmt.time(t.tradeTime)).font(.caption2).foregroundStyle(.white.opacity(0.35))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(Fmt.price(t.price.value)) × \(t.quantity.value)")
                                        .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.8))
                                    Text("手续费 \(t.fee?.value ?? "0")")
                                        .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.35))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("交易历史")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadTradeStats()
            await store.loadTrades()
        }
    }
}

/// 交易日志
struct TradingLogView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "交易日志", subtitle: "引擎与订单运行记录") {
            if store.tradingLogs.isEmpty {
                EmptyHint(icon: "doc.text", text: "暂无交易日志")
            } else {
                ForEach(store.tradingLogs) { log in
                    Card(padding: 11) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let s = log.symbol { Text(s).font(.caption.monospaced()).foregroundStyle(.white) }
                                if let sig = log.signal {
                                    StatusBadge(text: sig, color: sig == "BUY" ? .green : (sig == "SELL" ? .red : .gray))
                                }
                                if let src = log.source {
                                    StatusBadge(text: src, color: .blue)
                                }
                                Spacer()
                                if let pnl = log.pnl?.value, !pnl.isEmpty, pnl != "0" {
                                    Text(Fmt.pnl(pnl)).font(.caption.monospaced()).foregroundStyle(Fmt.pnlColor(pnl))
                                }
                            }
                            HStack {
                                Text(log.result ?? "--").font(.caption2).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(Fmt.time(log.createdAt)).font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("交易日志")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadTradingLogs() }
    }
}

/// 系统日志
struct SystemLogView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "系统日志", subtitle: "服务端系统事件") {
            if store.systemLogs.isEmpty {
                EmptyHint(icon: "doc.plaintext", text: "暂无系统日志")
            } else {
                ForEach(store.systemLogs) { log in
                    Card(padding: 11) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                StatusBadge(text: log.level, color: log.level == "error" ? .red : (log.level == "warning" ? .orange : .blue))
                                StatusBadge(text: log.channel, color: .gray)
                                Spacer()
                                Text(Fmt.time(log.createdAt)).font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                            Text(log.message)
                                .font(.caption).foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("系统日志")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadSystemLogs() }
    }
}
