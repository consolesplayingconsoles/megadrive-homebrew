#!/usr/bin/env bash
# Build vanilla Sonic 2 (no edits) to verify the build pipeline.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s2disasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/" 2>/dev/null || true

( cd "$DIST" && lua build.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic2-vanilla.bin"
cp "$DIST/s2built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
