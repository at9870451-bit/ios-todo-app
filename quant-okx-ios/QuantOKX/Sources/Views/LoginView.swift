import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: BackendStore
    @EnvironmentObject private var config: AppConfig

    @State private var mode = 0          // 0 = 登录，1 = 注册
    @State private var username = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var localError: String?
    @FocusState private var focusedField: Int?

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.indigo, Color.purple],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    formCard
                    errorCard
                }
                .padding(24)
            }
        }
        .onAppear {
            if !config.backendURL.isEmpty { }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.white)
            Text("QuantOKX")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
            Text(config.backendURL.isEmpty ? "先在下方填后台地址" : "OKX 量化交易控制台")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(.top, 40)
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            Picker("模式", selection: $mode) {
                Text("登录").tag(0)
                Text("注册").tag(1)
            }
            .pickerStyle(.segmented)

            TextField("后台地址（如 http://1.2.3.4:8080）", text: $config.backendURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))
                .font(.callout.monospaced())

            TextField("用户名（3-20 位字母/数字/下划线）", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: 0)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))

            SecureField("密码（至少 6 位）", text: $password)
                .focused($focusedField, equals: 1)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))

            if mode == 1 {
                SecureField("确认密码", text: $password2)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if store.busy {
                        ProgressView().tint(Color.white).scaleEffect(0.8)
                    }
                    Text(mode == 0 ? "登录" : "注册并进入")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white)
            .foregroundStyle(Color.indigo)
            .disabled(!canSubmit || store.busy)

            if mode == 1 && !password2.isEmpty && password != password2 {
                Text("两次密码不一致")
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var errorCard: some View {
        if let e = localError ?? store.authError {
            Text(e)
                .font(.footnote)
                .foregroundStyle(Color.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func submit() {
        guard canSubmit else { return }
        guard !config.backendURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            localError = "请先填写后台地址"
            return
        }
        localError = nil
        config.save()
        let u = username.trimmingCharacters(in: .whitespaces)
        if mode == 0 {
            Task { await store.login(username: u, password: password) }
        } else {
            guard password == password2 else { return }
            Task { await store.register(username: u, password: password) }
        }
    }
}