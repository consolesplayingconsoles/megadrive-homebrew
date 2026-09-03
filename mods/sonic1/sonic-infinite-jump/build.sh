#!/usr/bin/env bash
# Build "Sonic Infinite Jump": vanilla Sonic 1 + a mid-air relaunch on every jump
# press. Copies the shared pristine ../s1disasm-bk into dist/, overlays this mod's one
# edited file, and assembles.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s1disasm"     # shared pristine disassembly
DIST="$HERE/dist"                            # disposable build tree (gitignored)

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/"
python3 "$HERE/../cpc-title-brand.py" "$DIST/sonic.asm"   # "BY CPC" on the title screen (shared)

( cd "$DIST" && lua build.lua ) >/dev/null

# ROM goes to rom/ (gitignored) — easy to grab; full Sonic 1 so never committed.
mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic-infinite-jump.bin"
cp "$DIST/s1built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
echo "  vanilla Sonic 1 + infinite jump (tap jump in the air to relaunch)"
