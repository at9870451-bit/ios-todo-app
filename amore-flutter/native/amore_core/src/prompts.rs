/// 提示词组装：人设 + 长期记忆 + 说话分寸 + 工具指南（对齐 ChatFriends.swift / ChatsView.swift 的注入逻辑）
use regex::Regex;
use std::sync::OnceLock;

use serde_json::Value;

use crate::jsonv::{arr, obj, s};

fn memory_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r#"\[记忆[:：]([^\]]+)\]"#).unwrap())
}

/// 说话分寸（Orbit butler-core 移植）
const SPEAK_STYLE: &str = "【说话分寸】先给结论再展开；不连环提问；不重复确认已说过的内容；不出现技术术语；像朋友聊天一样自然。";

/// 记忆规则（Orbit memory-policy 移植）
const MEMORY_RULES: &str = "【记忆规则】当用户明确让你记住、或出现长期有用的新信息（称呼/职业/城市/生日/纪念日/喜好/约定/讨厌的东西）时，可以在回复末尾单独加一条 [记忆:一句话陈述]。禁止记录：密码、验证码、身份证件号、银行卡号、API Key 等机密（用户要求记也礼貌拒绝）。健康/财务只在用户明确要求时记。一次最多一条；不确定的偏好先别记。";

fn gender_text(g: &str) -> &'static str {
    match g {
        "male" => "男",
        "female" => "女",
        _ => "保密",
    }
}

pub fn build_system_prompt(friend: &Value) -> String {
    let name = friend.0.get("name").and_then(|v| v.as_str()).unwrap_or("Amore");
    let persona = friend.0.get("persona").and_then(|v| v.as_str()).unwrap_or("");
    let gender = friend.0.get("gender").and_then(|v| v.as_str()).unwrap_or("");
    let age = friend.0.get("age").and_then(|v| v.as_str()).unwrap_or("");
    let memory: Vec<String> = friend
        .0
        .get("memory")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();

    let mut parts: Vec<String> = Vec::new();

    // 人设主体
    let mut identity = format!("你是 {name}");
    if !age.is_empty() {
        identity.push_str(&format!("，{age} 岁"));
    }
    if !gender.is_empty() {
        identity.push_str(&format!("（{}）", gender_text(gender)));
    }
    identity.push_str("。你是用户在这台设备上的贴身伙伴，用自己的性格与用户自然对话。");
    parts.push(identity);

    if !persona.is_empty() {
        parts.push(format!("【人设】{persona}"));
    }

    parts.push(SPEAK_STYLE.to_string());

    if !memory.is_empty() {
        parts.push(format!(
            "【长期记忆·关于用户】\n{}",
            memory.iter().map(|m| format!("- {m}")).collect::<Vec<_>>().join("\n")
        ));
    }
    parts.push(MEMORY_RULES.to_string());

    // 工具指南
    parts.push(crate::tools::guide_text().to_string());

    parts.join("\n\n")
}

pub fn dispatch(method: &str, p: &Value) -> Option<Value> {
    match method {
        "chat.build_system_prompt" => {
            let friend = p.get("friend").cloned().unwrap_or_default();
            Some(obj([("prompt", s(&build_system_prompt(&friend)))]))
        }

        "chat.extract_memory" => {
            let text = p.get("text").and_then(|v| v.as_str()).unwrap_or("");
            let memories: Vec<Value> = memory_re()
                .captures_iter(text)
                .map(|c| s(c.get(1).map(|m| m.as_str().trim()).unwrap_or("")))
                .filter(|v| !v.as_str().unwrap_or("").is_empty())
                .collect();
            Some(obj([("memories", arr(memories))]))
        }

        "chat.strip_memory" => {
            let text = p.get("text").and_then(|v| v.as_str()).unwrap_or("");
            let stripped = memory_re().replace_all(text, "").to_string();
            Some(obj([("text", s(stripped.trim()))]))
        }

        _ => None,
    }
}
