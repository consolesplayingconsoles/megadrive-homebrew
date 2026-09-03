#!/usr/bin/env bash
# Build "Sonic 2 Heroes" — Start hot-swaps the player character mid-level,
# with no level reload and no loss of position or momentum.
#
# Why this works. Character art is never bulk-loaded into VRAM. Each character
# streams only its CURRENT frame via a DPLC (LoadSonicDynPLC / LoadTailsDynPLC)
# into its own small VRAM window (ArtTile_ArtUnc_Sonic = $0780, 32 tiles;
# ArtTile_ArtUnc_Tails = $07A0, 16 tiles). That streaming routine belongs to the
# character's own object code, so swapping the object swaps the art with it.
#
# Obj01_Init / Obj02_Init set only identity - y_radius, x_radius, mappings,
# art_tile, top speed / acceleration / deceleration. They never write x_pos,
# y_pos or velocity, so an in-place swap keeps position and momentum for free.
#
# The swap is therefore three writes:
#   1. MainCharacter+id      = the new character's object ID
#   2. MainCharacter+routine = 0, so the object re-runs its init next frame
#   3. <char>_LastLoadedDPLC = -1, to force the art to re-stream
#
# This scales to a roster: a new character needs its own mappings, DPLC and art
# plus a VRAM window. Since only one character is playable at a time, they can
# all share one window rather than each reserving its own.
#
# NOTE: test in "Sonic Alone" (Options screen). In the default Sonic+Tails mode
# the sidekick is already Tails and owns the $07A0 window, so swapping the main
# character to Tails puts two objects on one window and one DPLC cache - expect
# glitching. That is a window-allocation conflict, not a flaw in the swap.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s2disasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/" 2>/dev/null || true

# Patch: in PauseGame, Start cycles the character instead of pausing.
# Setting Level_Inactive_flag makes Level_MainLoop re-enter Level on the next
# frame (see the tst.w/bne.w Level right after the PauseGame call), so the new
# character appears immediately instead of only after you die.
python3 - "$DIST/s2.asm" <<'PYEQU'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = 'include "s2.constants.asm"'
if anchor not in content:
    sys.exit("PATCH FAILED: constants include not found")

# Scratch for the swap. $FFFFFF60-$FFFFFF6F is unused and sits outside every
# region Level: wipes via clearRAM, though these only need to live one frame.
equs = (
    "\n\n; Sonic 2 Heroes scratch\n"
    "S2H_PendingRestore\tEQU\t$FFFFFF60\n"
    "S2H_SavedX\t\tEQU\t$FFFFFF62\n"
    "S2H_SavedY\t\tEQU\t$FFFFFF64\n"
    "\n; Knuckles DPLC streaming window. Player art ends at $07C0 (Sonic $0780/32\n"
    "; tiles, Tails $07A0/16, Tails_Tails $07B0/16) and VRAM tiles run to $07FF,\n"
    "; so $07C0 is free. 32 tiles, matching Sonic's allowance.\n"
    "ArtTile_ArtUnc_Knuckles\tEQU\t$07C0\n"
    "Knuckles_LastLoadedDPLC\tEQU\t$FFFFFF66\n"
)
i = content.index(anchor) + len(anchor)
content = content[:i] + equs + content[i:]

with open(path, "w") as f:
    f.write(content)
PYEQU

# Knuckles assets, lifted from TheBlad768/skdisasm (Sonic & Knuckles). Their
# formats already match Sonic 2: the DPLC header is a plain count word, and the
# 1P mappings are 6 bytes per piece (S&K keeps its 2P mappings in a separate
# file), so no conversion is needed.
python3 - "$DIST/s2.asm" <<'PYART'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = 'MapRUnc_Tails:\t\t\tinclude\t\t"mappings/spriteDPLC/Tails.asm"\n'
if anchor not in content:
    sys.exit("PATCH FAILED: Tails asset declarations not found")

decls = (
    "\nArtUnc_Knuckles:\t\tBINCLUDE\t\"art/uncompressed/Knuckles.bin\"\n"
    "\nMapUnc_Knuckles:\t\tinclude\t\t\"mappings/sprite/Knuckles.asm\"\n"
    "\nMapRUnc_Knuckles:\t\tinclude\t\t\"mappings/spriteDPLC/Knuckles.asm\"\n"
)
content = content.replace(anchor, anchor + decls, 1)

with open(path, "w") as f:
    f.write(content)
print("patched: Knuckles art, mappings and DPLC declared")
PYART

python3 - "$DIST/s2.asm" <<'PYPATCH'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

marker = (
    "\tbne.s\t+\t\t; if yes, branch\n"
    "\tmove.b\t(Ctrl_1_Press).w,d0 ; is Start button pressed?\n"
    "\tor.b\t(Ctrl_2_Press).w,d0 ; (either player)\n"
    "\tandi.b\t#button_start_mask,d0\n"
    "\tbeq.s\tPause_DoNothing\t; if not, branch\n"
)

# NOTE: do not use +/- local labels here. The instruction above this block is
# "bne.s +", which binds to the next + label; adding one would retarget it.
replacement = (
    "\tbne.w\t+\t\t; widened: our block exceeds the short-branch range\n"
    "; Sonic 2 Heroes - Start hot-swaps the player character instead of pausing.\n"
    "; First finish last frame's swap. A character's init may move the player\n"
    "; (Obj01_Init does x -= $20, y += 4; Obj02_Init does not), so we snapshot\n"
    "; position before the swap and put it back after init has run. Restoring a\n"
    "; snapshot rather than undoing a known offset keeps this correct for any\n"
    "; character added later.\n"
    "\ttst.b\t(S2H_PendingRestore).w\n"
    "\tbeq.s\tS2H_NoRestore\n"
    "\tclr.b\t(S2H_PendingRestore).w\n"
    "\tmove.w\t(S2H_SavedX).w,(MainCharacter+x_pos).w\n"
    "\tmove.w\t(S2H_SavedY).w,(MainCharacter+y_pos).w\n"
    "S2H_NoRestore:\n"
    "; Vanilla OR'd in Ctrl_2_Press here because either player could pause. We do\n"
    "; not, or P2's Start would swap P1's character.\n"
    "\tmove.b\t(Ctrl_1_Press).w,d0 ; is P1's Start pressed?\n"
    "\tandi.b\t#button_start_mask,d0\n"
    "\tbeq.w\tPause_DoNothing\t; if not, branch\n"
    "\tmove.w\t(MainCharacter+x_pos).w,(S2H_SavedX).w\n"
    "\tmove.w\t(MainCharacter+y_pos).w,(S2H_SavedY).w\n"
    "\tmove.b\t#1,(S2H_PendingRestore).w\n"
    "\tcmpi.b\t#ObjID_Sonic,(MainCharacter+id).w\n"
    "\tbne.s\tS2H_ToSonic\n"
    "\tmove.b\t#ObjID_Tails,(MainCharacter+id).w\n"
    "\tmove.b\t#-1,(Tails_LastLoadedDPLC).w ; force the DPLC to re-stream\n"
    "\tmove.w\t#make_art_tile(ArtTile_ArtUnc_Tails,0,0),(MainCharacter+art_tile).w\n"
    "\tbra.s\tS2H_SwapDone\n"
    "S2H_ToSonic:\n"
    "\tmove.b\t#ObjID_Sonic,(MainCharacter+id).w\n"
    "\tmove.b\t#-1,(Sonic_LastLoadedDPLC).w\n"
    "\tmove.w\t#make_art_tile(ArtTile_ArtUnc_Sonic,0,0),(MainCharacter+art_tile).w\n"
    "; Obj02_Init spawns Tails' tails as its own object parented to the player.\n"
    "; Nothing despawns it, so without this Sonic keeps wearing them. Any future\n"
    "; character with an accessory object needs the same teardown here.\n"
    "\tmove.b\t#0,(Tails_Tails+id).w\n"
    "S2H_SwapDone:\n"
    "; EXCLUSIVITY. Sonic 2 keeps per-CHARACTER globals, not per-slot: the logical\n"
    "; control word, the DPLC cache, top speed / acceleration / deceleration, the\n"
    "; accessory slot and the VRAM window. Two slots running the same character\n"
    "; share all of it and fight - that is why P2 moved P1's Tails. Evict the\n"
    "; duplicate. This compares IDs, so it holds for Knuckles or anyone else; it\n"
    "; does not depend on Tails being the sidekick.\n"
    "\tmove.b\t(MainCharacter+id).w,d0\n"
    "\tcmp.b\t(Sidekick+id).w,d0\n"
    "\tbne.s\tS2H_NoClash\n"
    "\tmove.b\t#0,(Sidekick+id).w\n"
    "S2H_NoClash:\n"
    "; Drop the outgoing character's animation state. mapping_frame is an index\n"
    "; into that character's mapping table, so a stale one renders garbage.\n"
    "; clr.l covers mapping_frame/anim_frame/anim/prev_anim ($1A-$1D).\n"
    "\tclr.l\t(MainCharacter+mapping_frame).w\n"
    "\tclr.b\t(MainCharacter+anim_frame_duration).w\n"
    "\tmove.b\t#0,(MainCharacter+routine).w ; re-run the character's init\n"
    "\tbra.w\tPause_DoNothing\t; never pause\n"
)

if marker not in content:
    sys.exit("PATCH FAILED: PauseGame Start-button block not found")

content = content.replace(marker, replacement, 1)

with open(path, "w") as f:
    f.write(content)

print("patched: Start hot-swaps the player character")
PYPATCH

( cd "$DIST" && lua build.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic2-heroes.bin"
cp "$DIST/s2built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
