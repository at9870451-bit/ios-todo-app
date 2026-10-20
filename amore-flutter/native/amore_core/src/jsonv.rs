/// serde_json 轻量包装：简化信封组装
use serde_json::{Map, Value};

#[derive(Clone, Debug)]
pub struct Json(pub Value);

pub fn obj<const N: usize>(fields: [(&str, Value); N]) -> Value {
    let mut m = Map::new();
    for (k, v) in fields {
        m.insert(k.to_string(), v);
    }
    Value::Object(m)
}

pub fn arr(v: Vec<Value>) -> Value {
    Value::Array(v)
}

pub fn s(v: &str) -> Value {
    Value::String(v.to_string())
}

pub fn n(v: i64) -> Value {
    Value::Number(Number::from(v))
}

pub fn f(v: f64) -> Value {
    Value::Number(Number::from_f64(v).unwrap_or(Number::from(0)))
}

pub use serde_json::Number;

/// 从 payload 里取字符串字段
pub fn get_str<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(|x| x.as_str()).unwrap_or("")
}

pub fn get_obj<'a>(v: &'a Value, k: &str) -> &'a Value {
    v.get(k).unwrap_or(&Value::Null)
}
