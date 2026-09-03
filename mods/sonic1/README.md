# Sonic 1 mods

ROM hacks of *Sonic the Hedgehog* (Mega Drive), built over **one shared
disassembly**. Each mod stores only its edited files and never touches the base,
so mods stay small and independent and the disassembly exists once.

```
sonic1/
├── s1disasm/            pristine base — the sonicretro/s1disasm "AS" branch (its own git repo)
└── <mod>/               one directory per mod
    ├── overlay/         the mod's edited disassembly files, mirroring the s1disasm tree
    ├── build.sh         copy base -> dist/, apply overlay, assemble -> rom/
    ├── dist/            disposable build tree, the whole disasm copy (gitignored)
    └── rom/             just the built ROM, easy to grab (gitignored — it's full Sonic 1)
```

Nothing Sega-owned is committed: the built ROM lives in `rom/`, the disasm copy and
any extracted level data stay in `dist/`, and both are gitignored. The generator
reads the real layouts straight from the base rather than keeping copies.

## Base

`s1disasm/` is a **git submodule** of the fork
[consolesplayingconsoles/s1disasm](https://github.com/consolesplayingconsoles/s1disasm)
pinned to its `AS` branch (a fork of sonicretro/s1disasm; forked so the base
commit is pinned and any base fixes are ours to carry). After a fresh checkout,
`git submodule update --init` populates it. It ships the AS assembler for every
platform in `build_tools/`, so the only host dependency is **lua**
(`brew install lua`). Pristine, it assembles byte-perfect Sonic 1 REV01
(`cd s1disasm && lua build.lua`) — a good sanity check before blaming a mod.
**Never edit files in `s1disasm/` directly**; edits live in a mod's `overlay/`.

## How a mod builds

`build.sh` does, into a throwaway `dist/`:

1. `rsync` the pristine `../s1disasm` into `dist/` (minus its `.git`).
2. Copy `overlay/.` over it — the mod's edited files win.
3. Run any generators (e.g. Random Green Hill emits level data into `dist/levels/`).
4. `cd dist && lua build.lua`, then copy the ROM into `rom/`.

Because every build starts from a fresh pristine copy, mods never drift and two
mods can't collide.

## Add a new mod

1. `mkdir <mod>/overlay` and copy `build.sh` from an existing mod as a starting point.
2. Edit the disassembly to prototype: work in a scratch copy of `s1disasm`, or edit
   in `dist/` after a build. Once happy, copy each **changed** file into
   `overlay/`, preserving its path (e.g. `overlay/_incObj/01 Sonic.asm`).
   Keep the overlay to genuinely-edited source only — build-generated files
   (`levels/*.bin`, patched `objpos/*.bin`, `s1built.bin`) are produced by the
   script, not stored.
3. Build with `./<mod>/build.sh`.

Tip to capture an overlay from a working `dist/`: `git -C dist status` (the base
is a git repo, so it lists exactly what you changed) — copy those paths into
`overlay/`.

## Mods

### sonic-infinite-jump
Vanilla Sonic 1, except a jump press in mid-air relaunches Sonic upward, any
number of times. One-file overlay (`_incObj/01 Sonic.asm`), no generator.
`./sonic-infinite-jump/build.sh` → `sonic-infinite-jump.bin`.

### random-green-hill
Endless, seed-randomised Green Hill Act 1: finishing the act reloads it with a
fresh layout forever (Groundhog Day), 99 frozen lives, no act number, a ~20%
longer level, and a double jump (tap jump in mid-air to relaunch — the same
`Sonic_AirJump` as sonic-infinite-jump). Layouts are permuted from all three real
Green Hill acts by `generate_level.py`; 32 variants are baked in and the console's
RNG picks one per run. `./random-green-hill/build.sh` → `sonic-random-green-hill.bin`.
