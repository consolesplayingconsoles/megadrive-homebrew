#!/usr/bin/env bash
# Vanilla Sonic 3 & Knuckles: the disassembly's own bit-perfect check (Sonic 3 and
# Sonic & Knuckles each rebuilt and compared with retail by MD5), then the combined
# Sonic 3 & Knuckles ROM the mods here build on.
# skdisasm ships no macOS build tools; they come from the hyper swap mod's overlay
# (copied from s2disasm, same AS toolchain), never written into the submodule.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/skdisasm"
TOOLS="$(cd "$HERE/.." && pwd)/sonic3-hyper-swap/overlay/build_tools"
DIST="$HERE/dist"
[ -d "$TOOLS" ] || { echo "[ERROR] macOS build tools not found at $TOOLS"; exit 1; }

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$TOOLS/." "$DIST/build_tools/"

CHECK=$( cd "$DIST" && lua chkbitperfect.lua 2>&1 ) || true
echo "$CHECK" | grep -E "bit-perfect" | sed 's/^/  /'
if echo "$CHECK" | grep -q "NOT bit-perfect" || [ "$(echo "$CHECK" | grep -c "is bit-perfect")" -ne 2 ]; then
  echo "  toolchain NOT verified" >&2
  exit 1
fi
echo "  toolchain verified"

( cd "$DIST" && lua buildS3Complete.lua ) >/dev/null
mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic3k-vanilla.bin"
cp "$DIST/sonic3k.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
echo "##OUTPUT:$ROM"
