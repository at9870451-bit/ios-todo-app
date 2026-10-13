import SwiftUI

/// 设置页：分类入口（AI 模型配置 / 人设 / 外观）+ 服务器 + 退出
struct SettingsScreen: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var ps: ProviderStore
    @EnvironmentObject var bg: BackgroundStore
    @AppStorage("persona.prompt") private var personaPrompt = ""

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
                                settingIcon("cpu", .blue)
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

                    Section("服务器") {
                        HStack {
                            Text("地址").font(.subheadline)
                            Spacer()
                            Text(config.serverURL.isEmpty ? "未配置" : config.serverURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Section {
                        Button("退出登录", role: .destructive) { config.loggedIn = false }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var subtitleForProviders: String {
        if let a = ps.active {
            return "使用中 · \(a.label)"
        }
        return ps.providers.isEmpty ? "未添加 · 点进去配置" : "\(ps.providers.count) 个配置"
    }

    private func settingIcon(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.gradient)
            .frame(width: 32, height: 32)
            .overlay(Image(systemName: name).font(.system(size: 13)).foregroundStyle(.white))
    }
}
