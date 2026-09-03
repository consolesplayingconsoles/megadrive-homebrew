#!/usr/bin/env bash
# Build the "Random Green Hill" Sonic 1 ROM hack.
#
# The mod keeps only its EDITS (overlay/) + the layout generator; it never touches
# the shared disassembly. Each build makes a fresh copy of the pristine ../s1disasm-bk
# into dist/, overlays this mod's files, generates the level variants, and assembles.
#
# Usage: ./build.sh [baseseed]   (32 variants from baseseed .. baseseed+31; default 1)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s1disasm"     # shared pristine disassembly
DIST="$HERE/dist"                            # disposable build tree (gitignored)
SEED="${1:-1}"

# 1. Fresh pristine base (mirror, minus its git repo).
mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"

# 2. Overlay this mod's edited source files.
cp -R "$HERE/overlay/." "$DIST/"
python3 "$HERE/../cpc-title-brand.py" "$DIST/sonic.asm"   # "BY CPC" on the title screen (shared)

# 3. Generate the 32 level variants into the build tree.
for i in $(seq 0 31); do
  python3 "$HERE/generate_level.py" $((SEED + i)) "$DIST/levels/ghz1_var${i}.bin" >/dev/null
done

# 4. Relocate the end signpost +0xA00 (10 chunks) to match the longer level.
#    (reads the pristine objpos from the base; writes only into the build tree)
python3 - "$BASE/objpos/ghz1.bin" "$DIST/objpos/ghz1.bin" <<'PY'
import sys
b = bytearray(open(sys.argv[1], "rb").read())
i = 0
while i + 6 <= len(b) and not (b[i] == 0xFF and b[i+1] == 0xFF):
    if (b[i+4] & 0x7F) == 0x0D:            # signpost object
        x = ((b[i] << 8) | b[i+1]) + 0xA00
        b[i], b[i+1] = (x >> 8) & 0xFF, x & 0xFF
    i += 6
open(sys.argv[2], "wb").write(b)
PY

# 5. Assemble (bundled AS toolchain, needs lua: `brew install lua`).
( cd "$DIST" && lua build.lua ) >/dev/null

# ROM goes to rom/ (gitignored) — easy to grab; full Sonic 1 so never committed.
mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic-random-green-hill.bin"
cp "$DIST/s1built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
echo "  infinite lives + endless random Green Hill (32 variants, seeds ${SEED}..$((SEED+31)))"
