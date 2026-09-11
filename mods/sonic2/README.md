# Sonic 2 mods

ROM hacks of *Sonic the Hedgehog 2* (Mega Drive), built over **one shared
disassembly**. Each mod stores only its edited files and never touches the base,
so mods stay small and independent and the disassembly exists once.

```
sonic2/
├── s2disasm/            pristine base — the sonicretro/s2disasm repo (its own git repo)
└── <mod>/               one directory per mod
    ├── overlay/         the mod's edited disassembly files, mirroring the s2disasm tree
    ├── build.sh         copy base -> dist/, apply overlay, assemble -> rom/
    ├── dist/            disposable build tree, the whole disasm copy (gitignored)
    └── rom/             just the built ROM, easy to grab (gitignored — it's full Sonic 2)
```

Nothing Sega-owned is committed: the built ROM lives in `rom/`, the disasm copy and
any extracted level data stay in `dist/`, and both are gitignored. The generator
reads the real layouts straight from the base rather than keeping copies.

## Base

`s2disasm/` is a **git submodule** of [consolesplayingconsoles/s2disasm](https://github.com/consolesplayingconsoles/s2disasm),
pinned so the base commit is stable and any base fixes are ours to carry. After a fresh checkout,
`git submodule update --init` populates it. It ships the AS assembler for every
platform in `build_tools/`, so the only host dependency is **lua**
(`brew install lua`). Pristine, it assembles byte-perfect Sonic 2 REV01
(`cd s2disasm && lua build.lua`) — a good sanity check before blaming a mod.
**Never edit files in `s2disasm/` directly**; edits live in a mod's `overlay/`.

## How a mod builds

`build.sh` does, into a throwaway `dist/`:

1. `rsync` the pristine `../s2disasm` into `dist/` (minus its `.git`).
2. Copy `overlay/.` over it — the mod's edited files win.
3. Run any generators (if applicable).
4. `cd dist && lua build.lua`, then copy the ROM into `rom/`.

Because every build starts from a fresh pristine copy, mods never drift and two
mods can't collide.

## Add a new mod

1. `mkdir <mod>/overlay` and copy `build.sh` from an existing mod as a starting point.
2. Edit the disassembly to prototype: work in a scratch copy of `s2disasm`, or edit
   in `dist/` after a build. Once happy, copy each **changed** file into
   `overlay/`, preserving its path (e.g. `overlay/sonic/sonic.asm`).
   Keep the overlay to genuinely-edited source only — build-generated files
   are produced by the script, not stored.
3. Build with `./<mod>/build.sh`.

Tip to capture an overlay from a working `dist/`: `git -C dist status` (the base
is a git repo, so it lists exactly what you changed) — copy those paths into
`overlay/`.

## Planned

- **Light-gun mod** — shoot anything on screen: Tails endlessly (he just respawns),
  plus enemies, monitors, and Sonic himself. Input is a **Konami Justifier**, a
  native Mega Drive light gun read via the VDP H/V-counter latch, so it needs a CRT.
  Build order: first a throwaway crosshair test ROM to prove aim tracking and
  calibration standalone, then wire the hit-test and each object's existing
  death/explode routine into a mod here. The damage is the easy part; the gun input
  is the real work.
