#!/usr/bin/env bash
# Build the roster mod: rom/dbz-cpc.md (playable) + rom/dbz-cpc.ips (the shareable patch).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/../.env" ] && source "$HERE/../.env"   # shared: BASE_ROM
[ -f "$HERE/.env" ] && source "$HERE/.env"
[ -n "${BASE_ROM:-}" ] || { echo "[ERROR] BASE_ROM is not set (game .env)"; exit 1; }
[ -f "$BASE_ROM" ] || { echo "[ERROR] BASE_ROM not found: $BASE_ROM"; exit 1; }
args=("$BASE_ROM")
[ -n "${REPLACE:-}" ] && args+=(--replace "$REPLACE")
[ "${BLACK:-no}" = "yes" ] && args+=(--black)
python3 "$HERE/build.py" "${args[@]}"
echo "##OUTPUT:$HERE/rom/dbz-cpc.md"
