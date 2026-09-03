# Integration Checklist

## Variables to add to `_variables.asm`

```asm
; Character select persistent RAM (2P support)
v_current_char_p1:  ds.b 1  ; P1 character index (0-based)
v_current_char_p2:  ds.b 1  ; P2 character index (0-based)
v_char_count:       ds.b 1  ; Total available characters
```

Add these after the existing Sonic 2 RAM variables (e.g., after v_lives, v_score, etc.). Keep near the beginning of persistent RAM so they survive level reloads.

## Files to overlay

- `sonic/character_select.asm` — Character switching logic
- `sonic/sonic.asm` — Integrate CharacterSelect_CheckInput in main loop
- `_variables.asm` — Add character RAM slots
- `characters/*.asm` — Each character's object code (Knuckles, Amy, etc.) as ported

## Integration points in s2disasm

1. **Level init** (likely `LevelInit` or `GM_Level_Init`):
   - Call `CharacterSelect_Init`

2. **Main input loop** (joypad handler):
   - Call `CharacterSelect_CheckInput` after normal input

3. **Character spawn** (where Sonic/Tails object is created):
   - Call `CharacterSelect_LoadCharacter` to pick the right character object

4. **Level end** (results screen):
   - Reset `v_current_char` to 0 (or keep across runs — TBD)

## Character Porting Sources & Plan

### Priority 1: Knuckles
- **Source**: https://github.com/giovannidotgen/Sonic-2-with-Knuckles
- **License**: Custom non-commercial (educational use, credit required)
- **Status**: Complete disassembly + Knuckles fully playable
- **Notes**: Extract Knuckles init/physics from their `characters/` code, adapt to our framework
- **Effort**: Medium (code already works, just integrate)

### Priority 2: Amy Rose
- **Source**: https://gamebanana.com/mods/251037 (GameBanana mod by E-122-Psi et al)
- **License**: Non-commercial (GameBanana host, credit all contributors)
- **Status**: Disassembled mod, can extract ASM diff
- **Notes**: Slower than Sonic, special attack moves, different from Sonic Advance style
- **Effort**: Medium (may need to reverse-engineer from patched ROM or find source ASM)

### Priority 3+ (Optional): Mighty, Shadow, others
- **Source**: Sonic 2 Megamix (https://archive.org/details/Sonic_2_Megamix_S2_Hack)
- **License**: Check original mod license
- **Status**: ROM hack, likely requires reverse-engineering
- **Effort**: High (manual disassembly from ROM diff)

## Character porting checklist

For each character (Knuckles, Amy, etc.):

- [ ] Find source code / open mod (✓ done above)
- [ ] Extract character object code
- [ ] Port sprite/animation mappings
- [ ] Port physics constants (acceleration, max speed, jump)
- [ ] Adapt level collision if needed (e.g., Knuckles gliding)
- [ ] Add to `characters/<name>_data.asm`
- [ ] Add init branch in `CharacterSelect_LoadCharacter`
- [ ] Update README character table
- [ ] Test with P1 + P2 both selecting character
- [ ] Credit source in README + code comments

## Testing workflow

1. Build vanilla (no characters): `./build.sh`
2. Build with 2 chars (Sonic + Tails): Should work (already in S2)
3. Add Knuckles: Integrate S2+K port, test X+Y switching
4. Add others: One by one, test each in emulator
5. GBA serial later: Sonic Advance 2 sends character ID instead of X+Y

## Future: GBA integration

The Pi will read serial data from GBA (Sonic Advance 2 picker screen), extract character ID, and send to MD console. For now, X+Y local input suffices.
