import SwiftUI

/// 控制台：资产概览、盈亏、订单持仓速览、紧急开关
struct DashboardView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        assetGrid
                        pnlCard
                        quickStats
                        ordersPreview
                        positionsPreview
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshDashboard() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.blue)
                        Text("控制台").font(.headline).foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await store.refreshServer() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        Button {
                            Task { await store.logout() }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .task { await store.refreshDashboard() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("你好，\(config.nickname.isEmpty ? config.username : config.nickname)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                StatusBadge(text: config.membershipLevel.uppercased(), color: memberColor)
                if let d = store.dashboard {
                    StatusBadge(text: d.liveTradingEnabled ? "实盘开启" : "实盘关闭",
                                color: d.liveTradingEnabled ? .orange : .gray)
                    if d.emergencyStop {
                        StatusBadge(text: "紧急停止中", color: .red)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var memberColor: Color {
        switch config.membershipLevel {
        case "ultimate": return Color.orange
        case "diamond": return Color.cyan
        case "gold": return Color.orange
        default: return .gray
        }
    }

    private var assetGrid: some View {
        HStack(spacing: 10) {
            StatTile(title: "现货资产", value: Fmt.money(store.dashboard?.okx["spot"]?.totalAssets),
                     sub: store.dashboard?.okx["spot"]?.configured == true ? nil : "未配置")
            StatTile(title: "合约资产", value: Fmt.money(store.dashboard?.okx["swap"]?.totalAssets),
                     sub: store.dashboard?.okx["swap"]?.configured == true ? nil : "未配置")
        }
    }

    private var pnlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("已实现盈亏").font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let today = store.dashboard?.pnl.today ?? 0
                    Text(String(format: "%+.2f", today))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(today >= 0 ? Color.green
                                                    : Color.red)
                    Text("USDT · 今日").font(.caption).foregroundStyle(.secondary)
                }
                Divider().overlay(Color(uiColor: .systemGray6))
                InfoRow(label: "近 30 天累计", value: String(format: "%+.4f", store.dashboard?.pnl.total30d ?? 0),
                        valueColor: (store.dashboard?.pnl.total30d ?? 0) >= 0
                            ? Color.green
                            : Color.red)
                InfoRow(label: "服务器时间", value: store.dashboard?.serverTime.replacingOccurrences(of: "T", with: " ").prefix(19).description ?? "--")
            }
        }
    }

    private var quickStats: some View {
        HStack(spacing: 10) {
            StatTile(title: "运行中策略", value: "\(store.dashboard?.strategyCount ?? 0)", color: Color.blue)
            StatTile(title: "AI 运行中", value: "\(store.dashboard?.aiRunning ?? 0)", color: Color.purple)
            StatTile(title: "持仓", value: "\(store.dashboard?.positions.count ?? 0)")
        }
    }

    private var ordersPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近订单").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text("\(store.dashboard?.orders.count ?? 0) 条").font(.caption).foregroundStyle(.secondary)
            }
            if let orders = store.dashboard?.orders, !orders.isEmpty {
                ForEach(orders.prefix(5)) { o in
                    Card(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(o.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    StatusBadge(text: o.side, color: o.side == "BUY" ? Color.green : Color.red)
                                    StatusBadge(text: o.mode, color: .gray)
                                }
                                Text("\(o.orderType) · \(Fmt.time(o.createdAt))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("×\(o.quantity.value)").font(.caption.monospaced()).foregroundStyle(.primary)
                                Text(orderStatusText(o.status))
                                    .font(.caption2)
                                    .foregroundStyle(orderStatusColor(o.status))
                            }
                        }
                    }
                }
            } else {
                EmptyHint(icon: "tray", text: "暂无订单")
            }
        }
    }

    private var positionsPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前持仓").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            if let positions = store.dashboard?.positions, !positions.isEmpty {
                ForEach(positions.prefix(5)) { p in
                    Card(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("\(p.positionSide) · \(p.leverage)x")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Fmt.pnl(p.unrealizedPnl.value))
                                    .font(.caption.monospaced()).foregroundStyle(Fmt.pnlColor(p.unrealizedPnl.value))
                                Text("开仓 \(Fmt.price(p.entryPrice.value))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                EmptyHint(icon: "square.stack.3d.up.slash", text: "暂无持仓")
            }
        }
    }

    private func orderStatusText(_ s: String) -> String {
        switch s {
        case "FILLED": return "已成交"
        case "NEW": return "挂单中"
        case "PENDING_SUBMIT": return "提交中"
        case "PARTIALLY_FILLED": return "部分成交"
        case "CANCELED": return "已撤销"
        case "REJECTED": return "已拒绝"
        case "UNKNOWN": return "状态未知"
        default: return s
        }
    }

    private func orderStatusColor(_ s: String) -> Color {
        switch s {
        case "FILLED": return Color.green
        case "NEW", "PENDING_SUBMIT", "PARTIALLY_FILLED": return .orange
        case "REJECTED", "UNKNOWN": return .red
        default: return .gray
        }
    }
}
