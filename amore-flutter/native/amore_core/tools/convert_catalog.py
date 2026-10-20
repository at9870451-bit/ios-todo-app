#!/usr/bin/env python3
"""从 AIVendorCatalog.swift / AIModelCatalog.swift 生成 catalog_data.rs"""
import re

ROOT = '/var/minis/workspace/amore-src/quant-php-ios/QuantOKX/Sources/Core'
OUT = '/var/minis/workspace/amore-src/amore-flutter/native/amore_core/src/catalog_data.rs'

# ---- 1. vendors ----
vend = open(f'{ROOT}/AIVendorCatalog.swift', encoding='utf-8').read()
vendors = []
for m in re.finditer(
    r'AIVendor\(key:\s*"([^"]+)",\s*name:\s*"([^"]*)",\s*group:\s*"([^"]*)",\s*base:\s*"([^"]*)",\s*model:\s*"([^"]*)",\s*format:\s*"([^"]*)"\)',
    vend,
):
    vendors.append(m.groups())

# ---- 2. models 字典 ----
mod = open(f'{ROOT}/AIModelCatalog.swift', encoding='utf-8').read()
block = re.search(r'static let models:\s*\[String:\s*\[String\]\]\s*=\s*\[(.*?)\n\s*\]', mod, re.S).group(1)
models = {}
for m in re.finditer(r'"([^"]+)"\s*:\s*\[([^\]]*)\]', block, re.S):
    key, body = m.group(1), m.group(2)
    items = re.findall(r'"([^"]+)"', body)
    models[key] = items

total = sum(len(v) for v in models.values())
print(f'vendors: {len(vendors)}, model keys: {len(models)}, total models: {total}')

# ---- 3. 生成 Rust ----
lines = []
lines.append('/// 由 tools/convert_catalog.py 从 Operit 目录自动生成（勿手改）')
lines.append('/// 来源：AIVendorCatalog.swift / AIModelCatalog.swift（33+ 厂商，%d 模型）' % total)
lines.append('')
lines.append('pub struct VendorRow {')
lines.append('    pub key: &\'static str,')
lines.append('    pub name: &\'static str,')
lines.append('    pub group: &\'static str,')
lines.append('    pub base: &\'static str,')
lines.append('    pub model: &\'static str,')
lines.append('    pub format: &\'static str,')
lines.append('}')
lines.append('')
lines.append('pub static VENDOR_ROWS: &[VendorRow] = &[')
for k, name, group, base, model, fmt in vendors:
    esc = lambda s: s.replace('\\', '\\\\').replace('"', '\\"')
    lines.append(f'    VendorRow {{ key: "{esc(k)}", name: "{esc(name)}", group: "{esc(group)}", base: "{esc(base)}", model: "{esc(model)}", format: "{esc(fmt)}" }},')
lines.append('];')
lines.append('')
lines.append('/// 厂商 key → 模型列表')
lines.append('pub static MODEL_ROWS: &[(&str, &[&str])] = &[')
for key, items in models.items():
    joined = ', '.join(f'"{i}"' for i in items)
    lines.append(f'    ("{key}", &[{joined}]),')
lines.append('];')

open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print(f'written: {OUT} ({os.path.getsize(OUT)} bytes)' if (os := __import__("os")) else OUT)
