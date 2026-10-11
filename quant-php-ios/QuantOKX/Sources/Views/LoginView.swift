import SwiftUI

/// 登录 / 注册页（Apple 极简浅色风格）
struct LoginView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    @State private var mode: Int = 0          // 0 登录 / 1 注册
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirm: String = ""
    @State private var email: String = ""
    @State private var localError: String = ""
    @State private var connOK: Bool?
    @State private var connMsg: String = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    // 品牌
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.blue)
                                .frame(width: 68, height: 68)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("QuantOKX")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("OKX 现货与永续量化控制台")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 26)

                    // 分段切换
                    Picker("", selection: $mode) {
                        Text("登录").tag(0)
                        Text("注册").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    // 表单
                    VStack(spacing: 12) {
                        FieldRow(icon: "server.rack", placeholder: "服务器地址，如 http://[2404:1:2::be]", text: $serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        FieldRow(icon: "person.fill", placeholder: "用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if mode == 1 {
                            FieldRow(icon: "envelope.fill", placeholder: "邮箱（可选）", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                        }

                        SecureFieldRow(icon: "lock.fill", placeholder: mode == 0 ? "密码" : "密码（至少 8 位）", text: $password)

                        if mode == 1 {
                            SecureFieldRow(icon: "lock.rotation", placeholder: "确认密码", text: $confirm)
                        }
                    }

                    // 连通性测试
                    Button {
                        Task {
                            connOK = nil
                            let r = await store.testConnection(url: serverURL)
                            connOK = r.ok
                            connMsg = r.message
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if store.busy {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text("测试连接")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let ok = connOK {
                        HStack(spacing: 6) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? Color.green : Color.red)
                            Text(connMsg)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 主按钮
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if store.busy { ProgressView().tint(.white) }
                            Text(mode == 0 ? "登 录" : "注册并登录")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(store.busy)

                    // 错误卡
                    if !(store.loginError.isEmpty ? localError : store.loginError).isEmpty {
                        let msg = !store.loginError.isEmpty ? store.loginError : localError
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(msg).font(.footnote).foregroundStyle(.primary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
            }
        }
        .onAppear { serverURL = config.serverURL }
    }

    private func submit() async {
        localError = ""
        store.loginError = ""
        guard !serverURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            localError = "请填写服务器地址"
            return
        }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            localError = "请填写用户名"
            return
        }
        if mode == 1 {
            guard password.count >= 8 else { localError = "密码至少 8 位"; return }
            guard password == confirm else { localError = "两次输入的密码不一致"; return }
        }
        config.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        if mode == 0 {
            await store.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
        } else {
            await store.register(username: username.trimmingCharacters(in: .whitespaces),
                                 password: password, confirm: confirm, email: email)
        }
    }
}

/// 带图标的输入框（白底圆角）
struct FieldRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.tertiary))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SecureFieldRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.tertiary))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
