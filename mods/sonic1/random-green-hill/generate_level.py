#!/usr/bin/env python3
"""Green Hill layout generator (POC) - 3-act column permutation.

Chops all three real Green Hill acts into vertical 256px column-slices and
reassembles them into a novel Act 1 layout from a seed. Rows are indexed from
the top (world Y=0 at row 0), so a column's ground sits at the same absolute
height regardless of which act it came from -> the three are freely mixable.
Acts differ in height (ghz1=5, ghz2/3=6 chunks tall); we normalize every act
to 6 rows by padding sky at the BOTTOM (keeps absolute Y aligned).

Layout format: byte0=width-1, byte1=height-1, then w*h chunk IDs row-major.
Chunk 0x00 = sky.

Method: keep ghz1's spawn columns (0..4) and end columns (36..47, signpost at
col 37) verbatim so start/end always align with startpos/objpos; regenerate the
middle as a seeded random walk over the pooled interior columns of all three
acts, stepping only where surface height matches within one chunk row.
"""
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
# Read the real Green Hill layouts straight from the shared pristine disassembly.
# We keep NO copies of Sega level data in the mod (nothing Sega-owned is committed).
BASE = os.path.join(HERE, "..", "s1disasm")
ORIG = {
    "ghz1": os.path.join(BASE, "levels", "ghz1.bin"),
    "ghz2": os.path.join(BASE, "levels", "ghz2.bin"),
    "ghz3": os.path.join(BASE, "levels", "ghz3.bin"),
}
OUT_H = 6          # normalized world height (chunks)
OUT_W = 58         # ~20% longer than the original 48 (RAM layout buffer maxes at 64)
SPAWN_KEEP = 5     # ghz1 cols 0..4 kept verbatim (spawn)
END_BOOKEND = 12   # ghz1 cols 36..47 kept verbatim (approach + signpost terrain + runway)
GHZ1_END_FIRST = 36           # first ghz1 col of the end bookend
END_START = OUT_W - END_BOOKEND        # first OUTPUT col of the end bookend (=46)
SIGNPOST_COL = END_START + 1           # output col holding ghz1 col 37's signpost terrain
# Signpost object + camera boundary move by (END_START - GHZ1_END_FIRST) columns.
# That shift (in px) is applied to objpos/LevelSizeArray by the build script:
SHIFT_COLS = END_START - GHZ1_END_FIRST  # =10; *256 = 0xA00 px


def load_grid(path):
    b = open(path, "rb").read()
    w, h = b[0] + 1, b[1] + 1
    data = b[2:]
    grid = [[data[r * w + c] for c in range(w)] for r in range(h)]
    # normalize to OUT_H rows, padding sky at the bottom
    while len(grid) < OUT_H:
        grid.append([0] * w)
    return w, grid


def columns(w, grid):
    return [tuple(grid[r][c] for r in range(OUT_H)) for c in range(w)]


def surface(col):
    """Topmost solid row (lower index = higher ground). None = pure sky."""
    for r, v in enumerate(col):
        if v != 0:
            return r
    return None


def near(a, b):
    return a is not None and b is not None and abs(a - b) <= 1


def grounded(col):
    """True if the column has solid mass under its surface (not a floating ledge
    with a pit below). Filters out the columns that open unbreachable gaps."""
    s = surface(col)
    if s is None:
        return False
    if s + 1 < OUT_H and col[s + 1] == 0:   # sky directly under the surface = floater/pit
        return False
    return True


def solid_surface_chunks():
    """The surface chunk IDs Sonic provably runs across in the real Act 1: the
    opening straight (cols 0..5) and the signpost approach (cols 36..39). Chunks
    are context-free, so a chunk that's solid flat ground there is solid anywhere.
    Restricting the highway to these avoids the slope/edge chunks that have holes
    inside them (the source of the "gaps")."""
    w1, g1 = load_grid(ORIG["ghz1"])
    cols1 = columns(w1, g1)
    solid = set()
    for c in list(range(0, 6)) + list(range(36, 40)):
        s = surface(cols1[c])
        if s is not None:
            solid.add(cols1[c][s])
    return solid, cols1


def generate(seed):
    w1, g1 = load_grid(ORIG["ghz1"])
    cols1 = columns(w1, g1)

    # VARIED terrain (rolling hills + gaps), re-enabled now that the drop-enemy
    # "double jump" lets you bounce out of anything. Pool = grounded columns from
    # all three acts, any surface chunk (so slope/edge chunks with internal holes
    # ARE included = real gaps to bounce over).
    pool = []
    for key in ("ghz1", "ghz2", "ghz3"):
        w, g = load_grid(ORIG[key])
        cols = columns(w, g)
        lo = SPAWN_KEEP if key == "ghz1" else 1
        hi = GHZ1_END_FIRST if key == "ghz1" else w - 1
        for c in range(lo, hi):
            if grounded(cols[c]):
                pool.append(cols[c])

    rng = random.Random(seed)
    base = surface(cols1[SPAWN_KEEP - 1])
    seam_right = surface(cols1[GHZ1_END_FIRST])   # middle must connect into the end bookend
    middle_len = END_START - SPAWN_KEEP

    # Mean-reverting walk: mostly flat, occasional +-1 chunk-row hill/ledge that
    # trends back to the ground line. The steps are the walls/drops you bounce past.
    # Over the final columns it converges onto the end-bookend seam so the join is
    # always smooth (start descending/climbing exactly when we must to arrive).
    # Converge onto `base` at the end: it's a reachable pool surface AND within one
    # row of the bookend seam, so the join is always <=1. (seam_right itself may be
    # unreachable, e.g. the bookend sits a row higher than any pooled column.)
    assert abs(base - seam_right) <= 1, f"bookend seam {seam_right} not within 1 of base {base}"
    new_middle = []
    prev = base
    for i in range(middle_len):
        remaining = middle_len - 1 - i               # columns placed after this one
        if remaining <= abs(prev - base):
            # Must head home now: step one row toward base (monotonic arrival).
            desired = prev + (1 if base > prev else -1 if base < prev else 0)
            cands = [c for c in pool if surface(c) == desired]
            if not cands:
                cands = [c for c in pool if abs(surface(c) - prev) <= 1] or pool
            choice = rng.choice(cands)
        else:
            cands, weights = [], []
            for c in pool:
                s = surface(c)
                if abs(s - prev) > 1:
                    continue
                if s == prev:
                    w = 12                              # flat, common
                elif abs(s - base) < abs(prev - base):
                    w = 5                               # step back toward base
                else:
                    w = 2                               # step away from base
                cands.append(c)
                weights.append(w)
            if not cands:
                cands = [c for c in pool if abs(surface(c) - prev) <= 1] or pool
                weights = [1] * len(cands)
            choice = rng.choices(cands, weights)[0]
        new_middle.append(choice)
        prev = surface(choice)

    # Assemble output: ghz1 spawn bookend (cols 0..4), pooled middle, then the
    # ghz1 end bookend (cols 36..47) relocated to the new far right.
    out = [[0] * OUT_W for _ in range(OUT_H)]
    for c in range(OUT_W):
        if c < SPAWN_KEEP:
            col = cols1[c]
        elif c >= END_START:
            col = cols1[GHZ1_END_FIRST + (c - END_START)]
        else:
            col = new_middle[c - SPAWN_KEEP]
        for r in range(OUT_H):
            out[r][c] = col[r]
    return out


def validate(grid):
    surfs = [surface(tuple(grid[r][c] for r in range(OUT_H))) for c in range(OUT_W)]
    for c in range(0, SIGNPOST_COL + 1):     # spawn..signpost must have ground
        assert surfs[c] is not None, f"bottomless column at {c}"
    for c in range(0, SIGNPOST_COL):
        assert abs(surfs[c] - surfs[c + 1]) <= 1, f"cliff at col {c}->{c+1}"
    return surfs


def save(path, grid):
    out = bytearray([OUT_W - 1, OUT_H - 1])
    for r in range(OUT_H):
        out.extend(grid[r][c] for c in range(OUT_W))
    open(path, "wb").write(out)


if __name__ == "__main__":
    import sys
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "generated_ghz1.bin")
    grid = generate(seed)
    surfs = validate(grid)
    save(out, grid)
    print(f"seed={seed} -> {out} ({OUT_W}x{OUT_H})")
    print("surface:", " ".join("-" if s is None else str(s) for s in surfs))
