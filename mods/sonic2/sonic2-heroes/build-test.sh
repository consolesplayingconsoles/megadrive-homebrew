#!/usr/bin/env bash
# Build "Sonic 2 Heroes" — [DESCRIBE FEATURE]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/.." && pwd)/s2disasm"
DIST="$HERE/dist"

mkdir -p "$DIST"
rsync -a --delete --exclude='.git' "$BASE/" "$DIST/"
cp -R "$HERE/overlay/." "$DIST/" 2>/dev/null || true

# Patch 1: Knuckles include DISABLED for now (too many symbol dependencies)
# TODO: Port Knuckles properly when we have all S2+K resources

# Patch 2: Add character selection RAM variable address definitions (use free RAM at $FFFFF7AB)
python3 - "$DIST/s2.asm" <<'PY'
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find where RAM addresses are defined (search for v_ constants)
# Add our variable addresses in the constants section
marker = 'include "s2.constants.asm"'
if marker in content:
    # Add after constants are included
    insert_point = content.find(marker) + len(marker)
    var_defs = '\n\n; Sonic 2 Heroes — Character selection & direction (free RAM at $FFFFF7AB-$FFFFF7AF)\nv_current_char_p1\t\tEQU\t$FFFFF7AB\nv_current_char_p2\t\tEQU\t$FFFFF7AC\nv_current_dir_p1\t\tEQU\t$FFFFF7AD\t; 0=Right, 1=Left (future use for directional character art)\nv_current_dir_p2\t\tEQU\t$FFFFF7AE\t; 0=Right, 1=Left\n'
    content = content[:insert_point] + var_defs + content[insert_point:]

with open(sys.argv[1], 'w') as f:
    f.write(content)
PY

# Patch 2b: Initialize character selection variables at game start (P1=Sonic, P2=Tails)
python3 - "$DIST/s2.asm" <<'PY'
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find Level_Init and add character init
marker = "InitPlayers:"
if marker in content:
    idx = content.find(marker)
    # Add init code at the very start of InitPlayers
    init_code = """; Sonic 2 Heroes — Initialize character selection & direction
\ttst.b\t(v_current_char_p1).w
\tbne.s\t.skip_init
\tclr.b\t(v_current_char_p1).w  ; P1 = Sonic (0)
\tmove.b\t#1, (v_current_char_p2).w  ; P2 = Tails (1)
\tclr.b\t(v_current_dir_p1).w   ; P1 direction = Right (0)
\tclr.b\t(v_current_dir_p2).w   ; P2 direction = Right (0)
.skip_init:
"""
    insert_idx = content.find('\n', idx) + 1
    content = content[:insert_idx] + init_code + content[insert_idx:]

with open(sys.argv[1], 'w') as f:
    f.write(content)
PY

# Patch 3: Inline character cycling into level VInt handler (DISABLED)
# NOTE: This was attempting to add C button handler in Vint_Level, but corrupted s2.asm during
# regex replacement. Since Start button (Patch 3b) already cycles characters, this is not needed.
# Future: If we want separate P1/P2 controls mid-level, revisit this using a safer insertion point.

# Patch 3b: Replace Start button pause with character cycling
python3 - "$DIST/s2.asm" <<'PYPATCH'
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find line 1585-1592 (pause check) and replace the START button handler
# Keep the "already paused" check, replace only the START button action
marker = "\tmove.b\t(Ctrl_1_Press).w,d0 ; is Start button pressed?\n\tor.b\t(Ctrl_2_Press).w,d0 ; (either player)\n\tandi.b\t#button_start_mask,d0\n\tbeq.s\tPause_DoNothing\t; if not, branch"

replacement = """; Sonic 2 Heroes — Start cycles character instead of pausing
\tmove.b\t(Ctrl_1_Press).w,d0 ; is Start button pressed (P1)?
\tandi.b\t#button_start_mask,d0
\tbeq.s\tPause_DoNothing\t; if not, branch
\t; Start pressed — cycle P1 character and skip pause
\taddq.b\t#1, (v_current_char_p1).w
\tcmpi.b\t#2, (v_current_char_p1).w
\tblo.s\tPause_DoNothing
\tclr.b\t(v_current_char_p1).w
\tbra.s\tPause_DoNothing"""

if marker in content:
    content = content.replace(marker, replacement)

with open(sys.argv[1], 'w') as f:
    f.write(content)
PYPATCH

# Patch 4: Replace ObjID_Sonic with conditional read for MainCharacter
python3 - "$DIST/s2.asm" <<'PYPATCH'
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find the first move.b #ObjID_Sonic,(MainCharacter+id).w in InitPlayers and replace it
# with conditional logic
marker1 = "\tmove.b\t#ObjID_Sonic,(MainCharacter+id).w ; load Obj01 Sonic object"
marker2 = "\tmove.b\t#ObjID_SpindashDust,(Sonic_Dust+id).w"

if marker1 in content and marker2 in content:
    # Find the InitPlayers section
    init_idx = content.find("InitPlayers:")
    first_sonic_idx = content.find(marker1, init_idx)

    if first_sonic_idx > init_idx:
        # Replace with conditional logic
        replacement = """; Sonic 2 Heroes — Character selection for P1
\tmove.b\t(v_current_char_p1).w, d0
\tcmp.b\t#1, d0
\tbeq.s\t.load_tails
\tmove.b\t#ObjID_Sonic,(MainCharacter+id).w
\tbra.s\t.after_p1_select
.load_tails:

TAILS_TEST:
\tmove.b\t#ObjID_Tails,(MainCharacter+id).w
.after_p1_select:"""

        line_end = content.find('\n', first_sonic_idx)
        content = content[:first_sonic_idx] + replacement + content[line_end:]

with open(sys.argv[1], 'w') as f:
    f.write(content)
PYPATCH


( cd "$DIST" && lua build.lua ) >/dev/null

mkdir -p "$HERE/rom"
ROM="$HERE/rom/sonic2-heroes.bin"
cp "$DIST/s2built.bin" "$ROM"
echo "built: $ROM ($(wc -c < "$ROM") bytes)"
