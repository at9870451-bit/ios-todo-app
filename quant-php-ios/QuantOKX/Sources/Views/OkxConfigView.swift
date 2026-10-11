import SwiftUI

/// OKX API 配置：查看已有账号 + 新增/编辑
struct OkxConfigView: View {
    @EnvironmentObject var store: BackendStore

    @State private var showEditor = false
    @State private var editingMarket: String = "spot"
    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var passphrase: String = ""
    @State private var environment: String = "demo"
    @State private var testResult: String = ""
    @State private var testing = false

    var body: some View {
        PageScaffold(title: "API 配置", subtitle: "凭据在服务端 AES-256-GCM 加密存储，不回显明文") {
            // 双市场槽位
            HStack(spacing: 10) {
                slotCard("现货 Spot", slot: store.okxConfig?.spot)
                slotCard("永续 Swap", slot: store.okxConfig?.swap)
            }

            // 账号列表
            VStack(alignment: .leading, spacing: 8) {
                Text("账号列表").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if let accounts = store.okxConfig?.accounts, !accounts.isEmpty {
                    ForEach(accounts) { acc in
                        Card(padding: 13) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(acc.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        StatusBadge(text: acc.marketType == "spot" ? "现货" : "永续",
                                                    color: acc.marketType == "spot" ? .blue : .purple)
                                    }
                                    HStack(spacing: 6) {
                                        StatusBadge(text: acc.environment == "demo" ? "模拟盘" : (acc.environment == "live" ? "实盘" : acc.environment),
                                                    color: acc.environment == "demo" ? .teal : .orange)
                                        StatusBadge(text: acc.enabled ? "已启用" : "已停用", color: acc.enabled ? .green : .gray)
                                        if acc.credentialsSaved {
                                            StatusBadge(text: "凭据已存", color: .green)
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    startEdit(market: acc.marketType, name: acc.name)
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    EmptyHint(icon: "key.slash", text: "还没有配置账号")
                }
            }

            PrimaryButton(title: "新增 / 更新账号", icon: "plus.circle.fill") {
                startEdit(market: "spot", name: "")
            }

            // 编辑表单
            if showEditor {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("账号凭据").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)

                        Picker("市场", selection: $editingMarket) {
                            Text("现货 Spot").tag("spot")
                            Text("永续 Swap").tag("swap")
                        }
                        .pickerStyle(.segmented)

                        FieldRow(icon: "tag.fill", placeholder: "账号名称（如 主账号）", text: $name)

                        Picker("环境", selection: $environment) {
                            Text("模拟盘 Demo").tag("demo")
                            Text("实盘 Live").tag("live")
                        }
                        .pickerStyle(.segmented)

                        SecureFieldRow(icon: "key.fill", placeholder: "API Key", text: $apiKey)
                        SecureFieldRow(icon: "lock.shield.fill", placeholder: "Secret Key", text: $apiSecret)
                        SecureFieldRow(icon: "lock.rotation", placeholder: "Passphrase", text: $passphrase)

                        Text("更新时留空则保留原凭据。OKX 需要三项凭据：Key + Secret + Passphrase。")
                            .font(.caption2).foregroundStyle(.secondary)

                        PrimaryButton(title: testing ? "测试中…" : "保存并测试", icon: "bolt.fill", disabled: testing || name.isEmpty) {
                            Task { await saveAndTest() }
                        }

                        if !testResult.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: testResult.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(testResult.contains("成功") ? .green : .orange)
                                Text(testResult).font(.caption).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            // 连接测试
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("连接测试").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("使用已保存的凭据执行只读测试（公共时间 → 账户 → 余额 → 持仓 → 挂单）")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        PrimaryButton(title: "测试现货", icon: "antenna.radiowaves.left.and.right") {
                            Task { testResult = await store.testOkx(marketType: "spot") }
                        }
                        PrimaryButton(title: "测试永续", icon: "antenna.radiowaves.left.and.right") {
                            Task { testResult = await store.testOkx(marketType: "swap") }
                        }
                    }
                }
            }
        }
        .navigationTitle("API 配置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadOkxConfig() }
    }

    private func slotCard(_ title: String, slot: OkxConfigSlot?) -> some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if slot?.configured == true {
                    Text(slot?.name ?? "已配置")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    StatusBadge(text: slot?.environment == "demo" ? "模拟盘" : "实盘",
                                color: slot?.environment == "demo" ? .teal : .orange)
                } else {
                    Text("未配置").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startEdit(market: String, name: String) {
        editingMarket = market
        self.name = name
        apiKey = ""
        apiSecret = ""
        passphrase = ""
        environment = "demo"
        testResult = ""
        withAnimation { showEditor = true }
    }

    private func saveAndTest() async {
        testing = true
        defer { testing = false }
        await store.saveOkxAccount(name: name, marketType: editingMarket, apiKey: apiKey,
                                   apiSecret: apiSecret, passphrase: passphrase, environment: environment)
        testResult = await store.testOkx(marketType: editingMarket)
    }
}
