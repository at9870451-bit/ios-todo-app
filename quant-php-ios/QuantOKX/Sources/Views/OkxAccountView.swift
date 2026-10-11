import SwiftUI

/// 账户资产：余额 + 持仓
struct OkxAccountView: View {
    @EnvironmentObject var store: BackendStore
    @State private var market: String = "spot"

    var body: some View {
        PageScaffold(title: "账户资产", subtitle: "OKX 账户余额与持仓") {
            Picker("市场", selection: $market) {
                Text("现货 Spot").tag("spot")
                Text("永续 Swap").tag("swap")
            }
            .pickerStyle(.segmented)
            .onChange(of: market) { _, m in
                Task { await store.loadAccount(market: m) }
            }

            if let summary = store.accountSummary {
                if summary.configured == false {
                    EmptyHint(icon: "key.slash", text: "该市场未配置 OKX 账号\n请先在「API 配置」中填写")
                } else {
                    HStack(spacing: 10) {
                        StatTile(title: "总资产 (USDT)", value: Fmt.money(summary.totalAssets), color: .white)
                        StatTile(title: "可用余额", value: Fmt.money(summary.availableBalance), color: Color.cyan)
                    }
                    StatTile(title: "未实现盈亏", value: Fmt.pnl(summary.unrealizedPnl),
                             color: Fmt.pnlColor(summary.unrealizedPnl))

                    // 余额明细
                    VStack(alignment: .leading, spacing: 8) {
                        Text("余额明细").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if let balances = summary.balances, !balances.isEmpty {
                            ForEach(balances.filter { ($0.total.doubleValue) > 0 }) { b in
                                Card(padding: 12) {
                                    HStack {
                                        Text(b.asset).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(Fmt.money(b.total.value)).font(.subheadline.monospaced()).foregroundStyle(.primary)
                                            Text("可用 \(Fmt.money(b.free.value))")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            EmptyHint(icon: "tray", text: "暂无余额数据")
                        }
                    }

                    // 持仓
                    if market == "swap" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("交易所持仓").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if let positions = summary.positions, !positions.isEmpty {
                                ForEach(positions) { p in
                                    positionCard(p)
                                }
                            } else {
                                EmptyHint(icon: "square.stack.3d.up.slash", text: "暂无持仓")
                            }
                        }
                    }
                }
            } else {
                LoadingHint()
            }
        }
        .navigationTitle("账户资产")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAccount(market: market) }
    }

    private func positionCard(_ p: ExchangePosition) -> some View {
        Card(padding: 12) {
            VStack(spacing: 8) {
                HStack {
                    Text(p.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    StatusBadge(text: p.positionSide.uppercased(), color: .purple)
                    Spacer()
                    Text(Fmt.pnl(p.unrealizedProfit.value))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Fmt.pnlColor(p.unrealizedProfit.value))
                }
                HStack {
                    InfoRow(label: "数量", value: p.positionAmt.value, mono: true)
                    Divider().frame(height: 14).overlay(Color(uiColor: .separator))
                    InfoRow(label: "开仓价", value: Fmt.price(p.entryPrice.value), mono: true)
                    Divider().frame(height: 14).overlay(Color(uiColor: .separator))
                    InfoRow(label: "杠杆", value: "\(p.leverage.value)x", mono: true)
                }
            }
        }
    }
}
