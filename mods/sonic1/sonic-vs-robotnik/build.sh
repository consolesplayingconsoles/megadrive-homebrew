#!/usr/bin/env bash
# Build "Sonic vs Robotnik" (WIP): the boss encounters as a 2-player fighting game.
# Step 1: boot straight into the level select, and start Green Hill 3 at the boss.
# Copies the shared pristine ../s1disasm-bk into dist/, overlays this mod's edits.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s1disasm"     # shared pristine disassembly
DIST="$HERE/dist"                            # disposable build tree (gitignored)

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/"
# No title-screen "BY CPC" here: this mod boots straight to the picker (which already
# prints "BY CPC"), and stamping it would land on the picker's first menu line.

# Spawn Green Hill 3 right at the boss so the fight (and the screen lock) start on
# load. X=$2A00 clamps the camera to the $2960 trigger; Y=$03B0 is the ground line.
# The locked screen means the blanked flat-sky background (see overlay sonic.asm)
# never gets scrolled/redrawn back to the buggy GHZ tiles.
python3 -c "open('$DIST/startpos/ghz3.bin','wb').write(bytes([0x2A,0x00,0x03,0xB0]))"

# Marble Zone 3: drop Sonic into the boss arena. The centre column (chunk 48 at
# X=$1800) is the LAVA PIT; solid ground is the ledge just right of it (chunk 4A,
# X=$1900) before the prison floor (X=$1A00). Spawn Sonic on that right ledge at
# X=$1920, a bit above it (Y=$0280) so he drops onto it. Camera settles ~$1880, past the
# $17F0 boss trigger, so Eggman descends and the flame-gun duel starts on load.
python3 -c "open('$DIST/startpos/mz3.bin','wb').write(bytes([0x19,0x20,0x02,0x80]))"

# Spring Yard 3: boss arena at boss_syz_x=$2C00; block floor sits ~Y=$556 over a pit.
# Spawn Sonic on the blocks at X=$2CC0 (past the $2C00 camera trigger), Y=$0520 above
# the floor so he drops onto it. (First guess -- tune Y if he clips or floats.)
python3 -c "open('$DIST/startpos/syz3.bin','wb').write(bytes([0x2C,0xC0,0x05,0x20]))"

# Star Light 3: boss arena at boss_slz_x=$2000; floor ~Y=$2C0 with the seesaws.
# Spawn Sonic at X=$20C0 (past the $2000 trigger), Y=$0280 so he drops to the floor.
python3 -c "open('$DIST/startpos/slz3.bin','wb').write(bytes([0x20,0xC0,0x02,0x80]))"

( cd "$DIST" && lua build.lua ) >/dev/null

# ROM goes to rom/ (gitignored) — easy to grab; full Sonic 1 so never committed.
mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic-vs-robotnik.bin"
cp "$DIST/s1built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
echo "  WIP: boots into level select; Green Hill 3 starts at the boss fight"
