#!/usr/bin/env python3
"""生成 1024x1024 的 iOS App 图标。
iOS 会自动裁圆角，所以画满幅方形即可，别自己画圆角。
"""
from PIL import Image, ImageDraw
import math

S = 1024
img = Image.new("RGB", (S, S), (10, 114, 245))
px = img.load()

# 1. 背景：对角渐变
c1 = (52, 152, 255)   # 亮蓝
c2 = (4, 82, 200)     # 深蓝
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S - 2)          # 0..1 对角
        r = int(c1[0] + (c2[0] - c1[0]) * t)
        g = int(c1[1] + (c2[1] - c1[1]) * t)
        b = int(c1[2] + (c2[2] - c1[2]) * t)
        px[x, y] = (r, g, b)

d = ImageDraw.Draw(img)

# 2. 顶部柔光（模拟高光）
glow = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([-S * 0.35, -S * 0.75, S * 1.35, S * 0.42], fill=70)
glow = glow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(80))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, glow)
d = ImageDraw.Draw(img)

# 3. 主体：白色圆环 + 勾
cx = cy = S / 2
R = S * 0.285
ring_w = int(S * 0.052)
d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(255, 255, 255), width=ring_w)

# 勾：两段折线，粗圆头
w = int(S * 0.062)
p1 = (cx - R * 0.42, cy + R * 0.04)
p2 = (cx - R * 0.10, cy + R * 0.36)
p3 = (cx + R * 0.50, cy - R * 0.36)
for a, b in ((p1, p2), (p2, p3)):
    d.line([a, b], fill=(255, 255, 255), width=w)
for p in (p1, p2, p3):
    d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(255, 255, 255))

img = img.convert("RGB")
out = "/var/minis/workspace/ios-app-demo/MyApp/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
img.save(out, "PNG", optimize=True)

# 顺手生成一个预览小图给用户看
img.resize((256, 256), Image.LANCZOS).save("/var/minis/workspace/ios-app-demo/icon-preview.png", "PNG")
print("已写出:", out)
print("尺寸:", img.size, "模式:", img.mode)
