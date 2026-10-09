#!/usr/bin/env python3
"""生成 QuantOKX 的 1024x1024 App 图标：深色背景 + 上升折线与箭头。"""
from PIL import Image, ImageDraw, ImageFilter
import math

S = 1024
img = Image.new("RGB", (S, S), (10, 14, 26))
px = img.load()

# 深色渐变背景（左上偏蓝 → 右下偏黑）
c1 = (18, 28, 52)
c2 = (6, 8, 16)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S - 2)
        px[x, y] = (
            int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t),
        )

d = ImageDraw.Draw(img)

# 背景里的淡网格（行情图感）
for i in range(1, 6):
    y = int(S * i / 6)
    d.line([(S * 0.08, y), (S * 0.92, y)], fill=(255, 255, 255, 12), width=2)
for i in range(1, 6):
    x = int(S * i / 6)
    d.line([(x, S * 0.08), (x, S * 0.92)], fill=(255, 255, 255, 12), width=2)

# 发光层：上升折线
glow = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(glow)
pts = [
    (S * 0.16, S * 0.70),
    (S * 0.33, S * 0.56),
    (S * 0.45, S * 0.62),
    (S * 0.62, S * 0.40),
    (S * 0.84, S * 0.24),
]
gd.line(pts, fill=110, width=int(S * 0.055), joint="curve")
glow = glow.filter(ImageFilter.GaussianBlur(26))
img = Image.composite(Image.new("RGB", (S, S), (0, 255, 170)), img, glow)
d = ImageDraw.Draw(img)

# 主折线
d.line(pts, fill=(52, 255, 190), width=int(S * 0.036), joint="curve")
for p in pts:
    r = S * 0.026
    d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(255, 255, 255))

# 末端箭头
tip = pts[-1]
ax, ay = tip
d.polygon([
    (ax + S * 0.075, ay - S * 0.075),
    (ax - S * 0.010, ay - S * 0.028),
    (ax + S * 0.028, ay + S * 0.010),
], fill=(52, 255, 190))

img = img.convert("RGB")
out = "/var/minis/workspace/quant-okx-ios/QuantOKX/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
img.save(out, "PNG", optimize=True)
img.resize((256, 256), Image.LANCZOS).save("/var/minis/workspace/quant-okx-ios/icon-preview.png", "PNG")
print("已写出:", out, img.size)
