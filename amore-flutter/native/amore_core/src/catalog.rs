/// 厂商/模型目录：数据在 catalog_data.rs（由 tools/convert_catalog.py 生成）
use crate::jsonv::{arr, obj, s, Json};
use crate::catalog_data::{MODEL_ROWS, VENDOR_ROWS};

pub fn dispatch(method: &str, p: &Json) -> Option<Json> {
    match method {
        "catalog.vendors" => Some(obj([("vendors", arr(
            VENDOR_ROWS.iter().map(|v| obj([
                ("key", s(v.key)),
                ("name", s(v.name)),
                ("group", s(v.group)),
                ("base", s(v.base)),
                ("model", s(v.model)),
                ("format", s(v.format)),
            ])).collect()
        ))])),

        "catalog.models" => {
            let vendor = p.0.get("vendor").and_then(|v| v.as_str()).unwrap_or("");
            let models = MODEL_ROWS.iter()
                .find(|(k, _)| *k == vendor)
                .map(|(_, list)| list.iter().map(|m| s(m)).collect::<Vec<_>>())
                .unwrap_or_default();
            Some(obj([("models", arr(models))]))
        }

        "catalog.search" => {
            let q = p.0.get("q").and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
            let mut out: Vec<Json> = Vec::new();
            if !q.is_empty() {
                for (vendor, list) in MODEL_ROWS {
                    for m in *list {
                        if m.to_lowercase().contains(&q) {
                            out.push(s(&format!("{vendor}|{m}")));
                            if out.len() >= 200 { break; }
                        }
                    }
                    if out.len() >= 200 { break; }
                }
            }
            Some(obj([("models", arr(out))]))
        }

        _ => None,
    }
}
