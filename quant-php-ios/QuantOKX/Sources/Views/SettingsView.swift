import SwiftUI

/// 设置页：分类入口（AI 模型配置 / 人设 / 外观）+ 朗读
struct SettingsScreen: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var ps: ProviderStore
    @EnvironmentObject var bg: BackgroundStore
    @AppStorage("persona.prompt") private var personaPrompt = ""
    @AppStorage("tts.engine") private var ttsEngine = "local"       // local 本地语音 / model 语音模型
    @AppStorage("tts.providerId") private var ttsProviderId = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    Section("个性化") {
                        NavigationLink {
                            ProviderListView()
                        } label: {
                            HStack(spacing: 12) {
                                settingIcon("cpu", Theme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("AI 模型配置").font(.subheadline.weight(.medium))
                                    Text(subtitleForProviders)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        NavigationLink {
                            PersonaView()
                        } label: {
                            HStack(spacing: 12) {
                                settingIcon("face.smiling", .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("人设").font(.subheadline.weight(.medium))
                                    Text(personaPrompt.isEmpty ? "未设置 · 使用默认助手" : "已设置 · \(personaPrompt.prefix(18))…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        NavigationLink {
                            AppearanceView()
                        } label: {
                            HStack(spacing: 12) {
                                settingIcon("paintbrush.fill", .purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("外观").font(.subheadline.weight(.medium))
                                    Text(bg.image == nil ? "默认蓝白渐变" : "自定义背景图")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section("朗读") {
                        Picker(selection: $ttsEngine) {
                            Label("本地语音", systemImage: "iphone").tag("local")
                            Label("语音模型", systemImage: "waveform").tag("model")
                        } label: {
                            HStack(spacing: 12) {
                                settingIcon("speaker.wave.2", .teal)
                                Text("朗读引擎").font(.subheadline.weight(.medium))
                            }
                        }
                        if ttsEngine == "model" {
                            if ttsProviders.isEmpty {
                                NavigationLink {
                                    ProviderListView()
                                } label: {
                                    HStack(spacing: 12) {
                                        settingIcon("waveform.badge.plus", .orange)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("选择语音模型").font(.subheadline.weight(.medium))
                                            Text("尚未添加语音模型 · 点此前往添加")
                                                .font(.caption)
                                                .foregroundStyle(Theme.accent)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            } else {
                                Picker(selection: $ttsProviderId) {
                                    ForEach(ttsProviders) { p in
                                        Text("\(p.label) · \(p.model.isEmpty ? "tts-1" : p.model)").tag(p.id.uuidString)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        settingIcon("waveform", .indigo)
                                        Text("语音模型").font(.subheadline.weight(.medium))
                                    }
                                }
                                Text("朗读将调用所选语音模型合成（需支持 OpenAI 风格 /v1/audio/speech）")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            Text("使用设备内置语音离线朗读，无需网络")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var ttsProviders: [ProviderStore.Provider] {
        ps.providers.filter { $0.kind == .tts && !$0.apiKey.isEmpty }
    }

    private var subtitleForProviders: String {
        if let a = ps.active {
            return "使用中 · \(a.label)"
        }
        return ps.providers.isEmpty ? "未添加 · 点进去配置" : "\(ps.providers.count) 个模型"
    }

    private func settingIcon(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.gradient)
            .frame(width: 32, height: 32)
            .overlay(Image(systemName: name).font(.system(size: 13)).foregroundStyle(.white))
    }
}
