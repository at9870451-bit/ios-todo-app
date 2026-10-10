import SwiftUI

// MARK: - 数据模型

struct User: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var bio: String
}

struct Comment: Codable, Identifiable, Equatable {
    let id: UUID
    var author: String
    var text: String
    var createdAt: Date
}

struct Post: Codable, Identifiable, Equatable {
    let id: UUID
    var authorName: String
    var authorId: UUID
    var text: String
    var tag: String
    var createdAt: Date
    var likeCount: Int
    var likedByMe: Bool
    var comments: [Comment]
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var detail: String
    var at: Date
}

// MARK: - 存储层

@MainActor
final class CommunityStore: ObservableObject {
    @Published var me: User
    @Published var posts: [Post]

    private let key = "community.store.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Save.self, from: d) {
            me = s.me
            posts = s.posts
        } else {
            let user = User(id: UUID(), name: "我", bio: "这个人很懒，什么都没写")
            me = user
            posts = Self.seed(myId: user.id, myName: user.name)
            persist()
        }
    }

    private struct Save: Codable { var me: User; var posts: [Post] }

    private func persist() {
        if let d = try? JSONEncoder().encode(Save(me: me, posts: posts)) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    func resetDemo() {
        posts = Self.seed(myId: me.id, myName: me.name)
        persist()
    }

    // MARK: 操作

    func publish(_ text: String, tag: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        posts.insert(Post(id: UUID(),
                          authorName: me.name,
                          authorId: me.id,
                          text: t,
                          tag: tag,
                          createdAt: Date(),
                          likeCount: 0,
                          likedByMe: false,
                          comments: []),
                     at: 0)
        persist()
    }

    func toggleLike(_ id: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].likedByMe.toggle()
        posts[i].likeCount += posts[i].likedByMe ? 1 : -1
        persist()
    }

    func comment(_ post: Post, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[i].comments.append(Comment(id: UUID(), author: me.name, text: t, createdAt: Date()))
        persist()
    }

    // MARK: 派生数据

    var myPosts: [Post] { posts.filter { $0.authorId == me.id } }

    var likesReceived: Int {
        posts.filter { $0.authorId == me.id }.map(\.likeCount).reduce(0, +)
    }

    var notices: [Notice] {
        var out: [Notice] = []
        for p in posts where p.authorId == me.id {
            for c in p.comments where c.author != me.name {
                out.append(Notice(text: "\(c.author) 评论了你的帖子",
                                  detail: c.text,
                                  at: c.createdAt))
            }
        }
        let liked = posts.filter { $0.authorId == me.id && $0.likeCount > 0 }
        if !liked.isEmpty {
            out.append(Notice(text: "❤️ 收到新赞",
                              detail: "你的 \(liked.count) 篇帖子共获得 \(likesReceived) 个赞",
                              at: Date()))
        }
        return out.sorted { $0.at > $1.at }
    }

    // MARK: 示例数据

    nonisolated static func seed(myId: UUID, myName: String) -> [Post] {
        let others = ["老王聊交易", "K线少女", "卷不动了", "凌晨四点的程序员", "节气养生"]
        func mk(_ author: String, _ minutesAgo: Int,
                _ tag: String, _ text: String,
                likes: Int, comments: [String]) -> Post {
            var cs: [Comment] = []
            for (i, c) in comments.enumerated() {
                cs.append(Comment(id: UUID(),
                                  author: others[(i + 2) % others.count],
                                  text: c,
                                  createdAt: Date().addingTimeInterval(Double(-minutesAgo * 60 + (i + 1) * 137))))
            }
            return Post(id: UUID(),
                        authorName: author,
                        authorId: author == myName ? myId : UUID(),
                        text: text,
                        tag: tag,
                        createdAt: Date().addingTimeInterval(Double(-minutesAgo * 60)),
                        likeCount: likes,
                        likedByMe: false,
                        comments: cs)
        }
        return [
            mk(others[0], 12, "行情", "BTC 又在 6 万上方震荡了，横了三天没方向。你们最近都在看什么？", likes: 24,
               comments: ["震荡就是等突破，别猜", "我选择空仓看戏 🍿"]),
            mk(others[1], 45, "干货", "分享一个我自己整理的入场检查清单：1️⃣ 趋势方向 2️⃣ 关键位 3️⃣ 仓位 4️⃣ 止损位。四项没齐就不开单，胜率肉眼可见地上来了。", likes: 87,
               comments: ["收藏了，第3点最容易被忽略", "求详细版！", "太真实了，我就是死在仓位上"]),
            mk(others[2], 120, "闲聊", "盯着盘 twelve 小时，收益还没我朋友睡觉睡得多，这合理吗 😅", likes: 156,
               comments: ["合理，人家是拿着不动的", "心态第一，兄弟"]),
            mk(others[3], 200, "求助", "刚把量化机器人跑起来，模拟盘第一晚就被止损打了三次……大家一般怎么定 ATR 倍数？", likes: 9,
               comments: ["试过 1.5 倍 ATR，太紧了", "从 2.5 开始慢慢调"]),
            mk(myName, 300, "分享", "入坑记录：从零开始写了一个自己的自动交易 App，前后端都是手机上写完推到 GitHub 云端编译的。下一步接 AI 做决策。", likes: 32,
               comments: ["牛的，手机开发是真的顶", "求教程！"]),
            mk(others[4], 420, "闲聊", "看盘别久坐，起来活动五分钟，颈椎不是开玩笑的。", likes: 41,
               comments: ["收到，这就起来", "已经贴上膏药了……"]),
        ]
    }
}
