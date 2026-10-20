// amore_core — Rust Core 入口
//
// 桥接协议（C FFI JSON 总线）：
//   Dart 调用 amore_call(method, payload_json) -> resp_json（每次调用互不共享状态，
//   需要跨调用的状态放在 Core 内部全局存储里）。返回统一信封：
//   { "ok": true, "data": ... } 或 { "ok": false, "error": { "code", "message" } }
//
// M0 里程碑只实现 core.ping / core.version / core.sysinfo，用于验证
// Flutter ↔ Rust 工具链全链路（CI 编译 + FFI 桥 + 真机运行）。

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use serde_json::{json, Value};

/// 成功信封
fn ok(data: Value) -> String {
    json!({ "ok": true, "data": data }).to_string()
}

/// 失败信封
fn err(code: &str, message: &str) -> String {
    json!({ "ok": false, "error": { "code": code, "message": message } }).to_string()
}

/// 方法分发：所有业务入口从这里走（后续里程碑按模块拆分到子模块）
fn dispatch(method: &str, payload: &str) -> String {
    let parsed: Value = match serde_json::from_str(payload) {
        Ok(v) => v,
        Err(e) => return err("bad_payload", &format!("payload 不是合法 JSON: {e}")),
    };

    match method {
        "core.ping" => ok(json!({
            "pong": true,
            "echo": parsed,
        })),

        "core.version" => ok(json!({
            "name": "AmoreCore",
            "version": env!("CARGO_PKG_VERSION"),
            "api": 1,
            "platform": std::env::consts::OS,
            "arch": std::env::consts::ARCH,
        })),

        "core.sysinfo" => ok(json!({
            "api_version": 1,
            "build_mode": "release",
            "runtime_targets": ["aarch64-apple-ios", "aarch64-apple-darwin"],
            "milestone": "M0-skeleton",
        })),

        _ => err("unknown_method", &format!("未实现的方法: {method}")),
    }
}

/// 统一入口：把 panic 转成错误信封，保证 C ABI 不跨边界 unwind
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
        // 返回串里出现 NUL（理论上不可能：JSON 字符串会转义）时兜底
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
