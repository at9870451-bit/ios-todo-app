import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 聊天主界面：顶部对话摘要卡 + 气泡消息流 + 附件输入 + 推理强度
struct ChatScreen: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var router: Router
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var sessionId: Int64 = 0
    @State private var sending = false
    @State private var pendingAtts: [ChatAttachment] = []
    @State private var loadingAtt = false
    @State private var showPhotoPicker = false
    @State private var showVideoPicker = false
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @AppStorage("chat.reasoning") private var reasoning = "medium"
    @FocusState private var inputFocus: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            headerCard
                            if messages.isEmpty {
                                emptyState
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
                VStack(spacing: 0) {
                    Divider()
                    reasoningRow
                    attachBar
                    InputBar(text: $input, sending: sending, onSend: send)
                }
                .background(.regularMaterial)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 6, matching: .images)
            .photosPicker(isPresented: $showVideoPicker, selection: $videoItem, matching: .videos)
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: false, onCompletion: handleFilePick)
            .sheet(isPresented: $showCamera) {
                CameraPicker { img in
                    if let data = img.jpegData(compressionQuality: 0.65) {
                        pendingAtts.append(ChatAttachment(name: "拍照_\(Self.stamp()).jpg", kind: "image", mime: "image/jpeg", data: data))
                    }
                }
                .ignoresSafeArea()
            }
            .task { await store.loadChatModel() }
            .onChange(of: photoItems) { _, items in processPhotos(items) }
            .onChange(of: videoItem) { _, item in processVideo(item) }
        }
    }

    // MARK: - 空状态 + 建议

    private let suggestions = ["帮我写一封请假邮件", "用通俗语言解释量子纠缠", "制定一周健身计划"]

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 84, height: 84)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 36)
            VStack(spacing: 5) {
                Text("开始新对话").font(.headline).foregroundStyle(.secondary)
                Text("发送消息、图片或文件，AI 为你解答").font(.footnote).foregroundStyle(.tertiary)
            }
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        input = s
                        inputFocus = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(s)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.circle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.top, 20)
    }

    // MARK: - 顶部卡片：第一条消息 + 模型配置

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let first = messages.first(where: { $0.role == "user" }) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(first.content.isEmpty ? "[附件消息]" : first.content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("新对话 · 发送第一条消息开始")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Divider()
            modelRow
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)
    }

    private var modelRow: some View {
        Button {
            if !store.chatConfigured { router.tab = 1 }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(store.chatConfigured ? Color.blue : Color.orange)
                if store.chatConfigured {
                    Text("模型：\(store.chatModelName)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("已配置")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("AI 模型未添加")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("去添加 ›")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 推理强度 + 附件栏

    private var reasoningRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("推理强度")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $reasoning) {
                Text("关闭").tag("off")
                Text("低").tag("low")
                Text("中").tag("medium")
                Text("高").tag("high")
            }
            .pickerStyle(.segmented)
            .frame(width: 228)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var attachBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                attachButton("photo", "照片") { showPhotoPicker = true }
                attachButton("video.fill", "视频") { showVideoPicker = true }
                attachButton("camera.fill", "拍照") { showCamera = true }
                attachButton("paperclip", "文件") { showFilePicker = true }
                if loadingAtt { ProgressView().controlSize(.small) }
                Spacer()
                if !pendingAtts.isEmpty {
                    Text("已加 \(pendingAtts.count) 个附件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if !pendingAtts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAtts) { a in
                            AttChip(att: a) {
                                pendingAtts.removeAll { $0.id == a.id }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func attachButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.10), in: Circle())
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 发送

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAtts.isEmpty), !sending else { return }
        input = ""; inputFocus = false
        let atts = pendingAtts
        pendingAtts = []
        messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970), role: "user", content: text, attachments: atts))
        sending = true
        Task {
            do {
                let reply = try await store.sendChat(sessionId: sessionId, content: text, attachments: atts, reasoning: reasoning)
                if sessionId == 0 { sessionId = reply.sessionId }
                if reply.degraded == true { store.toast = "当前模型不支持图片，已按附件说明回答" }
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: reply.reply))
            } catch {
                messages.append(ChatMessage(id: Int64(Date().timeIntervalSince1970) + 1, role: "assistant", content: "⚠️ \(error.localizedDescription)"))
            }
            sending = false
        }
    }

    private func newChat() {
        messages = []; sessionId = 0; pendingAtts = []
    }

    // MARK: - 附件处理

    private func processPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingAtt = true
        Task {
            for (idx, item) in items.enumerated() {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    let data = Self.downscaleJPEG(raw) ?? raw
                    pendingAtts.append(ChatAttachment(name: "照片\(Self.stamp())_\(idx + 1).jpg", kind: "image", mime: "image/jpeg", data: data))
                }
            }
            photoItems = []
            loadingAtt = false
        }
    }

    private func processVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingAtt = true
        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                guard let data, !data.isEmpty else { throw APIError(message: "视频读取失败", code: "ATTACHMENT", status: 0) }
                guard data.count <= 20 * 1024 * 1024 else {
                    store.toast = "视频过大（限 20MB）"
                    videoItem = nil
                    loadingAtt = false
                    return
                }
                let ext = (item.supportedContentTypes.first?.preferredFilenameExtension ?? "mp4").lowercased()
                pendingAtts.append(ChatAttachment(name: "视频\(Self.stamp()).\(ext)", kind: "video", mime: Self.mime(for: ext), data: data))
            } catch {
                store.toast = "视频读取失败：\(error.localizedDescription)"
            }
            videoItem = nil
            loadingAtt = false
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 15 * 1024 * 1024 else {
                    store.toast = "文件过大（限 15MB）"
                    return
                }
                let ext = url.pathExtension.lowercased()
                let kind = ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) ? "image" : (["mp4", "mov", "m4v"].contains(ext) ? "video" : "file")
                pendingAtts.append(ChatAttachment(name: url.lastPathComponent, kind: kind, mime: Self.mime(for: ext), data: data))
            } catch {
                store.toast = "读取文件失败"
            }
        }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        return f.string(from: Date())
    }

    static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov", "m4v": return "video/quicktime"
        case "pdf": return "application/pdf"
        case "txt", "md": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    /// 压缩图片到长边 1568px / 质量 0.65，控制 base64 体积
    static func downscaleJPEG(_ data: Data, maxDim: CGFloat = 1568, quality: CGFloat = 0.65) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSide = max(img.size.width, img.size.height)
        if maxSide <= maxDim && data.count < 2_000_000 { return data }
        let scale = min(1, maxDim / maxSide)
        let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let out = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        return out.jpegData(compressionQuality: quality)
    }
}

/// 待发送附件圆片
struct AttChip: View {
    let att: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: att.icon).font(.caption2).foregroundStyle(.blue)
            Text(att.name).font(.caption2).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
            Text(att.sizeLabel).font(.caption2).foregroundStyle(.tertiary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }
}

struct ChatMessage: Identifiable {
    let id: Int64
    let role: String
    let content: String
    var attachments: [ChatAttachment] = []
}

struct MessageBubble: View {
    let msg: ChatMessage
    var isUser: Bool { msg.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                if !msg.attachments.isEmpty {
                    attView
                }
                if !msg.content.isEmpty {
                    Text(msg.content)
                        .font(.subheadline)
                        .foregroundStyle(isUser ? .white : .primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser
                    ? LinearGradient(colors: [.blue, Color(red: 0.2, green: 0.45, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color(uiColor: .secondarySystemGroupedBackground)],
                                     startPoint: .top, endPoint: .bottom),
                in: isUser
                    ? UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 5, style: .continuous)
                    : UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
            )
            .shadow(color: Color.black.opacity(isUser ? 0.1 : 0.04), radius: 4, y: 2)
            if !isUser { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var attView: some View {
        let images = msg.attachments.filter { $0.kind == "image" }
        let others = msg.attachments.filter { $0.kind != "image" }
        if !images.isEmpty {
            let cols = images.count > 1 ? [GridItem(.adaptive(minimum: 96), spacing: 6)] : [GridItem(.fixed(190))]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(images) { a in
                    if let img = UIImage(data: a.data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 190, maxHeight: 190)
                            .frame(minWidth: 96, minHeight: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        if !others.isEmpty {
            VStack(spacing: 5) {
                ForEach(others) { a in
                    HStack(spacing: 6) {
                        Image(systemName: a.icon).font(.caption2)
                        Text(a.name).font(.caption2).lineLimit(1)
                        Text(a.sizeLabel).font(.caption2).opacity(0.6)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(isUser ? 0.14 : 0.06), in: Capsule())
                    .foregroundStyle(isUser ? .white : .primary)
                }
            }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// 拍照组件（无摄像头设备自动回退相册）
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
