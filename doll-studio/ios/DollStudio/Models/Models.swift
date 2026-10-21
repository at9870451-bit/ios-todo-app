// DollStudio3D — 数据模型（与后端 API /api/clothes 等字段对齐）
import Foundation

// MARK: - 性别（外观分类，不限制穿搭自由）

enum DollGender: String, Codable, CaseIterable, Identifiable {
    case male, female, neutral
    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: return "男性玩偶"
        case .female: return "女性玩偶"
        case .neutral: return "中性玩偶"
        }
    }
}

// MARK: - 服装分类（后台可扩展，本地内置兜底）

struct ClothCategory: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    let sort: Int
    var id: String { key }

    static let builtIn: [ClothCategory] = [
        .init(key: "top", title: "上衣", sort: 1),
        .init(key: "bottom", title: "下装", sort: 2),
        .init(key: "scarf", title: "围巾", sort: 3),
        .init(key: "hat", title: "帽子", sort: 4),
        .init(key: "shoes", title: "鞋子", sort: 5),
        .init(key: "hair", title: "发型", sort: 6),
        .init(key: "accessory", title: "配饰", sort: 7),
        .init(key: "other", title: "其他", sort: 8),
    ]
}

// MARK: - 服装

/// 3D 呈现方式：
/// - kind 为程序化模型（内置渲染器解释，随 API 动态下发即可穿戴）
/// - kind == "usdz" 时使用 url 加载 SCNReferenceNode（正式资源通道）
struct ClothItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String          // ClothCategory.key
    let kind: String              // tee / shirt / hoodie / pants / skirt / scarf / cap / beanie / beret / sneakers / leather / boots / hairShort / hairLong / hairCurly / glasses / necklace / bag / usdz ...
    let color: String             // hex，如 #333333
    let price: Double             // 0 = 免费
    let thumb: String?            // 缩略图 URL（可选；为空时本地程序化生成）
    let modelURL: String?         // kind == usdz 时的模型地址
    let exclusiveGroup: String?   // 互斥组（如 hat：一次只能戴一顶）
    var isFree: Bool { price <= 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, category, kind, color, price, thumb
        case modelURL = "model_url"
        case exclusiveGroup = "exclusive_group"
    }

    init(id: String, name: String, category: String, kind: String,
         color: String, price: Double = 0, thumb: String? = nil,
         modelURL: String? = nil, exclusiveGroup: String? = nil) {
        self.id = id; self.name = name; self.category = category
        self.kind = kind; self.color = color; self.price = price
        self.thumb = thumb; self.modelURL = modelURL; self.exclusiveGroup = exclusiveGroup
    }

    static func colorFromHex(_ hex: String) -> (Double, Double, Double) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return (0.5, 0.5, 0.5) }
        return (Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255,
                Double(v & 0xFF) / 255)
    }
}

// MARK: - 玩偶模型（外观参数）

struct DollModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let gender: DollGender
    let skin: String              // 肤色 hex
    let heightScale: Double       // 0.9 - 1.1
    let url: String?              // 正式 USDZ（可空 = 程序化模型）
}

// MARK: - 穿搭（作品）

/// 当前身上的穿搭快照：分类 → ClothItem.id + 颜色覆盖
struct OutfitSlot: Codable, Hashable {
    var clothId: String
    var color: String             // 用户改色后的 hex（默认取服装原色）
}

struct Outfit: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "我的穿搭"
    var gender: DollGender = .female
    var dollId: String = "doll_female_default"
    var skin: String = "#F3C6A5"
    var slots: [String: OutfitSlot] = [:]   // category → slot
    var createdAt: Date = Date()
}

// MARK: - 内置示例目录（可运行示例；正式运营经 /api/clothes 下发）

enum BuiltInCatalog {
    static let dolls: [DollModel] = [
        .init(id: "doll_female_default", name: "小雅", gender: .female, skin: "#F3C6A5", heightScale: 1.0, url: nil),
        .init(id: "doll_male_default", name: "小辰", gender: .male, skin: "#E8B48C", heightScale: 1.06, url: nil),
        .init(id: "doll_neutral_default", name: "小七", gender: .neutral, skin: "#F0C0A8", heightScale: 0.98, url: nil),
    ]

    static let clothes: [ClothItem] = [
        // 上衣
        .init(id: "top_tee_white", name: "白色 T 恤", category: "top", kind: "tee", color: "#F5F5F7"),
        .init(id: "top_tee_black", name: "黑色 T 恤", category: "top", kind: "tee", color: "#2B2B2E"),
        .init(id: "top_shirt_blue", name: "蓝色衬衫", category: "top", kind: "shirt", color: "#5B8DEF"),
        .init(id: "top_hoodie_gray", name: "灰色卫衣", category: "top", kind: "hoodie", color: "#8E8E93"),
        .init(id: "top_hoodie_pink", name: "粉色卫衣", category: "top", kind: "hoodie", color: "#F4A6C0", price: 6),
        .init(id: "top_sweater_red", name: "红色毛衣", category: "top", kind: "sweater", color: "#C4453C"),
        .init(id: "top_jacket_denim", name: "牛仔夹克", category: "top", kind: "jacket", color: "#4A6B8A", price: 8),
        .init(id: "top_coat_beige", name: "驼色大衣", category: "top", kind: "coat", color: "#C8A882", price: 12),
        // 下装
        .init(id: "bot_jeans_blue", name: "牛仔裤", category: "bottom", kind: "pants", color: "#4A6B9A"),
        .init(id: "bot_cargo_gray", name: "工装裤", category: "bottom", kind: "pants", color: "#7A7A6E"),
        .init(id: "bot_shorts_beige", name: "休闲短裤", category: "bottom", kind: "shorts", color: "#D8C8A8"),
        .init(id: "bot_skirt_plaid", name: "百褶裙", category: "bottom", kind: "skirt", color: "#9A4A5A", price: 6),
        .init(id: "bot_longskirt_black", name: "黑色长裙", category: "bottom", kind: "longskirt", color: "#2B2B2E"),
        // 围巾
        .init(id: "scarf_knit_gray", name: "深灰针织围巾", category: "scarf", kind: "scarf", color: "#5A5A5E"),
        .init(id: "scarf_long_red", name: "红色长围巾", category: "scarf", kind: "scarflong", color: "#B4443C", price: 4),
        .init(id: "scarf_neck_orange", name: "活力橙围脖", category: "scarf", kind: "scarfneck", color: "#FF9500"),
        // 帽子（互斥组 hat）
        .init(id: "hat_cap_black", name: "黑色棒球帽", category: "hat", kind: "cap", color: "#2B2B2E", exclusiveGroup: "hat"),
        .init(id: "hat_beanie_knit", name: "针织帽", category: "hat", kind: "beanie", color: "#7A5A8A", exclusiveGroup: "hat"),
        .init(id: "hat_beret_red", name: "红色贝雷帽", category: "hat", kind: "beret", color: "#B4443C", exclusiveGroup: "hat", price: 5),
        .init(id: "hat_bucket_cream", name: "渔夫帽", category: "hat", kind: "bucket", color: "#E8DCC8", exclusiveGroup: "hat"),
        // 鞋子
        .init(id: "shoe_sneakers_white", name: "白色运动鞋", category: "shoes", kind: "sneakers", color: "#F0F0F2"),
        .init(id: "shoe_leather_black", name: "黑色皮鞋", category: "shoes", kind: "leather", color: "#2B2B2E"),
        .init(id: "shoe_boots_brown", name: "棕色短靴", category: "shoes", kind: "boots", color: "#6B4A32", price: 7),
        // 发型
        .init(id: "hair_short_black", name: "黑色短发", category: "hair", kind: "hairShort", color: "#2B2B2E"),
        .init(id: "hair_long_brown", name: "棕色长发", category: "hair", kind: "hairLong", color: "#5A3A28"),
        .init(id: "hair_curly_gold", name: "金色卷发", category: "hair", kind: "hairCurly", color: "#C8A050", price: 5),
        .init(id: "hair_pony_pink", name: "粉色马尾", category: "hair", kind: "hairPony", color: "#E88AA8", price: 5),
        // 配饰
        .init(id: "acc_glasses_black", name: "黑框眼镜", category: "accessory", kind: "glasses", color: "#2B2B2E"),
        .init(id: "acc_necklace_gold", name: "金色项链", category: "accessory", kind: "necklace", color: "#D8B84A", price: 4),
        .init(id: "acc_bag_brown", name: "棕色挎包", category: "accessory", kind: "bag", color: "#6B4A32", price: 5),
        .init(id: "acc_earring_pearl", name: "珍珠耳饰", category: "accessory", kind: "earring", color: "#F0EAE0", price: 3),
    ]

    /// 互斥规则（后台可配置；内置兜底）
    static let exclusiveRules: [String: String] = ["hat": "hat"]
}

// MARK: - SwiftUI Color(hex:)

import SwiftUI

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
