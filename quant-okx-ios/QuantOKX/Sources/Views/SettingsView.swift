import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: BackendStore

    @State private var url = ""
    @State private var token = ""
    @State private var pingResult: String?
    @State private var pinging = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: 连接状态
                Section {
                    HStack {
                        Circle()
                            .fill(store.connected ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                        Text(store.connected ? "后台在线" : "后台未连接")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if let v = store.serverVersion {
                            Text("v\(v)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let e = store.lastError, !store.connected {
                        Text(e).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.connected {
                        HStack {
                            Text("最后刷新").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(store.lastRefreshText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("连接状态")
                }

                // MARK: 后台地址
                Section {
                    HStack {
                        Text("地址")
                        TextField("http://1.2.3.4:8080", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .font(.callout.monospaced())
                    }
                    HStack {
                        Text("访问令牌")
                        SecureField("X-Auth-Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                            .font(.callout.monospaced())
                    }
                } header: {
                    Text("Java 后台")
                } footer: {
                    Text("填后台服务地址（含端口）。令牌要和服务器 application.yml 里的 quantokx.auth-token 一致。\n\nApp 里不保存任何 OKX 密钥——密钥只在服务器上，这样手机丢了也安全。")
                }

                // MARK: 操作
                Section {
                    Button {
                        save()
                    } label: {
                        Label("保存并重连", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(url.isEmpty)

                    Button {
                        Task { await ping() }
                    } label: {
                        HStack {
                            Label("测试后台连通性", systemImage: "antenna.radiowaves.left.and.right")
                            if pinging { Spacer(); ProgressView().scaleEffect(0.8) }
                        }
                    }
                    .disabled(url.isEmpty || pinging)

                    Button {
                        Task { await store.testOKX() }
                    } label: {
                        Label("测试 OKX 连接（后台发起）", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(!store.connected || store.busy)

                    if let r = pingResult {
                        Text(r)
                            .font(.caption)
                            .foregroundStyle(r.hasPrefix("✅") ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // MARK: 当前配置
                if let c = store.remoteConfig {
                    Section {
                        row("OKX 密钥", c.okxConfigured ? (c.okxApiKeyMasked ?? "已配置") : "未配置",
                            ok: c.okxConfigured)
                        row("运行模式", c.demoTrading ? "模拟盘" : "实盘", ok: c.demoTrading)
                        row("交易对", c.instId, ok: true)
                        row("策略", StrategyKind(rawValue: c.activeStrategy)?.title ?? c.activeStrategy, ok: true)
                        row("AI 决策", c.aiEnabled ? "已启用" : "未启用", ok: true)
                        row("轮询间隔", "\(c.pollSeconds) 秒", ok: true)
                        row("止盈/止损", "\(fmt(c.takeProfitPct))% / \(fmt(c.stopLossPct))%", ok: true)
                    } header: {
                        Text("后台当前配置")
                    } footer: {
                        Text("这些配置在「策略」页修改，保存在服务器上。")
                    }
                }

                // MARK: 关于
                Section {
                    HStack {
                        Text("App 版本")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/at9870451-bit/quant-okx-server")!) {
                        Label("后端项目", systemImage: "shippingbox")
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("交易逻辑全部跑在 Java 后台，App 只是控制台。\n关闭 App 不影响后台继续交易。")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                url = config.backendURL
                token = config.authToken
            }
        }
    }

    private func row(_ k: String, _ v: String, ok: Bool) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v)
                .foregroundStyle(ok ? .secondary : .orange)
                .font(.callout.monospaced())
                .lineLimit(1)
        }
    }

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(format: "%.0f", d) : String(format: "%.1f", d)
    }

    private func save() {
        config.backendURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        config.authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        config.save()
        store.attach(config)
        store.startPolling(interval: 5)
        Task { await store.refreshAll() }
    }

    private func ping() async {
        pinging = true
        defer { pinging = false }
        // 先把当前输入框的值应用上再测
        config.backendURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        config.authToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        config.save()
        store.attach(config)
        pingResult = await store.pingBackend()
    }
}
