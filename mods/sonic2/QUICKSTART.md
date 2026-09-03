# Sonic 2 Mods — Quick Start

## Setup (one-time)

The full `sonic2/` structure is already initialized:

```
sonic2/
├── s2disasm/        Git submodule (pristine disassembly, never edit)
├── vanilla/         Test mod (builds vanilla Sonic 2)
├── BUILD_TEMPLATE.sh Template for new mods
└── README.md        Full architecture docs
```

Verify the build system works:
```bash
cd nodes/local/megadrive/homebrew/mods/sonic2/vanilla
./build.sh
# → rom/sonic2-vanilla.bin (1.0 MB)
```

## Add a new mod

1. **Clone the template:**
   ```bash
   mkdir -p my-mod/overlay
   cp BUILD_TEMPLATE.sh my-mod/build.sh
   chmod +x my-mod/build.sh
   ```

2. **Prototype edits.** Edit in `dist/` after a test build, then copy changed files to `overlay/`:
   ```bash
   ./my-mod/build.sh
   # ... edit files in dist/ to test ...
   # Copy changed files back:
   git -C my-mod/dist status  # Shows what you changed
   cp my-mod/dist/sonic/sonic.asm my-mod/overlay/sonic/sonic.asm
   ```

3. **Update the build script** if needed (generators, special args, ROM name).

4. **Test the build:**
   ```bash
   ./my-mod/build.sh
   # → my-mod/rom/sonic2-mod.bin
   ```

## Build System

- **`rsync`** copies the pristine `s2disasm/` → `dist/` (fresh each build).
- **`overlay/`** overlays your edited files on top.
- **Generators** (optional) create runtime data in `dist/`.
- **`lua build.lua`** assembles into `s2built.bin`.
- **ROM** copied to `rom/` (git-ignored).

Both `dist/` and `rom/` are `.gitignored` — only commit `overlay/` and `build.sh`.

## Dev Workflow

For rapid prototyping:

1. Run a build: `./my-mod/build.sh`
2. Edit files directly in `my-mod/dist/`
3. Re-run: `./my-mod/build.sh` (overwrites `dist/`, so **save changes to `overlay/` before rebuilding**)
4. Once happy, copy edited files from `dist/` to `overlay/`, mirroring the path.

## Partial Source Changes

To build from **partial source** (not all files), only include edited files in `overlay/`:

- Original file: `s2disasm/sonic/sonic.asm`
- Edited copy in overlay: `overlay/sonic/sonic.asm`
- Unmodified files: skip (they come from `s2disasm/`)

The build merges `s2disasm/ + overlay/` → `dist/`, so missing files are supplied by the base.

## Troubleshooting

**"build.lua not found"**: Verify `s2disasm/` is populated.
```bash
git submodule update --init --recursive
```

**ROM won't build**: Verify `lua` is installed (`brew install lua`).

**Changes not appearing in ROM**: Confirm files are in `overlay/` with correct paths.
```bash
git -C dist status  # Shows exactly what changed
```
