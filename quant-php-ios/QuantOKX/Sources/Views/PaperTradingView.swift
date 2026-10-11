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
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            StatusBadge(text: st.configured ? "已配置" : "未配置",
                                        color: st.configured ? .green : .gray)
                        }
                        // 本地交易开关 + 重置
                        HStack(spacing: 10) {
                            Button {
                                Task { await store.setLocalTrading(!st.localTradingEnabled) }
                            } label: {
                                Text(st.localTradingEnabled ? "关闭本地交易" : "开启本地交易")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(st.localTradingEnabled ? .orange : Color.green)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background((st.localTradingEnabled ? Color.orange : Color.green).opacity(0.13),
                                                in: RoundedRectangle(cornerRadius: 9))
                            }
                            Button {
                                Task { await store.resetPaper(includePaper: true) }
                            } label: {
                                Text("重置本地记录")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Color.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                            }
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
                        Text("模拟持仓").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        ForEach(positions) { p in
                            Card(padding: 11) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.symbol).font(.subheadline.monospaced()).foregroundStyle(.primary)
                                        Text("开仓 \(Fmt.price(p.entryPrice.value)) · \(p.leverage.value)x")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(Fmt.pnl(p.unrealizedProfit.value))
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(Fmt.pnlColor(p.unrealizedProfit.value))
                                        Text("量 \(p.positionAmt.value)").font(.caption2.monospaced()).foregroundStyle(.secondary)
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
                    Text("模拟下单").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)

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
                                  color: side == "BUY" ? Color.green : Color.red,
                                  disabled: placing) {
                        Task { await place() }
                    }

                    Text("「OKX 模拟盘」需要 Demo Trading 凭据；「本地模拟」仅记录本地状态。")
                        .font(.caption2).foregroundStyle(.secondary)
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
