#!/usr/bin/env bash
# Build "Sonic 3 Tornado" — Angel Island as a flight simulator.
#
# You are the Tornado. There is no Sonic, no Knuckles, no Tails. That is the
# whole point, and it is also what makes it work: the plane sprite needs ~128
# tiles, and in sonic3-heroes there was nowhere to put them because two
# characters, a sidekick and a HUD were already using every tile. With nobody
# else on screen, the player art region is free and the plane simply takes it.
#
# Rings are collateral - the art overruns into ArtTile_Ring - and that is fine
# here: there is nothing to collect and no score to chase. You cruise.
#
# NOTE: skdisasm ships no macOS build tools, so the Lua build fails asking for
# build_tools/Mac-x86_64/. We supply them from overlay/build_tools/ (copied from
# s2disasm - same AS toolchain) rather than writing into the submodule, so the
# base disassembly stays pristine.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/skdisasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/" 2>/dev/null || true

# STEP 1: vanilla game plus level select, nothing else.
#
# The Tornado work is deliberately NOT here. Establish first that the ending
# scene is reachable and what it looks like untouched; only then put a plane in
# it. Everything tried inside AIZ failed on VRAM or the camera, so there is no
# point layering the drone onto an unverified baseline.
#
# Level select on from the start, so the ending zone is reachable without
# forcing the boot zone (which never hit the real start path and just broke it)
# and without playing the whole game. Line ~10031 shows the game's own commented
# out version of exactly this.
python3 - "$DIST/sonic3k.asm" <<'PYLEVSEL'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Set it as the TITLE SCREEN loads its objects. Setting it at level init was
# useless: the flag only mattered once you had already played a level and come
# back, so it was never on when you first reached the menu.
anchor = "\t\tmove.l\t#Obj_TitleCopyright,(Dynamic_object_RAM).w\n"
if anchor not in content:
    sys.exit("PATCH FAILED: title object spawn not found")

content = content.replace(
    anchor,
    "\t\tmove.w\t#(1<<8)|1,(Level_select_flag).w\t; level select always available\n" + anchor,
    1)

with open(path, "w") as f:
    f.write(content)
print("patched: level select enabled")
PYLEVSEL

# Re-skin the player as the Tornado, in The Doomsday only. Doomsday already IS
# a flight stage - Super Sonic flies freely, the camera follows him, hazards are
# objects not terrain - so no new object, no camera work and no collision code
# is needed. Only the sprite changes.
#
# The plane has 6 mapping frames against Sonic's 251, so his animations index
# far past the end. Clamp at the two points the frame is USED - the draw and the
# DPLC - never at object entry, which is a frame too late to guard either.
python3 - "$DIST/sonic3k.asm" <<'PYSKIN'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

DDZ = "$C"
FRAMES = 6

# Mappings, at Sonic's init.
old = "\t\tmove.l\t#Map_Sonic,mappings(a0)\n"
i = content.find("Obj_Sonic:")
at = content.find(old, i)
if at < 0:
    sys.exit("PATCH FAILED: Sonic init mappings not found")
content = (content[:at]
           + "\t\tmove.l\t#Map_Sonic,mappings(a0)\n"
             "\t\tcmpi.b\t#" + DDZ + ",(Current_zone).w\n"
             "\t\tbne.s\t.s3tMapOk\n"
             "\t\tmove.l\t#Map_TitleTailsPlane,mappings(a0)\n"
             ".s3tMapOk:\n"
           + content[at + len(old):])

# Clamp the frame before the draw.
old = "\t\tjsr\t(Draw_Sprite).l\n"
i = content.find("Sonic_Display:")
at = content.find(old, i)
if at < 0:
    sys.exit("PATCH FAILED: Sonic_Display draw not found")
content = (content[:at]
           + "\t\tcmpi.b\t#" + DDZ + ",(Current_zone).w\n"
             "\t\tbne.s\t.s3tDrawOk\n"
             "\t\tcmpi.b\t#%d,mapping_frame(a0)\n" % FRAMES
           + "\t\tblo.s\t.s3tDrawOk\n"
             "\t\tmove.b\t#0,mapping_frame(a0)\n"
             ".s3tDrawOk:\n"
           + content[at:])

# Clamp the frame the DPLC reads.
old = "\t\tmove.b\tmapping_frame(a0),d0\n"
i = content.find("Sonic_Load_PLC:")
at = content.find(old, i)
if at < 0:
    sys.exit("PATCH FAILED: Sonic_Load_PLC frame read not found")
content = (content[:at + len(old)]
           + "\t\tcmpi.b\t#" + DDZ + ",(Current_zone).w\n"
             "\t\tbne.s\t.s3tPlcOk\n"
             "\t\tcmpi.b\t#%d,d0\n" % FRAMES
           + "\t\tblo.s\t.s3tPlcOk\n"
             "\t\tmoveq\t#0,d0\n"
             ".s3tPlcOk:\n"
           + content[at + len(old):])

# ISOLATION STEP: no art load at all. Calling Load_PLC_Raw from Sonic's init is
# the remaining crash suspect, so prove it by removing it. The plane will draw
# with Sonic's tiles - wrong pixels, right shape - but if that runs, the load is
# the only thing left to solve, and it belongs in Doomsday's own PLC list rather
# than in an object init.

with open(path, "w") as f:
    f.write(content)
print("patched: player re-skinned as the Tornado in Doomsday")
PYSKIN

( cd "$DIST" && lua buildS3Complete.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic3-tornado.bin"
cp "$DIST/sonic3k.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
