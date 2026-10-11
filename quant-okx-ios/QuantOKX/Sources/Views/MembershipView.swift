import SwiftUI

// MARK: - 会员 DTO（与后端契约逐字对齐）

struct MembershipPlanDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let pricePerMonth: Double
    let badge: String?
    let minPollSeconds: Int
    let aiEnabled: Bool
    let features: [String]
    let highlight: Bool

    var priceText: String { pricePerMonth == 0 ? "免费" : "¥\(fmtPrice(pricePerMonth))" }

    private func fmtPrice(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }
}

struct MembershipStatusDTO: Decodable {
    let level: String
    let planName: String
    let expiresAt: String?
    let active: Bool
    let daysLeft: Int?
    let benefits: Benefits

    struct Benefits: Decodable {
        let minPollSeconds: Int
        let aiEnabled: Bool
    }
}

struct MembershipOrderDTO: Decodable, Identifiable {
    var id: String { orderId }
    let orderId: String
    let planId: String
    let planName: String
    let months: Int
    let total: Double
    let createdAt: String
    let status: String
}

struct SubscribeResultDTO: Decodable {
    let orderId: String
    let level: String
    let planName: String
    let expiresAt: String?
    let total: Double
    let payUrl: String?
    let demo: Bool
}

struct AuthDataDTO: Decodable {
    let token: String
    let userId: String
    let username: String
    let level: String
    let planName: String
    let active: Bool
    let daysLeft: Int
}

// MARK: - API

extension BackendClient {
    func membershipPlans() async throws -> [MembershipPlanDTO] {
        try await send("GET", "/api/membership/plans", as: [MembershipPlanDTO].self)
    }

    func membershipStatus() async throws -> MembershipStatusDTO {
        try await send("GET", "/api/membership/status", as: MembershipStatusDTO.self)
    }

    func subscribe(planId: String, months: Int) async throws -> SubscribeResultDTO {
        struct Body: Encodable { let planId: String; let months: Int }
        return try await send("POST", "/api/membership/subscribe",
                              body: Body(planId: planId, months: months),
                              as: SubscribeResultDTO.self)
    }

    func membershipOrders() async throws -> [MembershipOrderDTO] {
        try await send("GET", "/api/membership/orders", as: [MembershipOrderDTO].self)
    }

    // MARK: - 认证

    func register(username: String, password: String) async throws -> AuthDataDTO {
        struct Body: Encodable { let username: String; let password: String }
        return try await send("POST", "/api/auth/register",
                              body: Body(username: username, password: password),
                              as: AuthDataDTO.self, auth: false)
    }

    func login(username: String, password: String) async throws -> AuthDataDTO {
        struct Body: Encodable { let username: String; let password: String }
        return try await send("POST", "/api/auth/login",
                              body: Body(username: username, password: password),
                              as: AuthDataDTO.self, auth: false)
    }
}

// MARK: - 会员中心

struct MembershipView: View {
    @EnvironmentObject private var store: BackendStore
    @State private var months = 1
    @State private var loadedOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if store.membership == nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("加载会员信息…")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            statusCard
                            monthsPicker
                            plansSection
                            ordersSection
                        }
                        .padding(12)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("会员中心")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.drawerOpen = true } label: { Image(systemName: "line.3.horizontal") }
                }
            }
            .onAppear {
                Task { await store.loadMembership() }
            }
            .refreshable { await store.loadMembership() }
        }
    }

    // MARK: 当前状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.membership?.planName ?? "免费版")
                        .font(.headline)
                    if let m = store.membership {
                        if m.active, let e = m.expiresAt {
                            Text("有效期至 \(String(e.prefix(10))) · 剩 \(m.daysLeft ?? 0) 天")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        } else {
                            Text("未开通付费会员")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                Spacer()
                if store.membership?.active == true {
                    Text("生效中")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.green)
                }
            }

            Divider()

            HStack {
                benefitTile(icon: "timer",
                            title: "轮询下限",
                            value: "\(store.minPoll) 秒")
                Divider().frame(height: 30)
                benefitTile(icon: "brain.head.profile",
                            title: "AI 决策",
                            value: store.aiAllowed ? "已解锁" : "未开通",
                            tint: store.aiAllowed ? Color.green : Color.secondary)
                Divider().frame(height: 30)
                benefitTile(icon: "checkmark.seal",
                            title: "等级",
                            value: store.membership?.level.uppercased() ?? "FREE")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.orange.opacity(0.14), Color.indigo.opacity(0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.orange.opacity(0.25)))
    }

    private func benefitTile(icon: String, title: String, value: String, tint: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.footnote).foregroundStyle(Color.secondary)
            Text(value).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(title).font(.system(size: 10)).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 时长

    private var monthsPicker: some View {
        Picker("订阅时长", selection: $months) {
            Text("1 个月").tag(1)
            Text("3 个月").tag(3)
            Text("12 个月（8 折）").tag(12)
        }
        .pickerStyle(.segmented)
    }

    // MARK: 套餐

    private var plansSection: some View {
        VStack(spacing: 10) {
            ForEach(store.plans) { p in
                planCard(p)
            }
        }
    }

    private func planCard(_ p: MembershipPlanDTO) -> some View {
        let isCurrent = store.membership?.level == p.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.name).font(.subheadline.weight(.bold))
                if let b = p.badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(p.highlight ? Color.orange : Color.indigo.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(p.highlight ? Color.white : Color.indigo)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(p.priceText)
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                    Text("/月").font(.system(size: 9)).foregroundStyle(Color.secondary)
                }
            }

            ForEach(p.features, id: \.self) { f in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.green)
                    Text(f).font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }

            Button {
                Task { await store.subscribe(planId: p.id, months: months) }
            } label: {
                Text(isCurrent ? "当前套餐" : (p.id == "free" ? "基础可用" : "立即开通"))
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(p.highlight ? Color.orange : Color.indigo)
            .disabled(isCurrent || p.id == "free" || store.busy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(p.highlight ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: 订单

    @ViewBuilder
    private var ordersSection: some View {
        if !store.memOrders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("订单记录").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondary)
                ForEach(store.memOrders.prefix(10)) { o in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.planName).font(.caption.weight(.semibold))
                            Text(String(o.createdAt.prefix(16)).replacingOccurrences(of: "T", with: " "))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("¥\(String(format: "%.2f", o.total))")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text("\(o.months) 个月")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
