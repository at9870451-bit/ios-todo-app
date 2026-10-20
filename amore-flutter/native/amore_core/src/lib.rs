// amore_core — Rust Core 入口
//
// 桥接协议（C FFI JSON 总线）：
//   Dart 调用 amore_call(method, payload_json) -> resp_json。返回统一信封：
//   { "ok": true, "data": ... } 或 { "ok": false, "error": { "code", "message" } }
//
// 模块：
//   store   — JSON 文件持久化（好友/群组/智能体/供应商/配置/历史）
//   catalog — 厂商/模型目录（34 厂商 505 模型，Operit 迁移）
//   tools   — 工具调用协议（XML 解析 + 本地工具执行）
//   prompts — 提示词组装（人设/记忆/工具指南）+ 记忆标记抽取
//   tts     — TTS 请求组装

mod catalog;
mod catalog_data;
mod jsonv;
mod prompts;
mod store;
mod tools;
mod tts;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use serde_json::Value;

use jsonv::{obj, s, Json};

fn ok(data: Value) -> String {
    serde_json::json!({ "ok": true, "data": data }).to_string()
}

fn err(code: &str, message: &str) -> String {
    serde_json::json!({ "ok": false, "error": { "code": code, "message": message } }).to_string()
}

fn dispatch(method: &str, payload: &str) -> String {
    let parsed: Value = match serde_json::from_str(payload) {
        Ok(v) => v,
        Err(e) => return err("bad_payload", &format!("payload 不是合法 JSON: {e}")),
    };
    let p = Json(parsed);

    let out = match method {
        "core.ping" => Some(obj([("pong", Value::Bool(true)), ("echo", p.0.clone())])),
        "core.version" => Some(obj([
            ("name", s("AmoreCore")),
            ("version", s(env!("CARGO_PKG_VERSION"))),
            ("api", Value::Number(serde_json::Number::from(2))),
            ("platform", s(std::env::consts::OS)),
            ("arch", s(std::env::consts::ARCH)),
        ])),
        "core.sysinfo" => Some(obj([
            ("api_version", Value::Number(serde_json::Number::from(2))),
            ("build_mode", s("release")),
            ("runtime_targets", Value::Array(vec![
                s("aarch64-apple-ios"),
                s("aarch64-apple-darwin"),
            ])),
            ("milestone", s("M1-storage")),
        ])),
        "core.init" => {
            let dir = p.0.get("data_dir").and_then(|v| v.as_str()).unwrap_or("");
            if dir.is_empty() {
                return err("bad_args", "data_dir 为空");
            }
            store::init(dir);
            Some(obj([]))
        }
        _ => None,
    };

    if let Some(data) = out {
        return ok(data);
    }

    // 模块分发链
    let module_result = store::dispatch(method, &p)
        .or_else(|| catalog::dispatch(method, &p))
        .or_else(|| tools::dispatch(method, &p))
        .or_else(|| prompts::dispatch(method, &p))
        .or_else(|| tts::dispatch(method, &p));

    match module_result {
        Some(data) => ok(data.0),
        None => err("unknown_method", &format!("未实现的方法: {method}")),
    }
}

fn dispatch_safe(method: &str, payload: &str) -> String {
    match std::panic::catch_unwind(|| dispatch(method, payload)) {
        Ok(s) => s,
        Err(_) => err("core_panic", "Rust Core 内部错误（panic 已捕获）"),
    }
}

/// C ABI：Dart → Rust
///
/// # Safety
/// method/payload 必须是合法的 NUL 结尾 UTF-8 指针；返回值用 amore_free 释放。
#[no_mangle]
pub extern "C" fn amore_call(method: *const c_char, payload: *const c_char) -> *mut c_char {
    if method.is_null() {
        let resp = CString::new(err("bad_args", "method 为空")).unwrap();
        return resp.into_raw();
    }
    let m = unsafe { CStr::from_ptr(method) }.to_string_lossy().to_string();
    let p = if payload.is_null() {
        "{}".to_string()
    } else {
        unsafe { CStr::from_ptr(payload) }.to_string_lossy().to_string()
    };

    let resp = dispatch_safe(&m, &p);
    match CString::new(resp) {
        Ok(s) => s.into_raw(),
        Err(_) => CString::new(err("core_error", "响应包含非法 NUL")).unwrap().into_raw(),
    }
}

/// C ABI：释放 amore_call 返回的内存
///
/// # Safety
/// ptr 必须是 amore_call 返回的指针，且只能释放一次。
#[no_mangle]
pub extern "C" fn amore_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) };
    }
}
