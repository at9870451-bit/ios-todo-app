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
                .preferredColorScheme(.light)
                .tint(.orange)
                .task { await store.bootstrap() }
        }
    }
}

/// 全局 Tab 路由（跨页跳转：对话页「去添加配置」→ 设置页等）
final class Router: ObservableObject {
    @Published var tab: Int = 0
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
            .background(.regularMaterial, in: Capsule())
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
    }
}

/// 底部导航：对话 / 设置 / 我的
struct MainTabView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            AuthGate(gotoProfile: { router.tab = 2 }) {
                ChatScreen()
            }
            .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(0)

            AuthGate(gotoProfile: { router.tab = 2 }) {
                SettingsScreen()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(1)

            ProfileView(onLoggedIn: { router.tab = 0 })
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(2)
        }
        .tint(.blue)
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
