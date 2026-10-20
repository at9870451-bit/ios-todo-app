import Foundation

/// 聊天记录本地存储（服务端不保存消息，全部留在本机）
enum LocalHistory {

    private struct Row: Codable {
        let id: Int64
        let role: String
        let content: String
    }

    private static func storeKey(_ key: String) -> String { "local.msgs." + key }

    static func load(_ key: String) -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: storeKey(key)),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.map { ChatMessage(id: $0.id, role: $0.role, content: $0.content) }
    }

    static func save(_ key: String, _ msgs: [ChatMessage]) {
        let rows = msgs.suffix(300).map { Row(id: $0.id, role: $0.role, content: $0.content) }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: storeKey(key))
    }

    @discardableResult
    static func clear(_ key: String) -> Int {
        let n = count(key)
        UserDefaults.standard.removeObject(forKey: storeKey(key))
        return n
    }

    static func count(_ key: String) -> Int {
        load(key).count
    }
}
