import SwiftUI

/// 设置页：以原生导航栏为骨架，内容使用白色分组卡片与 Liquid Glass。
struct SettingsScreen: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var ps: ProviderStore
    @EnvironmentObject var bg: BackgroundStore
    @AppStorage("persona.prompt") private var personaPrompt = ""
    @AppStorage("tts.engine") private var ttsEngine = "local"
    @AppStorage("tts.providerId") private var ttsProviderId = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spaceXL) {
                        settingsHeader
                        personalizationCard
                        speechCard
                        versionCard
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("偏好设置")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("定制你的 Amore 体验")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    private var personalizationCard: some View {
        VStack(spacing: 0) {
            settingLink(icon: "cpu", title: "AI 模型配置", subtitle: subtitleForProviders) {
                ProviderListView()
            }
            rowDivider
            settingLink(icon: "face.smiling", title: "人设", subtitle: personaPrompt.isEmpty ? "未设置 · 使用默认助手" : "已设置 · \(personaPrompt.prefix(18))…") {
                PersonaView()
            }
            rowDivider
            settingLink(icon: "paintbrush", title: "外观", subtitle: bg.image == nil ? "苹果白与蓝橙渐变" : "自定义背景图片") {
                AppearanceView()
            }
        }
        .glassPanel(Theme.radiusL)
    }

    private var speechCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeading(icon: "speaker.wave.2", title: "朗读")
            HStack(spacing: 12) {
                SquircleIcon(system: "iphone", size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("朗读引擎")
                        .font(.subheadline.weight(.semibold))
                    Text(ttsEngine == "local" ? "使用设备内置语音" : "使用已配置的语音模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("朗读引擎", selection: $ttsEngine) {
                    Text("本地语音").tag("local")
                    Text("语音模型").tag("model")
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 12)

            if ttsEngine == "model" {
                rowDivider.padding(.leading, 62)
                if ttsProviders.isEmpty {
                    settingLink(icon: "waveform.badge.plus", title: "选择语音模型", subtitle: "尚未添加语音模型 · 点此前往添加") {
                        ProviderListView()
                    }
                } else {
                    HStack(spacing: 12) {
                        SquircleIcon(system: "waveform", size: 38, tinted: true)
                        Picker("语音模型", selection: $ttsProviderId) {
                            ForEach(ttsProviders) { p in
                                Text("\(p.label) · \(p.model.isEmpty ? "tts-1" : p.model)").tag(p.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.vertical, 10)
                }
            }

            Text(ttsEngine == "local" ? "使用设备内置语音离线朗读，无需网络" : "朗读将调用所选语音模型合成（需支持 /v1/audio/speech）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.cardPadding)
                .padding(.bottom, Theme.cardPadding)
        }
        .glassPanel(Theme.radiusL)
    }

    private var versionCard: some View {
        HStack(spacing: 12) {
            SquircleIcon(system: "app.badge.fill", size: 38, tinted: true)
            Text("版本")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(Self.versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.cardPadding)
        .glassPanel(Theme.radiusL)
    }

    private func cardHeading(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.top, Theme.cardPadding)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func settingLink<Destination: View>(icon: String, title: String, subtitle: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                SquircleIcon(system: icon, size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.62))
            .frame(height: 0.8)
    }

    private var ttsProviders: [ProviderStore.Provider] {
        ps.providers.filter { $0.kind == .tts && !$0.apiKey.isEmpty }
    }

    private var subtitleForProviders: String {
        if let a = ps.active { return "使用中 · \(a.label)" }
        return ps.providers.isEmpty ? "未添加 · 点进去配置" : "\(ps.providers.count) 个模型"
    }

    private static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.9"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "31"
        return "v\(v) (\(b))"
    }
}
