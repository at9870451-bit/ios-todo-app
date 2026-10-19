import Foundation

/// Operit iOS 开源的 AI 厂商目录（移植自 YChaiyi/Operit-iOS 的 ModelCatalog.rs）
struct AIVendor: Identifiable, Hashable {
    let key: String
    let name: String
    let group: String
    let base: String
    let model: String
    let format: String
    var id: String { key }
}

enum AIVendorCatalog {

    static let all: [AIVendor] = [
        AIVendor(key: "openai", name: "OpenAI", group: "官方", base: "https://api.openai.com/v1", model: "gpt-3.5-turbo", format: "chat"),
        AIVendor(key: "openai_responses", name: "OpenAI Responses", group: "官方", base: "https://api.openai.com/v1", model: "", format: "responses"),
        AIVendor(key: "openai_responses_generic", name: "OpenAI Responses（自定义）", group: "自定义", base: "", model: "", format: "responses"),
        AIVendor(key: "openai_generic", name: "OpenAI 兼容（自定义）", group: "自定义", base: "", model: "", format: "chat"),
        AIVendor(key: "anthropic", name: "Anthropic Claude", group: "官方", base: "https://api.anthropic.com/v1", model: "claude-fable-5", format: "chat"),
        AIVendor(key: "anthropic_generic", name: "Claude（自定义）", group: "自定义", base: "", model: "", format: "chat"),
        AIVendor(key: "google", name: "Google Gemini", group: "官方", base: "https://generativelanguage.googleapis.com/v1beta/models", model: "gemini-2.0-flash", format: "chat"),
        AIVendor(key: "gemini_generic", name: "Gemini（自定义）", group: "自定义", base: "", model: "", format: "chat"),
        AIVendor(key: "baidu", name: "百度文心", group: "国内", base: "https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop", model: "", format: "chat"),
        AIVendor(key: "aliyun", name: "阿里通义千问", group: "国内", base: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "", format: "chat"),
        AIVendor(key: "xunfei", name: "讯飞星火", group: "国内", base: "https://spark-api-open.xf-yun.com/v2", model: "", format: "chat"),
        AIVendor(key: "zhipu", name: "智谱 GLM", group: "国内", base: "https://open.bigmodel.cn/api/paas/v4", model: "", format: "chat"),
        AIVendor(key: "baichuan", name: "百川", group: "国内", base: "https://api.baichuan-ai.com/v1", model: "", format: "chat"),
        AIVendor(key: "moonshot", name: "月之暗面 Kimi", group: "国内", base: "https://api.moonshot.cn/v1", model: "", format: "chat"),
        AIVendor(key: "mimo", name: "小米 MiMo", group: "国内", base: "https://api.xiaomimimo.com/v1", model: "", format: "chat"),
        AIVendor(key: "deepseek", name: "DeepSeek 深度求索", group: "国内", base: "https://api.deepseek.com/v1", model: "deepseek-chat", format: "chat"),
        AIVendor(key: "mistral", name: "Mistral", group: "聚合", base: "https://codestral.mistral.ai/v1", model: "codestral-latest", format: "chat"),
        AIVendor(key: "siliconflow", name: "硅基流动", group: "国内", base: "https://api.siliconflow.cn/v1", model: "baidu/ERNIE-4.5-300B-A47B", format: "chat"),
        AIVendor(key: "iflow", name: "iFlow 心流", group: "国内", base: "https://apis.iflow.cn/v1", model: "", format: "chat"),
        AIVendor(key: "openrouter", name: "OpenRouter 聚合", group: "聚合", base: "https://openrouter.ai/api/v1", model: "ai21/jamba-large-1.7", format: "chat"),
        AIVendor(key: "four_router", name: "4Router 聚合", group: "聚合", base: "https://4router.net/v1", model: "", format: "chat"),
        AIVendor(key: "nous_portal", name: "Nous Portal", group: "聚合", base: "https://inference-api.nousresearch.com/v1", model: "", format: "chat"),
        AIVendor(key: "infiniai", name: "无问芯穹", group: "国内", base: "https://cloud.infini-ai.com/maas/v1", model: "", format: "chat"),
        AIVendor(key: "alipay_bailing", name: "支付宝百灵", group: "国内", base: "https://api.tbox.cn/api/llm/v1", model: "", format: "chat"),
        AIVendor(key: "doubao", name: "字节豆包", group: "国内", base: "https://ark.cn-beijing.volces.com/api/v3", model: "", format: "chat"),
        AIVendor(key: "nvidia", name: "NVIDIA NIM", group: "聚合", base: "https://integrate.api.nvidia.com/v1", model: "", format: "chat"),
        AIVendor(key: "lmstudio", name: "LM Studio 本地", group: "本地", base: "http://localhost:1234/v1", model: "", format: "chat"),
        AIVendor(key: "ollama", name: "Ollama 本地", group: "本地", base: "http://localhost:11434/v1", model: "", format: "chat"),
        AIVendor(key: "openai_local", name: "本地 OpenAI", group: "本地", base: "http://localhost:8000/v1", model: "", format: "chat"),
        AIVendor(key: "local_model", name: "本地模型", group: "本地", base: "", model: "", format: "chat"),
        AIVendor(key: "ppinfra", name: "派欧云", group: "国内", base: "https://api.ppinfra.com/openai/v1", model: "", format: "chat"),
        AIVendor(key: "novita", name: "Novita AI", group: "聚合", base: "https://api.novita.ai/openai/v1", model: "", format: "chat"),
        AIVendor(key: "other", name: "其他", group: "自定义", base: "", model: "", format: "chat"),
    ]

    static var groups: [String] { ["官方", "国内", "聚合", "本地", "自定义"] }

    static func vendors(in group: String) -> [AIVendor] { all.filter { $0.group == group } }

    static func vendor(_ key: String) -> AIVendor? { all.first { $0.key == key } }

    /// 端点根地址（去掉 /chat/completions 等后缀）
    static func rootBase(_ key: String) -> String {
        guard let v = vendor(key) else { return "" }
        var b = v.base
        for suffix in ["/chat/completions", "/responses", "/messages"] {
            if b.hasSuffix(suffix) { b = String(b.dropLast(suffix.count)) }
        }
        return b
    }
}
