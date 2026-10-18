import SwiftUI
import PhotosUI

// MARK: - AI 服务商列表（类 Minis：分组 + 状态点 + 掩码 Key）

struct ProviderListView: View {
    @EnvironmentObject var ps: ProviderStore
    @State private var showTypePicker = false
    @State private var editTarget: ProviderStore.Provider?
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ProviderStore.Kind.allCases) { kind in
                    let items = ps.providers.filter { $0.kind == kind }
                    if !items.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: kind.icon).font(.caption).foregroundStyle(Theme.accent)
                            Text(kind.title)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("· \(kind.subtitle)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(items.count) 个")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        card(items)
                    }
                }
                if ps.providers.isEmpty {
                    DEmpty(icon: "cpu", text: "还没有 AI 模型\n点右上角 + 添加主模型 / 副模型 / 语音模型 / 图片模型")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("AI 模型配置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTypePicker = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showTypePicker, onDismiss: {}) {
            ProviderTypePicker { kind, vendor, label in
                editTarget = ProviderStore.Provider(label: label, vendor: vendor, kind: kind, apiKey: "")
                showEditSheet = true
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let target = editTarget {
                ProviderEditView(provider: target, isNew: !ps.providers.contains(where: { $0.id == target.id }))
            }
        }
    }

    private func card(_ items: [ProviderStore.Provider]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                row(p)
                if idx < items.count - 1 { Divider().padding(.leading, 52) }
            }
        }
        .glassPanel(18)
    }

    private func row(_ p: ProviderStore.Provider) -> some View {
        Button {
            editTarget = p
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                // Operit 风格：厂商色 squircle 图标
                SquircleIcon(system: p.kind.icon, size: 40, tinted: p.apiKey.isEmpty)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if ps.activeId == p.id && p.kind == .main {
                            Text("使用中")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(p.model.isEmpty ? "未设置模型 · \(p.maskedKey)" : "\(p.model) · \(p.maskedKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if ps.activeId != p.id && p.kind == .main {
                Button { ps.activate(p) } label: { Label("设为当前使用", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { ps.remove(p) } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// MARK: - 添加服务商类型选择（官方 / 第三方）

struct ProviderTypePicker: View {
    let onPick: (ProviderStore.Kind, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ProviderStore.Kind = .main

    struct Option: Identifiable {
        let id: String
        let name: String
        let sub: String
        let icon: String
        let color: Color
        let label: String
    }

    private let official: [Option] = [
        Option(id: "openai", name: "OpenAI", sub: "GPT · o 系列与官方端点", icon: "brain.filled.head.profile", color: Theme.heroBlue, label: "OpenAI"),
        Option(id: "deepseek", name: "DeepSeek", sub: "深度求索官方 API", icon: "whale", color: Theme.accent, label: "DeepSeek"),
        Option(id: "moonshot", name: "Moonshot Kimi", sub: "Kimi 系列模型", icon: "moon.stars.fill", color: Theme.heroBlue, label: "Kimi"),
        Option(id: "grok", name: "xAI (Grok)", sub: "支持 Grok 系列模型", icon: "x.squareroot", color: Theme.heroBlue, label: "Grok"),
        Option(id: "openrouter", name: "OpenRouter", sub: "聚合 GPT、Claude、Gemini 等主流模型", icon: "arrow.triangle.branch", color: Theme.heroSky, label: "OpenRouter"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("模型角色")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(ProviderStore.Kind.allCases) { k in
                            Button {
                                kind = k
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: k.icon)
                                        .font(.subheadline)
                                        .foregroundStyle(kind == k ? .white : Theme.accent)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(k.title).font(.subheadline.weight(kind == k ? .semibold : .regular))
                                        Text(k.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if kind == k {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(kind == .tts ? Theme.warn : Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(kind == k ? (k == .tts ? Theme.warn.opacity(0.10) : Theme.accent.opacity(0.10)) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassPanel(16)

                    // Operit 开源厂商目录（仅列出与 OpenAI 协议兼容的，可直接用）
                    ForEach(AIVendorCatalog.groups, id: \.self) { g in
                        let vs = AIVendorCatalog.vendors(in: g).filter { v in
                            v.base.isEmpty || v.base.contains("/chat/completions") || v.base.contains("/responses")
                        }
                        if !vs.isEmpty {
                            Text(g + "厂商")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                            card(vs.map { v in
                                Option(id: v.key,
                                       name: v.name,
                                       sub: v.model.isEmpty ? (v.base.isEmpty ? "自定义端点" : v.base) : "\(v.model) · \(v.base.replacingOccurrences(of: "https://", with: ""))",
                                       icon: "cpu",
                                       color: Theme.accent,
                                       label: v.name)
                            })
                        }
                    }

                    Text("自定义 / 其他")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    card([
                        Option(id: "custom", name: "自定义兼容 API", sub: "任意 OpenAI 兼容端点（Chat / Responses / TTS / Images）", icon: "slider.horizontal.3", color: .gray, label: "自定义"),
                    ])

                    Text("您可以添加同一 AI 服务商的多个实例（例如工作和个人账户）。角色决定它出现在设置页的哪个分组；语音模型需支持 OpenAI 风格 /v1/audio/speech。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .navigationTitle("添加 AI 模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func card(_ opts: [Option]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(opts.enumerated()), id: \.element.id) { idx, o in
                Button {
                    onPick(kind, o.id, o.label)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(o.color)
                            .frame(width: 38, height: 38)
                            .overlay(Image(systemName: o.icon).font(.system(size: 15)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(o.sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < opts.count - 1 { Divider().padding(.leading, 64) }
            }
        }
        .glassPanel(18)
    }
}

// MARK: - 服务商配置表单（标签 / Key / 地址 / API 格式）

struct ProviderEditView: View {
    @EnvironmentObject var ps: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @State var provider: ProviderStore.Provider
    let isNew: Bool

    @State private var showKey = false
    @State private var models: [String] = []
    @State private var verifying = false
    @State private var verifyOK: Bool?
    @State private var verifyMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field(title: "标签") {
                        TextField("如 OpenAI 1", text: $provider.label)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    field(title: "模型角色") {
                        Picker("", selection: $provider.kind) {
                            ForEach(ProviderStore.Kind.allCases) { k in
                                Label(k.title + " · " + k.subtitle, systemImage: k.icon).tag(k)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    field(title: "API Key") {
                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-...", text: $provider.apiKey)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("sk-...", text: $provider.apiKey)
                                }
                            }
                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text("密钥保存在本机沙盒；保存后同步至你的服务器用于调用，不会发送给任何第三方。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // 验证连接 + 读取模型列表
                    Button {
                        verify()
                    } label: {
                        HStack(spacing: 7) {
                            if verifying {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text("验证并读取模型列表")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(.primary)
                    }
                    .disabled(verifying)

                    if let ok = verifyOK {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? Theme.ok : Theme.danger)
                            Text(verifyMsg)
                                .font(.caption)
                                .foregroundStyle(ok ? Theme.ok : Theme.danger)
                        }
                    }

                    if !models.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("选择默认模型（点击填入）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(Array(models.enumerated()), id: \.element) { idx, m in
                                            Button {
                                                provider.model = m
                                            } label: {
                                                HStack {
                                                    Text(m)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    if provider.model == m {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(Theme.accent)
                                                    }
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            if idx < models.count - 1 { Divider().padding(.leading, 14) }
                                        }
                                    }
                                }
                                .frame(maxHeight: 230)
                            }
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    field(title: "自定义 API 地址（可选）") {
                        VStack(spacing: 0) {
                            TextField("https://api.\(provider.vendor == "custom" ? "example.com" : ProviderStore.defaultBase(provider.vendor).replacingOccurrences(of: "https://api.", with: ""))", text: $provider.baseURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            Divider().padding(.leading, 14)
                            Toggle(isOn: $provider.autoV1) {
                                Text("自动附加 \"/v1\"").font(.subheadline)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text("留空则使用官方默认端点。\"/v1\" 会自动附加 — 只需输入基础主机地址。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    field(title: "API 格式") {
                        Picker("", selection: $provider.apiFormat) {
                            ForEach(ProviderStore.APIFormat.allCases) { f in
                                Text(f.title).tag(f)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text(provider.apiFormat.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    field(title: provider.kind == .tts ? "语音模型（可选）" : (provider.kind == .image ? "图片模型（可选）" : "默认模型（可选）")) {
                        TextField(modelPlaceholder, text: $provider.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    // Operit 风格：常用模型一键填入
                    if !modelSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(modelSuggestions, id: \.self) { m in
                                    Button {
                                        provider.model = m
                                        Haptics.tap()
                                    } label: {
                                        Text(m)
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(provider.model == m ? Theme.accent.opacity(0.16) : Theme.fillGray, in: Capsule())
                                            .foregroundStyle(provider.model == m ? Theme.accent : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    if provider.kind == .tts {
                        field(title: "音色（可选）") {
                            TextField("alloy / ash / nova / shaley", text: $provider.ttsVoice)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Text("需服务商支持 OpenAI 风格 /v1/audio/speech；不填模型则默认 tts-1。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    DButton(title: isNew ? "添加 AI 模型" : "保存修改", icon: "checkmark") {
                        save()
                    }
                    .padding(.top, 6)

                    if !isNew {
                        Button {
                            ps.remove(provider)
                            dismiss()
                        } label: {
                            Text("删除此模型")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .onAppear {
                // Operit 厂商目录：新建时预填默认端点与模型
                if isNew, let v = AIVendorCatalog.vendor(provider.vendor) {
                    if provider.model.isEmpty { provider.model = v.model }
                    if provider.baseURL.isEmpty, !v.base.isEmpty {
                        provider.baseURL = AIVendorCatalog.rootBase(provider.vendor)
                    }
                    if !v.format.isEmpty {
                        provider.apiFormat = v.format == "responses" ? .responses : .chat
                    }
                }
            }
            .navigationTitle(isNew ? "配置 \(provider.label)" : "编辑 \(provider.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                }
            }
        }
    }

    private var modelPlaceholder: String {
        switch provider.kind {
        case .tts: return "如 tts-1 / tts-1-hd / cosyvoice-v1"
        case .image: return "如 dall-e-3 / gpt-image-1 / flux-schnell"
        default: return "如 gpt-4o / deepseek-chat"
        }
    }

    /// 常用模型速选（借鉴 Operit 官方预设）
    private var modelSuggestions: [String] {
        switch provider.vendor {
        case "openai": return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        case "deepseek": return ["deepseek-chat", "deepseek-reasoner"]
        case "moonshot": return ["moonshot-v1-8k", "moonshot-v1-32k", "kimi-latest"]
        case "grok": return ["grok-3", "grok-3-mini"]
        case "openrouter": return ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.0-flash-001"]
        default: return []
        }
    }

    private func field<V: View>(title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        var p = provider
        p.label = p.label.trimmingCharacters(in: .whitespaces)
        if p.label.isEmpty { p.label = "AI 模型" }
        if isNew {
            ps.add(p)
        } else {
            ps.update(p)
        }
        dismiss()
    }

    /// 用地址+Key 直连 /v1/models 验证并拉取模型列表
    private func verify() {
        verifying = true
        verifyOK = nil
        models = []
        Task {
            do {
                let list = try await ps.fetchModels(provider)
                models = list
                verifyOK = true
                verifyMsg = "验证成功，共 \(list.count) 个模型"
            } catch {
                verifyOK = false
                verifyMsg = error.localizedDescription
            }
            verifying = false
        }
    }
}
