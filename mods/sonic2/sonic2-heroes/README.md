# Sonic 2 Heroes

A Sonic 2 mod adding a multi-character roster. Press **Start** to cycle P1 character (temporary input), **L+R** on GBA later for persistent selection UI.

## Characters

| Slot | Character | Status | Source |
|------|-----------|--------|--------|
| 0    | Sonic     | ✓ Base | S2 vanilla |
| 1    | Tails     | ✓ Base | S2 vanilla |
| 2    | Knuckles  | ⏳ Next | giovannidotgen/Sonic-2-with-Knuckles (non-comm) |
| 3    | Amy       | ⏳ Soon | GameBanana Sonic 2 Amy mod (E-122-Psi et al) |
| 4    | Mighty    | ⏳ TBD | Sonic 2 Megamix (Mighty port) |
| 5    | Shadow    | ⏳ TBD | Sonic 2 Megamix (Shadow port) |

### Notes
- **Overlap allowed**: Both P1 and P2 can pick the same character.
- **Input**: P1 = Start (cycles Sonic ↔ Tails). Temp implementation; GBA L+R will replace this.
- **Licenses**: All sources non-commercial, educational use. Will credit each author.

## How it works

1. **Character select**: Press **Start** to cycle P1 character (Sonic ↔ Tails).
   - Character switches at next level load (respawns current player).
   - P2 defaults to Tails; GBA input will control both independently later.
2. **Character data**: Each character inherits vanilla S2 physics, sprites, animations.
3. **Persistence**: Character choice persists per level (reset on level end).
4. **GBA future**: Sonic Advance 2 on GBA will act as picker UI, sending L+R input over serial link (via Pi, replaces Start button).

## Architecture

```
overlay/
├── sonic/
│   └── sonic.asm              Character select + input handler
├── characters/
│   ├── sonic_data.asm         Sonic object/physics
│   ├── tails_data.asm         Tails object/physics
│   ├── knuckles_data.asm      Knuckles (to be ported)
│   └── [others]
└── [level patches as needed]
```

## Build

```bash
./build.sh
# → rom/sonic2-heroes.bin
```

## Credits

- **Sonic Retro**: s2disasm, community ports
- Character ports: [to be filled as we integrate]
