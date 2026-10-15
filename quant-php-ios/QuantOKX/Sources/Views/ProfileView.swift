import SwiftUI

/// 我的：未登录 → 登录/注册表单；已登录 → 账号卡片 + 退出
struct ProfileView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    var onLoggedIn: (() -> Void)? = nil

    @State private var mode: Int = 0          // 0 登录 / 1 注册
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
        .onChange(of: config.loggedIn) { _, now in
            if now { onLoggedIn?() }
        }
    }

    // MARK: - 已登录：账号卡片

    private var loggedInSection: some View {
        VStack(spacing: 14) {
            // 账号卡：头像 + 名字/等级徽章 + 连接状态（对齐参考稿个人中心）
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.heroGradient)
                        .frame(width: 58, height: 58)
                    Text(String(config.username.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .shadow(color: Theme.accent.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(config.username)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(levelBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isPaid ? Theme.accent : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                isPaid ? AnyShapeStyle(Theme.accent.opacity(0.14))
                                       : AnyShapeStyle(Color.white.opacity(0.72)),
                                in: Capsule()
                            )
                        Circle().fill(Theme.ok).frame(width: 6, height: 6)
                        Text("已连接")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .solidCard(Theme.radiusL)

            // 会员入口卡：跟随等级主题（黄金/钻石/至尊），未登录为橙色引导
            NavigationLink {
                MembershipView()
            } label: {
                let t = Theme.tierTheme(isPaid ? config.membershipLevel : nil)
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isPaid ? AnyShapeStyle(t.fg) : AnyShapeStyle(Color.white))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPaid ? amoreLevelName(config.membershipLevel) : "开通会员")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isPaid ? AnyShapeStyle(t.fg) : AnyShapeStyle(Color.white))
                        Text(isPaid ? "查看权益与续费" : "解锁全部高级权益")
                            .font(.caption)
                            .foregroundStyle(isPaid ? AnyShapeStyle(t.sub) : AnyShapeStyle(Color.white.opacity(0.88)))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isPaid ? AnyShapeStyle(t.fg) : AnyShapeStyle(Color.white.opacity(0.9)))
                }
                .padding(14)
                .background(isPaid ? AnyShapeStyle(t.bg) : AnyShapeStyle(Theme.accent), in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PressableButtonStyle())

            // 退出登录（白卡）
            Button {
                Task { await store.logout() }
            } label: {
                HStack(spacing: 8) {
                    if store.busy { ProgressView().tint(Theme.danger) }
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text("退出登录")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .solidCard(Theme.radiusM)
                .foregroundStyle(Theme.danger)
            }
            .disabled(store.busy)
        }
    }

    private var isPaid: Bool {
        config.membershipLevel != "" && config.membershipLevel != "free"
    }

    private var levelBadge: String {
        isPaid ? amoreLevelName(config.membershipLevel) : "免费版"
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
                    .foregroundStyle(Theme.warn)
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
                        let r = await store.testConnection(url: config.serverURL)
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
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .foregroundStyle(ok ? Theme.ok : Theme.danger)
                    Text(connMsg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !(store.loginError.isEmpty ? localError : store.loginError).isEmpty {
                let msg = !store.loginError.isEmpty ? store.loginError : localError
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text(msg).font(.footnote).foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
            }
        }
    }

    private func submit() async {
        localError = ""
        store.loginError = ""
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            localError = "请填写用户名"
            return
        }
        if mode == 1 {
            guard password.count >= 8 else { localError = "密码至少 8 位"; return }
            guard password == confirm else { localError = "两次输入的密码不一致"; return }
        }
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
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
