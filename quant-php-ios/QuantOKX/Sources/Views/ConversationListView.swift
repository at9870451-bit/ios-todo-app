import SwiftUI

/// 历史会话列表（Apple 风格卡片行 + 相对时间 + 重命名/删除）
struct ConversationListView: View {
    @Binding var sessionId: Int64
    @Binding var messages: [ChatMessage]
    @EnvironmentObject var store: BackendStore
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [Conversation] = []
    @State private var loading = true
    @State private var renaming: Conversation?
    @State private var renameText = ""

    struct Conversation: Identifiable, Decodable {
        let id: Int64
        let title: String
        let lastMsg: String?
        let updatedAt: String?
        enum CodingKeys: String, CodingKey { case id, title, lastMsg = "last_msg", updatedAt = "updated_at" }
    }

    var body: some View {
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
        .navigationTitle("历史会话")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
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

    private func row(_ c: Conversation) -> some View {
        let isCurrent = c.id == sessionId
        return Button {
            loadConversation(c.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: isCurrent
                                ? [Color(red: 1.0, green: 0.49, blue: 0.10), Color(red: 1.0, green: 0.38, blue: 0.02)]
                                : [Color(uiColor: .systemGray4), Color(uiColor: .systemGray3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(c.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    Text((c.lastMsg?.isEmpty == false) ? c.lastMsg! : "暂无消息")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Self.relTime(c.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.045), radius: 9, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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
                    .fill(Theme.accent.opacity(0.10))
                    .frame(width: 76, height: 76)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 5) {
                Text("暂无历史会话").font(.headline).foregroundStyle(.secondary)
                Text("在对话页发送消息后会自动保存到这里")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
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

    private func loadConversation(_ id: Int64) {
        sessionId = id
        Task {
            do {
                messages = try await store.fetchMessages(sessionId: id)
            } catch {
                store.toast = "加载消息失败"
            }
        }
    }

    private func deleteByID(_ id: Int64) {
        conversations.removeAll { $0.id == id }
        if id == sessionId {
            sessionId = 0
            messages = []
        }
        Task { try? await store.deleteConversation(id: id) }
    }

    private func rename() async {
        guard let c = renaming else { return }
        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            try await store.renameConversation(id: c.id, title: t)
            if let i = conversations.firstIndex(where: { $0.id == c.id }) {
                conversations[i] = Conversation(id: c.id, title: t, lastMsg: c.lastMsg, updatedAt: c.updatedAt)
            }
            store.toast = "已重命名"
        } catch {
            store.toast = "重命名失败"
        }
    }

    /// "2026-10-12 22:27:21" → 今天/昨天/M月d日/yy/M/d
    static func relTime(_ s: String?) -> String {
        guard let s, s.count >= 16 else { return "" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let d = df.date(from: s) else { return String(s.prefix(10)) }
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return tf.string(from: d) }
        if cal.isDateInYesterday(d) { return "昨天 " + tf.string(from: d) }
        let days = cal.dateComponents([.day], from: d, to: Date()).day ?? 0
        if days < 7 {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return f.string(from: d)
        }
        let f = DateFormatter()
        f.dateFormat = "yy/M/d"
        return f.string(from: d)
    }
}
