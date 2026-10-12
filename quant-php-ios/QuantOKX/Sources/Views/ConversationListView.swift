import SwiftUI

/// 会话历史列表（从工具栏进入）
struct ConversationListView: View {
    @Binding var sessionId: Int64
    @Binding var messages: [ChatMessage]
    @EnvironmentObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [Conversation] = []
    @State private var loading = true

    struct Conversation: Identifiable, Decodable {
        let id: Int64
        let title: String
        let lastMsg: String?
        let updatedAt: String?
        enum CodingKeys: String, CodingKey { case id, title, lastMsg = "last_msg", updatedAt = "updated_at" }
    }

    var body: some View {
        List {
            if loading {
                ProgressView("加载中...").center
            } else if conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.title2).foregroundStyle(.tertiary)
                    Text("暂无历史会话").font(.subheadline).foregroundStyle(.secondary)
                }.center
            } else {
                ForEach(conversations) { c in
                    Button {
                        loadConversation(c.id); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            Text(c.lastMsg ?? "").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("历史会话")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
        .refreshable { await loadSessions() }
    }

    private func loadSessions() async {
        do {
            conversations = try await store.fetchConversations()
        } catch { }
        loading = false
    }
    private func loadConversation(_ id: Int64) {
        sessionId = id
        Task {
            do {
                messages = try await store.fetchMessages(sessionId: id)
            } catch { }
        }
    }
    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { conversations[$0].id }
        conversations.remove(atOffsets: offsets)
        for t in targets { Task { try? await store.deleteConversation(id: t) } }
    }
}

extension View { var center: some View { frame(maxWidth: .infinity, maxHeight: .infinity) } }
