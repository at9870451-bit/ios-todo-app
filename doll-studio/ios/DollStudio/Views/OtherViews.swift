// DollStudio3D — 其余页面：作品列表 / 收藏 / 性别选择 / 设置（含音频与登录）
import SwiftUI

// MARK: - 我的作品

struct OutfitListView: View {
    @EnvironmentObject var store: OutfitStore
    @State private var pendingDelete: Outfit?

    var body: some View {
        List {
            if store.outfits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tshirt").font(.system(size: 40)).foregroundStyle(Color(hex: 0xFFC7C7CC))
                    Text("还没有保存的穿搭").foregroundStyle(Color(hex: 0xFF86868B)).font(.system(size: 14))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowSeparator(.hidden)
            }
            ForEach(store.outfits) { o in
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.name).font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(o.gender.title).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF86868B))
                        Text("\(o.slots.count) 件单品").font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF86868B))
                        Text(o.createdAt, style: .date).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFFAEAEB2))
                    }
                    // 单品速览
                    HStack(spacing: 4) {
                        ForEach(o.slots.values.sorted(by: { $0.clothId < $1.clothId }).prefix(6), id: \.self) { slot in
                            Circle().fill(Color(hexString: slot.color)).frame(width: 12, height: 12)
                        }
                    }
                    HStack(spacing: 14) {
                        Button("穿着它") { store.loadOutfit(o) }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color(hex: 0xFFFF9500))
                        Button("复制") { store.duplicateOutfit(o) }
                            .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF3478F6))
                        Button("删除", role: .destructive) { pendingDelete = o }
                            .font(.system(size: 12.5))
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("我的作品")
        .alert("删除该作品？", item: $pendingDelete) { o in
            Button("删除", role: .destructive) { store.deleteOutfit(o) }
            Button("取消", role: .cancel) {}
        } message: { o in
            Text("「\(o.name)」将被移除，无法恢复。")
        }
    }
}

// MARK: - 收藏

struct FavoritesView: View {
    @EnvironmentObject var store: OutfitStore

    private var favItems: [ClothItem] {
        store.catalog.filter { store.favorites.contains($0.id) }
    }

    var body: some View {
        List {
            if favItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "heart").font(.system(size: 40)).foregroundStyle(Color(hex: 0xFFC7C7CC))
                    Text("长按服装缩略图可收藏").foregroundStyle(Color(hex: 0xFF86868B)).font(.system(size: 14))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                .listRowSeparator(.hidden)
            }
            ForEach(favItems) { item in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hexString: item.color))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 15, weight: .medium))
                        Text(store.categories.first { $0.key == item.category }?.title ?? item.category)
                            .font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF86868B))
                    }
                    Spacer()
                    if !item.isFree {
                        Text("¥\(Int(item.price))").font(.system(size: 13)).foregroundStyle(Color(hex: 0xFFFF9500))
                    }
                    Button {
                        store.toggleFavorite(item.id)
                    } label: {
                        Image(systemName: "heart.slash").foregroundStyle(Color(hex: 0xFFC7C7CC))
                    }
                }
            }
        }
        .navigationTitle("收藏")
    }
}

// MARK: - 性别 / 角色选择

struct GenderPickerView: View {
    @EnvironmentObject var store: OutfitStore
    @Environment(\.dismiss) var dismiss
    @State private var skin = "#F3C6A5"
    @State private var name = ""

    private let skins = ["#F3C6A5", "#E8B48C", "#D69A72", "#B87A50", "#8A5A38", "#F0C0A8"]

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.gray.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Text("选择玩偶").font(.system(size: 18, weight: .bold))

            HStack(spacing: 12) {
                ForEach(DollGender.allCases) { g in
                    let selected = store.gender == g
                    Button {
                        store.gender = g
                        store.dollName = BuiltInCatalog.dolls.first { $0.gender == g }?.name ?? store.dollName
                        store.heightScale = BuiltInCatalog.dolls.first { $0.gender == g }?.heightScale ?? 1.0
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: g == .male ? "figure.stand" : g == .female ? "figure.dress.line.vertical.figure" : "figure.arms.open")
                                .font(.system(size: 26))
                            Text(g.title).font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: 18)
                            .fill(selected ? Color(hex: 0xFFFFF4E8) : Color(hex: 0xFFF2F2F7)))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(selected ? Color(hex: 0xFFFF9500) : Color.clear, lineWidth: 2))
                        .foregroundStyle(selected ? Color(hex: 0xFFE87500) : Color(hex: 0xFF1D1D1F))
                    }
                }
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("肤色").font(.system(size: 13)).foregroundStyle(Color(hex: 0xFF86868B))
                HStack(spacing: 10) {
                    ForEach(skins, id: \.self) { hex in
                        let selected = store.skin.lowercased() == hex.lowercased()
                        Button {
                            store.skin = hex
                        } label: {
                            Circle().fill(Color(hexString: hex))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(
                                    selected ? Color(hex: 0xFFFF9500) : Color(hex: 0xFFE3E3E8),
                                    lineWidth: selected ? 2.4 : 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Text("玩偶名称").font(.system(size: 13)).foregroundStyle(Color(hex: 0xFF86868B))
                Spacer()
                TextField("名称", text: $store.dollName)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
            }
            .padding(.horizontal, 20)

            Button {
                dismiss()
            } label: {
                Text("开始搭配")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(LinearGradient(colors: [Color(hex: 0xFF3478F6), Color(hex: 0xFF6CA8FF), Color(hex: 0xFFFF9500)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 16)))
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .presentationDetents([.height(430)])
    }
}

// MARK: - 设置（音频 / 账号 / 服务端 / 关于）

struct SettingsView: View {
    @EnvironmentObject var store: OutfitStore
    @EnvironmentObject var audio: AudioService
    @Environment(\.dismiss) var dismiss

    @State private var showLogin = false
    @State private var loginError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(Color(hex: 0xFF3478F6))
                        Text(store.username).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if store.authToken == nil {
                            Button("登录") { showLogin = true }
                                .font(.system(size: 13, weight: .semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: 0xFFFF9500))
                        } else {
                            Button("退出") {
                                store.authToken = nil
                                store.username = "游客"
                                UserDefaults.standard.removeObject(forKey: "doll.token.v1")
                            }
                            .font(.system(size: 13))
                        }
                    }
                    // Apple 登录（需开发者账号启用 Capability；未签名包中仅展示入口）
                    Button {
                        loginError = "Sign in with Apple 需要在开发者账号中启用 Capability 后可用（未签名 CI 包暂不支持）；可使用账号密码登录。"
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("使用 Apple 登录")
                        }
                        .font(.system(size: 14))
                    }
                    if let e = loginError {
                        Text(e).font(.system(size: 11.5)).foregroundStyle(Color(hex: 0xFFFF3B30))
                    }
                }

                Section("音频") {
                    Toggle(isOn: $audio.sfxOn) {
                        Text("交互音效").font(.system(size: 14.5))
                    }
                    if !audio.sfxOn {
                        Text("音效已关闭").font(.system(size: 11.5)).foregroundStyle(Color(hex: 0xFFAEAEB2))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("音效音量（跟随系统播放）").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF86868B))
                        Slider(value: $audio.sfxVolume)
                    }
                    Toggle(isOn: $audio.bgmOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("背景音乐").font(.system(size: 14.5))
                            if !audio.bgmAvailable {
                                Text("未检测到 bgm.mp3（放到 App 沙盒 Documents 目录后可用）")
                                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xFFAEAEB2))
                            }
                        }
                    }
                    .disabled(!audio.bgmAvailable)
                    if audio.bgmOn && audio.bgmAvailable {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("背景音乐音量").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF86868B))
                            Slider(value: $audio.bgmVolume)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI 语音音量").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF86868B))
                        Slider(value: $audio.voiceVolume)
                    }
                }

                Section("服务端") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API 地址（留空 = 纯本地模式）").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF86868B))
                        TextField("https://your-server.example.com", text: Binding(
                            get: { store.apiBase },
                            set: { store.apiBase = $0 }))
                            .font(.system(size: 13))
                            .textFieldStyle(.roundedBorder)
                        Text("服装目录通过 GET /api/clothes 动态获取；AI 搭配经 POST /api/ai/outfits（API Key 仅保存在服务端）。")
                            .font(.system(size: 11)).foregroundStyle(Color(hex: 0xFFAEAEB2))
                    }
                    Button("重新拉取服装目录") {
                        Task { await store.fetchRemoteCatalog() }
                    }
                    .font(.system(size: 14))
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0 (1)")
                    LabeledContent("渲染", value: "SceneKit 程序化模型")
                    LabeledContent("远程 3D", value: "USDZ 资源通道已预留")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var store: OutfitStore
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(.gray.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Text("账号登录").font(.system(size: 18, weight: .bold))
            Text("游客模式无需登录，本地数据始终可用")
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0xFF86868B))

            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 20)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 20)

            if let e = errorText {
                Text(e).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFFFF3B30))
                    .padding(.horizontal, 20)
            }

            Button {
                guard !username.isEmpty, !password.isEmpty else {
                    errorText = "请输入用户名和密码"
                    return
                }
                busy = true
                errorText = nil
                Task {
                    do {
                        let token = try await APIClient.shared.login(
                            base: store.apiBase, username: username, password: password)
                        store.authToken = token
                        store.username = username
                        UserDefaults.standard.set(token, forKey: "doll.token.v1")
                        UserDefaults.standard.set(username, forKey: "doll.username.v1")
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                    busy = false
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text("登录")
                }
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xFFFF9500)))
            }
            .padding(.horizontal, 20)
            .disabled(busy)
            Spacer()
        }
        .presentationDetents([.height(340)])
    }
}
