import SwiftUI

/// 登录 / 注册页
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
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.09, blue: 0.16),
                         Color(red: 0.02, green: 0.03, blue: 0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    // Logo
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.56, blue: 1.0),
                                                              Color(red: 0.12, green: 0.32, blue: 0.85)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                                .shadow(color: Color.blue.opacity(0.4), radius: 16, y: 6)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("QuantOKX")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("OKX 现货与永续量化控制台")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 30)

                    // 分段切换
                    Picker("", selection: $mode) {
                        Text("登录").tag(0)
                        Text("注册").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    VStack(spacing: 14) {
                        // 服务器地址
                        FieldRow(icon: "server.rack", placeholder: "服务器地址，如 http://1.2.3.4", text: $serverURL)
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
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text("测试连接")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let ok = connOK {
                        HStack(spacing: 6) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? .green : .red)
                            Text(connMsg)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
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
                        .background(LinearGradient(colors: [Color(red: 0.29, green: 0.56, blue: 1.0),
                                                            Color(red: 0.16, green: 0.38, blue: 0.92)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .shadow(color: Color.blue.opacity(0.35), radius: 12, y: 5)
                    }
                    .disabled(store.busy)

                    // 错误卡
                    if !(store.loginError.isEmpty ? localError : store.loginError).isEmpty {
                        let msg = !store.loginError.isEmpty ? store.loginError : localError
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(msg).font(.footnote).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
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

/// 带图标的输入框
struct FieldRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 22)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 22)
            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
