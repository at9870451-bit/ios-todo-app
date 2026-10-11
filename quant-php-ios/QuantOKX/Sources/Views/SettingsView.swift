import SwiftUI

/// 设置：服务器地址、账号信息、关于
struct SettingsView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    @State private var serverURL: String = ""
    @State private var testMsg: String = ""
    @State private var testing = false

    var body: some View {
        PageScaffold(title: "设置", subtitle: "服务器与账号") {
            // 服务器
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("服务器").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    FieldRow(icon: "server.rack", placeholder: "http://服务器地址", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    HStack(spacing: 10) {
                        PrimaryButton(title: testing ? "测试中…" : "测试连接", icon: "antenna.radiowaves.left.and.right", disabled: testing) {
                            Task {
                                testing = true
                                defer { testing = false }
                                let r = await store.testConnection(url: serverURL)
                                testMsg = r.message
                            }
                        }
                        PrimaryButton(title: "保存并重连", icon: "checkmark.circle.fill", color: Color(red: 0.16, green: 0.55, blue: 0.35)) {
                            Task {
                                config.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
                                await store.bootstrap()
                                store.toast = "服务器已更新"
                            }
                        }
                    }
                    if !testMsg.isEmpty {
                        Text(testMsg).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            // 账号
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("账号").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    InfoRow(label: "用户名", value: config.username)
                    InfoRow(label: "昵称", value: config.nickname.isEmpty ? "--" : config.nickname)
                    InfoRow(label: "角色", value: config.role == "admin" ? "管理员" : "普通用户")
                    InfoRow(label: "会员等级", value: config.membershipLevel.uppercased())
                    Divider().overlay(Color.white.opacity(0.08))
                    PrimaryButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", color: Color(red: 0.6, green: 0.2, blue: 0.2)) {
                        Task { await store.logout() }
                    }
                }
            }

            // 关于
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    InfoRow(label: "应用", value: "QuantOKX iOS")
                    InfoRow(label: "版本", value: "1.0.0")
                    InfoRow(label: "后端", value: "ThinkPHP 8.1 · PHP 8.2 · MySQL 5.7")
                    Text("本应用为 OKX 量化交易控制台 iOS 客户端，与网页端共用同一后端服务与账号体系。交易有风险，请谨慎操作。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { serverURL = config.serverURL }
    }
}
