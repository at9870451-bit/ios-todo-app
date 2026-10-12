import SwiftUI

/// 设置页：AI 配置 + 服务器 + 退出
struct SettingsScreen: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @AppStorage("ai_endpoint") var aiEndpoint = "https://api.deepseek.com"
    @AppStorage("ai_key") var aiKey = ""
    @AppStorage("ai_model") var aiModel = "deepseek-flash"
    @AppStorage("system_prompt") var systemPrompt = ""
    @AppStorage("memory") var memory = ""
    @State private var testing = false
    @State private var testResult = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    HStack { Text("地址").foregroundStyle(.secondary); Spacer(); Text(config.serverURL).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Section("AI 模型配置") {
                    TextField("API 地址", text: $aiEndpoint).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("API Key", text: $aiKey).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("模型", text: $aiModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button {
                        testing = true; testResult = ""
                        Task { testResult = await store.saveChatConfig(endpoint: aiEndpoint, key: aiKey, model: aiModel); testing = false }
                    } label: {
                        if testing { ProgressView().controlSize(.small) } else { Text("测试连接").font(.subheadline) }
                    }
                    if !testResult.isEmpty { Text(testResult).font(.caption).foregroundStyle(testResult.contains("200") ? .green : .red) }
                }
                Section("人设 / 系统提示词") {
                    TextEditor(text: $systemPrompt).frame(minHeight: 60).font(.subheadline)
                }
                Section("AI 记忆") {
                    TextEditor(text: $memory).frame(minHeight: 40).font(.subheadline)
                    Text("AI 会记住这段内容作为长期记忆").font(.caption2).foregroundStyle(.tertiary)
                }
                Section {
                    Button("退出登录", role: .destructive) { config.loggedIn = false }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
