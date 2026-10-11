import SwiftUI

/// 订单管理：下单表单 + 订单列表
struct OkxOrdersView: View {
    @EnvironmentObject var store: BackendStore

    @State private var showForm = false
    @State private var symbol = "BTC-USDT"
    @State private var market = "spot"
    @State private var mode = "paper"
    @State private var side = "BUY"
    @State private var orderType = "MARKET"
    @State private var quantity = "0.001"
    @State private var price = ""
    @State private var leverage = "1"
    @State private var stopLoss = ""
    @State private var takeProfit = ""
    @State private var placing = false

    var body: some View {
        PageScaffold(title: "订单管理", subtitle: "下单 · 撤单 · 订单列表") {
            PrimaryButton(title: "新建订单", icon: "plus.circle.fill") {
                withAnimation { showForm.toggle() }
            }

            if showForm {
                orderForm
            }

            // 订单列表
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("订单列表").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(store.orders.count) 条").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                if store.orders.isEmpty {
                    EmptyHint(icon: "tray", text: "暂无订单")
                } else {
                    ForEach(store.orders) { o in
                        Card(padding: 12) {
                            VStack(spacing: 8) {
                                HStack {
                                    Text(o.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    StatusBadge(text: o.side, color: o.side == "BUY" ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.36, blue: 0.36))
                                    StatusBadge(text: o.mode, color: .gray)
                                    Spacer()
                                    Text(orderStatusText(o.status))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(orderStatusColor(o.status))
                                }
                                HStack {
                                    InfoRow(label: "类型", value: o.orderType)
                                    InfoRow(label: "价格", value: Fmt.price(o.price.value), mono: true)
                                    InfoRow(label: "数量", value: o.quantity.value, mono: true)
                                }
                                HStack {
                                    Text(Fmt.time(o.createdAt)).font(.caption2).foregroundStyle(.white.opacity(0.35))
                                    Spacer()
                                    if ["NEW", "PENDING_SUBMIT", "PARTIALLY_FILLED"].contains(o.status) {
                                        Button {
                                            Task { await store.cancelOrder(o.id) }
                                        } label: {
                                            Text("撤单")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 5)
                                                .background(Color.orange.opacity(0.15), in: Capsule())
                                        }
                                    }
                                }
                                if let reason = o.rejectReason, !reason.isEmpty {
                                    Text(reason).font(.caption2).foregroundStyle(.red.opacity(0.8))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("订单管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadOrders() }
    }

    private var orderForm: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("下单").font(.subheadline.weight(.semibold)).foregroundStyle(.white)

                FieldRow(icon: "bitcoinsign.circle", placeholder: "交易对，如 BTC-USDT", text: $symbol)

                Picker("市场", selection: $market) {
                    Text("现货").tag("spot")
                    Text("永续").tag("swap")
                }
                .pickerStyle(.segmented)

                Picker("模式", selection: $mode) {
                    Text("本地模拟").tag("paper")
                    Text("OKX 模拟盘").tag("testnet")
                    Text("实盘").tag("live")
                }
                .pickerStyle(.segmented)

                Picker("方向", selection: $side) {
                    Text("买入 BUY").tag("BUY")
                    Text("卖出 SELL").tag("SELL")
                }
                .pickerStyle(.segmented)

                Picker("类型", selection: $orderType) {
                    Text("市价 MARKET").tag("MARKET")
                    Text("限价 LIMIT").tag("LIMIT")
                }
                .pickerStyle(.segmented)

                FieldRow(icon: "number", placeholder: "数量", text: $quantity)
                    .keyboardType(.decimalPad)

                if orderType == "LIMIT" {
                    FieldRow(icon: "dollarsign.circle", placeholder: "限价价格", text: $price)
                        .keyboardType(.decimalPad)
                }

                if market == "swap" {
                    FieldRow(icon: "gauge.with.dots.needle.67percent", placeholder: "杠杆 1-125", text: $leverage)
                        .keyboardType(.numberPad)
                }

                HStack(spacing: 10) {
                    FieldRow(icon: "shield.lefthalf.filled", placeholder: "止损价（可选）", text: $stopLoss)
                        .keyboardType(.decimalPad)
                }
                HStack(spacing: 10) {
                    FieldRow(icon: "flag.checkered", placeholder: "止盈价（可选）", text: $takeProfit)
                        .keyboardType(.decimalPad)
                }

                Text("实盘下单需：全局实盘开关开启 + 账户为 live 环境 + 风控未触发。市价单价格留空即可。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))

                PrimaryButton(title: placing ? "提交中…" : "提交订单", icon: "paperplane.fill",
                              color: side == "BUY" ? Color(red: 0.16, green: 0.55, blue: 0.35) : Color(red: 0.7, green: 0.25, blue: 0.25),
                              disabled: placing) {
                    Task { await submit() }
                }
            }
        }
    }

    private func submit() async {
        placing = true
        defer { placing = false }
        let ok = await store.placeOrder(
            symbol: symbol.uppercased(), marketType: market, mode: mode, side: side,
            orderType: orderType, quantity: quantity, price: price,
            leverage: Int(leverage), stopLoss: stopLoss, takeProfit: takeProfit
        )
        if ok { withAnimation { showForm = false } }
    }

    private func orderStatusText(_ s: String) -> String {
        switch s {
        case "FILLED": return "已成交"
        case "NEW": return "挂单中"
        case "PENDING_SUBMIT": return "提交中"
        case "PARTIALLY_FILLED": return "部分成交"
        case "CANCELED": return "已撤销"
        case "REJECTED": return "已拒绝"
        case "UNKNOWN": return "未知"
        default: return s
        }
    }

    private func orderStatusColor(_ s: String) -> Color {
        switch s {
        case "FILLED": return Color(red: 0.25, green: 0.85, blue: 0.5)
        case "NEW", "PENDING_SUBMIT", "PARTIALLY_FILLED": return .orange
        case "REJECTED", "UNKNOWN": return .red
        default: return .gray
        }
    }
}
