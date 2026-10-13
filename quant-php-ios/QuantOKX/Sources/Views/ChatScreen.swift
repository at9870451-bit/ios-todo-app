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
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var pickedItems: [PhotosPickerItem] = []
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
                VStack(spacing: 8) {
                    if !pendingAtts.isEmpty {
                        pendingChips
                    }
                    statusRow
                    inputPanel
                }
                .padding(.top, 8)
                .background(.regularMaterial)
            }
            .photosPicker(isPresented: $showPicker, selection: $pickedItems, maxSelectionCount: 6, matching: .any(of: [.images, .videos]))
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
            .onChange(of: pickedItems) { _, items in processPicked(items) }
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

    // MARK: - 输入区：状态行 + 单行面板（Minis 风格）

    private var statusRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("推理强度", selection: $reasoning) {
                    Text("关闭").tag("off")
                    Text("低").tag("low")
                    Text("中").tag("medium")
                    Text("高").tag("high")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                    Text("推理 · \(Self.reasoningLabel(reasoning))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.08), in: Capsule())
            }
            if loadingAtt {
                ProgressView().controlSize(.mini)
                Text("处理附件中...").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var inputPanel: some View {
        HStack(spacing: 10) {
            Menu {
                Button { showFilePicker = true } label: {
                    Label("添加文件", systemImage: "doc")
                }
                Button { showPicker = true } label: {
                    Label("选择照片和视频", systemImage: "photo.on.rectangle")
                }
                Button { showCamera = true } label: {
                    Label("拍照", systemImage: "camera")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("添加附件")

            TextField("输入消息...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocus)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAtts.isEmpty) || sending
                            ? Color(uiColor: .systemGray3)
                            : Color.blue,
                        in: Circle()
                    )
            }
            .disabled((input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAtts.isEmpty) || sending)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// 待发送附件预览（面板上方横滚胶囊）
    private var pendingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAtts) { a in
                    AttChip(att: a) {
                        pendingAtts.removeAll { $0.id == a.id }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    static func reasoningLabel(_ r: String) -> String {
        switch r {
        case "off": return "关闭"
        case "low": return "低"
        case "high": return "高"
        default: return "中"
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

    /// 混合处理照片/视频选择结果（按内容类型分流）
    private func processPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingAtt = true
        Task {
            for (idx, item) in items.enumerated() {
                let isImage = item.supportedContentTypes.contains { $0.conforms(to: .image) }
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
                do {
                    guard let raw = try await item.loadTransferable(type: Data.self), !raw.isEmpty else {
                        throw APIError(message: "内容读取失败", code: "ATTACHMENT", status: 0)
                    }
                    if isImage {
                        let data = Self.downscaleJPEG(raw) ?? raw
                        pendingAtts.append(ChatAttachment(name: "照片\(Self.stamp())_\(idx + 1).jpg", kind: "image", mime: "image/jpeg", data: data))
                    } else if isVideo {
                        guard raw.count <= 20 * 1024 * 1024 else {
                            store.toast = "视频过大（限 20MB）"
                            continue
                        }
                        let ext = (item.supportedContentTypes.first?.preferredFilenameExtension ?? "mp4").lowercased()
                        pendingAtts.append(ChatAttachment(name: "视频\(Self.stamp())_\(idx + 1).\(ext)", kind: "video", mime: Self.mime(for: ext), data: raw))
                    } else {
                        guard raw.count <= 15 * 1024 * 1024 else {
                            store.toast = "文件过大（限 15MB）"
                            continue
                        }
                        let ext = (item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat").lowercased()
                        pendingAtts.append(ChatAttachment(name: "文件\(Self.stamp())_\(idx + 1).\(ext)", kind: "file", mime: Self.mime(for: ext), data: raw))
                    }
                } catch {
                    store.toast = "附件读取失败：\(error.localizedDescription)"
                }
            }
            pickedItems = []
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
