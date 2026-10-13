import Foundation
import SwiftUI

/// AI 服务商配置管理：本地多配置 + 激活配置同步后端
@MainActor
final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()

    enum APIFormat: String, Codable, CaseIterable, Identifiable {
        case chat = "chat_completions"
        case responses = "responses"
        var id: String { rawValue }
        var title: String { self == .chat ? "Chat Completions" : "Responses API" }
        var subtitle: String {
            self == .chat ? "标准 /v1/chat/completions 格式，兼容大多数服务" : "新 /v1/responses 格式（OpenAI 官方 / Codex 端点）"
        }
    }

    struct Provider: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var label: String
        var vendor: String          // openai / deepseek / moonshot / grok / openrouter / custom
        var apiFormat: APIFormat = .chat
        var apiKey: String
        var baseURL: String = ""      // 空 = 使用官方默认地址
        var autoV1: Bool = true
        var model: String = ""

        var effectiveBase: String {
            let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return base.isEmpty ? ProviderStore.defaultBase(vendor) : base
        }
        var maskedKey: String {
            let k = apiKey.trimmingCharacters(in: .whitespaces)
            guard k.count > 12 else { return k.isEmpty ? "未填 Key" : k }
            return String(k.prefix(6)) + "..." + String(k.suffix(4))
        }
    }

    @Published var providers: [Provider] = []
    @Published var activeId: UUID?

    var active: Provider? { providers.first { $0.id == activeId } }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("providers.json")
    }

    private init() { load() }

    // MARK: - 持久化

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Provider].self, from: data) {
            providers = list
        }
        if let s = UserDefaults.standard.string(forKey: "provider.active"), let id = UUID(uuidString: s) {
            activeId = providers.contains { $0.id == id } ? id : providers.first?.id
        } else {
            activeId = providers.first?.id
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            try? data.write(to: fileURL, options: .atomic)
        }
        UserDefaults.standard.set(activeId?.uuidString, forKey: "provider.active")
    }

    // MARK: - 操作

    func add(_ p: Provider) {
        providers.append(p)
        activate(p)
    }

    func update(_ p: Provider) {
        if let i = providers.firstIndex(where: { $0.id == p.id }) {
            providers[i] = p
            if activeId == p.id { syncActive() }
            persist()
        }
    }

    func remove(_ p: Provider) {
        providers.removeAll { $0.id == p.id }
        if activeId == p.id {
            activeId = providers.first?.id
            syncActive()
        }
        persist()
    }

    func activate(_ p: Provider) {
        activeId = p.id
        persist()
        syncActive()
    }

    /// 激活配置同步到服务端（/api/chat/send 依此后端配置调用 AI）
    func syncActive() {
        guard let a = active else { return }
        let base = a.effectiveBase
        let model = a.model
        let name = a.label
        let style = a.apiFormat.rawValue
        let key = a.apiKey
        Task {
            _ = await BackendStore.shared.saveChatConfig(endpoint: base, key: key, model: model, apiStyle: style, name: name)
            BackendStore.shared.chatModelName = model.isEmpty ? name : model
            BackendStore.shared.chatConfigured = true
        }
    }

    nonisolated static func defaultBase(_ vendor: String) -> String {
        switch vendor {
        case "openai": return "https://api.openai.com"
        case "deepseek": return "https://api.deepseek.com"
        case "moonshot": return "https://api.moonshot.cn"
        case "grok": return "https://api.x.ai"
        case "openrouter": return "https://openrouter.ai/api"
        default: return ""
        }
    }

    // MARK: - 验证连接 + 模型列表（GET {base}/v1/models）

    nonisolated static func modelsURL(for base: String) -> String {
        var u = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        if u.hasSuffix("/v1") { return u + "/models" }
        return u + "/v1/models"
    }

    private struct ModelListResponse: Decodable {
        struct M: Decodable { let id: String }
        let data: [M]
    }

    func fetchModels(_ p: Provider) async throws -> [String] {
        struct VerifyError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
        let key = p.apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw VerifyError(message: "请先填写 API Key") }
        guard let url = URL(string: Self.modelsURL(for: p.effectiveBase)) else {
            throw VerifyError(message: "API 地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw VerifyError(message: "网络错误：\(error.localizedDescription)")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let hint = status == 401 ? "（Key 无效或未授权）" : (status == 404 ? "（该端点不支持 /v1/models，可手动填写模型名）" : "")
            throw VerifyError(message: "验证失败 HTTP \(status) \(hint)\(body.isEmpty ? "" : "：" + String(body.prefix(120)))")
        }
        if let d = try? JSONDecoder().decode(ModelListResponse.self, from: data) {
            let ids = d.data.map { $0.id }.filter { !$0.isEmpty }.sorted()
            guard !ids.isEmpty else { throw VerifyError(message: "验证成功但模型列表为空，可手动填写模型名") }
            return ids
        }
        throw VerifyError(message: "响应无法解析（非 OpenAI 兼容格式），可手动填写模型名")
    }
}
