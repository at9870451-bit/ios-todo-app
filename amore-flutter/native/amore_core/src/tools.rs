/// 工具调用协议：解析 `<tool name=".."><param name="..">v</param></tool>`，
/// 本地执行 6 个工具，生成随机 tag 回注 XML（对齐 ChatTools.swift / Operit ChatMarkupRegex）
use std::sync::OnceLock;

use regex::Regex;

use crate::jsonv::{arr, f, n, obj, s, Json};
use crate::store;

pub fn guide_text() -> &'static str {
    r#"【工具调用】你可以调用以下本机工具（需要信息时主动调用）：
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
调用后系统会自动把工具结果回传给你，你再继续回答。复杂任务可拆步多次调用。回答里不要显示 XML。"#
}

struct Patterns {
    call: Regex,
    param: Regex,
    strip: Regex,
    memory: Regex,
}

fn patterns() -> &'static Patterns {
    static P: OnceLock<Patterns> = OnceLock::new();
    P.get_or_init(|| Patterns {
        call: Regex::new(r#"(?is)<(tool[_a-z0-9]*)\s+name="([^"]+)"[^>]*>(.*?)</\1>"#).unwrap(),
        param: Regex::new(r#"(?is)<param\s+name="([^"]+)"[^>]*>(.*?)</param>"#).unwrap(),
        strip: Regex::new(r#"(?is)<(tool[_a-z0-9]*|tool_result_[a-z0-9]+)\s[^>]*>.*?</\1>"#).unwrap(),
        memory: Regex::new(r#"[记忆[:：]([^\]]+)]"#).unwrap(),
    })
}

/// 一个解析出的工具调用
struct ToolCall {
    name: String,
    params: Vec<(String, String)>,
    start: usize,
    end: usize,
}

fn parse_calls(text: &str) -> Vec<ToolCall> {
    let p = patterns();
    let mut out = Vec::new();
    for c in p.call.captures_iter(text) {
        let whole = c.get(0).unwrap();
        let name = c.get(2).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        if name.is_empty() {
            continue;
        }
        let body = c.get(3).map(|m| m.as_str()).unwrap_or("");
        let mut params = Vec::new();
        for pm in p.param.captures_iter(body) {
            let k = pm.get(1).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
            let v = pm.get(2).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
            params.push((k, v));
        }
        out.push(ToolCall { name, params, start: whole.start(), end: whole.end() });
    }
    out
}

fn random_tag() -> String {
    // 6 个小写字母（用时间做种子即可，无需 rand crate）
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(12345);
    let letters = b"abcdefghijklmnopqrstuvwxyz";
    let mut s = String::new();
    let mut x = t;
    for _ in 0..6 {
        s.push(letters[(x % 26) as usize] as char);
        x /= 26;
        if x == 0 { x = (t >> 7) | 7919; }
    }
    format!("tool_result_{s}")
}

fn result_xml(name: &str, status: &str, content: &str) -> String {
    let tag = random_tag();
    format!("<{tag} name=\"{name}\" status=\"{status}\">\n{content}\n</{tag}>")
}

pub fn dispatch(method: &str, p: &Json) -> Option<Json> {
    match method {
        "chat.tools_guide" => Some(obj([("guide", s(guide_text()))])),

        "chat.parse_assistant" => {
            let text = p.0.get("text").and_then(|v| v.as_str()).unwrap_or("");
            let calls = parse_calls(text);
            if calls.is_empty() {
                return Some(obj([
                    ("clean", s(text.trim())),
                    ("feedback", Json(serde_json::Value::Null)),
                    ("called", arr(vec![])),
                ]));
            }
            let mut clean = String::with_capacity(text.len());
            let mut last = 0usize;
            for c in &calls {
                clean.push_str(&text[last..c.start]);
                last = c.end;
            }
            clean.push_str(&text[last..]);

            let mut feedback = String::new();
            let mut called = Vec::new();
            for c in &calls {
                let params: serde_json::Map<String, serde_json::Value> = c
                    .params
                    .iter()
                    .map(|(k, v)| (k.clone(), serde_json::Value::String(v.clone())))
                    .collect();
                called.push(obj([
                    ("name", s(&c.name)),
                    ("params", Json(serde_json::Value::Object(params))),
                ]));
                let (status, content) = exec(c.name, &c.params.iter().cloned().collect());
                if !feedback.is_empty() {
                    feedback.push('\n');
                }
                feedback.push_str(&result_xml(&c.name, &status, &content));
            }
            Some(obj([
                ("clean", s(clean.trim())),
                ("feedback", s(&feedback)),
                ("called", arr(called)),
            ]))
        }

        "chat.exec_tool" => {
            let name = p.0.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let mut params: Vec<(String, String)> = Vec::new();
            if let Some(m) = p.0.get("params").and_then(|v| v.as_object()) {
                for (k, v) in m {
                    params.push((k.clone(), v.as_str().unwrap_or("").to_string()));
                }
            }
            let (status, content) = exec(name, &params.iter().cloned().collect::<std::collections::HashMap<_, _>>());
            Some(obj([("status", s(&status)), ("content", s(&content))]))
        }

        _ => None,
    }
}

pub type Params = std::collections::HashMap<String, String>;

/// 本地工具执行（语义对齐 ChatTools.swift exec）
pub fn exec(name: &str, params: &Params) -> (String, String) {
    match name {
        "get_time" => {
            let ts = store::now_ts() as i64;
            ("ok".into(), fmt_local_time(ts))
        }
        "list_friends" => {
            let friends = store::friends_list();
            if friends.is_empty() {
                return ("ok".into(), "本机暂无好友".into());
            }
            let lines: Vec<String> = friends
                .iter()
                .map(|fr| {
                    let gender = fr.0.get("gender").and_then(|v| v.as_str()).unwrap_or("");
                    let g = match gender { "male" => "男", "female" => "女", _ => "保密" };
                    let age = fr.0.get("age").and_then(|v| v.as_str()).unwrap_or("");
                    let name = fr.0.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    if age.is_empty() { format!("{name}｜{g}") } else { format!("{name}｜{g} {age}岁") }
                })
                .collect();
            ("ok".into(), lines.join("\n"))
        }
        "list_chats" => {
            let mut out: Vec<String> = Vec::new();
            for fr in store::friends_list() {
                let id = fr.0.get("id").and_then(|v| v.as_str()).unwrap_or("");
                let name = fr.0.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let n = store::count_history(&format!("friend.{id}"));
                if n > 0 {
                    out.push(format!("好友·{name}：{n} 条"));
                }
            }
            for g in store::groups_list() {
                let id = g.0.get("id").and_then(|v| v.as_str()).unwrap_or("");
                let name = g.0.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let n = store::count_history(&format!("group.{id}"));
                if n > 0 {
                    out.push(format!("群·{name}：{n} 条"));
                }
            }
            if out.is_empty() {
                ("ok".into(), "本机暂无聊天记录".into())
            } else {
                ("ok".into(), out.join("\n"))
            }
        }
        "calc" => {
            let expr = params.get("expression").cloned().unwrap_or_default();
            if expr.is_empty() || !expr.chars().all(|c| "+-*/(). 0123456789".contains(c)) {
                return ("error".into(), "算式无效，仅支持数字与 +-*/()".into());
            }
            match eval_expr(&expr.replace(' ', "")) {
                Some(v) => {
                    let text = if v.fract() == 0.0 {
                        format!("{}", v as i64)
                    } else {
                        format!("{:.4}", v)
                    };
                    ("ok".into(), format!("{expr} = {text}"))
                }
                None => ("error".into(), "无法计算".into()),
            }
        }
        "device_info" => {
            let friends_n = store::friends_list().len();
            let groups_n = store::groups_list().len();
            let docs_bytes = store::data_size();
            let pretty = if docs_bytes > 1024 * 1024 {
                format!("{:.1} MB", docs_bytes as f64 / 1024.0 / 1024.0)
            } else {
                format!("{:.1} KB", docs_bytes as f64 / 1024.0)
            };
            (
                "ok".into(),
                format!(
                    "设备：iPhone · iOS 15+\nApp：Amore 4.0 (Flutter + Rust Core)\n本机数据：{pretty}\n好友 {friends_n} 位 · 群 {groups_n} 个"
                ),
            )
        }
        "random" => {
            let raw = params.get("min,max").cloned().unwrap_or_else(|| params.get("min").cloned().unwrap_or_default());
            let parts: Vec<i64> = raw
                .split(',')
                .filter_map(|x| x.trim().parse::<i64>().ok())
                .collect();
            let lo = parts.first().copied().unwrap_or(1);
            let hi = parts.get(1).copied().unwrap_or(100);
            let (a, b) = (lo.min(hi), lo.max(hi));
            let t = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos() as i64)
                .unwrap_or(42);
            let v = a + (t % (b - a + 1));
            ("ok".into(), v.to_string())
        }
        _ => ("error".into(), format!("未知工具 {name}")),
    }
}

/// unix 秒 → "2026年10月20日 22:15:08"（UTC+8 近似，够用）
fn fmt_local_time(ts: i64) -> String {
    // 简单 civil 算法（Howard Hinnant 变体），+8 小时时区
    let secs = ts + 8 * 3600;
    let days = secs / 86400;
    let rem = secs % 86400;
    let (h, mi, sec) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y}年{m}月{d}日 {h:02}:{mi:02}:{sec:02}")
}

/// 递归下降四则运算求值（支持 + - * / 和括号）
fn eval_expr(expr: &str) -> Option<f64> {
    let bytes: Vec<char> = expr.chars().collect();
    let mut pos = 0usize;
    let v = parse_add(&bytes, &mut pos)?;
    if pos != bytes.len() {
        return None;
    }
    if v.is_finite() {
        Some(v)
    } else {
        None
    }
}

fn parse_add(chars: &[char], pos: &mut usize) -> Option<f64> {
    let mut lhs = parse_mul(chars, pos)?;
    while *pos < chars.len() {
        match chars[*pos] {
            '+' => {
                *pos += 1;
                lhs += parse_mul(chars, pos)?;
            }
            '-' => {
                *pos += 1;
                lhs -= parse_mul(chars, pos)?;
            }
            _ => break,
        }
    }
    Some(lhs)
}

fn parse_mul(chars: &[char], pos: &mut usize) -> Option<f64> {
    let mut lhs = parse_unary(chars, pos)?;
    while *pos < chars.len() {
        match chars[*pos] {
            '*' => {
                *pos += 1;
                lhs *= parse_unary(chars, pos)?;
            }
            '/' => {
                *pos += 1;
                let rhs = parse_unary(chars, pos)?;
                if rhs == 0.0 {
                    return None;
                }
                lhs /= rhs;
            }
            _ => break,
        }
    }
    Some(lhs)
}

fn parse_unary(chars: &[char], pos: &mut usize) -> Option<f64> {
    if *pos < chars.len() && chars[*pos] == '-' {
        *pos += 1;
        return parse_unary(chars, pos).map(|v| -v);
    }
    if *pos < chars.len() && chars[*pos] == '+' {
        *pos += 1;
        return parse_unary(chars, pos);
    }
    parse_atom(chars, pos)
}

fn parse_atom(chars: &[char], pos: &mut usize) -> Option<f64> {
    if *pos < chars.len() && chars[*pos] == '(' {
        *pos += 1;
        let v = parse_add(chars, pos)?;
        if *pos < chars.len() && chars[*pos] == ')' {
            *pos += 1;
            return Some(v);
        }
        return None;
    }
    let start = *pos;
    while *pos < chars.len() && (chars[*pos].is_ascii_digit() || chars[*pos] == '.') {
        *pos += 1;
    }
    if start == *pos {
        return None;
    }
    chars[start..*pos].iter().collect::<String>().parse::<f64>().ok()
}
