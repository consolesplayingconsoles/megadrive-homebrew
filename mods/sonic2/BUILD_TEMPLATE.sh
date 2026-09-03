#!/usr/bin/env bash
# Build a Sonic 2 ROM hack.
#
# This template copies the shared pristine disassembly into dist/, overlays
# this mod's edited files, generates any variants, and assembles.
#
# Usage: ./build.sh [arguments]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s2disasm"     # shared pristine disassembly
DIST="$HERE/dist"                            # disposable build tree (gitignored)

# TODO: parse arguments if needed (e.g., seed for randomization)

# 1. Fresh pristine base (mirror, minus its git repo).
mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"

# 2. Overlay this mod's edited source files.
cp -R "$HERE/overlay/." "$DIST/"

# 3. Run any generators here (e.g., level randomization).
# Example:
# for i in $(seq 0 31); do
#   python3 "$HERE/generate_level.py" $((SEED + i)) "$DIST/level/level_var${i}.bin" >/dev/null
# done

# 4. Assemble (bundled AS toolchain, needs lua: `brew install lua`).
( cd "$DIST" && lua build.lua ) >/dev/null

# ROM goes to rom/ (gitignored) — easy to grab; full Sonic 2 so never committed.
mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic2-mod.bin"
cp "$DIST/s2built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
