import SwiftUI

/// 管理端首页（仅管理员）：概览统计 + 各管理入口
struct AdminHomeView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "管理端", subtitle: "用户 · 订单 · 套餐 · 站点设置") {
            if let s = store.adminStats {
                HStack(spacing: 10) {
                    StatTile(title: "用户总数", value: "\(s.userTotal)", color: Color(red: 0.55, green: 0.85, blue: 1.0))
                    StatTile(title: "今日新增", value: "\(s.userToday)", color: Color(red: 0.25, green: 0.85, blue: 0.5))
                }
                HStack(spacing: 10) {
                    StatTile(title: "订单总数", value: "\(s.orderTotal)")
                    StatTile(title: "已支付", value: "\(s.orderPaid)", color: Color(red: 0.25, green: 0.85, blue: 0.5))
                    StatTile(title: "待支付", value: "\(s.orderPending)", color: .orange)
                }
                HStack(spacing: 10) {
                    StatTile(title: "总收入", value: "¥\(s.incomeTotal)", color: Color(red: 1.0, green: 0.78, blue: 0.25))
                    StatTile(title: "今日收入", value: "¥\(s.incomeToday)", color: Color(red: 1.0, green: 0.78, blue: 0.25))
                }
            } else {
                LoadingHint()
            }

            VStack(spacing: 10) {
                NavCard(icon: "person.2.fill", title: "用户管理", desc: "等级 / 时长 / 状态 / 密码", color: Color(red: 0.29, green: 0.56, blue: 1.0)) {
                    AdminUsersView()
                }
                NavCard(icon: "list.bullet.rectangle.portrait.fill", title: "订单管理", desc: "会员订单与手动补单", color: Color(red: 0.25, green: 0.85, blue: 0.5)) {
                    AdminOrdersView()
                }
                NavCard(icon: "crown.fill", title: "会员计划", desc: "价格与额度设置", color: Color(red: 1.0, green: 0.78, blue: 0.25)) {
                    AdminPlansView()
                }
                NavCard(icon: "creditcard.fill", title: "支付设置", desc: "易支付接口配置", color: Color(red: 0.75, green: 0.65, blue: 1.0)) {
                    AdminPaymentView()
                }
                NavCard(icon: "cpu.fill", title: "平台免费 AI", desc: "共享模型（用户无需自带 Key）", color: Color(red: 0.4, green: 0.8, blue: 0.8)) {
                    AdminFreeAiView()
                }
                NavCard(icon: "gearshape.2.fill", title: "站点设置", desc: "注册开关 · 站点名 · 公告", color: .gray) {
                    AdminSiteSettingsView()
                }
            }
        }
        .navigationTitle("管理端")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAdminStats() }
    }
}

/// 用户管理：搜索 + 列表 + 编辑
struct AdminUsersView: View {
    @EnvironmentObject var store: BackendStore

    @State private var keyword = ""
    @State private var editing: AdminUserRow?
    @State private var actionType = "set_level"
    @State private var level = "gold"
    @State private var months = "1"
    @State private var newPassword = ""
    @State private var nickname = ""
    @State private var email = ""

    var body: some View {
        PageScaffold(title: "用户管理", subtitle: "共 \(store.adminUsers?.total ?? 0) 个用户") {
            HStack(spacing: 8) {
                TextField("", text: $keyword, prompt: Text("搜索用户名/昵称/邮箱").foregroundStyle(.white.opacity(0.3)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit { Task { await store.loadAdminUsers(keyword: keyword) } }
                Button {
                    Task { await store.loadAdminUsers(keyword: keyword) }
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 1.0))
                }
            }

            if let data = store.adminUsers {
                ForEach(data.items) { u in
                    Card(padding: 12) {
                        VStack(spacing: 8) {
                            HStack {
                                Text(u.username).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                StatusBadge(text: u.membershipName,
                                            color: levelColor(u.membershipLevel))
                                StatusBadge(text: u.role == "admin" ? "管理员" : "用户",
                                            color: u.role == "admin" ? .purple : .gray)
                                if u.status != 1 { StatusBadge(text: "已禁用", color: .red) }
                                Spacer()
                                Text("#\(u.id)").font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.3))
                            }
                            HStack {
                                Text(u.email ?? "无邮箱").font(.caption2).foregroundStyle(.white.opacity(0.4))
                                Spacer()
                                if let days = u.daysLeft { Text("剩 \(days) 天").font(.caption2).foregroundStyle(.orange) }
                                Text("注册 \(Fmt.time(u.createdAt))").font(.caption2).foregroundStyle(.white.opacity(0.3))
                            }
                            HStack(spacing: 8) {
                                Button { openEdit(u, "set_level") } label: { miniBtn("设等级", .blue) }
                                Button { openEdit(u, "toggle_status") } label: { miniBtn(u.status == 1 ? "禁用" : "启用", .orange) }
                                Button { openEdit(u, "reset_password") } label: { miniBtn("改密码", .gray) }
                                Button { openEdit(u, "update_profile") } label: { miniBtn("资料", .gray) }
                            }
                        }
                    }
                }
            } else {
                LoadingHint()
            }
        }
        .navigationTitle("用户管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAdminUsers() }
        .sheet(item: $editing) { u in
            editSheet(u)
        }
    }

    private func miniBtn(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.caption.weight(.semibold))
            .foregroundStyle(c)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(c.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
    }

    private func levelColor(_ l: String) -> Color {
        switch l {
        case "ultimate": return Color(red: 1.0, green: 0.78, blue: 0.25)
        case "diamond": return Color(red: 0.55, green: 0.85, blue: 1.0)
        case "gold": return Color(red: 1.0, green: 0.68, blue: 0.3)
        default: return .gray
        }
    }

    private func openEdit(_ u: AdminUserRow, _ action: String) {
        actionType = action
        level = u.membershipLevel == "free" ? "gold" : u.membershipLevel
        months = "1"
        newPassword = ""
        nickname = u.nickname
        email = u.email ?? ""
        editing = u
    }

    private func editSheet(_ u: AdminUserRow) -> some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("编辑用户 #\(u.id) · \(u.username)")
                        .font(.headline).foregroundStyle(.white)
                        .padding(.top, 8)

                    Picker("操作", selection: $actionType) {
                        Text("设等级").tag("set_level")
                        Text("赠时长").tag("extend")
                        Text("禁用/启用").tag("toggle_status")
                        Text("改角色").tag("set_role")
                        Text("改密码").tag("reset_password")
                        Text("资料").tag("update_profile")
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    if actionType == "set_level" || actionType == "extend" {
                        Picker("等级", selection: $level) {
                            Text("免费版").tag("free")
                            Text("黄金版").tag("gold")
                            Text("钻石版").tag("diamond")
                            Text("至尊版").tag("ultimate")
                        }
                        .pickerStyle(.segmented)
                        FieldRow(icon: "calendar", placeholder: "月数 1-36", text: $months)
                            .keyboardType(.numberPad)
                    }

                    if actionType == "reset_password" {
                        SecureFieldRow(icon: "lock.fill", placeholder: "新密码（至少 8 位）", text: $newPassword)
                    }

                    if actionType == "update_profile" {
                        FieldRow(icon: "person.fill", placeholder: "昵称", text: $nickname)
                        FieldRow(icon: "envelope.fill", placeholder: "邮箱", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    PrimaryButton(title: "执行操作", icon: "checkmark.circle.fill") {
                        Task { await applyAction(u) }
                    }
                    Button {
                        editing = nil
                    } label: {
                        Text("取消").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applyAction(_ u: AdminUserRow) async {
        var fields: [String: Any] = ["action": actionType]
        switch actionType {
        case "set_level", "extend":
            fields["level"] = level
            fields["months"] = Int(months) ?? 1
        case "reset_password":
            if newPassword.count < 8 {
                store.toast = "密码至少 8 位"
                return
            }
            fields["password"] = newPassword
        case "set_role":
            fields["role"] = u.role == "admin" ? "user" : "admin"
        case "update_profile":
            fields["nickname"] = nickname
            fields["email"] = email
        default: break
        }
        await store.adminUserUpdate(id: u.id, fields: fields)
        editing = nil
    }
}

/// 订单管理：筛选 + 列表 + 补单
struct AdminOrdersView: View {
    @EnvironmentObject var store: BackendStore

    @State private var status = ""
    @State private var keyword = ""

    var body: some View {
        PageScaffold(title: "订单管理", subtitle: "共 \(store.adminOrders?.total ?? 0) 笔会员订单") {
            Picker("状态", selection: $status) {
                Text("全部").tag("")
                Text("待支付").tag("pending")
                Text("已支付").tag("paid")
                Text("已过期").tag("expired")
            }
            .pickerStyle(.segmented)
            .onChange(of: status) { _, s in
                Task { await store.loadAdminOrders(status: s, keyword: keyword) }
            }

            HStack(spacing: 8) {
                TextField("", text: $keyword, prompt: Text("搜索订单号").foregroundStyle(.white.opacity(0.3)))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    Task { await store.loadAdminOrders(status: status, keyword: keyword) }
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 1.0))
                }
            }

            if let data = store.adminOrders {
                if data.items.isEmpty {
                    EmptyHint(icon: "receipt", text: "暂无订单")
                } else {
                    ForEach(data.items) { o in
                        Card(padding: 12) {
                            VStack(spacing: 7) {
                                HStack {
                                    Text(o.username).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    StatusBadge(text: o.levelName, color: .blue)
                                    StatusBadge(text: statusText(o.status), color: statusColor(o.status))
                                    Spacer()
                                    Text("¥\(o.amount.value)").font(.subheadline.monospaced()).foregroundStyle(.white)
                                }
                                HStack {
                                    Text(o.tradeNo).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.3))
                                    Spacer()
                                    Text("\(o.months) 个月 · \(Fmt.time(o.createdAt))")
                                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                                }
                                if o.status == "pending" {
                                    Button {
                                        Task { await store.adminMarkOrderPaid(o.id) }
                                    } label: {
                                        Text("手动补单（标记已支付）")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.green)
                                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                                            .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                if let paid = o.paidAt {
                                    Text("支付时间 \(Fmt.time(paid)) · 来源 \(o.paidSource ?? "-")")
                                        .font(.caption2).foregroundStyle(.white.opacity(0.35))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingHint()
            }
        }
        .navigationTitle("订单管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAdminOrders() }
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

/// 会员计划编辑（四档）
struct AdminPlansView: View {
    @EnvironmentObject var store: BackendStore

    @State private var editing: AdminPlanRow?
    @State private var form: [String: String] = [:]

    var body: some View {
        PageScaffold(title: "会员计划", subtitle: "价格与额度（保存后立即生效）") {
            if store.adminPlans.isEmpty {
                LoadingHint()
            } else {
                ForEach(store.adminPlans) { plan in
                    Card(padding: 13) {
                        VStack(spacing: 8) {
                            HStack {
                                Text(plan.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                StatusBadge(text: plan.enabled == 1 ? "上架" : "下架",
                                            color: plan.enabled == 1 ? .green : .gray)
                                Spacer()
                                Text("¥\(plan.priceMonth.value) / 月")
                                    .font(.subheadline.monospaced()).foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.25))
                            }
                            HStack {
                                Text("策略 \(plan.strategyLimit) · AI \(plan.aiConfigLimit) · 账号 \(plan.accountLimit) · 杠杆 \(plan.maxLeverage)x")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                Text("自动交易 \(plan.autoTrade == 1 ? "✓" : "✗") · 实盘 \(plan.liveTrade == 1 ? "✓" : "✗")")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
                                Spacer()
                                Button {
                                    openEdit(plan)
                                } label: {
                                    Text("编辑")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.13), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("会员计划")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAdminPlans() }
        .sheet(item: $editing) { plan in
            planSheet(plan)
        }
    }

    private func openEdit(_ plan: AdminPlanRow) {
        form = [
            "price_month": plan.priceMonth.value,
            "price_quarter": plan.priceQuarter.value,
            "price_year": plan.priceYear.value,
            "strategy_limit": "\(plan.strategyLimit)",
            "ai_config_limit": "\(plan.aiConfigLimit)",
            "account_limit": "\(plan.accountLimit)",
            "max_leverage": "\(plan.maxLeverage)",
            "backtest_daily": "\(plan.backtestDaily)",
            "ai_daily": "\(plan.aiDaily)",
            "multi_symbol_limit": "\(plan.multiSymbolLimit)",
            "auto_trade": "\(plan.autoTrade)",
            "live_trade": "\(plan.liveTrade)",
            "features": plan.features ?? "",
            "enabled": "\(plan.enabled)",
        ]
        editing = plan
    }

    private func planSheet(_ plan: AdminPlanRow) -> some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("编辑 \(plan.name)").font(.headline).foregroundStyle(.white).padding(.top, 8)

                    Group {
                        planField("月付价格 ¥", "price_month")
                        planField("季付价格 ¥", "price_quarter")
                        planField("年付价格 ¥", "price_year")
                        planField("策略上限", "strategy_limit")
                        planField("AI 配置上限", "ai_config_limit")
                        planField("账号上限", "account_limit")
                        planField("杠杆上限", "max_leverage")
                        planField("每日回测（-1 不限）", "backtest_daily")
                        planField("每日 AI（-1 不限）", "ai_daily")
                        planField("多币种上限", "multi_symbol_limit")
                    }

                    HStack(spacing: 10) {
                        Toggle("自动交易", isOn: Binding(
                            get: { form["auto_trade"] == "1" },
                            set: { form["auto_trade"] = $0 ? "1" : "0" }
                        ))
                        .tint(.green)
                        Toggle("实盘", isOn: Binding(
                            get: { form["live_trade"] == "1" },
                            set: { form["live_trade"] = $0 ? "1" : "0" }
                        ))
                        .tint(.orange)
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))

                    Toggle("上架", isOn: Binding(
                        get: { form["enabled"] == "1" },
                        set: { form["enabled"] = $0 ? "1" : "0" }
                    ))
                    .tint(.green)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("功能说明（每行一条）").font(.caption).foregroundStyle(.white.opacity(0.5))
                        TextEditor(text: Binding(
                            get: { form["features"] ?? "" },
                            set: { form["features"] = $0 }
                        ))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                    PrimaryButton(title: "保存计划", icon: "checkmark.circle.fill") {
                        Task { await save(plan) }
                    }
                    Button {
                        editing = nil
                    } label: {
                        Text("取消").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
    }

    private func planField(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.6))
                .frame(width: 150, alignment: .leading)
            TextField("", text: Binding(
                get: { form[key] ?? "" },
                set: { form[key] = $0 }
            ))
            .font(.footnote.monospaced())
            .foregroundStyle(.white)
            .multilineTextAlignment(.trailing)
            .keyboardType(key.contains("price") ? .decimalPad : (key == "features" ? .default : .numbersAndPunctuation))
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func save(_ plan: AdminPlanRow) async {
        var row: [String: Any] = [:]
        for (k, v) in form {
            if k == "features" { row[k] = v; continue }
            if k == "auto_trade" || k == "live_trade" || k == "enabled" {
                row[k] = Int(v) ?? 0
                continue
            }
            if k.contains("price") {
                row[k] = Double(v) ?? 0
            } else {
                row[k] = Int(v) ?? 0
            }
        }
        await store.adminSavePlans([plan.level: row])
        editing = nil
    }
}

/// 支付设置（易支付）
struct AdminPaymentView: View {
    @EnvironmentObject var store: BackendStore

    @State private var apiUrl = ""
    @State private var pid = ""
    @State private var key = ""
    @State private var enabled = false
    @State private var siteName = ""
    @State private var loaded = false

    var body: some View {
        PageScaffold(title: "支付设置", subtitle: "易支付（彩虹通用协议）") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("启用状态").font(.footnote).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Toggle("", isOn: $enabled).tint(.green).labelsHidden()
                    }
                    FieldRow(icon: "link", placeholder: "接口地址，如 https://pay.example.com/", text: $apiUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    FieldRow(icon: "number", placeholder: "商户 PID", text: $pid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureFieldRow(icon: "key.fill", placeholder: "商户 KEY（留空保持原值）", text: $key)
                    FieldRow(icon: "storefront", placeholder: "站点名称（收银台显示）", text: $siteName)

                    PrimaryButton(title: "保存支付设置", icon: "checkmark.circle.fill") {
                        var body: [String: Any] = [
                            "api_url": apiUrl, "pid": pid, "site_name": siteName,
                            "enabled": enabled ? 1 : 0,
                        ]
                        if !key.isEmpty { body["key"] = key }
                        Task { await store.adminSavePayment(body) }
                    }

                    if let payload = store.adminPayment {
                        Text(payload.configured ? "支付已配置：用户可在线购买会员" : "未配置：用户购买将返回演示模式")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .navigationTitle("支付设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadAdminPayment()
            fill()
        }
    }

    private func fill() {
        guard let c = store.adminPayment?.config, !loaded else { return }
        apiUrl = c.apiUrl ?? ""
        pid = c.pid ?? ""
        siteName = c.siteName ?? ""
        enabled = c.enabled == 1
        loaded = true
    }
}

/// 平台免费 AI
struct AdminFreeAiView: View {
    @EnvironmentObject var store: BackendStore

    @State private var name = "平台免费 AI"
    @State private var model = ""
    @State private var apiUrl = ""
    @State private var apiKey = ""
    @State private var strategyNote = ""
    @State private var enabled = false
    @State private var loaded = false

    var body: some View {
        PageScaffold(title: "平台免费 AI", subtitle: "共享模型：用户无需自带 API Key") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("启用").font(.footnote).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Toggle("", isOn: $enabled).tint(.green).labelsHidden()
                    }
                    FieldRow(icon: "tag.fill", placeholder: "名称", text: $name)
                    FieldRow(icon: "cpu", placeholder: "模型，如 gpt-4o-mini", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    FieldRow(icon: "link", placeholder: "API 地址（OpenAI 兼容）", text: $apiUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureFieldRow(icon: "key.fill", placeholder: "API Key（留空保持原值）", text: $apiKey)
                    FieldRow(icon: "text.bubble", placeholder: "策略提示词补充（可选）", text: $strategyNote)

                    PrimaryButton(title: "保存", icon: "checkmark.circle.fill") {
                        var body: [String: Any] = [
                            "name": name, "model": model, "api_url": apiUrl,
                            "enabled": enabled ? 1 : 0, "strategy_note": strategyNote,
                        ]
                        if !apiKey.isEmpty { body["api_key"] = apiKey }
                        Task { await store.adminSaveFreeAi(body) }
                    }

                    Text("会员在未添加个人 AI 配置时，将自动使用本平台共享 AI。密钥只加密存储，不回显。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .navigationTitle("平台免费 AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadAdminFreeAi()
            fill()
        }
    }

    private func fill() {
        guard let d = store.adminFreeAi, !loaded else { return }
        name = d.config.name
        model = d.config.model ?? ""
        apiUrl = d.config.apiUrl ?? ""
        strategyNote = d.config.strategyNote ?? ""
        enabled = d.config.enabled
        loaded = true
    }
}

/// 站点设置
struct AdminSiteSettingsView: View {
    @EnvironmentObject var store: BackendStore

    @State private var registerEnabled = true
    @State private var registerNeedEmail = false
    @State private var siteName = "QuantOKX"
    @State private var announcement = ""
    @State private var loaded = false

    var body: some View {
        PageScaffold(title: "站点设置", subtitle: "注册开关与站点信息") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开放注册", isOn: $registerEnabled).tint(.green)
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    Toggle("注册必填邮箱", isOn: $registerNeedEmail).tint(.green)
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    FieldRow(icon: "textformat", placeholder: "站点名", text: $siteName)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("公告").font(.caption).foregroundStyle(.white.opacity(0.5))
                        TextEditor(text: $announcement)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    PrimaryButton(title: "保存站点设置", icon: "checkmark.circle.fill") {
                        Task {
                            await store.adminSaveSettings([
                                "register_enabled": registerEnabled ? 1 : 0,
                                "register_need_email": registerNeedEmail ? 1 : 0,
                                "site_name": siteName,
                                "announcement": announcement,
                            ])
                        }
                    }
                }
            }
        }
        .navigationTitle("站点设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadAdminSettings()
            fill()
        }
    }

    private func fill() {
        guard let s = store.adminSettings, !loaded else { return }
        registerEnabled = s.registerEnabled == 1
        registerNeedEmail = s.registerNeedEmail == 1
        siteName = s.siteName
        announcement = s.announcement
        loaded = true
    }
}
