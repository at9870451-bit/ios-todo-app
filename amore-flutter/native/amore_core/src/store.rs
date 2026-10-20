use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::jsonv::{arr, obj, s};

/// 简易 id：时间戳36进制 + 随机尾巴
pub fn new_id() -> String {
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_micros();
    let r = (ts * 7919 + 104729) % 1_000_000;
    format!("{}{:06x}", ts.to_radix_36(), r)
}

trait Radix36 {
    fn to_radix_36(self) -> String;
}
impl Radix36 for u128 {
    fn to_radix_36(self) -> String {
        let mut n = self;
        let mut out = Vec::new();
        if n == 0 {
            out.push(b'0');
        }
        while n > 0 {
            let d = (n % 36) as u8;
            out.push(if d < 10 { b'0' + d } else { b'a' + d - 10 });
            n /= 36;
        }
        out.reverse();
        String::from_utf8(out).unwrap()
    }
}

pub fn now_ts() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as f64 / 1000.0
}

/// 全局存储（数据目录 + 内存缓存 + 互斥锁）
pub struct Store {
    pub dir: PathBuf,
    pub active_provider: String,
    pub config: HashMap<String, String>,
}

static STORE: Mutex<Option<Store>> = Mutex::new(None);

fn history_dir(root: &Path) -> PathBuf {
    root.join("history")
}

fn history_file(root: &Path, key: &str) -> PathBuf {
    // key 如 friend.abc-123 → history/friend_abc-123.json
    let safe: String = key
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    history_dir(root).join(format!("{safe}.json"))
}

fn read_json(path: &Path) -> Option<Value> {
    let text = fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

/// 原子写：临时文件 + rename
fn write_json(path: &Path, value: &Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let tmp = path.with_extension("tmp");
    let text = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    fs::write(&tmp, text).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())?;
    Ok(())
}

/// 初始化（core.init）
pub fn init(data_dir: &str) {
    let dir = PathBuf::from(data_dir);
    let _ = fs::create_dir_all(dir.join("history"));
    let config: HashMap<String, String> = read_json(&dir.join("config.json"))
        .and_then(|j| serde_json::from_value(j).ok())
        .unwrap_or_default();
    let active_provider = config.get("active_provider").cloned().unwrap_or_default();
    *STORE.lock().unwrap() = Some(Store {
        dir,
        active_provider,
        config,
    });
}

fn with<R>(f: impl FnOnce(&Store) -> R, fallback: R) -> R {
    let guard = STORE.lock().unwrap();
    match guard.as_ref() {
        Some(s) => f(s),
        None => fallback,
    }
}

/// 可变访问（写操作用）
fn with_mut<R>(f: impl FnOnce(&mut Store) -> R, fallback: R) -> R {
    let mut guard = STORE.lock().unwrap();
    match guard.as_mut() {
        Some(s) => f(s),
        None => fallback,
    }
}

// ---------- 通用列表存取 ----------

fn load_array(root: &Path, name: &str) -> Vec<Value> {
    read_json(&root.join(name))
        .and_then(|j| j.as_array().cloned())
        .unwrap_or_default()
}

fn save_array(root: &Path, name: &str, items: &[Value]) {
    let _ = write_json(&root.join(name), &arr(items.to_vec()));
}

/// 按 id upsert
fn upsert(items: &mut Vec<Value>, item: Value) {
    let id = item.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let id = if id.is_empty() { new_id() } else { id };
    let mut item = item;
    item["id"] = s(&id);
    if let Some(pos) = items.iter().position(|x| x.get("id").and_then(|v| v.as_str()) == Some(id.as_str())) {
        items[pos] = item;
    } else {
        items.push(item);
    }
}

fn remove_by_id(items: &mut Vec<Value>, id: &str) -> bool {
    let before = items.len();
    items.retain(|x| x.get("id").and_then(|v| v.as_str()) != Some(id));
    items.len() != before
}

/// 按 sort 字段排序
fn by_sort(a: &Value, b: &Value) -> std::cmp::Ordering {
    let sa = a.get("sort").and_then(|v| v.as_i64()).unwrap_or(0);
    let sb = b.get("sort").and_then(|v| v.as_i64()).unwrap_or(0);
    sa.cmp(&sb).then(std::cmp::Ordering::Equal)
}

// ---------- 给其它模块的公开访问器 ----------

pub fn friends_list() -> Vec<Value> {
    with(|s| load_array(&s.dir, "friends.json"), vec![])
}

pub fn groups_list() -> Vec<Value> {
    with(|s| load_array(&s.dir, "groups.json"), vec![])
}

pub fn data_size() -> u64 {
    with(|s| dir_size(&s.dir), 0)
}

fn dir_size(path: &Path) -> u64 {
    let mut total = 0u64;
    if let Ok(entries) = fs::read_dir(path) {
        for e in entries.flatten() {
            if let Ok(m) = e.metadata() {
                if m.is_file() {
                    total += m.len();
                } else if m.is_dir() {
                    total += dir_size(&e.path());
                }
            }
        }
    }
    total
}

pub fn count_history(key: &str) -> usize {
    with(
        |s| {
            read_json(&history_file(&s.dir, key))
                .and_then(|j| j.as_array().cloned())
                .map(|a| a.len())
                .unwrap_or(0)
        },
        0,
    )
}

pub fn config_value(key: &str) -> String {
    with(|s| s.config.get(key).cloned().unwrap_or_default(), String::new())
}

pub fn set_config_value(key: &str, value: &str) {
    with_mut(
        |s| {
            s.config.insert(key.to_string(), value.to_string());
            let cfg: Value = serde_json::to_value(&s.config).unwrap_or_default();
            let _ = write_json(&s.dir.join("config.json"), &cfg);
        },
        (),
    );
}

// ---------- 分发 ----------

pub fn dispatch(method: &str, p: &Value) -> Option<Value> {
    match method {
        "store.list_friends" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "friends.json");
                items.sort_by(by_sort);
                obj([("friends", arr(items))])
            },
            obj([("friends", arr(vec![]))]),
        )),
        "store.save_friend" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "friends.json");
                upsert(&mut items, p.get("friend").cloned().unwrap_or(Value::Null));
                save_array(&s.dir, "friends.json", &items);
                obj([])
            },
            obj([]),
        )),
        "store.delete_friend" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "friends.json");
                let id = p.get("id").and_then(|v| v.as_str()).unwrap_or("");
                remove_by_id(&mut items, id);
                save_array(&s.dir, "friends.json", &items);
                obj([])
            },
            obj([]),
        )),

        "store.list_groups" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "groups.json");
                items.sort_by(by_sort);
                obj([("groups", arr(items))])
            },
            obj([("groups", arr(vec![]))]),
        )),
        "store.save_group" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "groups.json");
                upsert(&mut items, p.get("group").cloned().unwrap_or(Value::Null));
                save_array(&s.dir, "groups.json", &items);
                obj([])
            },
            obj([]),
        )),
        "store.delete_group" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "groups.json");
                let id = p.get("id").and_then(|v| v.as_str()).unwrap_or("");
                remove_by_id(&mut items, id);
                save_array(&s.dir, "groups.json", &items);
                obj([])
            },
            obj([]),
        )),

        "store.list_agents" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "agents.json");
                if items.is_empty() && !s.dir.join("agents.json").exists() {
                    items = default_agents();
                    save_array(&s.dir, "agents.json", &items);
                }
                items.sort_by(by_sort);
                obj([("agents", arr(items))])
            },
            obj([("agents", arr(vec![]))]),
        )),
        "store.save_agent" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "agents.json");
                upsert(&mut items, p.get("agent").cloned().unwrap_or(Value::Null));
                save_array(&s.dir, "agents.json", &items);
                obj([])
            },
            obj([]),
        )),
        "store.delete_agent" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "agents.json");
                let id = p.get("id").and_then(|v| v.as_str()).unwrap_or("");
                remove_by_id(&mut items, id);
                save_array(&s.dir, "agents.json", &items);
                obj([])
            },
            obj([]),
        )),

        "store.list_providers" => Some(with(
            |s| obj([("providers", arr(load_array(&s.dir, "providers.json")))]),
            obj([("providers", arr(vec![]))]),
        )),
        "store.save_provider" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "providers.json");
                upsert(&mut items, p.get("provider").cloned().unwrap_or(Value::Null));
                save_array(&s.dir, "providers.json", &items);
                obj([])
            },
            obj([]),
        )),
        "store.delete_provider" => Some(with(
            |s| {
                let mut items = load_array(&s.dir, "providers.json");
                let id = p.get("id").and_then(|v| v.as_str()).unwrap_or("");
                remove_by_id(&mut items, id);
                save_array(&s.dir, "providers.json", &items);
                obj([])
            },
            obj([]),
        )),
        "store.get_active_provider" => Some(with(
            |st| obj([("id", s(&st.active_provider))]),
            obj([("id", s(""))]),
        )),
        "store.set_active_provider" => Some(with_mut(
            |s| {
                let id = p.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                s.active_provider = id.clone();
                s.config.insert("active_provider".into(), id);
                let cfg: Value = serde_json::to_value(&s.config).unwrap_or_default();
                let _ = write_json(&s.dir.join("config.json"), &cfg);
                obj([])
            },
            obj([]),
        )),

        "store.get_all_config" => Some(with(
            |s| {
                let m: serde_json::Map<String, serde_json::Value> =
                    s.config.iter().map(|(k, v)| (k.clone(), serde_json::Value::String(v.clone()))).collect();
                obj([("values", serde_json::Value::Object(m))])
            },
            obj([("values", obj([]))]),
        )),
        "store.set_config" => Some(with(
            |s| {
                let k = p.get("key").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let v = p.get("value").and_then(|v| v.as_str()).unwrap_or("").to_string();
                s.config.insert(k, v);
                let cfg: Value = serde_json::to_value(&s.config).unwrap_or_default();
                let _ = write_json(&s.dir.join("config.json"), &cfg);
                obj([])
            },
            obj([]),
        )),

        // ---- 历史 ----
        "history.load" => Some(with(
            |s| {
                let key = p.get("key").and_then(|v| v.as_str()).unwrap_or("");
                let msgs = read_json(&history_file(&s.dir, key))
                    .and_then(|j| j.as_array().cloned())
                    .unwrap_or_default();
                obj([("messages", arr(msgs))])
            },
            obj([("messages", arr(vec![]))]),
        )),
        "history.append" => Some(with(
            |s| {
                let key = p.get("key").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let role = p.get("role").and_then(|v| v.as_str()).unwrap_or("user");
                let content = p.get("content").and_then(|v| v.as_str()).unwrap_or("");
                let mut msgs = read_json(&history_file(&s.dir, &key))
                    .and_then(|j| j.as_array().cloned())
                    .unwrap_or_default();
                msgs.push(obj([
                    ("id", serde_json::Value::Number(serde_json::Number::from(
                        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_micros() as u64)))),
                    ("role", s(role)),
                    ("content", s(content)),
                    ("ts", serde_json::Value::Number(
                        serde_json::Number::from_f64(now_ts()).unwrap_or(serde_json::Number::from(0))))),
                ]));
                // 上限 300 条，超出丢最旧
                if msgs.len() > 300 {
                    let extra = msgs.len() - 300;
                    msgs.drain(0..extra);
                }
                let count = msgs.len();
                let _ = write_json(&history_file(&s.dir, &key), &arr(msgs));
                obj([("count", serde_json::Value::Number(serde_json::Number::from(count)))])
            },
            obj([("count", serde_json::Value::Number(serde_json::Number::from(0)))]),
        )),
        "history.clear" => Some(with(
            |s| {
                let key = p.get("key").and_then(|v| v.as_str()).unwrap_or("");
                let f = history_file(&s.dir, key);
                let n = read_json(&f).and_then(|j| j.as_array().cloned()).map(|a| a.len()).unwrap_or(0);
                let _ = fs::remove_file(&f);
                obj([("count", serde_json::Value::Number(serde_json::Number::from(n))))])
            },
            obj([("count", serde_json::Value::Number(serde_json::Number::from(0)))]),
        )),
        "history.count" => Some(with(
            |s| {
                let key = p.get("key").and_then(|v| v.as_str()).unwrap_or("");
                let n = read_json(&history_file(&s.dir, key))
                    .and_then(|j| j.as_array().cloned())
                    .map(|a| a.len())
                    .unwrap_or(0);
                obj([("count", serde_json::Value::Number(serde_json::Number::from(n))))])
            },
            obj([("count", serde_json::Value::Number(serde_json::Number::from(0)))]),
        )),

        _ => None,
    }
}

/// 内置智能体模板（对齐 AgentTemplates.swift）
fn default_agents() -> Vec<Value> {
    vec![
        obj([
            ("id", s(&new_id())),
            ("name", s("温柔姐姐")),
            ("desc", s("轻声细语，体贴入微，像冬日暖阳")),
            ("persona", s("你是一位温柔体贴的姐姐，说话轻声细语、善解人意。你关心对方的身体和心情，会提醒按时吃饭睡觉，语气永远柔和耐心。偶尔撒娇但不过度，让人如沐春风。")),
            ("gender", s("female")),
            ("age", s("26")),
            ("voice_engine", s("cloud_sf")),
            ("voice_id", s("female-yujie")),
            ("model_id", s("")),
            ("sort", serde_json::Value::Number(serde_json::Number::from(1))),
            ("enabled", serde_json::Value::Bool(true)),
        ]),
        obj([
            ("id", s(&new_id())),
            ("name", s("毒舌损友")),
            ("desc", s("嘴上不饶人，心里全是关心")),
            ("persona", s("你是用户的损友，嘴上毒舌、爱吐槽、爱拆台，但关键时刻永远靠得住。你用调侃表达关心，从不真的恶意。语言犀利幽默，偶尔爆粗但不带脏字。")),
            ("gender", s("male")),
            ("age", s("24")),
            ("voice_engine", s("cloud_sf")),
            ("voice_id", s("male-qn-qingse")),
            ("model_id", s("")),
            ("sort", serde_json::Value::Number(serde_json::Number::from(2))),
            ("enabled", serde_json::Value::Bool(true)),
        ]),
        obj([
            ("id", s(&new_id())),
            ("name", s("理性助手")),
            ("desc", s("结论先行，条理清晰，从不废话")),
            ("persona", s("你是一位理性、克制的专业助手。回答结论先行、条理清晰，能一句话说清就不用三句。你尊重事实，不确定就说不确定，绝不编造。")),
            ("gender", s("")),
            ("age", s("")),
            ("voice_engine", s("cloud_sf")),
            ("voice_id", s("female-shaonv")),
            ("model_id", s("")),
            ("sort", serde_json::Value::Number(serde_json::Number::from(3))),
            ("enabled", serde_json::Value::Bool(true)),
        ]),
        obj([
            ("id", s(&new_id())),
            ("name", s("冷淡银灰")),
            ("desc", s("高冷寡言，一句顶一万句")),
            ("persona", s("你话很少，语气冷淡淡的，像一部用心良苦的机器人。你只回答被问到的东西，从不主动寒暄。偶尔在句尾流露一丝不易察觉的温柔。")),
            ("gender", s("female")),
            ("age", s("22")),
            ("voice_engine", s("cloud_sf")),
            ("voice_id", s("female-chengshu")),
            ("model_id", s("")),
            ("sort", serde_json::Value::Number(serde_json::Number::from(4))),
            ("enabled", serde_json::Value::Bool(true)),
        ]),
    ]
}
