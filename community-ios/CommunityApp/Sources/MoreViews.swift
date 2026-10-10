import SwiftUI

// MARK: - 消息（通知）

struct MessagesView: View {
    @EnvironmentObject private var store: CommunityStore

    var body: some View {
        NavigationStack {
            Group {
                if store.notices.isEmpty {
                    ContentUnavailableView("暂无消息",
                                           systemImage: "bell.slash",
                                           description: Text("有人评论或点赞你的帖子时会出现在这里"))
                } else {
                    List(store.notices) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.text).font(.subheadline.weight(.semibold))
                            Text(n.detail)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(n.at, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("消息")
        }
    }
}

// MARK: - 我的

struct ProfileView: View {
    @EnvironmentObject private var store: CommunityStore
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Avatar(name: store.me.name, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("昵称", text: $store.me.name)
                                .font(.headline)
                            Text(store.me.bio)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("资料")
                } footer: {
                    Text("昵称会同步显示在你发出的帖子和评论里")
                }

                Section("数据") {
                    statRow(icon: "square.and.pencil", title: "我的帖子", value: "\(store.myPosts.count)")
                    statRow(icon: "heart", title: "收到的赞", value: "\(store.likesReceived)")
                    statRow(icon: "bubble.right", title: "社区总帖数", value: "\(store.posts.count)")
                }

                Section("我的帖子") {
                    if store.myPosts.isEmpty {
                        Text("还没有发过帖子")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(store.myPosts.prefix(10)) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.text).font(.subheadline).lineLimit(2)
                                HStack {
                                    TagChip(text: p.tag)
                                    Spacer()
                                    Label("\(p.likeCount)", systemImage: "heart")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("重置示例数据", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("会清空你发的内容并恢复初始示例帖（本地演示数据）")
                }
            }
            .navigationTitle("我的")
            .confirmationDialog("重置全部数据？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置", role: .destructive) { store.resetDemo() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.indigo)
        }
    }
}
