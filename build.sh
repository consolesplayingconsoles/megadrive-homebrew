#!/usr/bin/env bash
# Build an SGDK Mega Drive ROM via the stephane-d/sgdk Docker image (no local toolchain).
# SGDK's makefile always emits out/rom.bin; this stamps a descriptive copy so the file on
# the SD says what it is (everything on the card is a ROM), and can't drift out of date.
#
# SGDK projects live under games/ (homebrew) and tools/ (infrastructure); this resolves a
# project by name across both. ROM hacks under mods/ are NOT SGDK -- each has its own build.sh.
#
# Usage (from anywhere):  ./build.sh [project] [output-name.bin]
#   ./build.sh                 -> tools/datalink/out/cpc-player.bin  (the usual, zero args)
#   ./build.sh room            -> games/room/out/room.bin
#   ./build.sh datalink x.bin  -> tools/datalink/out/x.bin
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
rom="${1:-datalink}"                       # default: the ROM we iterate on
dir=""
for parent in games tools; do              # SGDK projects live under these
  [ -d "$here/$parent/$rom/src" ] && dir="$here/$parent/$rom" && break
done
[ -n "$dir" ] || { echo "no SGDK project '$rom' under games/ or tools/ (mods/ build themselves)"; exit 1; }
if   [ -n "${2:-}" ];          then out="$2"
elif [ "$rom" = "datalink" ];  then out="cpc-player.bin"   # its canonical SD name
else                                out="$rom.bin"
fi

# The Docker CLI here runs on the Colima context; start it if the daemon is down.
if ! docker info >/dev/null 2>&1; then
  echo "docker daemon down -> colima start"
  colima start
fi

echo "building $rom ..."
docker run --rm -v "$dir":/src ghcr.io/stephane-d/sgdk

cp "$dir/out/rom.bin" "$dir/out/$out"
echo "built: $rom/out/$out"
ls -la "$dir/out/$out"
