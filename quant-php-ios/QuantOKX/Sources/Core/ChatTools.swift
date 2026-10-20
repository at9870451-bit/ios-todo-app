import Foundation
import UIKit

/// Operit 式工具调用循环（本地实现，来源：operit-tools ToolExecutionManager + SystemPromptConfig）
/// 模型输出 <tool name="..."><param name="...">value</param></tool> → App 本地执行 → 结果以随机 tag XML 回注
enum ChatTools {

    struct ToolCall {
        let name: String
        let params: [String: String]
        let range: Range<String.Index>
    }

    // MARK: - 解析（对齐 ChatMarkupRegex.tool_call_matches）

    static func calls(in text: String) -> [ToolCall] {
        var out: [ToolCall] = []
        // <tool name="xxx"> ... </tool>（容忍 tool_ 前缀随机名）
        guard let regex = try? NSRegularExpression(pattern: #"<(tool[_a-z0-9]*)\s+name="([^"]+)"[^>]*>([\s\S]*?)</\1>"#, options: [.caseInsensitive]) else { return out }
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = m.range(at: 2)
            guard name.location != NSNotFound else { continue }
            let body = m.range(at: 3)
            var params: [String: String] = [:]
            if body.location != NSNotFound, let pre = try? NSRegularExpression(pattern: #"<param\s+name="([^"]+)"[^>]*>([\s\S]*?)</param>"#, options: [.caseInsensitive]) {
                for pm in pre.matches(in: text, range: body) {
                    let k = ns.substring(with: pm.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let v = ns.substring(with: pm.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    params[k] = v
                }
            }
            guard let r = Range(m.range, in: text) else { continue }
            out.append(ToolCall(name: ns.substring(with: name).trimmingCharacters(in: .whitespaces), params: params, range: r))
        }
        return out
    }

    /// 随机工具结果 tag（对齐 ConversationMarkupManager.generate_random_tool_result_tag_name）
    private static func randomTag() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let s = String((0..<6).map { _ in letters.randomElement()! })
        return "tool_result_\(s)"
    }

    static func resultXml(tool name: String, status: String, content: String) -> String {
        let tag = randomTag()
        return "<\(tag) name=\"\(name)\" status=\"\(status)\">\n\(content)\n</\(tag)>"
    }

    /// 从展示文本中剥离全部工具标记
    static func stripMarkup(_ text: String) -> String {
        var s = text
        if let re = try? NSRegularExpression(pattern: #"<(tool[_a-z0-9]*|tool_result_[a-z0-9]+)\s[^>]*>[\s\S]*?</\1>"#, options: [.caseInsensitive]) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 本地工具集（iOS 沙盒内可执行）

    static let guide = """
    【工具调用】你可以调用以下本机工具（需要信息时主动调用）：
    1. get_time —— 无参数，获取当前日期时间
    2. list_friends —— 无参数，列出本机好友（名字/性别/年龄）
    3. list_chats —— 无参数，本机聊天记录概况（每会话条数）
    4. calc —— 参数 expression：四则运算，如 12*(3+4)
    5. device_info —— 无参数，设备与 App 信息
    6. random —— 参数 min,max：随机整数
    调用格式（XML 前必须换行，起始标签在行首）：
    <tool name="get_time">
    </tool>
    <tool name="calc">
    <param name="expression">12*(3+4)</param>
    </tool>
    调用后系统会自动把工具结果回传给你，你再继续回答。复杂任务可拆步多次调用。回答里不要显示 XML。
    """

    static func exec(name: String, params: [String: String]) -> (status: String, content: String) {
        switch name {
        case "get_time":
            return ("ok", DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))
        case "list_friends":
            let fs = FriendStore.shared.friends
            guard !fs.isEmpty else { return ("ok", "本机暂无好友") }
            return ("ok", fs.map { "\($0.name)｜\($0.genderText)\($0.age.isEmpty ? "" : " \($0.age)岁")" }.joined(separator: "\n"))
        case "list_chats":
            var out: [String] = []
            for f in FriendStore.shared.friends {
                let n = LocalHistory.count("friend.\(f.id)")
                if n > 0 { out.append("好友·\(f.name)：\(n) 条") }
            }
            for g in GroupStore.shared.groups {
                let n = LocalHistory.count("group.\(g.id)")
                if n > 0 { out.append("群·\(g.name)：\(n) 条") }
            }
            return ("ok", out.isEmpty ? "本机暂无聊天记录" : out.joined(separator: "\n"))
        case "calc":
            let expr = params["expression"] ?? ""
            guard !expr.isEmpty, expr.allSatisfy({ "+-*/(). 0123456789".contains($0) }) else {
                return ("error", "算式无效，仅支持数字与 +-*/()")
            }
            guard let v = (NSExpression(format: expr).expressionValue(with: nil, context: nil) as? Double) else {
                return ("error", "无法计算")
            }
            let fmt = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.4f", v)
            return ("ok", "\(expr) = \(fmt)")
        case "device_info":
            let dev = UIDevice.current
            let fm = FileManager.default
            let docSize = (try? fm.allocatedSizeOfDirectory(at: fm.urls(for: .documentDirectory, in: .userDomainMask)[0])) ?? 0
            return ("ok", """
            设备：\(dev.model) · iOS \(dev.systemVersion)
            App：Amore 3.9 (build 86)
            本机数据：\(ByteCountFormatter.string(fromByteCount: Int64(docSize), countStyle: .file))
            好友 \(FriendStore.shared.friends.count) 位 · 群 \(GroupStore.shared.groups.count) 个
            """)
        case "random":
            let parts = (params["min,max"] ?? params["min"] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let lo = parts.count > 0 ? parts[0] : 1
            let hi = parts.count > 1 ? parts[1] : 100
            return ("ok", String(Int.random(in: min(lo, hi)...max(lo, hi))))
        default:
            return ("error", "未知工具 \(name)")
        }
    }

    /// 执行一轮：解析调用 → 执行 → 生成回注文本
    static func roundtrip(_ reply: String) -> (clean: String, feedback: String?, called: [String]) {
        let calls = calls(in: reply)
        guard !calls.isEmpty else { return (reply, nil, []) }
        var results: [String] = []
        var names: [String] = []
        for c in calls {
            let r = exec(name: c.name, params: c.params)
            names.append(c.name)
            results.append(resultXml(tool: c.name, status: r.status, content: r.content))
        }
        let clean = stripMarkup(reply)
        let feedback = "工具执行结果：\n" + results.joined(separator: "\n")
        return (clean, feedback, names)
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let en = try contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
        for f in en {
            let vals = try f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if vals.isDirectory == true {
                size += (try? allocatedSizeOfDirectory(at: f)) ?? 0
            } else {
                size += UInt64(vals.fileSize ?? 0)
            }
        }
        return size
    }
}
