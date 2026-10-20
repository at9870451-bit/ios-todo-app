/// TTS 请求组装（对齐 SiliconFlowTTS.swift / DoubaoTTS.swift / PersonaVoice.swift）
/// 纯组装不发请求；HTTP 由 Dart 侧执行。
use serde_json::Value;

use crate::jsonv::{get_str, obj, s};

pub fn dispatch(method: &str, p: &Value) -> Option<Value> {
    if method != "tts.request" {
        return None;
    }
    let engine = get_str(p, "engine");
    let voice_id = get_str(p, "voice_id");
    let api_key = get_str(p, "api_key");
    let text = get_str(p, "text");

    match engine {
        // 硅基流动（SiliconFlow）TTS
        "cloud_sf" => {
            let url = "https://api.siliconflow.cn/v1/audio/speech";
            let mut headers = obj([
                ("Content-Type", s("application/json")),
                ("Authorization", s(&format!("Bearer {api_key}"))),
            ]);
            if api_key.is_empty() {
                headers = obj([("Content-Type", s("application/json"))]);
            }
            Some(obj([
                ("engine", s(engine)),
                ("url", s(url)),
                ("headers", headers),
                ("body", obj([
                    ("model", s("FunAudioLLM/CosyVoice2-0.5B")),
                    ("input", s(text)),
                    ("voice", s(if voice_id.is_empty() { "speech:your-voice-uid" } else { voice_id })),
                    ("response_format", s("mp3")),
                    ("sample_rate", Json(serde_json::Value::Number(serde_json::Number::from(32000)))),
                    ("speed", Json(serde_json::Value::Number(serde_json::Number::from_f64(1.0).unwrap()))),
                ])),
            ]))
        }
        // 豆包（字节）TTS —— 需要用户自建代理端点（原实现走服务端），这里组装 OpenAI 兼容形态
        "cloud_doubao" => {
            Some(obj([
                ("engine", s(engine)),
                ("url", s("doubao")),
                ("note", s("豆包 TTS 需要服务端代理（volcengine API），请配合后端 /api/tts/doubao 使用；Dart 侧遇到 url=doubao 时请求 {server}/api/tts/doubao")),
                ("headers", obj([
                    ("Content-Type", s("application/json")),
                ])),
                ("body", obj([
                    ("voice", s(if voice_id.is_empty() { "zh_female_cancan" } else { voice_id })),
                    ("text", s(text)),
                ])),
            ]))
        }
        // OpenAI 风格（跟随 provider）
        "model" => {
            let mut headers = obj([("Content-Type", s("application/json"))]);
            if !api_key.is_empty() {
                headers = obj([
                    ("Content-Type", s("application/json")),
                    ("Authorization", s(&format!("Bearer {api_key}"))),
                ]);
            }
            Some(obj([
                ("engine", s(engine)),
                ("url", s("provider")),
                ("note", s("OpenAI 风格：Dart 侧用当前激活 provider 的 base + /audio/speech，音色 voice_id，模型 tts 模型（如 gpt-4o-mini-tts）")),
                ("headers", headers),
                ("body", obj([
                    ("voice", s(if voice_id.is_empty() { "alloy" } else { voice_id })),
                    ("input", s(text)),
                    ("response_format", s("mp3")),
                ])),
            ]))
        }
        // 本机 / 服务端引擎：不在此组装
        _ => {
            Some(obj([
                ("engine", s(engine)),
                ("error", s(if engine.is_empty() || engine == "local" {
                    "local 引擎：使用系统 TTS（M5 接入 flutter_tts）"
                } else if engine == "server" {
                    "server 引擎：走服务端 /api/tts（需登录）"
                } else {
                    "未知语音引擎"
                })),
            ]))
        }
    }
}
