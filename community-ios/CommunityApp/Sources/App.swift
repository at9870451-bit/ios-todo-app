import SwiftUI

@main
struct CommunityApp: App {
    @StateObject private var store = CommunityStore()
    @State private var tab: Tab = .feed

    enum Tab: Hashable { case feed, compose, messages, me }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                FeedView(goCompose: { tab = .compose })
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(Tab.feed)

                ComposeView(onPublished: { tab = .feed })
                    .tabItem { Label("发布", systemImage: "plus.circle.fill") }
                    .tag(Tab.compose)

                MessagesView()
                    .tabItem { Label("消息", systemImage: "bell.fill") }
                    .tag(Tab.messages)
                    .badge(store.notices.isEmpty ? 0 : min(store.notices.count, 99))

                ProfileView()
                    .tabItem { Label("我的", systemImage: "person.fill") }
                    .tag(Tab.me)
            }
            .tint(Color.indigo)
            .environmentObject(store)
        }
    }
}

// MARK: - 头像

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    private var gradient: LinearGradient {
        let palette: [Color] = [.indigo, .teal, .orange, .pink, .blue, .purple, .mint]
        let idx = abs(name.hashValue) % palette.count
        return LinearGradient(colors: [palette[idx].opacity(0.85), palette[idx]],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(gradient, in: Circle())
    }
}

// MARK: - 标签胶囊

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.indigo.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.indigo)
    }
}
