import SwiftUI

@main
struct QuantOKXApp: App {
    @StateObject private var store = BackendStore.shared
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.config)
                .environmentObject(router)
                .environmentObject(ProviderStore.shared)
                .environmentObject(BackgroundStore.shared)
                .environmentObject(AvatarStore.shared)
                .tint(Theme.accent)
                .task { await store.bootstrap() }
        }
    }
}

/// 全局 Tab 路由（跨页跳转：对话页「去添加配置」→ 设置页等）
final class Router: ObservableObject {
    @Published var tab: Int = 0
    /// 跨 Tab 打开指定会话（聊天 Tab → 对话 Tab）
    @Published var pendingConversationId: Int64 = 0
    /// 请求新对话（聊天 Tab → 对话 Tab 清空开场）
    @Published var newChatRequested: Int = 0

    func openConversation(id: Int64) {
        pendingConversationId = id
        tab = 1
    }

    func startNewChat() {
        newChatRequested += 1
        tab = 1
    }
}

/// 根路由：底部三 Tab（对话 / 设置 / 我的），登录入口在「我的」
struct RootView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        MainTabView()
            .overlay(alignment: .top) {
            if !store.toast.isEmpty {
                ToastView(text: store.toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { store.toast = "" }
                    }
            }
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
    }
}

/// 底部导航：聊天 / 对话 / 玩偶 / 设置 / 我的
struct MainTabView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            AuthGate(gotoProfile: { router.tab = 4 }) {
                ChatRoomView()
            }
            .tabItem { Label("聊天", systemImage: "ellipsis.message.fill") }
            .tag(0)

            AuthGate(gotoProfile: { router.tab = 4 }) {
                ChatScreen()
            }
            .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(1)

            AuthGate(gotoProfile: { router.tab = 4 }) {
                DollStudioView()
            }
            .tabItem { Label("玩偶", systemImage: "teddybear.fill") }
            .tag(2)

            AuthGate(gotoProfile: { router.tab = 4 }) {
                SettingsScreen()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(3)

            ProfileView(onLoggedIn: { router.tab = 1 })
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .tint(Theme.accent)
        // 保留系统 TabView 的原生交互，同时统一为通透玻璃底栏。
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }
}

/// 登录门控：未登录显示引导占位，点击跳「我的」
struct AuthGate<Content: View>: View {
    @EnvironmentObject var config: AppConfig
    let gotoProfile: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if config.loggedIn {
            content()
        } else {
            SignedOutHint(gotoProfile: gotoProfile)
        }
    }
}
