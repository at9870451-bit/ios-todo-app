import SwiftUI

@main
struct QuantOKXApp: App {
    @StateObject private var store = BackendStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.config)
                .preferredColorScheme(.light)
                .tint(.orange)
                .task { await store.bootstrap() }
        }
    }
}

/// 根路由：未登录 → 登录页；已登录 → 聊天主界面
struct RootView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    var body: some View {
        Group {
            if config.loggedIn {
                ChatTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: config.loggedIn)
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

/// 聊天主界面（唯一 Tab，去掉交易标签）
struct ChatTabView: View {
    var body: some View {
        TabView {
            ChatScreen()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
