import Foundation
import UIKit

/// 聊天好友（每个好友有独立人设、会话、语音 API 配置）
struct ChatFriend: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "Amore"
    var avatarFile: String = ""       // Documents 内文件名
    var persona: String = ""          // 人设提示词
    var gender: String = ""           // male / female / ""
    var age: String = ""
    var sessionId: String = ""        // 服务端会话 id
    var sort: Int = 0
    var lastMessage: String = ""
    var lastAt: Double = 0
    // 语音 API（每人可单独指定，留空 = 跟随全局设置）
    var voiceEngine: String = ""      // local / server / cloud_sf / cloud_doubao / model
    var voiceId: String = ""          // 该引擎下的音色
    var ttsKey: String = ""           // 专属 API Key（硅基流动 / 豆包）
    var aiProviderId: String = ""     // 该好友使用的 AI 模型（ProviderStore id，空=跟随全局）
    // 长期记忆（Orbit memory-policy 移植）：AI 记住的关于用户的事实/偏好/日期
    var memory: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, avatarFile, persona, gender, age, sessionId, sort
        case lastMessage, lastAt, voiceEngine, voiceId, ttsKey, aiProviderId, memory
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Amore"
        avatarFile = try c.decodeIfPresent(String.self, forKey: .avatarFile) ?? ""
        persona = try c.decodeIfPresent(String.self, forKey: .persona) ?? ""
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        age = try c.decodeIfPresent(String.self, forKey: .age) ?? ""
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
        lastAt = try c.decodeIfPresent(Double.self, forKey: .lastAt) ?? 0
        voiceEngine = try c.decodeIfPresent(String.self, forKey: .voiceEngine) ?? ""
        voiceId = try c.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        ttsKey = try c.decodeIfPresent(String.self, forKey: .ttsKey) ?? ""
        aiProviderId = try c.decodeIfPresent(String.self, forKey: .aiProviderId) ?? ""
        memory = try c.decodeIfPresent([String].self, forKey: .memory) ?? []
    }

    var genderText: String {
        switch gender {
        case "male": return "男"
        case "female": return "女"
        default: return "不限"
        }
    }

    /// 好友头像（Documents 内图片）
    func avatarImage() -> UIImage? {
        guard !avatarFile.isEmpty else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return UIImage(contentsOfFile: dir.appendingPathComponent(avatarFile).path)
    }
}

/// 好友列表存储（UserDefaults JSON）
final class FriendStore: ObservableObject {
    static let shared = FriendStore()
    @Published var friends: [ChatFriend] = []

    private let key = "chat.friends.v1"

    private init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([ChatFriend].self, from: data), !list.isEmpty {
            friends = list.sorted { $0.sort < $1.sort }
            return
        }
        // 首次使用：把现有单人聊天迁移成第一个好友，保留会话
        var f = ChatFriend()
        f.name = UserDefaults.standard.string(forKey: "ai.displayName") ?? "Amore"
        f.persona = UserDefaults.standard.string(forKey: "persona.prompt") ?? ""
        f.gender = UserDefaults.standard.string(forKey: "persona.gender") ?? ""
        f.age = UserDefaults.standard.string(forKey: "persona.age") ?? ""
        f.sessionId = UserDefaults.standard.string(forKey: "chat.roomSessionId") ?? ""
        f.sort = 1
        friends = [f]
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func friend(_ id: String) -> ChatFriend? { friends.first { $0.id == id } }

    func update(_ id: String, _ body: (inout ChatFriend) -> Void) {
        guard let i = friends.firstIndex(where: { $0.id == id }) else { return }
        body(&friends[i])
        save()
    }

    func add(_ f: ChatFriend) {
        var n = f
        n.sort = (friends.map(\.sort).max() ?? 0) + 1
        friends.append(n)
        save()
    }

    func remove(_ id: String) {
        friends.removeAll { $0.id == id }
        save()
    }
}
