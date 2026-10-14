import Foundation

// MARK: - Doll Studio 3D 数据模型（与后端 /api/doll/** 对齐）

/// 服装分类（code 与后端 doll_categories.code 一致；顺序即 Tab 顺序）
struct DollCategory: Identifiable, Decodable, Equatable {
    let code: String
    let name: String
    let sort: Int
    var id: String { code }
}

/// 服装/配饰条目（本地内置或服务端目录；style 对应 3D 构建器款式键）
struct DollItem: Identifiable, Decodable, Equatable {
    let id: Int64
    let category: String
    let name: String
    let style: String
    let color: String
    let premium: Bool
    let modelUrl: String?
    let modelScale: Double?
    let modelOffsetY: Double?

    enum CodingKeys: String, CodingKey {
        case id, category, name, style, color, premium
        case modelUrl = "model_url"
        case modelScale = "model_scale"
        case modelOffsetY = "model_offset_y"
    }

    /// 内置条目快捷构造（id 用负数避免与服务端冲突）
    static func builtin(_ category: String, _ style: String, _ name: String, _ color: String, _ sort: Int) -> DollItem {
        DollItem(id: Int64(-sort), category: category, name: name, style: style, color: color,
                 premium: false, modelUrl: nil, modelScale: nil, modelOffsetY: nil)
    }
}

/// 服务端目录响应
struct DollCatalogData: Decodable {
    let categories: [DollCategory]
    let items: [DollItem]
}

// MARK: - 搭配状态（可 JSON 序列化，保存/撤销重做共用）

struct DollSelection: Codable, Equatable {
    var style: String
    var color: String
}

struct DollOutfitState: Codable, Equatable {
    var gender: String = "neutral"
    var skin: String = "#F6D7BE"
    var items: [String: DollSelection] = [:]

    var json: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func parse(_ s: String) -> DollOutfitState {
        guard let data = s.data(using: .utf8),
              let st = try? JSONDecoder().decode(DollOutfitState.self, from: data) else { return DollOutfitState() }
        return st
    }

    /// 新玩偶默认穿搭：短发 + T恤 + 短裤 + 小白鞋
    static var preset: DollOutfitState {
        var s = DollOutfitState()
        s.items = [
            "hair": DollSelection(style: "short", color: "#3B2B20"),
            "top": DollSelection(style: "tee", color: "#5B7FD4"),
            "bottom": DollSelection(style: "shorts", color: "#3E5C8A"),
            "shoes": DollSelection(style: "sneakers", color: "#FFFFFF"),
        ]
        return s
    }
}

// MARK: - 保存的穿搭记录

struct DollOutfitRow: Identifiable, Decodable {
    let id: Int64
    let name: String
    let gender: String
    let skin: String
    let state: String
    let favorite: Bool
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, gender, skin, state, favorite
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var outfitState: DollOutfitState { DollOutfitState.parse(state) }
}

// MARK: - AI 穿搭推荐

struct DollRecommendItem: Decodable {
    let style: String
    let color: String
    let name: String?
    let itemId: Int64?

    enum CodingKeys: String, CodingKey {
        case style, color, name
        case itemId = "item_id"
    }
}

struct DollRecommendData: Decodable {
    let outfit: [String: DollRecommendItem]
    let reason: String
}

// MARK: - 内置目录（离线兜底；与服务端种子数据一致）

enum DollCatalog {
    static let categories: [DollCategory] = [
        DollCategory(code: "hair", name: "发型", sort: 1),
        DollCategory(code: "top", name: "上衣", sort: 2),
        DollCategory(code: "bottom", name: "下装", sort: 3),
        DollCategory(code: "scarf", name: "围巾", sort: 4),
        DollCategory(code: "hat", name: "帽子", sort: 5),
        DollCategory(code: "shoes", name: "鞋子", sort: 6),
        DollCategory(code: "accessory", name: "配饰", sort: 7),
    ]

    /// 每类可用的款式键（与服务端 DollSvc.STYLES 一致，缺一不可）
    static let styleKeys: [String: [String]] = [
        "hair": ["short", "bob", "long", "twintails", "bun", "spiky"],
        "top": ["tee", "hoodie", "shirt", "vest", "sweater", "jacket"],
        "bottom": ["shorts", "pants", "skirt", "wide_leg"],
        "scarf": ["scarf", "bandana"],
        "hat": ["beanie", "cap", "bucket", "beret"],
        "shoes": ["sneakers", "boots", "loafers", "sandals"],
        "accessory": ["glasses", "necklace", "backpack", "earrings", "flower", "watch"],
    ]

    static func builtinItems() -> [DollItem] {
        var out: [DollItem] = []
        func add(_ cat: String, _ style: String, _ name: String, _ color: String) {
            out.append(DollItem.builtin(cat, style, name, color, out.count + 1))
        }
        add("hair", "short", "清爽短发", "#3B2B20")
        add("hair", "bob", "波波头", "#4A3226")
        add("hair", "long", "柔顺长发", "#5A3A22")
        add("hair", "twintails", "双马尾", "#6B4423")
        add("hair", "bun", "丸子头", "#2C2C2E")
        add("hair", "spiky", "刺猬头", "#1F1F22")
        add("top", "tee", "经典T恤", "#FFFFFF")
        add("top", "hoodie", "连帽卫衣", "#5B7FD4")
        add("top", "shirt", "衬衫", "#DDE5F0")
        add("top", "vest", "针织背心", "#E8C468")
        add("top", "sweater", "高领毛衣", "#C96F5E")
        add("top", "jacket", "牛仔夹克", "#3E5C8A")
        add("bottom", "shorts", "休闲短裤", "#3E5C8A")
        add("bottom", "pants", "直筒长裤", "#2C2C2E")
        add("bottom", "skirt", "百褶短裙", "#D96A7B")
        add("bottom", "wide_leg", "阔腿裤", "#8A7F6A")
        add("scarf", "scarf", "经典围巾", "#D9433B")
        add("scarf", "bandana", "三角巾", "#E8C468")
        add("hat", "beanie", "毛线帽", "#D9433B")
        add("hat", "cap", "棒球帽", "#2C2C2E")
        add("hat", "bucket", "渔夫帽", "#E8E2D4")
        add("hat", "beret", "贝雷帽", "#B0565B")
        add("shoes", "sneakers", "小白鞋", "#FFFFFF")
        add("shoes", "boots", "马丁靴", "#3A2A20")
        add("shoes", "loafers", "乐福鞋", "#5A3A22")
        add("shoes", "sandals", "凉鞋", "#C9A06B")
        add("accessory", "glasses", "圆框眼镜", "#2C2C2E")
        add("accessory", "necklace", "小金链", "#E8C468")
        add("accessory", "backpack", "双肩包", "#D96A7B")
        add("accessory", "earrings", "星星耳钉", "#E8C468")
        add("accessory", "flower", "头花", "#FF8FA3")
        add("accessory", "watch", "运动手表", "#2C2C2E")
        return out
    }

    /// 通用调色板（颜色调整）
    static let palette: [String] = [
        "#FFFFFF", "#2C2C2E", "#8E8E93", "#FF3B30", "#FF6B6B", "#FF9500",
        "#FFCC00", "#34C759", "#00C7BE", "#32ADE6", "#3478F6", "#5856D6",
        "#AF52DE", "#FF2D55", "#C68642", "#F6D7BE",
    ]

    /// 肤色（男女中性通用）
    static let skinTones: [String] = ["#F6D7BE", "#EFC49E", "#E0AC82", "#C68B60", "#9C6644"]

    static func genderName(_ g: String) -> String {
        switch g {
        case "male": return "男生"
        case "female": return "女生"
        default: return "中性"
        }
    }

    /// 分类图标（SF Symbol）
    static func icon(for code: String) -> String {
        switch code {
        case "hair": return "person.crop.square"
        case "top": return "tshirt"
        case "bottom": return "figure.walk"
        case "scarf": return "wind"
        case "hat": return "graduationcap"
        case "shoes": return "shoe"
        case "accessory": return "eyeglasses"
        default: return "circle"
        }
    }
}

// MARK: - 颜色工具

enum DollColor {
    static func ui(_ hex: String, alpha: CGFloat = 1) -> UIColor {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        guard h.count == 6 else { return .systemGray }
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255.0,
                       green: CGFloat((v >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(v & 0xFF) / 255.0,
                       alpha: alpha)
    }
}
