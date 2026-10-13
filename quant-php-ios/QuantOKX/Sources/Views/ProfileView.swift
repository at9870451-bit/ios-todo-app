import SwiftUI

/// 我的：未登录 → 登录/注册表单；已登录 → 账号卡片 + 退出
struct ProfileView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    var onLoggedIn: (() -> Void)? = nil

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
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        if config.loggedIn {
                            loggedInSection
                        } else {
                            authSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { serverURL = config.serverURL }
        .onChange(of: config.loggedIn) { _, now in
            if now { onLoggedIn?() }
        }
    }

    // MARK: - 已登录：账号卡片

    private var loggedInSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.heroGradient)
                        .frame(width: 66, height: 66)
                    Text(String(config.username.prefix(1)).uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 4) {
                    Text(config.username)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("已登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if config.membershipLevel != "" && config.membershipLevel != "free" {
                    Text("会员")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .solidCard(18)

            VStack(spacing: 0) {
                HStack {
                    Label("服务器", systemImage: "server.rack").font(.subheadline)
                    Spacer()
                    Text(config.serverURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(14)
            }
            .solidCard(14)

            Button {
                Task { await store.logout() }
            } label: {
                HStack {
                    if store.busy { ProgressView().tint(.red) }
                    Text("退出登录")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .solidCard(14)
                .foregroundStyle(.red)
            }
            .disabled(store.busy)
        }
    }

    // MARK: - 未登录：登录 / 注册表单

    private var authSection: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.heroGradient)
                        .frame(width: 58, height: 58)
                    Text("AI")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("Amore")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("登录后开始对话，历史会话云端同步")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Picker("", selection: $mode) {
                Text("登录").tag(0)
                Text("注册").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                FieldRow(icon: "server.rack", placeholder: "服务器地址，如 http://154.12.16.204:8080", text: $serverURL)
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
            .padding(14)
            .glassPanel(16)

            HStack(spacing: 10) {
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
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if store.busy { ProgressView().tint(.white) }
                        Text(mode == 0 ? "登 录" : "注册并登录")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.28), radius: 7, x: 0, y: 3)
                    .foregroundStyle(.white)
                }
                .disabled(store.busy)
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
        }
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

/// 未登录占位（对话/设置页在未登录时显示）
struct SignedOutHint: View {
    let gotoProfile: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 46))
                    .foregroundStyle(.tertiary)
                Text("尚未登录").font(.headline)
                Text("登录后即可使用 AI 对话与历史会话")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: gotoProfile) {
                    Text("去登录 / 注册")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.28), radius: 7, x: 0, y: 3)
                        .foregroundStyle(.white)
                }
                .padding(.top, 6)
            }
            .padding(30)
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
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
