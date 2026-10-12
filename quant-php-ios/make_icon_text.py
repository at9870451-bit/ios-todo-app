#!/usr/bin/env python3
"""QuantOKX 文字标识图标：蓝渐变底 + 白色粗体 OKX 字标 + 底部橙色点缀。"""
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGB", (S, S))
px = img.load()

# 蓝渐变背景：左上亮蓝 #0A84FF → 右下深蓝 #0050C8
c1 = (10, 132, 255)
c2 = (0, 80, 200)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S - 2)
        px[x, y] = (
            int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t),
        )

d = ImageDraw.Draw(img)
W = (255, 255, 255)
sw = int(S * 0.052)      # 笔画宽
cw = int(S * 0.185)      # 单字母宽
ch = int(S * 0.36)       # 字母高
gap = int(S * 0.062)
total = 3 * cw + 2 * gap
x0 = (S - total) // 2
y0 = (S - ch) // 2 - int(S * 0.02)

# O：圆环
cx, cy = x0 + cw / 2, y0 + ch / 2
rx = cw / 2 + sw / 2 - sw / 2
d.ellipse([cx - cw/2, cy - ch/2, cx + cw/2, cy + ch/2], outline=W, width=sw)
# K：竖笔 + 上斜 + 下斜
kx = x0 + cw + gap
d.line([(kx + sw/2, y0), (kx + sw/2, y0 + ch)], fill=W, width=sw)
d.line([(kx + sw/2, y0 + ch/2), (kx + cw, y0)], fill=W, width=sw)
d.line([(kx + sw/2, y0 + ch/2), (kx + cw, y0 + ch)], fill=W, width=sw)
# X：两交叉斜线
xx = kx + cw + gap
d.line([(xx, y0), (xx + cw, y0 + ch)], fill=W, width=sw)
d.line([(xx + cw, y0), (xx, y0 + ch)], fill=W, width=sw)

# 底部橙色小圆条（呼应 UI 橙色点缀）
d.rounded_rectangle([S*0.42, y0 + ch + S*0.085, S*0.58, y0 + ch + S*0.098], radius=10, fill=(255, 159, 10))

img = img.convert("RGB")
out = "/tmp/iosrepo/quant-php-ios/QuantOKX/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
img.save(out, "PNG", optimize=True)
img.resize((256, 256), Image.LANCZOS).save("/tmp/iosrepo/quant-php-ios/icon-preview.png", "PNG")
print("已写出:", out, img.size)
