import SwiftUI

// MARK: - 塔罗牌（22 张大阿卡纳）

struct TarotCard: Identifiable, Hashable {
    let id: Int
    let name: String
    let symbol: String        // SF Symbol
    let upright: String       // 正位含义
    let reversed: String      // 逆位含义

    static let deck: [TarotCard] = [
        TarotCard(id: 0,  name: "愚者",   symbol: "figure.walk",            upright: "新的开始、自由、冒险", reversed: "鲁莽、逃避、错失机会"),
        TarotCard(id: 1,  name: "魔术师", symbol: "wand.and.stars",         upright: "创造力、行动力、掌控", reversed: "操控、拖延、自信不足"),
        TarotCard(id: 2,  name: "女祭司", symbol: "moon.stars.fill",        upright: "直觉、神秘、内在智慧", reversed: "忽视直觉、隐瞒、表层化"),
        TarotCard(id: 3,  name: "皇后",   symbol: "leaf.fill",              upright: "丰盛、滋养、爱与美", reversed: "过度依赖、自我忽略、停滞"),
        TarotCard(id: 4,  name: "皇帝",   symbol: "crown.fill",             upright: "权威、秩序、稳固", reversed: "固执、控制欲、僵化"),
        TarotCard(id: 5,  name: "教皇",   symbol: "book.closed.fill",       upright: "传统、指导、信念", reversed: "教条、叛逆、被束缚"),
        TarotCard(id: 6,  name: "恋人",   symbol: "heart.fill",             upright: "结合、选择、真心", reversed: "犹豫、错配、诱惑"),
        TarotCard(id: 7,  name: "战车",   symbol: "car.fill",               upright: "前进、意志、胜利", reversed: "失控、方向混乱、蛮干"),
        TarotCard(id: 8,  name: "力量",   symbol: "flame.fill",             upright: "勇气、耐心、温柔的力量", reversed: "自我怀疑、急躁、软弱"),
        TarotCard(id: 9,  name: "隐者",   symbol: "lightbulb.fill",         upright: "内省、独处、寻找答案", reversed: "孤立、逃避、迷失"),
        TarotCard(id: 10, name: "命运之轮", symbol: "circle.grid.cross.fill", upright: "转机、循环、机缘", reversed: "低谷、拖延、逆势"),
        TarotCard(id: 11, name: "正义",   symbol: "scalemass.fill",         upright: "公平、因果、决断", reversed: "偏颇、推诿、失衡"),
        TarotCard(id: 12, name: "倒吊人", symbol: "arrow.down.circle.fill", upright: "暂停、换位思考、牺牲", reversed: "无谓牺牲、拖延、固执"),
        TarotCard(id: 13, name: "死神",   symbol: "moon.fill",              upright: "结束、蜕变、新生", reversed: "抗拒改变、纠缠、停滞"),
        TarotCard(id: 14, name: "节制",   symbol: "drop.fill",              upright: "平衡、调和、耐心", reversed: "失衡、过度、急躁"),
        TarotCard(id: 15, name: "恶魔",   symbol: "bolt.heart.fill",        upright: "欲望、束缚、执念", reversed: "挣脱、觉醒、放下"),
        TarotCard(id: 16, name: "高塔",   symbol: "house.fill",             upright: "突变、崩塌、真相", reversed: "缓冲、勉强维持、迟到的变化"),
        TarotCard(id: 17, name: "星星",   symbol: "star.fill",              upright: "希望、疗愈、灵感", reversed: "失望、迷茫、信心不足"),
        TarotCard(id: 18, name: "月亮",   symbol: "cloud.moon.fill",        upright: "潜意识、不安、幻象", reversed: "真相浮现、焦虑消退"),
        TarotCard(id: 19, name: "太阳",   symbol: "sun.max.fill",           upright: "成功、喜悦、生命力", reversed: "短暂低落、过度乐观"),
        TarotCard(id: 20, name: "审判",   symbol: "bell.fill",              upright: "觉醒、召唤、重生", reversed: "犹豫、后悔、逃避责任"),
        TarotCard(id: 21, name: "世界",   symbol: "globe.asia.australia.fill", upright: "圆满、完成、旅程终点", reversed: "未竟、差一步、循环未结"),
    ]

    /// 随机抽一张
    static func draw() -> (TarotCard, Bool) {
        let c = deck.randomElement() ?? deck[0]
        return (c, Bool.random())
    }

    var meaning: String { upright }
}

// MARK: - 狼人杀

enum WerewolfRole: String, CaseIterable {
    case villager = "村民"
    case wolf = "狼人"
    case seer = "预言家"
    case witch = "女巫"

    var symbol: String {
        switch self {
        case .villager: return "person.fill"
        case .wolf: return "pawprint.fill"
        case .seer: return "eye.fill"
        case .witch: return "sparkles"
        }
    }
    var tint: Color {
        switch self {
        case .villager: return Theme.ok
        case .wolf: return Theme.danger
        case .seer: return Theme.heroBlue
        case .witch: return Theme.warn
        }
    }
    var blurb: String {
        switch self {
        case .villager: return "没有特殊能力，靠推理找出狼人"
        case .wolf: return "夜里可以袭击一名玩家，白天伪装成好人"
        case .seer: return "每晚可以查验一名玩家的身份"
        case .witch: return "有一瓶解药和一瓶毒药"
        }
    }
}

/// 狼人杀一局的状态（单轮体验版）
struct WerewolfGame {
    var players: [(name: String, memberId: String)] = []
    var roles: [String: WerewolfRole] = [:]     // memberId → 角色
    var victim: String = ""                      // 昨夜被袭击者名字
    var phase: Int = 0                           // 0=已分配 1=天亮 2=发言完 3=结算
    var winner: String = ""
}

// MARK: - 游戏卡面（程序化绘制，无需图片资源）

struct GameCardView: View {
    enum Kind { case tarot, role, reveal }

    let kind: Kind
    let title: String            // 卡名 / 角色名
    let subtitle: String         // 正位·逆位 / 说明
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // 卡面渐变
                LinearGradient(colors: [tint.opacity(0.92), tint.opacity(0.55), Color.black.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 金色描边
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 0.96, green: 0.83, blue: 0.53), lineWidth: 1.6)
                    .padding(6)
                // 内框
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                    .padding(12)
                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color(red: 0.98, green: 0.88, blue: 0.62))
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                // 四角装饰
                ForEach(0..<4, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.96, green: 0.83, blue: 0.53).opacity(0.9))
                        .offset(x: i % 2 == 0 ? -46 : 46, y: i < 2 ? -66 : 66)
                }
            }
            .frame(width: 132, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
        }
    }
}

// MARK: - 卡牌消息标记（群聊与单聊共用）

struct CardMark {
    let kind: String      // 塔罗 / 角色 / 结算
    let title: String
    let sub: String
    let symbol: String
    let tone: String

    static func parse(_ text: String) -> CardMark? {
        guard text.hasPrefix("[卡牌]") else { return nil }
        let parts = String(text.dropFirst(4)).components(separatedBy: "|")
        guard parts.count >= 5 else { return nil }
        return CardMark(kind: parts[0], title: parts[1], sub: parts[2], symbol: parts[3], tone: parts[4])
    }

    var color: Color {
        switch tone {
        case "red": return Theme.danger
        case "green": return Theme.ok
        case "gold": return Color(red: 0.78, green: 0.60, blue: 0.18)
        case "blue": return Theme.heroBlue
        default: return Color(red: 0.36, green: 0.27, blue: 0.55)
        }
    }

    var cardKind: GameCardView.Kind {
        switch kind {
        case "塔罗": return .tarot
        case "结算": return .reveal
        default: return .role
        }
    }

    static func message(_ kind: String, _ title: String, _ sub: String, _ symbol: String, tone: String) -> String {
        "[卡牌]\(kind)|\(title)|\(sub)|\(symbol)|\(tone)"
    }
}

/// 卡牌气泡（统一渲染）
struct CardBubble: View {
    let mark: CardMark
    var body: some View {
        GameCardView(kind: mark.cardKind, title: mark.title, subtitle: mark.sub,
                     symbol: mark.symbol, tint: mark.color)
    }
}
