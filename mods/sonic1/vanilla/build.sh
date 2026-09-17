#!/usr/bin/env bash
# Vanilla Sonic 1: the disassembly rebuilt with no edits as Rev 00, checked against the
# retail "Sonic the Hedgehog (USA, Europe)" (CRC32 F9394E97, the ROM patches apply to).
# If it does not match, the toolchain is wrong and no mod built on it can be trusted.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s1disasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
# the disassembly defaults to Revision = 1; retail patches target Rev 00
python3 - "$DIST/sonic.asm" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
assert "\nRevision = 1\n" in s, "Revision line not found"
open(p, "w").write(s.replace("\nRevision = 1\n", "\nRevision = 0\n", 1))
PY

( cd "$DIST" && lua build.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic1-vanilla-rev00.bin"
cp "$DIST/s1built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
echo "##OUTPUT:$ROM"

CRC=$(python3 -c "import sys, zlib; print('%08X' % (zlib.crc32(open(sys.argv[1], 'rb').read()) & 0xffffffff))" "$ROM")
if [ "$CRC" = "F9394E97" ]; then
  echo "  byte-identical to retail Rev 00 (CRC32 F9394E97): toolchain verified"
else
  echo "  MISMATCH: CRC32 $CRC, expected F9394E97" >&2
  exit 1
fi
