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
            DrawerRoot()
                .environmentObject(config)
                .environmentObject(store)
                .task {
                    store.attach(config)
                    store.startPolling(interval: 5)
                }
        }
    }
}

// MARK: - 抽屉根视图

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard, strategy, logs, membership, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "交易台"
        case .strategy: return "策略"
        case .logs: return "日志"
        case .membership: return "会员中心"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .strategy: return "square.grid.3x3.fill"
        case .logs: return "list.bullet.rectangle"
        case .membership: return "crown.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct DrawerRoot: View {
    @EnvironmentObject private var store: BackendStore
    @State private var section: SidebarSection = .dashboard

    private let groups: [(String, [SidebarSection])] = [
        ("交易", [.dashboard, .strategy, .logs]),
        ("会员", [.membership]),
        ("系统", [.settings]),
    ]

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.drawerOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }

            SideBar(section: $section, groups: groups, onPick: { close() })
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .offset(x: store.drawerOpen ? 0 : -300)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.drawerOpen)
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
        .onChange(of: store.drawerOpen) { _, open in
            if !open { section = section }  // 无操作，仅为触发动画一致性
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.drawerOpen = false }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dashboard: DashboardView()
        case .strategy: StrategyView()
        case .logs: LogsView()
        case .membership: MembershipView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - 侧边栏

struct SideBar: View {
    @EnvironmentObject private var store: BackendStore
    @Binding var section: SidebarSection
    let groups: [(String, [SidebarSection])]
    var onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.orange)
                    Text("QuantOKX")
                        .font(.headline)
                }
                if let m = store.membership {
                    Text(m.active ? "\(m.planName) · 剩 \(m.daysLeft ?? 0) 天" : "免费版 · \(m.planName)")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                } else {
                    Text("量化交易控制台")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.0)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 4)

                            ForEach(group.1) { s in
                                row(s)
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(store.connected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(store.connected ? "后台在线" : "后台未连接")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                Spacer()
                if store.running {
                    Text("运行中")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.green)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(edges: .vertical)
    }

    private func row(_ s: SidebarSection) -> some View {
        let isOn = section == s
        return HStack(spacing: 12) {
            Image(systemName: s.icon)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
            Text(s.title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.white : Color.primary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(isOn ? Color.indigo : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            section = s
            onPick()
        }
    }
}

// MARK: - 抽屉按钮（各页左上角）

struct DrawerMenuButton: View {
    @EnvironmentObject private var store: BackendStore

    var body: some View {
        Button { store.drawerOpen = true } label: {
            Image(systemName: "line.3.horizontal")
        }
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
            Text(title).font(.caption).foregroundStyle(Color.secondary)
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
        .foregroundStyle(Color.white)
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
        .foregroundStyle(Color.white)
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
        .foregroundStyle(Color.white)
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
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.black.opacity(0.82), in: Capsule())
            .shadow(radius: 8, y: 3)
            .padding(.horizontal, 24)
    }
}
