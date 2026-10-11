import SwiftUI

/// 会员中心：套餐、权益、订单、购买
struct MembershipView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    @State private var months: Int = 1
    @State private var channel: String = "alipay"
    @State private var paying = false

    var body: some View {
        PageScaffold(title: "会员中心", subtitle: "套餐权益与在线购买") {
            // 当前状态
            if let badge = store.memberPlans?.badge {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "crown.fill").foregroundStyle(Color.orange)
                            Text(badge.name).font(.headline).foregroundStyle(.primary)
                            Spacer()
                            if let days = badge.daysLeft {
                                StatusBadge(text: "剩 \(days) 天", color: days > 7 ? .green : .orange)
                            } else if badge.isAdmin {
                                StatusBadge(text: "管理员", color: .purple)
                            }
                        }
                        if let exp = badge.expireAt {
                            InfoRow(label: "到期时间", value: exp)
                        }
                        if let limits = store.memberPlans?.limits {
                            Divider().overlay(Color(uiColor: .systemGray6))
                            HStack(spacing: 10) {
                                StatTile(title: "策略上限", value: "\(limits.strategyLimit)")
                                StatTile(title: "AI 配置", value: "\(limits.aiConfigLimit)")
                                StatTile(title: "账号数", value: "\(limits.accountLimit)")
                                StatTile(title: "杠杆上限", value: "\(limits.maxLeverage)x")
                            }
                            HStack(spacing: 10) {
                                StatTile(title: "自动交易", value: limits.autoTrade ? "支持" : "不支持",
                                         color: limits.autoTrade ? .green : .gray)
                                StatTile(title: "实盘交易", value: limits.liveTrade ? "支持" : "不支持",
                                         color: limits.liveTrade ? .green : .gray)
                            }
                        }
                    }
                }
            }

            // 用量
            if let usage = store.memberPlans?.usage {
                HStack(spacing: 10) {
                    StatTile(title: "今日回测", value: "\(usage.backtestToday)")
                    StatTile(title: "今日 AI 分析", value: "\(usage.aiToday)")
                }
            }

            // 购买时长
            VStack(alignment: .leading, spacing: 8) {
                Text("购买时长").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Picker("时长", selection: $months) {
                    Text("1 个月").tag(1)
                    Text("3 个月").tag(3)
                    Text("12 个月").tag(12)
                }
                .pickerStyle(.segmented)

                Picker("支付方式", selection: $channel) {
                    Text("支付宝").tag("alipay")
                    Text("微信").tag("wxpay")
                    Text("QQ 钱包").tag("qqpay")
                }
                .pickerStyle(.segmented)
            }

            // 套餐卡
            VStack(alignment: .leading, spacing: 8) {
                Text("选择套餐").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if let plans = store.memberPlans?.plans {
                    ForEach(plans.filter { $0.level != "free" }) { plan in
                        planCard(plan)
                    }
                } else {
                    LoadingHint()
                }
            }

            // 订单
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("我的订单").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    Button {
                        Task { await store.loadMemberOrders() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.memberOrders.isEmpty {
                    EmptyHint(icon: "receipt", text: "暂无订单")
                } else {
                    ForEach(store.memberOrders) { o in
                        Card(padding: 11) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(o.levelName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        StatusBadge(text: statusText(o.status), color: statusColor(o.status))
                                    }
                                    Text("\(o.tradeNo)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                    Text(Fmt.time(o.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("¥\(o.amount.value)").font(.subheadline.monospaced()).foregroundStyle(.primary)
                                    Text("\(o.months) 个月").font(.caption2).foregroundStyle(.secondary)
                                    if o.status == "pending", let url = o.payUrl, !url.isEmpty {
                                        Button {
                                            openPay(url)
                                        } label: {
                                            Text("去支付").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("会员中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadMemberPlans()
            await store.loadMemberOrders()
        }
    }

    private func planCard(_ plan: MembershipPlanRow) -> some View {
        let price: String = {
            switch months {
            case 3: return plan.priceQuarter.value
            case 12: return plan.priceYear.value
            default: return plan.priceMonth.value
            }
        }()
        let isCurrent = plan.level == (store.memberPlans?.badge?.level ?? config.membershipLevel)
        return Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(plan.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if isCurrent { StatusBadge(text: "当前", color: .green) }
                    Spacer()
                    Text("¥\(price)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange)
                }
                if let features = plan.features, !features.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(features.components(separatedBy: "\n").prefix(5), id: \.self) { f in
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10)).foregroundStyle(.green.opacity(0.8)).padding(.top, 2)
                                Text(f).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                PrimaryButton(title: paying ? "创建订单中…" : "立即购买", icon: "cart.fill", disabled: paying) {
                    Task { await buy(plan) }
                }
            }
        }
    }

    private func buy(_ plan: MembershipPlanRow) async {
        paying = true
        defer { paying = false }
        if let url = await store.subscribe(level: plan.level, months: months, channel: channel) {
            openPay(url)
        }
    }

    private func openPay(_ url: String) {
        guard let u = URL(string: url) else { return }
        UIApplication.shared.open(u)
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "paid": return "已支付"
        case "pending": return "待支付"
        case "expired": return "已过期"
        case "failed": return "失败"
        default: return s
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "paid": return .green
        case "pending": return .orange
        case "failed": return .red
        default: return .gray
        }
    }
}
