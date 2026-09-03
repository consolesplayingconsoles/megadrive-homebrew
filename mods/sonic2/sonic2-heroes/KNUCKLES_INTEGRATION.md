# Knuckles Integration Plan

## Status: Knuckles.asm copied, not yet wired

The Knuckles character code (3300 lines) is in `overlay/characters/knuckles_data.asm`, but it's **not yet included in the build**.

## What's needed to activate Knuckles

### 1. Include Knuckles.asm in s2disasm assembly

The main s2 disassembly includes character objects somewhere (Sonic, Tails). We need to:
- Find where Sonic/Tails objects are included in s2.asm
- Add an `include` directive for `characters/knuckles_data.asm`
- Or add Knuckles to the object jump table

### 2. Wire character-select logic to level loader

When a level starts:
- Read `v_current_char_p1` / `v_current_char_p2`
- Spawn the correct object (Sonic=Obj01, Tails=Obj02, Knuckles=Obj4C)

### 3. Verify symbol availability

Knuckles.asm references:
- `SK_Map_Knuckles` — sprite mappings (✓ copied to overlay)
- Knuckles-specific art/palettes (need to copy as required)
- Physics constants (may exist in s2disasm, or need S2+K versions)

## Quick checklist

- [ ] Locate character object includes in s2.asm
- [ ] Add Knuckles.asm include or alias
- [ ] Update character spawn logic to handle Obj4C (Knuckles)
- [ ] Copy art assets as needed (palettes, frames)
- [ ] Test build with Knuckles in character roster
- [ ] Verify 2P can pick Knuckles independently

## References

- SCHG guide: https://info.sonicretro.org/SCHG_How-to:Add_Extra_Characters_To_Sonic_2
- Sonic Retro forum: https://sonicresearch.org/community/index.php?threads/adding-new-characters-to-sonic-2.4062/
- Clean Engine: https://github.com/monolith4007/Starlight-9-Engine/ (reference implementation)
- TheBlad768 S2+K clone driver: https://github.com/TheBlad768/s2disasm-clone-driver (reference)
