#!/usr/bin/env python3.11
"""Extract a set of (col,row) tiles from the RPG sheet into a labeled contact sheet."""
from PIL import Image, ImageDraw

SHEET = "assets/rpg/Spritesheet/roguelikeSheet_transparent.png"
PITCH, TILE = 17, 16
sheet = Image.open(SHEET).convert("RGBA")

def tile(c, r):
    return sheet.crop((c * PITCH, r * PITCH, c * PITCH + TILE, r * PITCH + TILE))

# candidate coords grouped: floors, plants, furniture, window/deco
cands = []
cands += [(c, 26) for c in range(0, 20, 2)]      # floors row 26
cands += [(c, 28) for c in range(0, 20, 2)]      # floors row 28
cands += [(c, 8) for c in range(13, 27, 1)]      # plants/trees row 8
cands += [(c, 0) for c in range(15, 27, 1)]      # furniture row 0
cands += [(c, 4) for c in range(15, 27, 1)]      # furniture row 4
cands += [(1, 0), (8, 0), (9, 0), (12, 7), (13, 7), (14, 7), (10, 3), (11, 3)]

SC, PAD, COLS = 4, 22, 12
cw, ch = TILE * SC + PAD, TILE * SC + PAD
rows = (len(cands) + COLS - 1) // COLS
out = Image.new("RGB", (COLS * cw, rows * ch), (70, 74, 82))
d = ImageDraw.Draw(out)
for i, (c, r) in enumerate(cands):
    gx, gy = (i % COLS) * cw, (i // COLS) * ch
    t = tile(c, r).resize((TILE * SC, TILE * SC), Image.NEAREST)
    out.paste(t, (gx + 2, gy + 12), t)
    d.text((gx + 2, gy + 1), f"{c},{r}", fill=(255, 255, 0))
out.save("assets/candidates.png")
print("wrote assets/candidates.png", out.size, "tiles:", len(cands))
