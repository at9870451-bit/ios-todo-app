// DollStudio3D — AIAssistant：AI 穿搭助手（服务端 AI 优先，失败降级本地规则引擎并明确标注）
import Foundation

struct AIPlanResult {
    let slots: [String: OutfitSlot]
    let reason: String
    let source: String   // "server-ai" / "local-rules"
}

@MainActor
enum AIAssistant {

    /// 生成搭配方案：优先 POST /api/ai/outfits（Key 在服务端），失败走本地规则
    static func plan(store: OutfitStore, prompt: String) async -> AIPlanResult {
        let base = store.apiBase
        if base.hasPrefix("http"), store.remoteCatalogLoaded || base.contains("http") {
            if let r = try? await APIClient.shared.aiOutfit(
                base: base, token: store.authToken, gender: store.gender,
                prompt: prompt, catalog: store.catalog) {
                var slots: [String: OutfitSlot] = [:]
                for plan in r.items {
                    if let item = store.itemById(plan.cloth_id) {
                        slots[plan.category.isEmpty ? item.category : plan.category] =
                            OutfitSlot(clothId: item.id, color: item.color)
                    }
                }
                if !slots.isEmpty {
                    return AIPlanResult(slots: slots,
                                        reason: r.reason ?? "AI 已按你的描述完成搭配。",
                                        source: r.source ?? "server-ai")
                }
            }
        }
        return localPlan(store: store, prompt: prompt)
    }

    // MARK: 本地规则引擎（可运行示例：风格关键词 × 内置目录匹配）

    static func localPlan(store: OutfitStore, prompt: String) -> AIPlanResult {
        let p = prompt.lowercased()
        func pick(_ category: String, _ candidates: [String]) -> OutfitSlot? {
            for id in candidates {
                if let item = store.itemById(id), store.canWear(item) {
                    return OutfitSlot(clothId: item.id, color: item.color)
                }
            }
            // 兜底：该分类任一免费服装
            if let any = store.catalog.first(where: { $0.category == category && $0.isFree }) {
                return OutfitSlot(clothId: any.id, color: any.color)
            }
            return nil
        }

        var slots: [String: OutfitSlot] = [:]
        var reason: String

        let wantsWinter = p.contains("秋冬") || p.contains("冬") || p.contains("保暖")
        let isStreet = p.contains("街头") || p.contains("潮流") || p.contains("hip")
        let isJapanese = p.contains("日系") || p.contains("日")
        let isKorean = p.contains("韩") || p.contains("温柔")
        let isSport = p.contains("运动") || p.contains("健身")
        let isBusiness = p.contains("商务") || p.contains("正式") || p.contains("上班")
        let isCute = p.contains("可爱") || p.contains("甜美") || p.contains("萌")

        if isSport {
            slots["top"] = pick("top", ["top_tee_white"])
            slots["bottom"] = pick("bottom", ["bot_shorts_beige"])
            slots["shoes"] = pick("shoes", ["shoe_sneakers_white"])
            reason = "运动风：轻便 T 恤 + 短裤 + 白色运动鞋，干净利落。"
        } else if isBusiness {
            slots["top"] = pick("top", ["top_shirt_blue"])
            slots["bottom"] = pick("bottom", ["bot_cargo_gray", "bot_jeans_blue"])
            slots["shoes"] = pick("shoes", ["shoe_leather_black"])
            slots["accessory"] = pick("accessory", ["acc_glasses_black"])
            reason = "商务风：衬衫 + 深色裤装 + 皮鞋，黑框眼镜收束专业感。"
        } else if isCute {
            slots["top"] = pick("top", ["top_hoodie_pink", "top_tee_white"])
            slots["bottom"] = pick("bottom", ["bot_skirt_plaid"])
            slots["hair"] = pick("hair", ["hair_pony_pink", "hair_long_brown"])
            slots["shoes"] = pick("shoes", ["shoe_sneakers_white"])
            slots["accessory"] = pick("accessory", ["acc_earring_pearl"])
            reason = "甜美风：粉色卫衣 + 百褶裙 + 粉色马尾，点缀珍珠耳饰。"
        } else if isJapanese {
            slots["top"] = pick("top", ["top_tee_white", "top_sweater_red"])
            slots["bottom"] = pick("bottom", ["bot_skirt_plaid", "bot_jeans_blue"])
            slots["hat"] = pick("hat", ["hat_beret_red"])
            slots["shoes"] = pick("shoes", ["shoe_sneakers_white"])
            reason = "日系风：素色上衣 + 百褶裙 + 贝雷帽，松弛感低饱和。"
        } else if isKorean {
            slots["top"] = pick("top", ["top_shirt_blue", "top_tee_white"])
            slots["bottom"] = pick("bottom", ["bot_longskirt_black", "bot_jeans_blue"])
            slots["accessory"] = pick("accessory", ["acc_necklace_gold"])
            slots["shoes"] = pick("shoes", ["shoe_leather_black"])
            reason = "韩系风：衬衫 + 长裙，一条金色项链提亮整体。"
        } else if wantsWinter || isStreet {
            slots["top"] = pick("top", ["top_hoodie_gray", "top_sweater_red"])
            slots["bottom"] = pick("bottom", ["bot_cargo_gray"])
            slots["scarf"] = pick("scarf", ["scarf_knit_gray"])
            slots["hat"] = pick("hat", ["hat_beanie_knit"])
            slots["shoes"] = pick("shoes", ["shoe_sneakers_white", "shoe_boots_brown"])
            reason = wantsWinter
                ? "秋冬保暖：卫衣 + 工装裤，针织围巾与针织帽双重御寒。"
                : "街头风：宽松卫衣 + 工装裤 + 针织帽，层次感来自围巾。"
        } else {
            slots["top"] = pick("top", ["top_tee_white"])
            slots["bottom"] = pick("bottom", ["bot_jeans_blue"])
            slots["shoes"] = pick("shoes", ["shoe_sneakers_white"])
            reason = "经典百搭：白 T + 牛仔裤 + 运动鞋，怎么穿都不出错。"
        }

        // 移除 nil
        slots = slots.filter { $0.value.clothId.isEmpty == false }
        return AIPlanResult(slots: slots,
                            reason: reason + "（本地演示模式：接入后端 AI API 后由大模型生成）",
                            source: "local-rules")
    }
}
