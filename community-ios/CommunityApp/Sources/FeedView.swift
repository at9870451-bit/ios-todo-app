import SwiftUI

enum HomeFilter: Equatable {
    case recommend
    case follow
    case tag(String)
}

struct FeedView: View {
    @EnvironmentObject private var store: CommunityStore
    var goCompose: () -> Void

    @State private var selected: Post?
    @State private var filter: HomeFilter = .recommend

    static let followed = ["老王聊交易", "K线少女", "节气养生"]
    private let cats: [(String, String, String)] = [
        ("闲聊", "message.fill", "bubble.left.and.bubble.right.fill"),
        ("行情", "chart.line.uptrend.xyaxis", "chart.line.uptrend.xyaxis"),
        ("策略", "target", "target"),
        ("干货", "book.fill", "text.book.closed.fill"),
        ("求助", "hand.raised.fill", "hand.raised.fill"),
    ]

    private var shown: [Post] {
        switch filter {
        case .recommend:
            return store.posts.sorted { $0.likeCount > $1.likeCount }
        case .follow:
            return store.posts.filter { Self.followed.contains($0.authorName) }
        case .tag(let t):
            return store.posts.filter { $0.tag == t }
        }
    }

    private var filterLabel: String {
        switch filter {
        case .recommend: return "推荐"
        case .follow: return "关注"
        case .tag(let t): return t
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    categoryGrid
                    chipsRow

                    Text("\(filterLabel) · \(shown.count) 帖")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.leading, 4)

                    if shown.isEmpty {
                        emptyCard
                    } else {
                        ForEach(shown) { p in
                            PostRow(post: p) { store.toggleLike(p.id) }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 16))
                                .contentShape(Rectangle())
                                .onTapGesture { selected = p }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("社区")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: goCompose) { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(item: $selected) { p in
                PostDetailView(postID: p.id)
                    .environmentObject(store)
            }
        }
    }

    // MARK: 分区宫格

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分区")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(cats, id: \.0) { cat in
                    let count = store.posts.filter { $0.tag == cat.0 }.count
                    let isOn = filter == .tag(cat.0)
                    VStack(spacing: 6) {
                        Image(systemName: cat.2)
                            .font(.body)
                            .foregroundStyle(isOn ? Color.white : Color.indigo)
                        Text(cat.0)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                        Text("\(count) 帖")
                            .font(.system(size: 9))
                            .foregroundStyle(isOn ? Color.white.opacity(0.8) : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isOn ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { filter = isOn ? .recommend : .tag(cat.0) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: 快捷筛选条

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("推荐", .recommend)
                chip("关注", .follow)
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, _ f: HomeFilter) -> some View {
        let isOn = filter == f
        return Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .onTapGesture { filter = f }
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(Color.secondary)
            Text("这个分区还没有帖子")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
                                                    .foregroundStyle(Color.secondary)
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
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
                    }
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
