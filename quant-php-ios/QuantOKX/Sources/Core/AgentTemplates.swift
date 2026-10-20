import Foundation
import UIKit

/// 智能体模板（本地）：App 内置 + 用户自建，新建好友时可一键导入
struct AgentTemplate: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var desc: String = ""
    var persona: String = ""
    var gender: String = ""      // male / female / ""
    var age: String = ""
    var voiceEngine: String = "" // local / server / cloud_sf / cloud_doubao / 空=跟随全局
    var voiceId: String = ""
    var modelHint: String = ""
    var sort: Int = 0
    var enabled: Bool = true
    var builtin: Bool = false

    var genderText: String {
        switch gender {
        case "male": return "男"
        case "female": return "女"
        default: return "不限"
        }
    }
}

/// 本地智能体库（UserDefaults JSON，不依赖服务器）
@MainActor
final class AgentStore: ObservableObject {
    static let shared = AgentStore()
    @Published var templates: [AgentTemplate] = []

    private let key = "app.agent.templates.v1"

    private init() {
        load()
        if templates.isEmpty { seed() }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([AgentTemplate].self, from: data) {
            templates = list
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ t: AgentTemplate) {
        if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t }
        else { templates.append(t) }
        templates.sort { $0.sort == $1.sort ? $0.name < $1.name : $0.sort < $1.sort }
        persist()
    }

    func remove(_ t: AgentTemplate) {
        templates.removeAll { $0.id == t.id }
        persist()
    }

    var enabled: [AgentTemplate] { templates.filter(\.enabled) }

    /// 内置四套风格模板（首次启动种子）
    private func seed() {
        templates = [
            AgentTemplate(name: "温柔姐姐", desc: "温柔体贴，会照顾人", 
                          persona: "你是用户的温柔姐姐，说话轻声细语，习惯用叠词和语气词（呀、啦、嗯哼）。关心用户的身体和情绪，会提醒吃饭睡觉。偶尔撒娇但不过分。称呼用户「小宝」。", 
                          gender: "female", age: "26", voiceEngine: "", voiceId: "", modelHint: "", sort: 1, enabled: true, builtin: true),
            AgentTemplate(name: "毒舌损友", desc: "嘴毒心软的吐槽担当",
                          persona: "你是用户的毒舌损友，说话又快又损，爱吐槽用户但关键时刻靠得住。会互怼、会翻白眼（用文字表达），从不肉麻。称呼用户直接喊名字或「你小子」。", 
                          gender: "male", age: "24", voiceEngine: "", voiceId: "", modelHint: "", sort: 2, enabled: true, builtin: true),
            AgentTemplate(name: "理性助手", desc: "冷静高效，先结论后细节",
                          persona: "你是冷静高效的私人助手，回答先给结论再给依据，不废话不寒暄。擅长整理信息、拆解任务。语气克制专业，但不是机器人——偶尔冷幽默。", 
                          gender: "", age: "", voiceEngine: "", voiceId: "", modelHint: "", sort: 3, enabled: true, builtin: true),
            AgentTemplate(name: "冷淡银灰", desc: "清冷可爱的中性气质",
                          persona: "你是气质清冷的中性朋友，话不多但每句都在点上，用词简洁偏冷淡，偶尔冒出一句话戳中人心。不太用表情，最多一个句号。对用户有隐形的在意。", 
                          gender: "", age: "22", voiceEngine: "", voiceId: "", modelHint: "", sort: 4, enabled: true, builtin: true)
        ]
        persist()
    }
}
