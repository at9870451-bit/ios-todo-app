import Foundation

/// Operit 开源项目的 AI 厂商配置目录（移植自 ApiProviderConfigCollect.kt）
/// 每个厂商预置：默认 API 端点、默认模型、协议格式
struct AIVendor: Identifiable, Hashable {
    let key: String         // 与 Provider.vendor 对应
    let name: String        // 显示名
    let group: String       // 官方 / 国内 / 聚合 / 本地 / 自定义
    let base: String        // 默认端点（含 /chat/completions 或 /responses）
    let model: String       // 默认模型
    let format: String      // chat / responses

    var id: String { key }
}

enum AIVendorCatalog {

    static let all: [AIVendor] = [
        AIVendor(key: "openai", name: "OpenAI", group: "官方", base: "https://api.openai.com/v1/chat/completions", model: "gpt-4o", format: "chat"),
        AIVendor(key: "xai", name: "xAI Grok", group: "官方", base: "https://api.x.ai/v1/chat/completions", model: "grok-4.6", format: "chat"),
        AIVendor(key: "openai_responses", name: "OpenAI Responses", group: "官方", base: "https://api.openai.com/v1/responses", model: "gpt-4o", format: "responses"),
        AIVendor(key: "openai_codex", name: "OpenAI Codex", group: "官方", base: "https://chatgpt.com/backend-api/codex/responses", model: "gpt-5.6-luna", format: "chat"),
        AIVendor(key: "openai_responses_generic", name: "OpenAI Responses（自定义）", group: "自定义", base: "", model: "", format: "responses"),
        AIVendor(key: "openai_generic", name: "OpenAI 兼容（自定义）", group: "自定义", base: "", model: "", format: "chat"),
        AIVendor(key: "anthropic", name: "Anthropic Claude", group: "官方", base: "https://api.anthropic.com/v1/messages", model: "claude-3-opus-20240229", format: "chat"),
        AIVendor(key: "anthropic_generic", name: "Claude（自定义端点）", group: "自定义", base: "", model: "", format: "chat"),
        AIVendor(key: "google", name: "Google Gemini", group: "官方", base: "https://generativelanguage.googleapis.com/v1beta/models", model: "gemini-2.0-flash", format: "chat"),
        AIVendor(key: "gemini_generic", name: "Gemini（自定义端点）", group: "自定义", base: "", model: "gemini-2.0-flash", format: "chat"),
        AIVendor(key: "deepseek", name: "DeepSeek 深度求索", group: "国内", base: "https://api.deepseek.com/v1/chat/completions", model: "deepseek-v4-flash", format: "chat"),
        AIVendor(key: "baidu", name: "百度文心一言", group: "国内", base: "https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop/chat/completions", model: "ernie-bot-4", format: "chat"),
        AIVendor(key: "aliyun", name: "阿里通义千问", group: "国内", base: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", model: "qwen-max", format: "chat"),
        AIVendor(key: "xunfei", name: "讯飞星火", group: "国内", base: "https://spark-api-open.xf-yun.com/v2/chat/completions", model: "spark3.5", format: "chat"),
        AIVendor(key: "zhipu", name: "智谱 GLM", group: "国内", base: "https://open.bigmodel.cn/api/paas/v4/chat/completions", model: "glm-4.5", format: "chat"),
        AIVendor(key: "baichuan", name: "百川大模型", group: "国内", base: "https://api.baichuan-ai.com/v1/chat/completions", model: "baichuan4", format: "chat"),
        AIVendor(key: "moonshot", name: "月之暗面 Kimi", group: "国内", base: "https://api.moonshot.cn/v1/chat/completions", model: "moonshot-v1-128k", format: "chat"),
        AIVendor(key: "mimo", name: "小米 MiMo", group: "国内", base: "https://api.xiaomimimo.com/v1/chat/completions", model: "mimo-v2.5-pro", format: "chat"),
        AIVendor(key: "mistral", name: "Mistral", group: "聚合", base: "https://codestral.mistral.ai/v1/chat/completions", model: "codestral-latest", format: "chat"),
        AIVendor(key: "siliconflow", name: "硅基流动", group: "国内", base: "https://api.siliconflow.cn/v1/chat/completions", model: "yi-1.5-34b", format: "chat"),
        AIVendor(key: "iflow", name: "iFlow 心流", group: "国内", base: "https://apis.iflow.cn/v1/chat/completions", model: "TBStars2-200B-A13B", format: "chat"),
        AIVendor(key: "openrouter", name: "OpenRouter 聚合", group: "聚合", base: "https://openrouter.ai/api/v1/chat/completions", model: "google/gemini-pro", format: "chat"),
        AIVendor(key: "opencode", name: "OpenCode", group: "聚合", base: "https://opencode.ai/zen", model: "", format: "chat"),
        AIVendor(key: "four_router", name: "4Router 聚合", group: "聚合", base: "https://4router.net/v1/chat/completions", model: "gpt-5.4-mini", format: "chat"),
        AIVendor(key: "nous_portal", name: "Nous Portal", group: "聚合", base: "https://inference-api.nousresearch.com/v1/chat/completions", model: "", format: "chat"),
        AIVendor(key: "infiniai", name: "无问芯穹", group: "国内", base: "https://cloud.infini-ai.com/maas/v1/chat/completions", model: "infini-mini", format: "chat"),
        AIVendor(key: "alipay_bailing", name: "支付宝百灵", group: "国内", base: "https://api.tbox.cn/api/llm/v1/chat/completions", model: "Ling-1T", format: "chat"),
        AIVendor(key: "doubao", name: "字节豆包", group: "国内", base: "https://ark.cn-beijing.volces.com/api/v3/chat/completions", model: "Doubao-pro-4k", format: "chat"),
        AIVendor(key: "nvidia", name: "NVIDIA NIM", group: "聚合", base: "https://integrate.api.nvidia.com/v1/chat/completions", model: "nvidia/nemotron-3-nano-30b-a3b", format: "chat"),
        AIVendor(key: "lmstudio", name: "LM Studio 本地", group: "本地", base: "http://localhost:1234/v1/chat/completions", model: "meta-llama-3.1-8b-instruct", format: "chat"),
        AIVendor(key: "ollama", name: "Ollama 本地", group: "本地", base: "http://localhost:11434/v1/chat/completions", model: "", format: "chat"),
        AIVendor(key: "openai_local", name: "本地 OpenAI 兼容", group: "本地", base: "http://localhost:8000/v1/chat/completions", model: "", format: "chat"),
        AIVendor(key: "mnn", name: "MNN 本地", group: "本地", base: "", model: "", format: "chat"),
        AIVendor(key: "llama_cpp", name: "llama.cpp 本地", group: "本地", base: "", model: "", format: "chat"),
        AIVendor(key: "ppinfra", name: "派欧云 PPIO", group: "国内", base: "https://api.ppinfra.com/openai/v1/chat/completions", model: "gpt-4o-mini", format: "chat"),
        AIVendor(key: "novita", name: "Novita AI", group: "聚合", base: "https://api.novita.ai/openai/v1/chat/completions", model: "moonshotai/kimi-k2.5", format: "chat"),
        AIVendor(key: "minimax", name: "MiniMax", group: "国内", base: "https://api.minimaxi.com/v1/chat/completions", model: "MiniMax-M2.7", format: "chat"),
    ]

    static var groups: [String] {
        ["官方", "国内", "聚合", "本地", "自定义"]
    }

    static func vendors(in group: String) -> [AIVendor] {
        all.filter { $0.group == group }
    }

    static func vendor(_ key: String) -> AIVendor? {
        all.first { $0.key == key }
    }

    /// 端点根地址（去掉 /chat/completions 等后缀，供 Provider.baseURL 使用）
    static func rootBase(_ key: String) -> String {
        guard let v = vendor(key) else { return "" }
        var b = v.base
        for suffix in ["/chat/completions", "/responses", "/messages"] {
            if b.hasSuffix(suffix) { b = String(b.dropLast(suffix.count)) }
        }
        return b
    }
}
