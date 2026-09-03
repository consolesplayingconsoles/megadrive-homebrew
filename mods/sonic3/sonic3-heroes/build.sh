#!/usr/bin/env bash
# Build "Sonic 3 Heroes" — C hot-swaps the playable character, mid-level.
#
# Button scheme: A/B jump, C swaps. Vanilla S3&K maps all three of A/B/C to
# jump, which is why Sonic 2 forced us onto Start - but we have the source, so
# there is no reason to keep C on jump. Start is therefore left 100% vanilla,
# which removes the pause/intro-skip conflicts entirely rather than guarding
# around them.
#
# Hot swap: S3&K stores an object's CODE POINTER as a longword at offset 0, so
# becoming another character is one move.l. The DPLC window (ArtTile_Player_1)
# and dedupe (Player_prev_frame) are keyed to the SLOT, not the character, so
# the art follows the slot and a roster needs no per-character VRAM.
#
# Per-character state that must be handled on every swap (each found via a real
# symptom): the DPLC dedupe, the palette (Sonic and Tails SHARE Pal_SonicTails,
# Knuckles has his own), and Tails' tails, which is a separate object slot.
#
# Blocking: a character held by the other slot is skipped. Two objects running
# one character fight over per-character state - that was the meshed Tails.
#
# NOTE: skdisasm ships no macOS build tools, so the Lua build fails asking for
# build_tools/Mac-x86_64/. We supply them from overlay/build_tools/ (copied from
# s2disasm - same AS toolchain) rather than writing into the submodule, so the
# base disassembly stays pristine and every cpc-side change lives in overlay/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/skdisasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/" 2>/dev/null || true

# Patch 1: split the button roles so each one means exactly one thing.
#   A = jump (and only jump)
#   B = the double-jump action: shield move, or the Super transformation
#   C = swap character
# Vanilla maps A/B/C all to jump AND all to the double-jump action, which is why
# A and B felt "the same but not quite". The two are told apart by the
# double_jump_flag test that guards the shield-move entry (Sonic_ShieldMoves and
# its Tails/Knuckles equivalents); jump initiation has no such guard.
python3 - "$DIST/sonic3k.asm" <<'PYJUMP'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

start = next((i for i, l in enumerate(lines) if l.startswith("Obj_Sonic:")), None)
if start is None:
    sys.exit("PATCH FAILED: Obj_Sonic not found")

MASK = "#button_A_mask|button_B_mask|button_C_mask,d0"

jump = action = 0
for i in range(start, len(lines)):
    if MASK not in lines[i]:
        continue
    # A shield-move / double-jump site is guarded by double_jump_flag just above.
    context = "".join(lines[max(0, i - 8):i])
    if "double_jump_flag" in context:
        lines[i] = "\t\tandi.b\t#button_B_mask,d0\t; B does the double-jump action\n"
        action += 1
    else:
        lines[i] = "\t\tandi.b\t#button_A_mask,d0\t; A jumps; B and C are free\n"
        jump += 1

if jump == 0 or action == 0:
    sys.exit("PATCH FAILED: jump=%d action=%d" % (jump, action))

with open(path, "w") as f:
    f.writelines(lines)
print("patched: A jumps (%d), B double-jumps (%d), C swaps" % (jump, action))
PYJUMP

# Patch 1b: SUBSIDISE the transformation instead of removing its checks. Every
# cost check stays exactly as vanilla wrote it - we just hand the player the
# resources at level start. Patching the comparisons was what broke things: the
# same "cmpi.b #7,(Super_emerald_count)" is used BOTH as the cost gate (with
# bhs) and, in Sonic_Transform, to choose Super vs HYPER (with blo). Relaxing it
# blanket-style sent everyone Hyper, which loads Hyper stars/trail and, with
# object_control $81 freezing the transform animation, left the player stuck
# moving in place in mid-air.
#
# Granting CHAOS emeralds (leaving Super_emerald_count at 0) passes the gate and
# still resolves to Super rather than Hyper, through completely stock logic.
python3 - "$DIST/sonic3k.asm" <<'PYSUPER'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = "\t\tmove.b\t#1,(Level_started_flag).w\n"
if anchor not in content:
    sys.exit("PATCH FAILED: Level_started_flag init not found")

grant = (
    "; Sonic 3 Heroes - subsidise Super: hand over the emeralds and a ring float\n"
    "; so the vanilla cost checks pass untouched. Chaos, NOT Super, emeralds, or\n"
    "; Sonic_Transform would resolve to Hyper.\n"
    "\t\tmove.b\t#7,(Chaos_emerald_count).w\n"
    "\t\tclr.b\t(Emeralds_converted_flag).w\n"
)

content = content.replace(anchor, anchor + grant, 1)

with open(path, "w") as f:
    f.write(content)
print("patched: emeralds granted at level start")
PYSUPER

# Patch 1b2: rings are topped up to 50 AT THE TRANSFORM GATE rather than at
# level start, so you begin an act with whatever you actually collected.
# Effectively Ring_count = max(50, current) at the moment you transform.
python3 - "$DIST/sonic3k.asm" <<'PYRINGS'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

GATE = "cmpi.w\t#50,(Ring_count).w"

hits = 0
out = []
for i, line in enumerate(lines):
    if GATE in line and i + 1 < len(lines) and "blo" in lines[i + 1]:
        out.append("\t\tcmpi.w\t#50,(Ring_count).w\n")
        out.append("\t\tbhs.s\t.s3hRings%d\n" % hits)
        out.append("\t\tmove.w\t#50,(Ring_count).w\t; subsidise on transform\n")
        out.append("\t\tmove.b\t#1,(Update_HUD_ring_count).w\n")
        out.append(".s3hRings%d:\n" % hits)
        hits += 1
    out.append(line)

if hits == 0:
    sys.exit("PATCH FAILED: transform ring gate not found")

with open(path, "w") as f:
    f.writelines(out)
print("patched: rings topped up on transform (%d gates)" % hits)
PYRINGS

# Patch 1c: keep Super. Removing the entry cost alone was not enough - the
# sustain check in SonicKnux_SuperHyper (~23467) drains a ring per second and
# reverts at zero, so transforming with 0 rings lasted about a second. Turning
# its "bpl .return" into "bra .return" returns before the drain and the revert
# ever run, so Super persists. The level-over revert above it is untouched.
python3 - "$DIST/sonic3k.asm" <<'PYKEEP'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

hits = 0
for i, line in enumerate(lines[:-1]):
    if "subq.w" in line and "(Super_frame_count).w" in line:
        nxt = lines[i + 1]
        if "bpl.w" in nxt:
            lines[i + 1] = nxt.replace("bpl.w", "bra.w").split(";")[0].rstrip() \
                + "\t; Sonic 3 Heroes: never drain rings, never revert\n"
            hits += 1

if hits == 0:
    sys.exit("PATCH FAILED: Super sustain countdown not found")

with open(path, "w") as f:
    f.writelines(lines)
print("patched: Super persists (%d sustain checks)" % hits)
PYKEEP

# Patch 1d: B toggles Super off again. This has to live inside
# SonicKnux_SuperHyper rather than our Pause_Game hook, because .revertToNormal
# needs a0 (the player) and a4 (the Max_speed base), which only exist inside the
# character's own code. Gated to airborne so it mirrors the double-jump that
# transforms you - otherwise every ground jump would drop Super instantly.
python3 - "$DIST/sonic3k.asm" <<'PYTOGGLE'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# There is more than one ".continued:" in the file; anchor on the one INSIDE
# SonicKnux_SuperHyper, since only that routine has .revertToNormal in scope.
routine = content.find("SonicKnux_SuperHyper:")
if routine < 0:
    sys.exit("PATCH FAILED: SonicKnux_SuperHyper not found")

anchor = "\t.continued:\n"
idx = content.find(anchor, routine)
if idx < 0:
    sys.exit("PATCH FAILED: SonicKnux_SuperHyper .continued not found")

toggle = (
    "; Sonic 3 Heroes - press B in the air to drop Super again.\n"
    "; Another routine jumps straight into .continued (bypassing the Super check\n"
    "; at the top of this function), so re-test the flag here. Without it this\n"
    "; intercepted the very B press that transforms you and sent it to\n"
    "; .revertToNormal instead - leaving you stuck airborne in base form.\n"
    "\t\ttst.b\t(Super_Sonic_Knux_flag).w\n"
    "\t\tbeq.s\t.s3hNoToggle\n"
    "; Wait for the transformation to finish. Super_palette_status: 1 = fading,\n"
    "; -1 = done. Without this the toggle fired on the SAME B press that\n"
    "; transformed you: Sonic_Transform sets the flag and object_control $81 to\n"
    "; freeze you for the animation, we saw flag+B and reverted immediately, and\n"
    "; .revertToNormal does not clear object_control - leaving you floating in\n"
    "; base form. Waiting for the fade also guarantees object_control is cleared.\n"
    "\t\ttst.b\t(Super_palette_status).w\n"
    "\t\tbpl.s\t.s3hNoToggle\n"
    "\t\tbtst\t#Status_InAir,status(a0)\n"
    "\t\tbeq.s\t.s3hNoToggle\n"
    "\t\tmove.b\t(Ctrl_1_pressed).w,d0\n"
    "\t\tcmpa.w\t#Player_1,a0\n"
    "\t\tbeq.s\t.s3hGotPad\n"
    "\t\tmove.b\t(Ctrl_2_pressed).w,d0\t; P2 drops its own Super\n"
    "\t.s3hGotPad:\n"
    "\t\tandi.b\t#button_B_mask,d0\n"
    "\t\tbne.w\t.revertToNormal\n"
    "\t.s3hNoToggle:\n"
)

at = idx + len(anchor)
content = content[:at] + toggle + content[at:]

with open(path, "w") as f:
    f.write(content)
print("patched: B drops Super")
PYTOGGLE

# Patch 1e: stop Tails clobbering the other character's control word. Each
# character reads a FIXED logical word - Sonic and Knuckles read Ctrl_1_logical,
# Tails reads Ctrl_2_logical - and the slot decides which physical pad feeds it.
# But Tails-as-Player_1 also stamps its pad into Ctrl_1_logical, which is
# harmless in Tails-alone mode (nothing else reads it) and disastrous with a
# partner: both characters end up driven by one controller. Only do it when the
# other slot is empty.
python3 - "$DIST/sonic3k.asm" <<'PYCTRL'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

start = next((i for i, l in enumerate(lines) if l.startswith("Obj_Tails:")), None)
if start is None:
    sys.exit("PATCH FAILED: Obj_Tails not found")

target = "move.w\t(Ctrl_1).w,(Ctrl_1_logical).w\n"
hits = 0
for i, line in enumerate(lines):
    if i > start and line.strip() == target.strip() and "Ctrl_2_logical" in lines[i - 1]:
        indent = "\t\t"
        lines[i] = (
            indent + "tst.l\t(Player_2).w\t; is there a second character?\n"
            + indent + "bne.s\t.s3hSkipCtrl1\t; if so, leave its word alone\n"
            + indent + target
            + "\t.s3hSkipCtrl1:\n"
        )
        hits += 1

if hits != 1:
    sys.exit("PATCH FAILED: expected 1 Tails control clobber, found %d" % hits)

with open(path, "w") as f:
    f.writelines(lines)
print("patched: Tails no longer clobbers the partner's control word")
PYCTRL

# Patch 1f: release Player_2 after a transformation. SuperHyper_PalCycle ends
# the transform hold with "move.b #0,(Player_1+object_control).w" - hardcoded to
# slot 1, because vanilla never has a second character go Super. Sonic_Transform
# sets object_control $81 to freeze you for the animation, so an unreleased
# Player_2 floats in place forever. Clear both slots.
python3 - "$DIST/sonic3k.asm" <<'PYFLOAT'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

target = "move.b\t#0,(Player_1+object_control).w"
out, hits = [], 0
for line in lines:
    out.append(line)
    if target in line:
        indent = line[: len(line) - len(line.lstrip())]
        out.append(indent + "move.b\t#0,(Player_2+object_control).w\t; and the partner\n")
        hits += 1

if hits == 0:
    sys.exit("PATCH FAILED: transform release not found")

with open(path, "w") as f:
    f.writelines(out)
print("patched: both players released after transform (%d sites)" % hits)
PYFLOAT

# Patch 1g: make the player art loaders slot-aware. Sonic_Load_PLC and
# Knuckles_Load_PLC hardcode Player 1's dedupe byte (Player_prev_frame) and
# Player 1's VRAM window (ArtTile_Player_1) - vanilla never puts either of them
# in slot 2, so only Tails ever got a Player_2-aware loader. Under our swap a
# Sonic or Knuckles in slot 2 DMAs into slot 1's window and straight past it,
# corrupting the background and other art.
#
# Scoped tightly to those two routines. S3&K is packed close to the 68000's
# branch limits, and a wider substitution pushed an unrelated bsr.w out of its
# +/-32KB range, so keep the inserted bytes to a minimum.
python3 - "$DIST/sonic3k.asm" <<'PYSLOT'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

DEDUPE_CMP = "cmp.b\t(Player_prev_frame).w,d0"
DEDUPE_SET = "move.b\td0,(Player_prev_frame).w"
WINDOW = "move.w\t#tiles_to_bytes(ArtTile_Player_1),d4"

done = 0
for label in ("Sonic_Load_PLC2:", "Knuckles_Load_PLC2:"):
    at = next((i for i, l in enumerate(lines) if l.startswith(label)), None)
    if at is None:
        sys.exit("PATCH FAILED: %s not found" % label)

    for i in range(at, min(at + 40, len(lines))):
        if DEDUPE_CMP in lines[i]:
            # a1 is free here in both loaders; use it to pick the dedupe byte.
            lines[i] = (
                "\t\tlea\t(Player_prev_frame).w,a1\n"
                "\t\tcmpa.w\t#Player_2,a0\t; which slot is this character in?\n"
                "\t\tbne.s\t.s3hDedupe%d\n" % done
                + "\t\tlea\t(Player_prev_frame_P2).w,a1\n"
                ".s3hDedupe%d:\n" % done
                + "\t\tcmp.b\t(a1),d0\n"
            )
        elif DEDUPE_SET in lines[i]:
            lines[i] = "\t\tmove.b\td0,(a1)\n"
        elif WINDOW in lines[i]:
            lines[i] = (
                "\t\tmove.w\t#tiles_to_bytes(ArtTile_Player_1),d4\n"
                "\t\tcmpa.w\t#Player_2,a0\n"
                "\t\tbne.s\t.s3hWin%d\n" % done
                + "\t\tmove.w\t#tiles_to_bytes(ArtTile_Player_2),d4\n"
                ".s3hWin%d:\n" % done
            )
            done += 1
            break
    else:
        sys.exit("PATCH FAILED: window not found in %s" % label)

# The inserted bytes push this vanilla short branch out of range.
content = "".join(lines)
short = "\t\tbeq.s\tSonic_Load_PLC2\n"
if short not in content:
    sys.exit("PATCH FAILED: Perform_Player_DPLC branch not found")
content = content.replace(short, "\t\tbeq.w\tSonic_Load_PLC2\n")

with open(path, "w") as f:
    f.write(content)
print("patched: art loaders slot-aware (%d routines)" % done)
PYSLOT

# Patch 1h: make the Super palette follow the CHARACTER, not Player_mode.
# Three palette decisions branch on Player_mode - the fade-in, the revert, and
# Tails-vs-Knuckles inside the revert - so a swapped-in Knuckles took Sonic's
# path and came back blue. Syncing Player_mode to the swap fixed that but broke
# anything else keyed on it mid-level: the AIZ cave exit loads level art through
# a Player_mode branch, and a level initialised as Sonic+Tails then pulled the
# wrong art and corrupted the world. So leave Player_mode describing how the
# level was LOADED, and test who is actually in slot 1 here instead.
python3 - "$DIST/sonic3k.asm" <<'PYPAL'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

fixes = [
    # fade-in: mode < 2 meant "Sonic" -> ask if slot 1 IS Sonic
    ("\t\tcmpi.w\t#2,(Player_mode).w\n\t\tblo.s\tSuperHyper_PalCycle_FadeIn\n",
     "\t\tcmpi.l\t#Obj_Sonic,(Player_1).w\n\t\tbeq.s\tSuperHyper_PalCycle_FadeIn\n"),
    # revert: mode >= 2 meant "not Sonic" -> ask if slot 1 is NOT Sonic
    ("\t\tcmpi.w\t#2,(Player_mode).w\t; If Tails or Knuckles, branch, making this code Sonic-specific\n"
     "\t\tbhs.s\tSuperHyper_PalCycle_RevertNotSonic\n",
     "\t\tcmpi.l\t#Obj_Sonic,(Player_1).w\n\t\tbne.s\tSuperHyper_PalCycle_RevertNotSonic\n"),
    # revert, non-Sonic: mode >= 3 meant "Knuckles"
    ("\t\tcmpi.w\t#3,(Player_mode).w\t\t\t; If Knuckles, branch, making this code Tails-specific\n"
     "\t\tbhs.s\tSuperHyper_PalCycle_RevertKnuckles\n",
     "\t\tcmpi.l\t#Obj_Knuckles,(Player_1).w\n\t\tbeq.s\tSuperHyper_PalCycle_RevertKnuckles\n"),
]

done = 0
for old, new in fixes:
    if old in content:
        content = content.replace(old, new, 1)
        done += 1

if done != 3:
    sys.exit("PATCH FAILED: patched %d of 3 palette branches" % done)

with open(path, "w") as f:
    f.write(content)
print("patched: Super palette follows the character (%d branches)" % done)
PYPAL

# Patch 1z: branch-range fixups. S3&K sits close to the 68000's limits, and our
# inserted code pushes a few call sites past them. bsr.w tops out at +/-32KB;
# jsr with absolute addressing has unlimited range for two more bytes. Purely
# mechanical - same semantics, same stack behaviour.
python3 - "$DIST/sonic3k.asm" <<'PYRANGE'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

fixups = [
    ("\t\tbsr.w\tCheckRightWallDist\n", "\t\tjsr\t(CheckRightWallDist).l\n"),
    ("\t\tbsr.w\tCheckLeftWallDist\n", "\t\tjsr\t(CheckLeftWallDist).l\n"),
]

total = 0
for old, new in fixups:
    n = content.count(old)
    content = content.replace(old, new)
    total += n

if total == 0:
    sys.exit("PATCH FAILED: no range fixups applied")

with open(path, "w") as f:
    f.write(content)
print("patched: %d long-range call fixups" % total)
PYRANGE

# Patch 2: the swap itself. It lives in Pause_Game only because that routine is
# called once per frame from the level loop - we want the per-frame tick, not
# anything to do with pausing. Start is left untouched further down.
python3 - "$DIST/sonic3k.asm" <<'PYPATCH'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Marker must match VANILLA text: the build rsyncs a pristine skdisasm each run.
marker = (
    "\t\tbne.s\t+\n"
    "\t\tmove.b\t(Ctrl_1_pressed).w,d0\n"
    "\t\tandi.b\t#$80,d0\t; is Start pressed?\n"
    "\t\tbeq.w\tPause_NoPause\t; if not, branch\n"
)

# Do not introduce +/- local labels here: the "bne.s +" above binds to the next
# + label. Widen it, since our block pushes its target out of short range.
replacement = (
    "\t\tbne.w\t+\n"
    "; Sonic 3 Heroes - C hot-swaps the playable character. Gameplay only:\n"
    "; Game_mode $C is normal play (8 = demo), and Level_started_flag excludes\n"
    "; the AIZ plane intro, where Player_1 already holds Obj_Sonic.\n"
    "\t\tcmpi.b\t#$C,(Game_mode).w\n"
    "\t\tbne.w\tS3H_NoSwap\n"
    "\t\ttst.b\t(Level_started_flag).w\n"
    "\t\tbeq.w\tS3H_NoSwap\n"
    "\t\tmove.b\t(Ctrl_1_pressed).w,d0\n"
    "\t\tor.b\t(Ctrl_2_pressed).w,d0\n"
    "\t\tandi.b\t#button_C_mask,d0\n"
    "\t\tbeq.w\tS3H_NoSwap\t; neither player pressed C\n"
    "; No swapping while transformed. Super state spans the character (mappings,\n"
    "; palette cycle, per-slot speeds, object_control), and handing a consistent\n"
    "; version of it to a different character is far more moving parts than it is\n"
    "; worth. Drop Super with B first, then swap.\n"
    "\t\ttst.b\t(Super_Sonic_Knux_flag).w\n"
    "\t\tbne.w\tS3H_NoSwap\n"
    "\t\ttst.b\t(Super_Tails_flag).w\n"
    "\t\tbne.w\tS3H_NoSwap\n"
    "; a3 = slot to change, a4 = the other slot, whose character is blocked.\n"
    "; One code path serves both players.\n"
    "\t\tmovem.l\td1/a1-a4/d6,-(sp)\n"
    "\t\tlea\t(Player_1).w,a3\n"
    "\t\tlea\t(Player_2).w,a4\n"
    "\t\tmove.b\t(Ctrl_1_pressed).w,d0\n"
    "\t\tandi.b\t#button_C_mask,d0\n"
    "\t\tbne.s\tS3H_HaveSlot\t; P1 asked\n"
    "\t\tlea\t(Player_2).w,a3\t; otherwise it was P2\n"
    "\t\tlea\t(Player_1).w,a4\n"
    "S3H_HaveSlot:\n"
    "\t\tmove.l\t(a3),d0\n"
    "\t\tcmpi.l\t#Obj_Sonic,d0\n"
    "\t\tbeq.s\tS3H_NextChar\n"
    "\t\tcmpi.l\t#Obj_Tails,d0\n"
    "\t\tbeq.s\tS3H_NextChar\n"
    "\t\tcmpi.l\t#Obj_Knuckles,d0\n"
    "\t\tbeq.s\tS3H_NextChar\n"
    "S3H_Abort:\n"
    "\t\tmovem.l\t(sp)+,d1/a1-a4/d6\n"
    "\t\tbra.w\tS3H_NoSwap\t; nothing swappable, or the target is taken\n"
    "; Roster is Sonic and Knuckles. Tails stays vanilla and is NOT a swap target:\n"
    "; he is the only character with an AI sidekick mode, his own tail object in\n"
    "; an inverted slot, and the control-word clobber - keeping him out removes\n"
    "; all three. You can still swap AWAY from Tails, so P2 can join the roster.\n"
    "S3H_NextChar:\n"
    "\t\tmove.l\t#Obj_Sonic,d1\t; from Tails or Knuckles -> Sonic\n"
    "\t\tcmpi.l\t#Obj_Sonic,d0\n"
    "\t\tbne.s\tS3H_CheckHeld\n"
    "\t\tmove.l\t#Obj_Knuckles,d1\t; from Sonic -> Knuckles\n"
    "S3H_CheckHeld:\n"
    "\t\tcmp.l\t(a4),d1\t; the other player already has it?\n"
    "\t\tbeq.w\tS3H_Abort\n"
    "S3H_Chosen:\n"
    "\t\tmove.l\td1,(a3)\n"
"; Tails' init puts its tail object in Tails_tails_2P when Tails is PLAYER_1,\n"
    "; and in Tails_tails when it is PLAYER_2 (the names are inverted, see\n"
    "; sonic3k.asm ~25532 / ~25538). Clear the slot matching the player we just\n"
    "; changed. Clearing Tails_tails unconditionally left P1's outgoing tail\n"
    "; attached AND destroyed P2's legitimate one.\n"
    "\t\tcmpa.w\t#Player_1,a3\n"
    "\t\tbne.s\tS3H_TailP2\n"
    "\t\tmove.l\t#0,(Tails_tails_2P).w\n"
    "\t\tbra.s\tS3H_TailDone\n"
    "S3H_TailP2:\n"
    "\t\tmove.l\t#0,(Tails_tails).w\n"
    "S3H_TailDone:\n"
    "\t\tmove.b\t#0,routine(a3)\t; re-run the character's init\n"
    "; Swapping hands over the BASE form. The incoming character inherits none of\n"
    "; the Super state - mappings, palette, speeds - so leaving the flags set\n"
    "; stranded it in a form it could not leave. Also clear object_control, or a\n"
    "; swap during the transform freeze leaves the new character floating.\n"
    "\t\tmove.b\t#0,(Super_Sonic_Knux_flag).w\n"
    "\t\tmove.b\t#0,(Super_Tails_flag).w\n"
    "\t\tmove.b\t#0,(Super_palette_status).w\n"
    "\t\tmove.b\t#0,object_control(a3)\n"
    "; The DPLC skips its DMA when the frame number matches the cached one, so\n"
    "; without this the new character draws on the outgoing one's tiles. -1 is\n"
    "; vanilla's sentinel (~23495). The cache is per-SLOT, so pick to match.\n"
    "\t\tcmpa.w\t#Player_1,a3\n"
    "\t\tbne.s\tS3H_P2Frame\n"
    "\t\tmove.b\t#-1,(Player_prev_frame).w\n"
    "; Base-form speeds for this slot (the values .revertToNormal restores),\n"
    "; otherwise a character swapped in while Super keeps Super's handling.\n"
    "\t\tmove.w\t#$600,(Max_speed).w\n"
    "\t\tmove.w\t#$C,(Acceleration).w\n"
    "\t\tmove.w\t#$80,(Deceleration).w\n"
    "; Sonic and Tails share Pal_SonicTails; Knuckles has his own. Only the main\n"
    "; slot owns this palette line, so P2-as-Knuckles keeps whatever is loaded.\n"
    "\t\tlea\t(Pal_SonicTails).l,a1\n"
    "\t\tcmpi.l\t#Obj_Knuckles,d1\n"
    "\t\tbne.s\tS3H_PalGo\n"
    "\t\tlea\t(Pal_Knuckles).l,a1\n"
    "S3H_PalGo:\n"
    "\t\tlea\t(Normal_palette).w,a2\n"
    "\t\tmoveq\t#bytesToLcnt($20),d6\n"
    "S3H_PalLoop:\n"
    "\t\tmove.l\t(a1)+,(a2)+\n"
    "\t\tdbf\td6,S3H_PalLoop\n"
    "\t\tbra.s\tS3H_SwapDone\n"
    "S3H_P2Frame:\n"
    "\t\tmove.b\t#-1,(Player_prev_frame_P2).w\n"
    "\t\tmove.b\t#-1,(Player_prev_frame_P2_tail).w\n"
    "\t\tmove.w\t#$600,(Max_speed_P2).w\n"
    "\t\tmove.w\t#$C,(Acceleration_P2).w\n"
    "\t\tmove.w\t#$80,(Deceleration_P2).w\n"
    "S3H_SwapDone:\n"
    "\t\tmovem.l\t(sp)+,d1/a1-a4/d6\n"
    "S3H_NoSwap:\n"
    "; Start below is untouched vanilla: it still pauses, and still skips.\n"
    "\t\tmove.b\t(Ctrl_1_pressed).w,d0\n"
    "\t\tandi.b\t#$80,d0\t; is Start pressed?\n"
    "\t\tbeq.w\tPause_NoPause\t; if not, branch\n"
)

if marker not in content:
    sys.exit("PATCH FAILED: Pause_Main Start-button block not found")

content = content.replace(marker, replacement, 1)

with open(path, "w") as f:
    f.write(content)

print("patched: C hot-swaps Sonic <-> Knuckles, Start left vanilla")
PYPATCH

# Patch 3: sign the cartridge header. The title screen's text is pre-rendered
# art (ArtNem_TitleScreenText), not a font, so a subtitle there needs a drawn
# asset. The header is plain text and is what emulators and flashcarts display,
# so it signs the build without inventing artwork. Both name fields are exactly
# 48 characters - the header is fixed-width and the ROM will not boot if the
# length changes.
python3 - "$DIST/sonic3k.asm" <<'PYHEADER'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

OLD = '"SONIC & KNUCKLES                                "'
NEW = '"SONIC 3 HEROES - SWAP MOD BY CPC                "'

assert len(OLD) == len(NEW), "header fields are fixed width"

n = content.count(OLD)
if n != 2:
    sys.exit("PATCH FAILED: expected 2 header names, found %d" % n)

content = content.replace(OLD, NEW)

with open(path, "w") as f:
    f.write(content)
print("patched: cartridge header signed (%d fields)" % n)
PYHEADER

# Patch 4: "CPC" on the title screen, spelled from tiles already on it.
#
# The title text is pre-rendered art, not a font - but Map_TitleScreenText draws
# "COMPETITION" from tiles $0C-$17, twelve tiles for eleven letters, i.e. one
# tile per character. So $0C is C and $0F is P, and CPC costs no new artwork.
# Mirrors Obj_TitleCopyright for art base, palette and priority.
python3 - "$DIST/sonic3k.asm" <<'PYCPC'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = "\nObj_TitleCopyright:\n"
if anchor not in content:
    sys.exit("PATCH FAILED: Obj_TitleCopyright not found")

obj = (
    "\n; Sonic 3 Heroes - CPC credit, built from the title screen's own letters.\n"
    "S3H_Obj_CPC:\n"
    "\t\tmove.l\t#S3H_Map_CPC,mappings(a0)\n"
    "\t\tmove.w\t#make_art_tile($680,3,1),art_tile(a0)\n"
    "\t\tmove.w\t#$158,x_pos(a0)\t; right edge, as the copyright uses\n"
    "\t\tmove.w\t#$C0,y_pos(a0)\t; top right, down in the dark of the ring\n"
    "\t\tmove.w\t#$80,priority(a0)\t; priority is in units of $80 - $40 is invalid\n"
    "\t\tmove.b\t#$18,width_pixels(a0)\n"
    "\t\tmove.b\t#4,height_pixels(a0)\n"
    "\t\tmove.b\t#0,mapping_frame(a0)\n"
    "\t\tmove.l\t#S3H_Obj_CPC_Display,(a0)\n"
    "S3H_Obj_CPC_Display:\n"
    "\t\tjmp\t(Draw_Sprite).l\n"
    "; The row reads _COMPETITION_, so the underscore is $0C and the letters start\n"
    "; at $0D: C=$0D, O=$0E, M=$0F, P=$10. Rendering $0C/$0F gave \"_M_\".\n"
    "S3H_Map_CPC:\n"
    "\t\tdc.w\tS3H_CPC_Frame0-S3H_Map_CPC\n"
    "S3H_CPC_Frame0:\tdc.w 3\n"
    "; The O beside C is a fat glyph and spills into C's tile. Pieces draw in\n"
    "; order, so overlap them by a pixel: each letter paints over the previous\n"
    "; one's spillover. A blank tile ($02, the space in \"1 PLAYER\") caps the\n"
    "; trailing C is left alone: $02 was not actually blank and drew a stray\n"
    "; glyph, which looked worse than the edge it was meant to hide.\n"
    "\t\tdc.b\t0, 0, 0, $0D, 0, 0\t; C\n"
    "\t\tdc.b\t0, 0, 0, $10, 0, 6\t; P, 2px over C - 3px was too tight\n"
    "\t\tdc.b\t0, 0, 0, $0D, 0, $E\t; C, butted against P\n"
    "\t\teven\n"
)

content = content.replace(anchor, obj + anchor, 1)

spawn = "\t\tmove.l\t#Obj_TitleANDKnuckles,(Dynamic_object_RAM+(object_size*4)).w"
if spawn not in content:
    sys.exit("PATCH FAILED: title object spawn list not found")
content = content.replace(
    spawn,
    spawn + "\n\t\tmove.l\t#S3H_Obj_CPC,(Dynamic_object_RAM+(object_size*5)).w", 1)

with open(path, "w") as f:
    f.write(content)
print("patched: CPC on the title screen")
PYCPC

# Patch 5: level select and debug mode always on. Both are the retail game's own
# cheat (the title-screen button sequence at ~6295 sets exactly these two flags),
# and Sonic 3's developers had the same shortcut left in and commented out at
# ~10028 - "These two below lines from S3 were NOPed out". This mod is a god-mode
# cruise, so there is nothing to protect.
#
# Set them as the TITLE SCREEN loads its objects: at level init they would only
# apply after you had already played a level, which is too late to be useful.
python3 - "$DIST/sonic3k.asm" <<'PYCHEATS'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

anchor = "\t\tmove.l\t#Obj_TitleCopyright,(Dynamic_object_RAM).w\n"
if anchor not in content:
    sys.exit("PATCH FAILED: title object spawn not found")

content = content.replace(
    anchor,
    "\t\tmove.w\t#(1<<8)|1,(Level_select_flag).w\t; always available\n"
    "\t\tmove.w\t#(1<<8)|1,(Debug_cheat_flag).w\n"
    + anchor,
    1)

with open(path, "w") as f:
    f.write(content)
print("patched: level select and debug mode enabled")
PYCHEATS

( cd "$DIST" && lua buildS3Complete.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic3-heroes.bin"
cp "$DIST/sonic3k.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
