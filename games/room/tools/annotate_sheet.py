#!/usr/bin/env python3.11
"""Overlay a tile-coordinate grid on a Kenney sheet so I can pick tiles by (col,row)."""
import sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
pitch = int(sys.argv[3]) if len(sys.argv) > 3 else 17
tile = 16
sheet = Image.open(src).convert("RGBA")
# dark background so transparent tiles are visible
bg = Image.new("RGBA", sheet.size, (40, 44, 52, 255))
bg.alpha_composite(sheet)
img = bg.convert("RGB")

scale = 2
img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
d = ImageDraw.Draw(img)
cols = (sheet.width + 1) // pitch
rows = (sheet.height + 1) // pitch
for c in range(cols + 1):
    x = c * pitch * scale
    d.line([x, 0, x, img.height], fill=(255, 255, 0), width=1)
    if c % 2 == 0:
        d.text((x + 1, 0), str(c), fill=(255, 255, 0))
for r in range(rows + 1):
    y = r * pitch * scale
    d.line([0, y, img.width, y], fill=(255, 255, 0), width=1)
    if r % 2 == 0:
        d.text((0, y + 1), str(r), fill=(0, 255, 255))
img.save(out)
print("wrote", out, img.size, "grid", cols, "x", rows)
