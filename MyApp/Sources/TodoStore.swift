import Foundation
import Combine

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var createdAt: Date = Date()
}

/// 用 UserDefaults 存 JSON —— 零依赖、够用。
/// 数据量大或需要查询再换 SwiftData / CoreData。
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [Todo] = []

    private let key = "todos.v1"
    private let calendar = Calendar.current

    init() {
        load()
        if todos.isEmpty { seed() }
    }

    // MARK: - 增删改

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(Todo(title: trimmed), at: 0)
        save()
    }

    func toggle(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        save()
    }

    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        save()
    }

    func delete(at offsets: IndexSet, in list: [Todo]) {
        let ids = Set(offsets.map { list[$0].id })
        todos.removeAll { ids.contains($0.id) }
        save()
    }

    func rename(_ todo: Todo, to title: String) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos[i].title = trimmed
        save()
    }

    func clearDone() {
        todos.removeAll { $0.isDone }
        save()
    }

    // MARK: - 派生数据

    var doneCount: Int { todos.filter(\.isDone).count }
    var progress: Double {
        guard !todos.isEmpty else { return 0 }
        return Double(doneCount) / Double(todos.count)
    }

    /// 今天新增了几条
    var todayCount: Int {
        todos.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    // MARK: - 持久化

    private func save() {
        do {
            let data = try JSONEncoder().encode(todos)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            todos = try JSONDecoder().decode([Todo].self, from: data)
        } catch {
            print("load failed: \(error)")
        }
    }

    private func seed() {
        todos = [
            Todo(title: "在手机上写下第一行 SwiftUI"),
            Todo(title: "推送到 GitHub", isDone: true),
            Todo(title: "等云端 Mac 编译出 ipa"),
        ]
    }
}
