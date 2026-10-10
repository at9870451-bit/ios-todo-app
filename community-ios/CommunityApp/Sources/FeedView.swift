import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: CommunityStore
    var goCompose: () -> Void

    @State private var selected: Post?
    @State private var filterTag: String?

    private var shown: [Post] {
        if let t = filterTag { return store.posts.filter { $0.tag == t } }
        return store.posts
    }

    var body: some View {
        NavigationStack {
            Group {
                if shown.isEmpty {
                    ContentUnavailableView("这里还空着",
                                           systemImage: "tray",
                                           description: Text("点底部「发布」说点什么吧"))
                } else {
                    List {
                        Section {
                            tagBar
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        ForEach(shown) { p in
                            PostRow(post: p) { store.toggleLike(p.id) }
                                .contentShape(Rectangle())
                                .onTapGesture { selected = p }
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("社区")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        goCompose()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(item: $selected) { p in
                PostDetailView(postID: p.id)
                    .environmentObject(store)
            }
            .refreshable { }
        }
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagChip(text: "全部")
                    .onTapGesture { filterTag = nil }
                ForEach(["闲聊", "行情", "策略", "干货", "求助"], id: \.self) { t in
                    HStack(spacing: 4) {
                        if filterTag == t { Image(systemName: "checkmark").font(.caption2) }
                        Text(t)
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(filterTag == t ? Color.indigo : Color.indigo.opacity(0.12),
                                in: Capsule())
                    .foregroundStyle(filterTag == t ? Color.white : Color.indigo)
                    .onTapGesture { filterTag = (filterTag == t) ? nil : t }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 帖子行

struct PostRow: View {
    let post: Post
    var onLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(name: post.authorName, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName).font(.subheadline.weight(.semibold))
                    Text(post.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                TagChip(text: post.tag)
            }

            Text(post.text)
                .font(.subheadline)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Button(action: onLike) {
                    Label("\(post.likeCount)",
                          systemImage: post.likedByMe ? "heart.fill" : "heart")
                        .font(.subheadline)
                        .foregroundStyle(post.likedByMe ? Color.pink : Color.secondary)
                        .symbolEffect(.bounce, value: post.likedByMe)
                }
                .buttonStyle(.plain)

                Label("\(post.comments.count)", systemImage: "bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 帖子详情 + 评论

struct PostDetailView: View {
    @EnvironmentObject private var store: CommunityStore
    let postID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var post: Post? {
        store.posts.first { $0.id == postID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let p = post {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Avatar(name: p.authorName, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.authorName).font(.headline)
                                    Text(p.createdAt, format: .relative(presentation: .named))
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                TagChip(text: p.tag)
                            }

                            Text(p.text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            if p.comments.isEmpty {
                                Text("还没有评论，说点什么吧")
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            } else {
                                ForEach(p.comments) { c in
                                    HStack(alignment: .top, spacing: 10) {
                                        Avatar(name: c.author, size: 30)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(c.author).font(.caption.weight(.semibold))
                                                Spacer()
                                                Text(c.createdAt, format: .relative(presentation: .named))
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.tertiary)
                                            }
                                            Text(c.text).font(.subheadline)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 10) {
                            TextField("友善评论…", text: $draft)
                                .textFieldStyle(.roundedBorder)
                                .focused($focused)
                                .onSubmit { send() }
                            Button(action: send) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(draft.isEmpty ? Color.gray : Color.indigo)
                            }
                            .disabled(draft.isEmpty)
                        }
                        .padding(12)
                        .background(.bar)
                    }
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
                } else {
                    ContentUnavailableView("帖子不存在", systemImage: "questionmark.folder")
                }
            }
            .navigationTitle("帖子详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func send() {
        guard let p = post, !draft.isEmpty else { return }
        store.comment(p, text: draft)
        draft = ""
        focused = false
    }
}
