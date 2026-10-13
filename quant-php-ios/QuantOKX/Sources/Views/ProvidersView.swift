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
                ForEach(ProviderStore.APIFormat.allCases) { fmt in
                    let items = ps.providers.filter { $0.apiFormat == fmt }
                    if !items.isEmpty {
                        Text(fmt.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                        card(items)
                    }
                }
                if ps.providers.isEmpty {
                    DEmpty(icon: "cpu", text: "还没有 AI 服务商\n点右上角 + 添加官方或第三方模型")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("AI 服务商")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTypePicker = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showTypePicker, onDismiss: {}) {
            ProviderTypePicker { vendor, label in
                editTarget = ProviderStore.Provider(label: label, vendor: vendor, apiKey: "")
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ p: ProviderStore.Provider) -> some View {
        Button {
            editTarget = p
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(p.apiKey.isEmpty ? Color(uiColor: .systemGray3) : Color.green)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if ps.activeId == p.id {
                            Text("使用中")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("API Key · \(p.maskedKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(p.model.isEmpty ? ProviderStore.defaultBase(p.vendor) : "模型 · \(p.model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if ps.activeId != p.id {
                Button { ps.activate(p) } label: { Label("设为当前使用", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { ps.remove(p) } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// MARK: - 添加服务商类型选择（官方 / 第三方）

struct ProviderTypePicker: View {
    let onPick: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    struct Option: Identifiable {
        let id: String
        let name: String
        let sub: String
        let icon: String
        let color: Color
        let label: String
    }

    private let official: [Option] = [
        Option(id: "openai", name: "OpenAI", sub: "GPT · o 系列与官方端点", icon: "brain.filled.head.profile", color: .green, label: "OpenAI"),
        Option(id: "deepseek", name: "DeepSeek", sub: "深度求索官方 API", icon: "whale", color: .blue, label: "DeepSeek"),
        Option(id: "moonshot", name: "Moonshot Kimi", sub: "Kimi 系列模型", icon: "moon.stars.fill", color: .indigo, label: "Kimi"),
        Option(id: "grok", name: "xAI (Grok)", sub: "支持 Grok 系列模型", icon: "x.squareroot", color: .black, label: "Grok"),
        Option(id: "openrouter", name: "OpenRouter", sub: "聚合 GPT、Claude、Gemini 等主流模型", icon: "arrow.triangle.branch", color: .cyan, label: "OpenRouter"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("官方模型")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    card(official)

                    Text("第三方 / 兼容 API")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    card([
                        Option(id: "custom", name: "自定义兼容 API", sub: "任意 OpenAI 兼容端点（Chat / Responses）", icon: "slider.horizontal.3", color: .gray, label: "自定义"),
                    ])

                    Text("您可以添加同一 AI 服务商的多个实例（例如工作和个人账户）。OpenAI 格式同时支持 Chat Completions 与 Responses 两种 API。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .navigationTitle("添加 AI 服务商")
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
                    onPick(o.id, o.label)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(o.color.gradient)
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - 服务商配置表单（标签 / Key / 地址 / API 格式）

struct ProviderEditView: View {
    @EnvironmentObject var ps: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @State var provider: ProviderStore.Provider
    let isNew: Bool

    @State private var showKey = false

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

                    field(title: "默认模型（可选）") {
                        TextField("如 gpt-4o / deepseek-chat", text: $provider.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    DButton(title: isNew ? "添加 AI 服务商" : "保存修改", icon: "checkmark") {
                        save()
                    }
                    .padding(.top, 6)

                    if !isNew {
                        Button {
                            ps.remove(provider)
                            dismiss()
                        } label: {
                            Text("删除此服务商")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
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
        if p.label.isEmpty { p.label = "AI 服务商" }
        if isNew {
            ps.add(p)
        } else {
            ps.update(p)
        }
        dismiss()
    }
}
