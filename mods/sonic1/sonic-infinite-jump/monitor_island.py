#!/usr/bin/env python3
"""Meme island for Sonic Infinite Jump.

Prepend a floating grid of Sonic 1-up monitors above the GHZ1 start, so it reads
like a Sonic fan's Instagram profile (a 3-wide wall of Sonic faces). Infinite jump
is what lets you climb the tower.

objpos entry = 6 bytes, big-endian: Xpos(w), Ypos+flipflags(w), objID(b), subtype(b).
Monitor objID = 0x26; subtype 0x02 = the Sonic monitor (extra life / 1-up).
Freshly placed monitors default to the static-solid routine (no gravity), so a
mid-air grid just floats. The list is X-sorted ascending; our columns sit left of
the first real object (X=324), so we prepend. The FFFF terminator stays at the end.
"""
import sys, struct

MON_ID, MON_SUB = 0x26, 0x02        # Sonic 1-up monitor

# --- tweakables (position of the floating grid above the GHZ1 start) ---
COLS   = [160, 192, 224]            # 3 columns wide (X), just above the start
ROWS   = 10                         # rows tall (drop to fewer if objects don't all spawn)
Y_TOP  = 448                        # Y of the top row (smaller = higher in the sky)
Y_STEP = 32                         # vertical spacing (>= solid size so they don't overlap)
# ----------------------------------------------------------------------

def main(path):
    data = bytearray(open(path, "rb").read())
    grid = bytearray()
    for x in COLS:                                   # keep X-sorted: whole column, then next
        for r in range(ROWS):
            grid += struct.pack(">HHBB", x, Y_TOP + r * Y_STEP, MON_ID, MON_SUB)
    open(path, "wb").write(grid + data)
    print(f"  monitor island: {len(COLS)}x{ROWS} = {len(COLS) * ROWS} Sonic 1-up monitors above GHZ1 start")

if __name__ == "__main__":
    main(sys.argv[1])
