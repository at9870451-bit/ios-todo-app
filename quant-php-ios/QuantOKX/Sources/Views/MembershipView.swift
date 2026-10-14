import SwiftUI
import UIKit

/// 会员中心：当前状态 + 套餐购买（1/3/12 个月）+ 订单记录
struct MembershipView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    @State private var months: Int = 1
    @State private var purchasing: String = ""      // 正在购买的 level（防重复点击）
    @State private var confirmTarget: MembershipPlanRow?
    @State private var loaded = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    periodPicker
                    planList
                    buyButton
                    ordersCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("会员中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            await store.loadMemberPlans()
            await store.loadMemberStatus()
            await store.loadMemberOrders()
        }
        .alert("确认开通", isPresented: Binding(
            get: { confirmTarget != nil },
            set: { if !$0 { confirmTarget = nil } }
        )) {
            Button("取消", role: .cancel) { confirmTarget = nil }
            Button("确认开通") { if let t = confirmTarget { Task { await purchase(t) } } }
        } message: {
            if let t = confirmTarget {
                Text("将为账号「\(config.username)」开通 \(t.name) \(periodLabel(months))，金额 ¥\(priceText(t, months))")
            }
        }
    }

    // MARK: - 当前状态卡

    private var currentBadge: BadgeInfo? { store.memberStatus?.badge }

    private var statusCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(currentBadge?.level == "free" || currentBadge == nil
                              ? LinearGradient(colors: [Color(uiColor: .systemGray4), Color(uiColor: .systemGray3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.orange, Color(red: 1.0, green: 0.45, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(currentBadge?.name ?? "免费版")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        if currentBadge?.level != "free" && currentBadge != nil {
                            Text("生效中")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }
                    if let exp = currentBadge?.expireAt, !exp.isEmpty {
                        Text("到期时间：\(String(exp.prefix(10))) · 剩余 \(currentBadge?.daysLeft ?? 0) 天")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未开通会员，开通后享全部高级权益")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidCard(16)
    }

    // MARK: - 周期选择

    private var periodPicker: some View {
        HStack(spacing: 0) {
            periodButton(months: 1, title: "1 个月", sub: "")
            periodButton(months: 3, title: "3 个月", sub: "9 折")
            periodButton(months: 12, title: "12 个月", sub: "8 折")
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func periodButton(months m: Int, title: String, sub: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { months = m }
            Haptics.tap()
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub.isEmpty ? " " : sub)
                    .font(.caption2)
                    .foregroundStyle(months == m ? Color.white.opacity(0.85) : Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                months == m ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .foregroundStyle(months == m ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 套餐列表

    private var planList: some View {
        VStack(spacing: 12) {
            let plans = (store.memberPlans?.plans ?? []).filter { $0.level != "free" }
            ForEach(plans) { p in
                planCard(p)
            }
            if plans.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("加载套餐中…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .solidCard(14)
            }
        }
    }

    private func planCard(_ p: MembershipPlanRow) -> some View {
        let isCurrent = currentBadge?.level == p.level && (currentBadge?.expireAt ?? "").isEmpty == false
        let isSelected = selectedLevel == p.level || (selectedLevel.isEmpty && isCurrent)
        return Button {
            Haptics.tap()
            selectedLevel = p.level
        } label: {
            HStack(spacing: 13) {
                // 选中标记
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.accent : Color(uiColor: .systemGray4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Theme.accent).frame(width: 12, height: 12)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(p.name).font(.system(size: 16, weight: .bold, design: .rounded))
                        if isCurrent {
                            Text("当前")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.13), in: Capsule())
                        }
                    }
                    Text(featureLines(p))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("¥").font(.caption.weight(.bold))
                        Text(priceText(p, months))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Theme.accent)
                    Text(periodUnitLabel(months))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                isSelected ? AnyShapeStyle(Theme.accent.opacity(0.07)) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Color(uiColor: .systemGray5), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(paid)
    }

    // MARK: - 购买按钮

    private var buyButton: some View {
        Button {
            guard let lv = selectedLevelOrCurrent else { return }
            if let p = store.memberPlans?.plans.first(where: { $0.level == lv }) {
                confirmTarget = p
            }
        } label: {
            HStack {
                if !purchasing.isEmpty { ProgressView().tint(.white) }
                Text(buyTitle)
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.3), radius: 8, x: 0, y: 3)
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!purchasing.isEmpty)
    }

    private var selectedLevelOrCurrent: String? {
        if let s = selectedLevel.isEmpty ? nil : selectedLevel { return s }
        return store.memberPlans?.plans.first(where: { $0.level != "free" && $0.level != currentBadge?.level })?.level
    }

    private var buyTitle: String {
        if let lv = selectedLevelOrCurrent,
           let p = store.memberPlans?.plans.first(where: { $0.level == lv }) {
            return "立即开通 \(p.name) · ¥\(priceText(p, months))"
        }
        return "立即开通"
    }

    // MARK: - 订单记录

    private var ordersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("开通记录", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))

            if store.memberOrders.isEmpty {
                Text("暂无订单")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(store.memberOrders.prefix(5)) { o in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(o.levelName) · \(o.months) 个月")
                                .font(.subheadline.weight(.medium))
                            Text(String((o.createdAt ?? "").prefix(16)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("¥\(o.amount.value)")
                                .font(.subheadline.weight(.semibold))
                            Text(statusText(o.status))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusColor(o.status))
                        }
                    }
                    .padding(.vertical, 7)
                    if o.id != store.memberOrders.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidCard(14)
    }

    // MARK: - 购买动作

    private func purchase(_ plan: MembershipPlanRow) async {
        purchasing = plan.level
        defer { purchasing = "" }
        let payUrl = await store.subscribe(level: plan.level, months: months, channel: "alipay")
        Haptics.success()
        await store.loadMemberStatus()
        await store.loadMemberOrders()
        // 演示模式 payUrl 为空，已开通；有 payUrl 则跳转收银台
        if let s = payUrl, let url = URL(string: s), !s.isEmpty {
            await UIApplication.shared.open(url)
        }
    }

    // MARK: - 工具

    private func priceText(_ p: MembershipPlanRow, _ m: Int) -> String {
        switch m {
        case 3: return p.priceQuarter.value
        case 12: return p.priceYear.value
        default: return p.priceMonth.value
        }
    }

    private func periodLabel(_ m: Int) -> String { m == 1 ? "1 个月" : "\(m) 个月" }
    private func periodUnitLabel(_ m: Int) -> String { m == 1 ? "/ 月" : "/ \(m) 个月" }

    private func featureLines(_ p: MembershipPlanRow) -> String {
        let raw = p.features ?? ""
        let items = raw.split(separator: "\n").map(String.init)
        if items.isEmpty { return "更多高级权益" }
        return items.prefix(3).joined(separator: " · ")
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "paid": return "已支付"
        case "pending": return "待支付"
        case "canceled": return "已取消"
        default: return s
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "paid": return .green
        case "pending": return .orange
        default: return .secondary
        }
    }
}

/// 会员等级本地名称映射
func amoreLevelName(_ level: String) -> String {
    switch level {
    case "gold": return "黄金版"
    case "diamond": return "钻石版"
    case "ultimate": return "至尊版"
    default: return "免费版"
    }
}
