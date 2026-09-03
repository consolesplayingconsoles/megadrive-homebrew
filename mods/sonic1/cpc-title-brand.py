#!/usr/bin/env python3
"""Stamp "BY CPC" on the Sonic 1 title screen.

Shared across the Sonic 1 mods. Each mod's build.sh calls this on its dist copy
of sonic.asm (after the overlay is applied, before assembly).

Why this works with no new artwork: GM_Title already decompresses the level
select font (Art_Text) into VRAM so the level-select cheat can draw text. We
reuse those exact letter tiles, so all we add is a tiny draw routine + a call.

Usage: cpc-title-brand.py <path-to-dist/sonic.asm>
"""
import sys

# The call goes at the end of GM_Title's setup. The routine is appended after the
# level-select pointer table: it must NOT land between LevSel_Level_SS and its
# LevSel_Ptrs(pc,d0.w) table -- that addressing mode has only an 8-bit displacement,
# so widening that gap overflows it ("distance too big"). Everything downstream of
# LevSel_PtrsEnd shifts uniformly, so those PC-relative pairs are unaffected.
CALL_ANCHOR = "clear C counter for title screen cheats"
ROUTINE_ANCHOR = "LevSel_PtrsEnd:"

CALL_LINE = '\t\tbsr.w\tCPC_TitleBrand\t\t\t\t; CPC: print "BY CPC" on the title screen\n'

ROUTINE = r'''
; ---------------------------------------------------------------------------
; CPC: stamp "BY CPC" on the title screen. Uses the level select font that
; GM_Title already loads into VRAM (Art_Text), so it needs no new artwork.
; Foreground plane (static, doesn't scroll with the water), bottom row, centred.
; ---------------------------------------------------------------------------
CPC_brand_vram:	equ vram_fg+(4<<7)+(8<<1)		; fg nametable slot: row 4, col 8 -- the clear blue-sky pocket upper-left of Sonic (clear of the white emblem wings and the clouds, where light text actually reads)

CPC_TitleBrand:
		lea	(vdp_data_port).l,a6			; a6 = VDP data port (tiles get written here)
		locVRAM	CPC_brand_vram				; point the VDP at the brand's nametable slot
		lea	(CPC_BrandText).l,a1			; glyph indices into the level select font
		move.w	#ArtTile_Level_Select_Font|Tile_Pal4|Tile_Prio,d3 ; white, high priority (sits over the water)
		moveq	#CPC_BrandText_End-CPC_BrandText-1,d1
	.loop:
		moveq	#0,d0
		move.b	(a1)+,d0				; next glyph
		bmi.s	.blank					; $FF -> space
		add.w	d3,d0					; + font base tile / palette / priority
		move.w	d0,(a6)					; write the tile
		dbf	d1,.loop
		rts
	.blank:
		move.w	#0,(a6)					; blank tile for the space
		dbf	d1,.loop
		rts

CPC_BrandText:
		; level select font glyph indices: B=$12 Y=$0F space=$FF C=$13 P=$20 C=$13
		dc.b	$12,$0F,$FF,$13,$20,$13			; "BY CPC"
CPC_BrandText_End:
		even
; ---------------------------------------------------------------------------
'''


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: cpc-title-brand.py <dist/sonic.asm>")
    path = sys.argv[1]
    with open(path) as f:
        lines = f.readlines()

    # 1) insert the call right after the C-counter clear (end of title setup)
    for i, line in enumerate(lines):
        if CALL_ANCHOR in line:
            if "CPC_TitleBrand" in "".join(lines):
                break  # already patched
            lines.insert(i + 1, CALL_LINE)
            break
    else:
        sys.exit("PATCH FAILED: call anchor not found (%s)" % CALL_ANCHOR)

    # 2) append the routine after the level-select pointer table (safe from the
    #    8-bit PC-relative refs above it)
    if "CPC_TitleBrand:" not in "".join(lines):
        for i, line in enumerate(lines):
            if ROUTINE_ANCHOR in line:
                lines.insert(i + 1, ROUTINE)
                break
        else:
            sys.exit("PATCH FAILED: routine anchor not found (%s)" % ROUTINE_ANCHOR)

    with open(path, "w") as f:
        f.write("".join(lines))
    print('  patched: "BY CPC" on the title screen')


if __name__ == "__main__":
    main()
