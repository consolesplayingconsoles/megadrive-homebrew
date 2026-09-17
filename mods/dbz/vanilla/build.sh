#!/usr/bin/env bash
# Vanilla DBZ: the disassembly is analysis only (it builds no ROM), so vanilla checks
# your base ROM is the one every mod here starts from: L'Appel du Destin (France),
# SHA1 5ff71986f4911b5dfd16598a5a3a9ba398c92c60.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/../.env" ] && source "$HERE/../.env"
[ -n "${BASE_ROM:-}" ] || { echo "[ERROR] BASE_ROM is not set (game .env)"; exit 1; }
[ -f "$BASE_ROM" ] || { echo "[ERROR] BASE_ROM not found: $BASE_ROM"; exit 1; }

EXPECT="5ff71986f4911b5dfd16598a5a3a9ba398c92c60"
GOT=$(shasum "$BASE_ROM" | cut -c1-40)
[ "$GOT" = "$EXPECT" ] || { echo "  MISMATCH: sha1 $GOT, expected $EXPECT" >&2; exit 1; }
mkdir -p "$HERE/rom"
ROM="$HERE/rom/dbz-vanilla.md"
cp "$BASE_ROM" "$ROM"
echo "  base ROM verified (sha1 $EXPECT)"
echo "##OUTPUT:$ROM"
