import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: BackendStore
    @State private var showCloseConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.connected {
                        OfflineBanner(message: store.lastError ?? "正在连接…")
                    } else if store.demoTrading {
                        DemoBadge()
                    } else {
                        LiveWarning()
                    }

                    priceCard
                    metricsRow
                    signalCard

                    if !store.positions.isEmpty || store.connected {
                        positionCard
                    }

                    controlPanel

                    if let e = store.engineError {
                        GlassCard {
                            Label(e, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OKX 量化")
            .refreshable { await store.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.connected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(store.connected ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .confirmationDialog("确认平掉全部持仓？", isPresented: $showCloseConfirm, titleVisibility: .visible) {
                Button("全部平仓", role: .destructive) {
                    Task { await store.closeAll() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 行情

    private var priceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(config.instId).font(.headline)
                    Text(config.bar)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    if let t = store.ticker {
                        Text(String(format: "%+.2f%%", t.changePct))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(t.changePct >= 0 ? .green : .red)
                    }
                }

                if let t = store.ticker {
                    Text(t.last)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(t.changePct >= 0 ? .green : .red)

                    HStack(spacing: 16) {
                        miniStat("24h高", t.high24h ?? "—")
                        miniStat("24h低", t.low24h ?? "—")
                        miniStat("成交量", t.vol24h ?? "—")
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("等待行情…").foregroundStyle(.secondary).font(.footnote)
                    }
                }
            }
        }
    }

    private func miniStat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(shortNum(v)).font(.caption.weight(.medium)).lineLimit(1)
        }
    }

    private func shortNum(_ s: String) -> String {
        guard let d = Double(s) else { return s }
        if d >= 10000 { return String(format: "%.0f", d) }
        if d >= 100 { return String(format: "%.1f", d) }
        return String(format: "%.4f", d)
    }

    // MARK: - 指标

    private var metricsRow: some View {
        HStack(spacing: 12) {
            GlassCard {
                StatTile(title: "可用 USDT",
                         value: String(format: "%.2f", store.balanceUSDT),
                         tint: .blue)
            }
            GlassCard {
                StatTile(title: "轮询次数",
                         value: "\(store.tickCount)",
                         sub: store.connected ? "运行 \(store.uptimeText)" : nil)
            }
        }
    }

    // MARK: - 信号

    private var signalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("最新信号", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(store.activeStrategyTitle)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }

                if let s = store.lastSignal {
                    HStack(spacing: 10) {
                        Text(s.actionLabel)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(signalColor(s.action))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(signalColor(s.action).opacity(0.15), in: Capsule())

                        if s.confidence > 0 {
                            Text("置信度 \(Int(s.confidence * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let at = s.at, let d = parseISO(at) {
                            Text(shortTime(d)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(s.reason)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.connected ? "尚未产生信号" : "连接后台后显示")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !store.lastAIReply.isEmpty {
                    Divider()
                    Label("AI 决策", systemImage: "brain.head.profile")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(store.lastAIReply)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 持仓

    private var positionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("当前持仓", systemImage: "briefcase.fill")
                    .font(.subheadline.weight(.semibold))

                if store.positions.isEmpty {
                    Text("空仓").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(store.positions) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.isLong ? "多头" : "空头")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(p.isLong ? .green : .red)
                                Text("\(p.instId) · \(p.lever)x · 均价 \(shortNum(p.avgPx))")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%+.2f", p.uplDouble))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(p.uplDouble >= 0 ? .green : .red)
                                Text(String(format: "%+.2f%%", p.uplRatioPct))
                                    .font(.caption2)
                                    .foregroundStyle(p.uplDouble >= 0 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    Button(role: .destructive) {
                        showCloseConfirm = true
                    } label: {
                        Label("一键平仓", systemImage: "xmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(store.busy)
                }
            }
        }
    }

    // MARK: - 控制

    private var controlPanel: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if store.running { await store.stopEngine() } else { await store.startEngine() }
                }
            } label: {
                HStack(spacing: 8) {
                    if store.busy {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: store.running ? "stop.fill" : "play.fill")
                    }
                    Text(store.running ? "停止自动交易" : "启动自动交易")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.running ? .red : .blue)
            .disabled(!store.connected || store.busy)

            if !store.connected {
                Text("后台未连接，请检查「设置」里的地址和令牌")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if store.running {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("后台运行中 · 刷新于 \(store.lastRefreshText)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 工具

    private func signalColor(_ a: String) -> Color {
        switch a {
        case "buy", "closeShort": return .green
        case "sell", "closeLong": return .red
        default: return .gray
        }
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
