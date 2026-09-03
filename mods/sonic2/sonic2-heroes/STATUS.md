# Sonic 2 Heroes — Build Status

## What's Been Done

✅ **Framework**
- 2-player character selection (X+Y to cycle, independent P1/P2)
- Character selection RAM variables
- InitPlayers patched to read character selection
- Object table patched to add Knuckles at Obj4C
- Knuckles.asm included and ready to compile

✅ **Files in Overlay**
- `s2.asm` — InitPlayers patch + Knuckles include
- `sonic/character_select.asm` — Input handler for X+Y switching
- `sonic/variables_heroes.asm` — Character RAM definitions
- `sonic/objects_knuckles.asm` — Object table documentation
- `characters/knuckles_data.asm` — Knuckles character code (3300 lines from S2+K)
- `mappings/sprite/knuckles.bin` — Knuckles sprite mappings

✅ **Build System**
- `build.sh` — Patches object table with Python, assembles ROM
- `.gitignore` — Ignores dist/ and rom/

## Known Issues to Resolve

❓ **Symbol Dependencies**
- Knuckles.asm references S2+K-specific symbols (SK_Map_Knuckles, physics constants, etc.)
- May need to copy more resources from S2+K or create aliases

❓ **RAM Variables**
- Character selection variables defined but not yet included in the build
- Need to find where _variables.asm is included and add our vars there

❓ **Level Load Integration**
- Character-select input handler needs to be called in main loop
- Character spawn logic (InitPlayers) is patched but untested

## Next Steps

1. **Build test** — Run `./build.sh` and document any errors
2. **Symbol resolution** — Trace any undefined symbol errors and find/create needed definitions
3. **Variable integration** — Verify character RAM vars are accessible
4. **Input hookup** — Call character-select input handler in main loop
5. **Physical test** — Boot ROM in emulator and verify character switching works

## Test Build

```bash
cd /Users/francesc.montserrat/workspace/cpc/nodes/local/megadrive/homebrew/mods/sonic2/sonic2-heroes
./build.sh
# Watch for errors in lua build output
```
