import SwiftUI

/// 聊天主界面：消息气泡列表 + 输入栏 + 流式对话
struct ChatScreen: View {
    @EnvironmentObject var store: BackendStore
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var sessionId: Int64 = 0
    @State private var sending = false
    @FocusState private var inputFocus: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // 蓝白渐变背景
                LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if messages.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 44)).foregroundStyle(.tertiary)
                                    Text("开始新对话").font(.headline).foregroundStyle(.secondary)
                                    Text("输入消息，AI 将为你解答").font(.subheadline).foregroundStyle(.tertiary)
                                }.padding(.top, 100)
                            }
                            ForEach(messages) { m in
                                MessageBubble(msg: m).id(m.id)
                            }
                            if sending {
                                HStack {
                                    TypingIndicator()
                                    Spacer()
                                }.padding(.leading, 16)
                            }
                            Spacer(minLength: 80)
                        }
                        .padding(.horizontal, 14)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(messages.last?.id ?? 0, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("AI 对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ConversationListView(sessionId: $sessionId, messages: $messages) } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newChat() } label: { Image(systemName: "plus.message") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                InputBar(text: $input, sending: sending, onSend: send)
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""; inputFocus = false
        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970), role: "user", content: text))
        sending = true
        Task {
            do {
                let reply = try await store.sendChat(sessionId: sessionId, content: text)
                if sessionId == 0 { sessionId = reply.sessionId }
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: reply.reply))
            } catch {
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
            }
            sending = false
        }
    }

    private func newChat() {
        messages = []; sessionId = 0
    }
}

struct ChatMessage: Identifiable {
    let id: Int64
    let role: String
    let content: String
}

struct MessageBubble: View {
    let msg: ChatMessage
    var isUser: Bool { msg.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 0) {
                Text(msg.content)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser
                            ? LinearGradient(colors: [.blue, Color(red: 0.2, green: 0.45, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(uiColor: .secondarySystemGroupedBackground)],
                                             startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: Color.black.opacity(isUser ? 0.1 : 0.04), radius: 4, y: 2)
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

struct TypingIndicator: View {
    @State private var dot = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                    .opacity(dot == i ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.2), value: dot)
            }
        }
        .padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { withAnimation { dot = 1 } }
        .onChange(of: dot) { _, v in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { dot = (v + 1) % 3 } }
        }
    }
}

struct InputBar: View {
    @Binding var text: String
    let sending: Bool
    let onSend: () -> Void
    @FocusState private var focus: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("输入消息...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($focus)
                .onSubmit { onSend() }
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial)
    }
}
