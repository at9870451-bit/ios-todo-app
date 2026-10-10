import SwiftUI

struct ComposeView: View {
    @EnvironmentObject private var store: CommunityStore
    var onPublished: () -> Void

    @State private var text = ""
    @State private var tag = "闲聊"
    @State private var showDone = false
    @FocusState private var focused: Bool

    private let tags = ["闲聊", "行情", "策略", "干货", "求助"]

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextEditor(text: $text)
                            .frame(minHeight: 180)
                            .focused($focused)
                            .padding(10)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("分享点什么…（行情观点、学习笔记、踩坑经历都可以）")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.tertiary)
                                        .padding(18)
                                        .allowsHitTesting(false)
                                }
                            }

                        Text("选择话题")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.secondary)

                        FlowChips(tags: tags, selected: $tag)
                    }
                    .padding(16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("发帖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") {
                        store.publish(text, tag: tag)
                        text = ""
                        tag = "闲聊"
                        focused = false
                        showDone = true
                    }
                    .disabled(!canPost)
                    .font(.body.weight(.semibold))
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
            .alert("发布成功", isPresented: $showDone) {
                Button("去首页看看", role: .cancel) { onPublished() }
            } message: {
                Text("你的帖子已经出现在首页了")
            }
        }
    }
}

// MARK: - 自动换行的话题胶囊

struct FlowChips: View {
    let tags: [String]
    @Binding var selected: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(tags, id: \.self) { t in
                Text(t)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selected == t ? Color.indigo : Color.indigo.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(selected == t ? Color.white : Color.indigo)
                    .onTapGesture { selected = t }
            }
        }
    }
}
