import SwiftUI

/// 持仓管理：本地模拟持仓 + 交易所持仓，一键平仓
struct OkxPositionsView: View {
    @EnvironmentObject var store: BackendStore
    @State private var source: String = "local"
    @State private var market: String = "swap"

    var body: some View {
        PageScaffold(title: "持仓管理", subtitle: "本地模拟与交易所持仓") {
            Picker("来源", selection: $source) {
                Text("本地持仓").tag("local")
                Text("交易所持仓").tag("exchange")
            }
            .pickerStyle(.segmented)
            .onChange(of: source) { _, _ in reload() }

            Picker("市场", selection: $market) {
                Text("永续").tag("swap")
                Text("现货").tag("spot")
            }
            .pickerStyle(.segmented)
            .onChange(of: market) { _, _ in reload() }

            if source == "local" {
                if store.positions.isEmpty {
                    EmptyHint(icon: "square.stack.3d.up.slash", text: "暂无本地持仓")
                } else {
                    ForEach(store.positions) { p in
                        Card(padding: 13) {
                            VStack(spacing: 9) {
                                HStack {
                                    Text(p.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    StatusBadge(text: p.positionSide.uppercased(), color: p.positionSide.uppercased() == "SHORT" ? .red : .green)
                                    Spacer()
                                    Text(Fmt.pnl(p.unrealizedPnl.value))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(Fmt.pnlColor(p.unrealizedPnl.value))
                                }
                                HStack {
                                    InfoRow(label: "数量", value: p.quantity.value, mono: true)
                                    InfoRow(label: "开仓价", value: Fmt.price(p.entryPrice.value), mono: true)
                                    InfoRow(label: "标记价", value: Fmt.price(p.markPrice.value), mono: true)
                                }
                                HStack {
                                    Text("\(p.leverage)x · \(p.marketType)")
                                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                                    Spacer()
                                    Button {
                                        Task { await store.closePosition(symbol: p.symbol, marketType: p.marketType) }
                                    } label: {
                                        Text("平仓")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.red)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.red.opacity(0.15), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                if store.exchangePositions.isEmpty {
                    EmptyHint(icon: "square.stack.3d.up.slash", text: "交易所暂无持仓\n（需已配置 OKX 账号）")
                } else {
                    ForEach(store.exchangePositions) { p in
                        Card(padding: 13) {
                            VStack(spacing: 9) {
                                HStack {
                                    Text(p.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    StatusBadge(text: p.positionSide.uppercased(), color: .purple)
                                    Spacer()
                                    Text(Fmt.pnl(p.unrealizedProfit.value))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(Fmt.pnlColor(p.unrealizedProfit.value))
                                }
                                HStack {
                                    InfoRow(label: "数量", value: p.positionAmt.value, mono: true)
                                    InfoRow(label: "开仓价", value: Fmt.price(p.entryPrice.value), mono: true)
                                    InfoRow(label: "杠杆", value: "\(p.leverage.value)x", mono: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("持仓管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
    }

    private func reload() {
        Task { await store.loadPositions(market: market, source: source) }
    }
}
