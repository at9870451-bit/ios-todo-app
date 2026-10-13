import SwiftUI

/// 聊天 Tab：历史会话列表首页（点击会话 → 对话 Tab 继续聊）
struct ChatsListView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var router: Router
    @State private var conversations: [ConversationRow] = []
    @State private var loading = true
    @State private var renaming: ConversationRow?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("加载中...").font(.footnote).foregroundStyle(.tertiary)
                    }
                } else if conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("聊天")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        router.startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .onAppear { Task { await loadSessions() } }
            .refreshable { await loadSessions() }
            .alert("重命名会话", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("标题", text: $renameText)
                Button("保存") { Task { await rename() } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conversations) { c in
                    row(c)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func row(_ c: ConversationRow) -> some View {
        Button {
            Haptics.light()
            router.openConversation(id: c.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.heroGradient)
                        .frame(width: 42, height: 42)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text((c.lastMsg?.isEmpty == false) ? c.lastMsg! : "暂无消息")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(ConversationListView.relTime(c.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .solidCard(16)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button {
                renaming = c
                renameText = c.title
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteByID(c.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.heroGradient.opacity(0.12))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(Theme.heroGradient.opacity(0.28), lineWidth: 1)
                    .frame(width: 76, height: 76)
                Image(systemName: "ellipsis.message")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.heroGradient)
            }
            VStack(spacing: 5) {
                Text("暂无聊天").font(.headline).foregroundStyle(.secondary)
                Text("点右上角开始新对话").font(.footnote).foregroundStyle(.tertiary)
            }
            DButton(title: "开始新对话", icon: "square.and.pencil") {
                router.startNewChat()
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作

    private func loadSessions() async {
        do {
            conversations = try await store.fetchConversations()
        } catch {
            store.toast = "加载会话失败"
        }
        loading = false
    }

    private func deleteByID(_ id: Int64) {
        Haptics.medium()
        conversations.removeAll { $0.id == id }
        Task { try? await store.deleteConversation(id: id) }
    }

    private func rename() async {
        guard let c = renaming else { return }
        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            try await store.renameConversation(id: c.id, title: t)
            if let i = conversations.firstIndex(where: { $0.id == c.id }) {
                conversations[i] = ConversationRow(id: c.id, title: t, lastMsg: c.lastMsg, updatedAt: c.updatedAt)
            }
            store.toast = "已重命名"
        } catch {
            store.toast = "重命名失败"
        }
    }
}

/// 会话行模型（聊天 Tab 专用，避免与历史会话页共享 @Binding）
struct ConversationRow: Identifiable, Decodable {
    let id: Int64
    let title: String
    let lastMsg: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey { case id, title, lastMsg = "last_msg", updatedAt = "updated_at" }
}
