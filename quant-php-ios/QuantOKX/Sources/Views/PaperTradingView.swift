import SwiftUI

/// 模拟盘交易台：本地模拟 / OKX Demo Trading
struct PaperTradingView: View {
    @EnvironmentObject var store: BackendStore

    @State private var market = "swap"
    @State private var mode = "testnet"
    @State private var symbol = "BTC-USDT-SWAP"
    @State private var side = "BUY"
    @State private var orderType = "MARKET"
    @State private var quantity = "0.01"
    @State private var price = ""
    @State private var leverage = "5"
    @State private var placing = false

    var body: some View {
        PageScaffold(title: "模拟盘交易台", subtitle: "OKX Demo Trading · 练习下单") {
            // 账户状态
            if let st = store.paperStatus {
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(st.accountName?.isEmpty == false ? st.accountName! : "未配置账号")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            StatusBadge(text: st.configured ? "已配置" : "未配置",
                                        color: st.configured ? .green : .gray)
                            StatusBadge(text: st.localTradingEnabled ? "本地交易开" : "本地交易关",
                                        color: st.localTradingEnabled ? .green : .gray)
                        }
                        if st.configured {
                            HStack(spacing: 10) {
                                StatTile(title: "总资产", value: Fmt.money(st.totalAssets))
                                StatTile(title: "可用余额", value: Fmt.money(st.availableBalance))
                                StatTile(title: "未实现盈亏", value: Fmt.pnl(st.unrealizedPnl),
                                         color: Fmt.pnlColor(st.unrealizedPnl))
                            }
                        }
                        if let err = st.error, !err.isEmpty {
                            Text(err).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                // 持仓
                if let positions = st.positions, !positions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模拟持仓").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        ForEach(positions) { p in
                            Card(padding: 11) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.symbol).font(.subheadline.monospaced()).foregroundStyle(.white)
                                        Text("开仓 \(Fmt.price(p.entryPrice.value)) · \(p.leverage.value)x")
                                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(Fmt.pnl(p.unrealizedProfit.value))
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(Fmt.pnlColor(p.unrealizedProfit.value))
                                        Text("量 \(p.positionAmt.value)").font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingHint()
            }

            // 下单表单
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("模拟下单").font(.subheadline.weight(.semibold)).foregroundStyle(.white)

                    Picker("市场", selection: $market) {
                        Text("永续").tag("swap")
                        Text("现货").tag("spot")
                    }
                    .pickerStyle(.segmented)

                    Picker("模式", selection: $mode) {
                        Text("OKX 模拟盘").tag("testnet")
                        Text("本地模拟").tag("paper")
                    }
                    .pickerStyle(.segmented)

                    FieldRow(icon: "bitcoinsign.circle", placeholder: "交易对", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Picker("方向", selection: $side) {
                        Text("做多 / 买入").tag("BUY")
                        Text("做空 / 卖出").tag("SELL")
                    }
                    .pickerStyle(.segmented)

                    Picker("类型", selection: $orderType) {
                        Text("市价").tag("MARKET")
                        Text("限价").tag("LIMIT")
                    }
                    .pickerStyle(.segmented)

                    FieldRow(icon: "number", placeholder: "数量", text: $quantity).keyboardType(.decimalPad)

                    if orderType == "LIMIT" {
                        FieldRow(icon: "dollarsign.circle", placeholder: "限价", text: $price).keyboardType(.decimalPad)
                    }

                    if market == "swap" {
                        FieldRow(icon: "gauge.with.dots.needle.67percent", placeholder: "杠杆 1-125", text: $leverage)
                            .keyboardType(.numberPad)
                    }

                    PrimaryButton(title: placing ? "提交中…" : "模拟下单",
                                  icon: "paperplane.fill",
                                  color: side == "BUY" ? Color(red: 0.16, green: 0.55, blue: 0.35) : Color(red: 0.7, green: 0.25, blue: 0.25),
                                  disabled: placing) {
                        Task { await place() }
                    }

                    Text("「OKX 模拟盘」需要 Demo Trading 凭据；「本地模拟」仅记录本地状态。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .navigationTitle("模拟盘交易台")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPaperStatus(market: market) }
        .onChange(of: market) { _, m in
            Task { await store.loadPaperStatus(market: m) }
        }
    }

    private func place() async {
        placing = true
        defer { placing = false }
        do {
            var body: [String: Any] = [
                "symbol": symbol.uppercased(),
                "market_type": market,
                "mode": mode,
                "side": side,
                "order_type": orderType,
                "quantity": quantity,
            ]
            if orderType == "LIMIT", !price.isEmpty { body["price"] = price }
            if market == "swap" { body["leverage"] = Int(leverage) ?? 1 }
            _ = try await BackendClient.shared.post("/api/paper/place", body: body, as: EmptyData.self)
            store.toast = "模拟订单已提交"
            await store.loadPaperStatus(market: market)
        } catch {
            store.handle(error)
        }
    }
}
