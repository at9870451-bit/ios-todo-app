import Foundation
import SwiftUI

/// 全局状态管理：登录态、数据加载、统一错误处理
@MainActor
final class BackendStore: ObservableObject {
    static let shared = BackendStore()

    let config = AppConfig.shared
    private let client = BackendClient.shared

    // 登录表单
    @Published var loginError: String = ""
    @Published var busy: Bool = false

    // AI 对话
    @Published var chatConfigured: Bool = false
    @Published var chatModelName: String = ""

    // 会员
    @Published var memberPlans: MembershipPlansData?
    @Published var memberOrders: [MemberOrderRow] = []
    @Published var memberStatus: MemberStatusData?
    // Doll Studio 3D（玩偶换装）
    @Published var dollCategories: [DollCategory] = DollCatalog.categories
    @Published var dollItems: [DollItem] = DollCatalog.builtinItems()
    @Published var dollOutfits: [DollOutfitRow] = []
    var dollCatalogLoaded = false

    @Published var lastError: String = ""
    @Published var toast: String = ""

    private init() {
        Task { await client.configure(baseURL: config.serverURL) }
    }

    // MARK: - 会话

    /// 启动时恢复会话：配置地址并校验登录态
    func bootstrap() async {
        await client.configure(baseURL: config.serverURL)
        guard config.loggedIn else { return }
        do {
            let payload: SessionPayload = try await client.get("/api/ios/me", as: SessionPayload.self)
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
            await loadChatModel()
        } catch {
            // 会话失效：清空登录态（网络错误除外，保留以便重试）
            if let apiErr = error as? APIError, apiErr.isUnauthorized {
                config.clearAuth()
            }
        }
    }

    func login(username: String, password: String) async {
        busy = true
        loginError = ""
        defer { busy = false }
        do {
            await client.configure(baseURL: config.serverURL)
            let payload: SessionPayload = try await client.post(
                "/api/ios/login",
                body: ["username": username, "password": password],
                as: SessionPayload.self
            )
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
            await pushLocalChatConfigIfNeeded()
            toast = "欢迎回来，\(payload.user.nickname)"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func register(username: String, password: String, confirm: String, email: String) async {
        busy = true
        loginError = ""
        defer { busy = false }
        do {
            await client.configure(baseURL: config.serverURL)
            var body: [String: Any] = [
                "username": username,
                "password": password,
                "password_confirmation": confirm,
            ]
            if !email.isEmpty { body["email"] = email }
            let payload: SessionPayload = try await client.post("/api/ios/register", body: body, as: SessionPayload.self)
            config.applyAuth(user: payload.user, csrf: payload.csrfToken)
            await client.setCSRF(payload.csrfToken)
            await pushLocalChatConfigIfNeeded()
            toast = "注册成功"
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() async {
        _ = try? await client.post("/api/ios/logout", body: [:], as: EmptyData.self)
        config.clearAuth()
    }

    /// 连通性测试（登录页用）
    func testConnection(url: String) async -> (ok: Bool, message: String) {
        await client.configure(baseURL: url)
        do {
            struct PingData: Decodable { let app: String; let version: String; let csrfToken: String?
                enum CodingKeys: String, CodingKey { case app, version; case csrfToken = "csrf_token" }
            }
            let data: PingData = try await client.get("/api/ios/ping", as: PingData.self)
            if let token = data.csrfToken { await client.setCSRF(token) }
            return (true, "\(data.app) \(data.version) 连接正常")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 通用请求包装（统一 401 处理）

    func handle(_ error: Error) {
        if let apiErr = error as? APIError {
            if apiErr.isUnauthorized {
                config.clearAuth()
            }
            lastError = apiErr.message
            toast = apiErr.message
        } else {
            lastError = error.localizedDescription
            toast = error.localizedDescription
        }
    }

    // MARK: - 数据加载

    func loadMemberPlans() async {
        do { memberPlans = try await client.get("/api/member/plans", as: MembershipPlansData.self) }
        catch { handle(error) }
    }

    func loadMemberOrders() async {
        do { memberOrders = try await client.get("/api/member/orders", as: MemberOrdersData.self).items }
        catch { handle(error) }
    }

    func loadMemberStatus() async {
        do {
            memberStatus = try await client.get("/api/member/status", as: MemberStatusData.self)
            // 同步本地会员等级（购买/过期降级后保持一致）
            if let lv = memberStatus?.badge.level { config.membershipLevel = lv }
        }
        catch { handle(error) }
    }

    // MARK: - 写操作

    func subscribe(level: String, months: Int, channel: String) async -> String? {
        do {
            struct PayData: Decodable { let tradeNo: String; let amount: String; let payUrl: String
                enum CodingKeys: String, CodingKey { case tradeNo = "trade_no"; case amount; case payUrl = "pay_url" }
            }
            let r: PayData = try await client.post("/api/member/pay", body: ["level": level, "months": months, "channel": channel], as: PayData.self)
            await loadMemberOrders()
            if r.payUrl.isEmpty {
                toast = "已直接开通（演示模式）"
            } else {
                toast = "正在跳转支付"
            }
            return r.payUrl
        } catch {
            handle(error)
            return nil
        }
    }

    // MARK: - 管理端（仅管理员）

    @Published var adminStats: AdminStats?
    @Published var adminUsers: AdminUsersData?
    @Published var adminOrders: AdminOrdersData?
    @Published var adminPlans: [AdminPlanRow] = []
    @Published var adminFreeAi: FreeAiData?
    @Published var adminPayment: PaymentConfigData?
    @Published var adminSettings: SiteSettings?

    func loadAdminStats() async {
        do { adminStats = try await client.get("/api/admin/stats", as: AdminStats.self) }
        catch { handle(error) }
    }

    func loadAdminUsers(keyword: String = "", page: Int = 1) async {
        do {
            var q = ["page": "\(page)", "size": "20"]
            if !keyword.isEmpty { q["keyword"] = keyword }
            adminUsers = try await client.get("/api/admin/users", query: q, as: AdminUsersData.self)
        } catch { handle(error) }
    }

    /// 管理员更新用户（action: set_level / extend / toggle_status / set_role / reset_password / update_profile）
    func adminUserUpdate(id: Int, fields: [String: Any]) async {
        do {
            var body = fields
            body["id"] = id
            _ = try await client.post("/api/admin/user/update", body: body, as: EmptyData.self)
            toast = "用户已更新"
            await loadAdminUsers()
        } catch { handle(error) }
    }

    func loadAdminOrders(status: String = "", keyword: String = "", page: Int = 1) async {
        do {
            var q = ["page": "\(page)", "size": "20"]
            if !status.isEmpty { q["status"] = status }
            if !keyword.isEmpty { q["keyword"] = keyword }
            adminOrders = try await client.get("/api/admin/orders", query: q, as: AdminOrdersData.self)
        } catch { handle(error) }
    }

    func adminMarkOrderPaid(_ id: Int) async {
        do {
            _ = try await client.post("/api/admin/order/mark-paid", body: ["id": id], as: EmptyData.self)
            toast = "已标记支付"
            await loadAdminOrders()
        } catch { handle(error) }
    }

    func loadAdminPlans() async {
        do { adminPlans = try await client.get("/api/admin/plans", as: AdminPlansData.self).plans }
        catch { handle(error) }
    }

    func adminSavePlans(_ plans: [String: [String: Any]]) async {
        do {
            _ = try await client.post("/api/admin/plans/save", body: ["plans": plans], as: EmptyData.self)
            toast = "会员计划已保存"
            await loadAdminPlans()
        } catch { handle(error) }
    }

    func loadAdminFreeAi() async {
        do { adminFreeAi = try await client.get("/api/admin/free-ai", as: FreeAiData.self) }
        catch { handle(error) }
    }

    func adminSaveFreeAi(_ body: [String: Any]) async {
        do {
            _ = try await client.post("/api/admin/free-ai/save", body: body, as: EmptyData.self)
            toast = "平台免费 AI 设置已保存"
            await loadAdminFreeAi()
        } catch { handle(error) }
    }

    func loadAdminPayment() async {
        do { adminPayment = try await client.get("/api/admin/payment", as: PaymentConfigData.self) }
        catch { handle(error) }
    }

    func adminSavePayment(_ body: [String: Any]) async {
        do {
            _ = try await client.post("/api/admin/payment/save", body: body, as: EmptyData.self)
            toast = "支付设置已保存"
            await loadAdminPayment()
        } catch { handle(error) }
    }

    func loadAdminSettings() async {
        do { adminSettings = try await client.get("/api/admin/settings", as: SiteSettingsData.self).site }
        catch { handle(error) }
    }

    func adminSaveSettings(_ body: [String: Any]) async {
        do {
            _ = try await client.post("/api/admin/settings/save", body: body, as: EmptyData.self)
            toast = "站点设置已保存"
            await loadAdminSettings()
        } catch { handle(error) }
    }

    // MARK: - AI 配置创建 / 编辑

    func loadAiConfig(id: Int) async -> AiConfigDetail? {
        do { return try await client.get("/api/ai/get", query: ["id": "\(id)"], as: AiConfigDetail.self) }
        catch { handle(error); return nil }
    }

    func saveAiConfig(_ body: [String: Any]) async -> Bool {
        do {
            _ = try await client.post("/api/ai/config", body: body, as: EmptyData.self)
            toast = "AI 配置已保存"
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func deleteAiConfig(id: Int) async -> Bool {
        do {
            _ = try await client.post("/api/ai/delete", body: ["id": id], as: EmptyData.self)
            toast = "AI 配置已删除"
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func testAiConfig(id: Int) async -> String {
        do {
            struct TestData: Decodable { let success: Bool?; let message: String?; let reply: String? }
            let r: TestData = try await client.post("/api/ai/test", body: ["id": id], as: TestData.self)
            return r.message ?? r.reply ?? "连接测试成功"
        } catch {
            if let apiErr = error as? APIError { return apiErr.message }
            return error.localizedDescription
        }
    }
}

// MARK: - AI 对话助手（类 Minis）

/// 附件：本地直传 AI（base64），后端不落库
struct ChatAttachment: Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var kind: String        // image / video / file
    var mime: String
    var data: Data

    var icon: String {
        switch kind {
        case "image": return "photo.fill"
        case "video": return "video.fill"
        default: return "doc.fill"
        }
    }
    var sizeLabel: String {
        let kb = Double(data.count) / 1024.0
        return kb > 1024 ? String(format: "%.1fMB", kb / 1024) : String(format: "%.0fKB", kb)
    }
}

struct ChatReply: Decodable {
    let sessionId: Int64
    let reply: String
    let degraded: Bool?
    enum CodingKeys: String, CodingKey { case sessionId = "session_id", reply, degraded }
}

extension BackendStore {
    func sendChat(sessionId: Int64, content: String, attachments: [ChatAttachment] = [], reasoning: String = "", systemPrompt: String = "") async throws -> ChatReply {
        var body: [String: Any] = ["session_id": sessionId, "content": content]
        if !attachments.isEmpty {
            body["attachments"] = attachments.map { a in
                ["kind": a.kind, "name": a.name, "mime": a.mime, "dataBase64": a.data.base64EncodedString()]
            }
        }
        if !reasoning.isEmpty { body["reasoning"] = reasoning }
        if !systemPrompt.isEmpty { body["system_prompt"] = systemPrompt }
        return try await client.post("/api/chat/send", body: body, as: ChatReply.self)
    }
    /// 无状态对话：不落库，把本地历史一起发过去（聊天记录只存本机）
    func oneshot(messages: [[String: String]], systemPrompt: String, reasoning: String = "") async throws -> String {
        var body: [String: Any] = ["messages": messages]
        if !systemPrompt.isEmpty { body["system_prompt"] = systemPrompt }
        if !reasoning.isEmpty { body["reasoning"] = reasoning }
        struct Reply: Decodable { let reply: String }
        struct Wrap: Decodable { let data: Reply }
        do {
            let w = try await client.post("/api/chat/oneshot", body: body, as: Wrap.self)
            return w.data.reply
        } catch {
            // 兼容旧后端（尚未部署 /oneshot）：退回会话接口，保证聊天不中断
            let lastUser = messages.last(where: { $0["role"] == "user" })?["content"] ?? ""
            guard !lastUser.isEmpty else { throw error }
            let legacy = try await sendChat(sessionId: 0, content: lastUser, attachments: [],
                                            reasoning: reasoning, systemPrompt: systemPrompt)
            return legacy.reply
        }
    }

    func fetchConversations() async throws -> [ConversationListView.Conversation] {
        return try await client.get("/api/chat/sessions", as: [ConversationListView.Conversation].self)
    }
    func fetchMessages(sessionId: Int64) async throws -> [ChatMessage] {
        struct Msg: Decodable { let id: Int64; let role: String; let content: String }
        let rows = try await client.get("/api/chat/messages?session_id=\(sessionId)", as: [Msg].self)
        return rows.map { ChatMessage(id: $0.id, role: $0.role, content: $0.content) }
    }
    func deleteConversation(id: Int64) async throws {
        let _: EmptyData = try await client.post("/api/chat/session/delete", body: ["id": id], as: EmptyData.self)
    }
    func renameConversation(id: Int64, title: String) async throws {
        let _: EmptyData = try await client.post("/api/chat/session/rename", body: ["id": id, "title": title], as: EmptyData.self)
    }
    func saveChatConfig(endpoint: String, key: String, model: String, apiStyle: String = "chat_completions", name: String = "Chat") async -> String {
        do {
            let _: EmptyData = try await client.post("/api/ai/config", body: ["name": name, "api_url": endpoint, "api_key": key, "model": model, "enabled": true, "mode": "chat", "api_style": apiStyle], as: EmptyData.self)
            await MainActor.run {
                chatModelName = model
                chatConfigured = true
            }
            return "配置已保存 ✓"
        } catch { return "保存失败: \(error.localizedDescription)" }
    }

    /// 登录/注册后把本机激活的主模型同步到当前服务器。
    /// 这样换服务器后，聊天 Tab 与对话 Tab 仍共用同一个 GPT 配置。
    func pushLocalChatConfigIfNeeded() async {
        guard let p = ProviderStore.shared.active,
              p.kind == .main,
              !p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !p.effectiveBase.isEmpty else {
            await loadChatModel()
            return
        }
        _ = await saveChatConfig(
            endpoint: p.effectiveBase,
            key: p.apiKey,
            model: p.model,
            apiStyle: p.apiFormat.rawValue,
            name: p.label
        )
        await loadChatModel()
    }

    /// 拉取当前 chat 模型配置状态（顶部卡片显示用）
    func loadChatModel() async {
        do {
            let rows = try await client.get("/api/ai/list", as: [[String: FlexString]].self)
            var chosen: [String: FlexString]?
            for r in rows {
                let mode = r["mode"]?.value ?? ""
                let enabled = r["enabled"]?.value ?? ""
                if mode == "chat" && enabled == "1" { chosen = r; break }
            }
            if chosen == nil { chosen = rows.last }
            guard let r = chosen else {
                await MainActor.run { chatConfigured = false; chatModelName = "" }
                return
            }
            let model = r["model"]?.value ?? ""
            let name = r["name"]?.value ?? ""
            let url = r["api_url"]?.value ?? ""
            let hasKey = !(r["api_key"]?.value ?? "").isEmpty
            await MainActor.run {
                chatModelName = model.isEmpty ? (name.isEmpty ? "未命名配置" : name) : model
                chatConfigured = !url.isEmpty && (hasKey || !model.isEmpty)
            }
        } catch {
            // 拉取失败不阻塞 UI
        }
    }

    // MARK: - Doll Studio 3D（玩偶换装）

    /// 拉取服装目录（失败时保留内置目录，玩偶功能可离线使用）
    func loadDollCatalog() async {
        guard !dollCatalogLoaded else { return }
        do {
            let data = try await client.get("/api/doll/catalog", as: DollCatalogData.self)
            if !data.items.isEmpty {
                dollItems = data.items
                dollCategories = data.categories.isEmpty ? DollCatalog.categories : data.categories
            }
            dollCatalogLoaded = true
        } catch {
            // 网络失败：静默保留内置目录
        }
    }

    func loadDollOutfits() async {
        do { dollOutfits = try await client.get("/api/doll/outfits", as: [DollOutfitRow].self) }
        catch { handle(error) }
    }

    func saveDollOutfit(name: String, state: DollOutfitState) async {
        do {
            struct Saved: Decodable { let id: Int64 }
            _ = try await client.post(
                "/api/doll/outfits",
                body: ["name": name, "gender": state.gender, "skin": state.skin, "state": state.json],
                as: Saved.self
            )
            await loadDollOutfits()
            toast = "穿搭已保存"
        } catch { handle(error) }
    }

    func deleteDollOutfit(id: Int64) async {
        do {
            _ = try await client.post("/api/doll/outfits/delete", body: ["id": id], as: EmptyData.self)
            await loadDollOutfits()
        } catch { handle(error) }
    }

    func favoriteDollOutfit(id: Int64, fav: Bool) async {
        do {
            _ = try await client.post("/api/doll/outfits/favorite", body: ["id": id, "favorite": fav], as: EmptyData.self)
            await loadDollOutfits()
        } catch { handle(error) }
    }

    /// AI 穿搭推荐（服务端持有 AI 密钥，客户端只传需求文本）
    func dollRecommend(gender: String, prompt: String) async -> DollRecommendData? {
        do {
            return try await client.post(
                "/api/doll/ai/recommend",
                body: ["gender": gender, "prompt": prompt],
                as: DollRecommendData.self
            )
        } catch {
            handle(error)
            return nil
        }
    }
}
