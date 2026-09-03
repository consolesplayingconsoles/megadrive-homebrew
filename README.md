# Mega Drive Homebrew

Mega Drive ROMs for the Mega Drive node: from-scratch homebrew, ROM hacks of
existing games, and the tooling that supports them. Everything that lands on the
SD card is a ROM, named descriptively so the file says what it is.

## Layout

```
games/    from-scratch homebrew (SGDK)
mods/     ROM hacks of existing games (each owns its base + build)
tools/    shared tooling / infrastructure
```

- **games/** — [`room/`](games/room), a walkable room built with SGDK.
- **mods/** — [`sonic1/`](mods/sonic1), Sonic 1 ROM hacks over a shared
  disassembly. First hack: **Random Green Hill** (endless, seed-randomised Green
  Hill with infinite lives and a drop-a-badnik double jump).
- **tools/** — [`datalink/`](tools/datalink), the **data channel**: the console's
  controller port repurposed as a parallel data bus so a Pico can stream data into
  a running ROM. This is the transport the homebrew builds on.

## Building

**SGDK projects (games/, tools/)** — via the SGDK Docker image, no local
toolchain. `build.sh` resolves a project by name across `games/` and `tools/`:

```
./build.sh            # default: tools/datalink -> out/cpc-player.bin
./build.sh room       # games/room            -> out/room.bin
```

It starts Colima if the Docker daemon is down, runs the build, and stamps the
descriptive copy (SGDK always emits `out/rom.bin`). Build under this repo path;
Docker file sharing does not reach the system temp directory.

**ROM hacks (mods/)** are not SGDK — each mod has its own `build.sh` that copies
its game's pristine disassembly, overlays the mod's edited files, and assembles.
See [mods/sonic1](mods/sonic1) for the pattern (and `brew install lua`, which
those builds need).

## More

Each subproject documents itself: [games/room](games/room),
[mods/sonic1](mods/sonic1), [tools/datalink](tools/datalink).
