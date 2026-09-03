#!/usr/bin/env python3.11
"""Extract a 16x16 tile from a Kenney char/tile sheet into an indexed sprite PNG
with palette index 0 = transparent (what SGDK sprites expect)."""
from PIL import Image

PITCH, TILE = 17, 16

def extract(sheet, c, r):
    t = sheet.crop((c * PITCH, r * PITCH, c * PITCH + TILE, r * PITCH + TILE)).convert("RGBA")
    rgb = Image.new("RGB", t.size, (0, 0, 0))
    rgb.paste(t, (0, 0), t)
    q = rgb.quantize(colors=15, method=Image.MEDIANCUT)
    qpx = q.load()
    alpha = t.split()[3].load()
    out = Image.new("P", t.size, 0)
    op = out.load()
    for y in range(TILE):
        for x in range(TILE):
            op[x, y] = 0 if alpha[x, y] < 128 else qpx[x, y] + 1
    pal = [255, 0, 255] + q.getpalette()[:15 * 3]
    pal += [0, 0, 0] * (256 - len(pal) // 3)
    out.putpalette(pal)
    return out

if __name__ == "__main__":
    import sys
    from PIL import ImageDraw
    sheet = Image.open("assets/chars/Spritesheet/roguelikeChar_transparent.png").convert("RGBA")
    cands = [(0, 10), (1, 10), (1, 9), (0, 5), (1, 5), (0, 6), (1, 7), (0, 8)]
    SC = 8
    cw = TILE * SC + 26
    out = Image.new("RGB", (len(cands) * cw, TILE * SC + 20), (70, 74, 82))
    d = ImageDraw.Draw(out)
    for i, (c, r) in enumerate(cands):
        spr = extract(sheet, c, r)          # P mode
        pal = spr.getpalette()
        px = spr.load()
        spr_rgb = Image.new("RGB", spr.size, (70, 74, 82))
        pr = spr_rgb.load()
        for y in range(TILE):
            for x in range(TILE):
                idx = px[x, y]
                if idx != 0:
                    pr[x, y] = (pal[idx*3], pal[idx*3+1], pal[idx*3+2])
        big = spr_rgb.resize((TILE*SC, TILE*SC), Image.NEAREST)
        out.paste(big, (i*cw+2, 16))
        d.text((i*cw+2, 2), f"{c},{r}", fill=(255, 255, 0))
    out.save("assets/hero_cands.png")
    print("wrote assets/hero_cands.png")
