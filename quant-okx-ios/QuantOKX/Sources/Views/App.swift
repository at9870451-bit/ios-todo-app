import SwiftUI

@main
struct QuantOKXApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var store: BackendStore

    init() {
        let cfg = AppConfig()
        _config = StateObject(wrappedValue: cfg)
        _store = StateObject(wrappedValue: BackendStore(appConfig: cfg))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
                .environmentObject(store)
                .task {
                    store.attach(config)
                    store.startPolling(interval: 5)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var store: BackendStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("交易台", systemImage: "chart.line.uptrend.xyaxis") }
                .badge(store.running ? "运行中" : "")

            StrategyView()
                .tabItem { Label("策略", systemImage: "square.grid.3x3.fill") }

            LogsView()
                .tabItem { Label("日志", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.blue)
        .onChange(of: scenePhase) { _, phase in
            // 回前台立刻刷新一次，别让用户看陈旧数据
            if phase == .active {
                store.attach(config)
                store.startPolling(interval: 5)
            } else if phase == .background {
                // 后台不轮询，省电也省流量
                store.stopPolling()
            }
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(text: t)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation { store.toast = nil }
                    }
            }
        }
        .animation(.snappy, value: store.toast)
    }
}

// MARK: - 通用组件

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub { Text(sub).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveWarning: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("实盘模式：所有下单都是真金白银").font(.footnote.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DemoBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
            Text("模拟盘模式（不花真钱）")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OfflineBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text("后台未连接").font(.footnote.weight(.semibold))
                Text(message).font(.caption2).opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.82), in: Capsule())
            .shadow(radius: 8, y: 3)
            .padding(.horizontal, 24)
    }
}
