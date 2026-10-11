import SwiftUI

@main
struct QuantOKXApp: App {
    @StateObject private var store = BackendStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.config)
                .preferredColorScheme(.dark)
                .task { await store.bootstrap() }
        }
    }
}

/// 根视图：未登录 → 登录页；已登录 → 主界面
struct RootView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig

    var body: some View {
        Group {
            if config.loggedIn {
                MainTabView()
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
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// 主界面：底部五标签（控制台 / OKX / AI交易 / 策略 / 更多）
struct MainTabView: View {
    @EnvironmentObject var store: BackendStore
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("控制台", systemImage: "house.fill") }
                .tag(0)
            OkxHomeView()
                .tabItem { Label("OKX", systemImage: "wallet.pass.fill") }
                .tag(1)
            AiTradeView()
                .tabItem { Label("AI交易", systemImage: "cpu.fill") }
                .tag(2)
            StrategyHomeView()
                .tabItem { Label("策略", systemImage: "chart.xyaxis.line") }
                .tag(3)
            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
        .tint(Color(red: 0.29, green: 0.56, blue: 1.0))
    }
}
