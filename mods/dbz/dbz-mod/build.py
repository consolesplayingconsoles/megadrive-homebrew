#!/usr/bin/env python3
"""dbz-mod build: colour picking, End of Z Goku, and Goku Black.

Plays as Goku (borrows his animation record), with his own palette. This is the
roster kit's first real outing, and it also has to fill in the per-fighter
tables that only matter once a twelfth fighter exists:

    grid cursor bounds      $00D30B / $00D311, $0A -> $0B
    random-pick bounds      $078387 / $07839B, likewise
    portrait slot table     $03C30E index 11 reads $FF (unset)
    portrait art tables     $03A448 / $03A4AA index 11 is not a real entry
    fighter palette         slot 11 exists at $0801C4 and is ours to write

Already fine without us: the enable table at $080000 has a non-zero entry 11,
so the cursor will not skip the slot.

    build.py <base-rom>

Always writes the same two files, so a build never invents a new name:

    rom/dbz-cpc.md    the playable ROM
    rom/dbz-cpc.ips   the same changes as a patch, which is what gets shared
"""
import os, sys, json, struct, subprocess, tempfile

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _here)
for _c in (os.environ.get('DBZ_DISASM'), os.path.join(_here, '..', 'dbzbr-disasm')):
    if _c and os.path.isdir(os.path.join(_c, 'tools')):
        DISASM = os.path.abspath(_c)
        sys.path.insert(0, os.path.join(DISASM, 'tools'))
        break
import facts
import roster as rosterkit

NEW = 11                       # the slot the game left empty

# The English patch left some things behind. Names are ours to fix outright,
# since the roster kit rebuilds and repoints the name tables, so a longer name
# is no harder than a shorter one.
NAME_FIXES = {
    'LIKUM': 'RECOOME', 'REKUM': 'RECOOME',
    'KURILIN': 'KRILLIN',
    'GINIOU': 'GINYU',
    'FREEZER': 'FRIEZA', 'FREEZA': 'FRIEZA',
}

# A label the patch blanked rather than translated: the French ROM stores
# ORDINATEUR here as glyph words, and the English one wrote three tiles from a
# bank our font does not cover. The field is nine glyphs before its $FFFF
# terminator, so a replacement has to fit that.
TEXT_FIXES = {0x03C46A: 'CPU'}

# Replace a word everywhere it appears as text and still fits its field. Move
# names carry the fighters' names too, so the roster and the move list should
# agree. Anything that does not fit is reported rather than silently skipped.
WORD_FIXES = {'REKUM': 'RECOOME', 'KURILIN': 'KRILLIN', 'FREEZA': 'FRIEZA'}
PORTRAIT_ART_P1 = 0x03A448
PORTRAIT_ART_P2 = 0x03A4AA

# Black's colours, in the roles the silhouette probe established for Goku.
# The gi ramp covers top and pants together; the trim covers boots, belt,
# undershirt and bracelets together, so the white boots and the red sash cannot
# both be had. Boots win, being the larger shape, and the sash goes with them.
GI    = [(0, 0, 0), (36, 36, 36), (73, 73, 73), (109, 109, 109)]
TRIM  = [(109, 109, 109), (219, 219, 219)]
HAIR  = {'hair_1': (255, 146, 182), 'hair_2': (219, 73, 146)}   # rosé


def add_character(base, tmp_json, replace=None):
    """Dump the roster and put Goku Black in it.

    `replace` overwrites an existing fighter instead of adding a twelfth. That
    is the honest test of the data path: it uses only tables the game already
    has, so if Black plays correctly in someone else's slot, everything except
    the select screen works, and the twelfth slot is purely a UI problem."""
    subprocess.run([sys.executable, os.path.join(_here, 'roster.py'),
                    'dump', base, tmp_json], check=True, stdout=subprocess.DEVNULL)
    doc = json.load(open(tmp_json))
    goku = doc['characters'][0]
    black = {
        'name': 'GOKU BLACK',
        'name_short': 'BLACK',
        'assets_from': 0,                   # Goku's animations
        'moves': [list(m) for m in goku['moves']],
    }
    if replace is None:
        doc['characters'].append(black)
    else:
        doc['characters'][replace] = black
    for c in doc['characters']:
        for key in ('name', 'name_short'):
            fixed = NAME_FIXES.get(c[key].strip())
            if fixed:
                c[key] = fixed
    json.dump(doc, open(tmp_json, 'w'), indent=1)
    return len(doc['characters'])


def fix_names_only(base, tmp_json):
    """The release build: correct the roster names, add no one."""
    subprocess.run([sys.executable, os.path.join(_here, 'roster.py'),
                    'dump', base, tmp_json], check=True, stdout=subprocess.DEVNULL)
    doc = json.load(open(tmp_json))
    for c in doc['characters']:
        for key in ('name', 'name_short'):
            fixed = NAME_FIXES.get(c[key].strip())
            if fixed:
                c[key] = fixed
    json.dump(doc, open(tmp_json, 'w'), indent=1)
    return len(doc['characters'])


def paint(rom):
    """Give slot 11 its own palette, built from Goku's."""
    import patch as picker
    src = facts.FIGHTER_BANK_A
    pal = bytearray(rom[src:src + 32])                  # start from Goku's
    warm, cool = picker.costume_indices(rom, facts.FIGHTER_BANK_A,
                                        facts.FIGHTER_BANK_B, 0)
    picker.paint_ramps(rom, pal, warm, cool, GI, TRIM)
    for key, rgb in HAIR.items():
        struct.pack_into('>H', pal, 2 * facts.GOKU[key], picker.quantise(*rgb))
    dst = src + 32 * NEW
    rom[dst:dst + 32] = pal
    return warm, cool


def fix_words(rom):
    """Apply WORD_FIXES to every text field wide enough to take them."""
    import roster as rk
    from text import FONT
    done, skipped = 0, []
    a = 0
    while a < len(rom) - 1:
        w = struct.unpack_from('>H', rom, a)[0]
        if w != 0xFFFF:
            a += 2
            continue
        # walk back to the start of this run
        start = a
        while start >= 2 and FONT.get(struct.unpack_from('>H', rom, start - 2)[0] & 0x7FF):
            start -= 2
        width = (a - start) // 2
        if 2 < width < 40:
            text = ''.join(FONT.get(struct.unpack_from('>H', rom, start + 2 * i)[0] & 0x7FF, '?')
                           for i in range(width))
            for old, new in WORD_FIXES.items():
                if old in text:
                    cand = text.replace(old, new)
                    if len(cand.rstrip()) <= width and '?' not in text:
                        blob = rk.encode_name(cand.rstrip().ljust(width),
                                              struct.unpack_from('>H', rom, start)[0] & ~0x7FF)
                        rom[start:start + len(blob)] = blob
                        done += 1
                    else:
                        skipped.append((start, text.strip(), new))
        a += 2
    return done, skipped


def fix_text(rom):
    """Rewrite blanked labels in place, padding to the field's own width."""
    import roster as rk
    for addr, new in TEXT_FIXES.items():
        width = 0
        while struct.unpack_from('>H', rom, addr + 2 * width)[0] != 0xFFFF:
            width += 1
        if len(new) > width:
            raise SystemExit('%r does not fit the %d-glyph field at %06X'
                             % (new, width, addr))
        blob = rk.encode_name(new.ljust(width), 0x1000)
        rom[addr:addr + len(blob)] = blob
    return len(TEXT_FIXES)


def fill_tables(rom):
    """The entries a twelfth fighter needs and the stock ROM never had."""
    # the grid cursor: "cannot go right past the last" and "cannot go down off
    # the end". Patching only the first leaves the bottom row unreachable.
    for a, was, now in ((facts.SELECT_GRID_RIGHT, 0x0A, NEW),
                        (facts.SELECT_GRID_DOWN, 0x08, NEW - 2),
                        (facts.ROSTER_GRID_BOUNDS[0], 0x0A, NEW),
                        (facts.ROSTER_GRID_BOUNDS[1], 0x0A, NEW),
                        (facts.ROSTER_RANDOM_BOUNDS[0], 0x0A, NEW),
                        (facts.ROSTER_RANDOM_BOUNDS[1], 0x0A, NEW),
                        (facts.SELECT_CPU_MODULO, 0x0B, NEW + 1)):
        if rom[a] != was:
            raise SystemExit('%06X holds %02X, expected %02X' % (a, rom[a], was))
        rom[a] = now
    # portrait: borrow Goku's, both the palette slot and the art
    rom[facts.PORTRAIT_SLOT_TABLE + NEW] = rom[facts.PORTRAIT_SLOT_TABLE]
    for table in (PORTRAIT_ART_P1, PORTRAIT_ART_P2):
        goku_art = table + struct.unpack_from('>h', rom, table)[0]
        struct.pack_into('>h', rom, table + 2 * NEW, goku_art - (table + 2 * NEW))


def main(base, out, button='B', replace=None, black=False):
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as t:
        tmp_json = t.name
    import patch as picker
    n = add_character(base, tmp_json, replace) if black else fix_names_only(base, tmp_json)
    rosterkit.build(base, tmp_json, out)
    # the colour picker rides on top: button B swaps a fighter to bank B, and
    # bank B for Goku is End of Z rather than the stock mirror-match red
    picker.build(out, out, button=button, skin='eoz')
    rom = bytearray(open(out, 'rb').read())
    global NEW
    if replace is not None:
        NEW = replace                       # paint the slot he actually occupies
    fix_text(rom)
    done, skipped = fix_words(rom)
    print('  word fixes applied in %d fields' % done)
    for addr, text, new in skipped:
        print('     no room at %06X for %s in %r' % (addr, new, text))
    warm = cool = None
    if black:
        warm, cool = paint(rom)
        if replace is None:
            fill_tables(rom)
    total = facts.fix_checksum(rom)
    open(out, 'wb').write(rom)
    os.unlink(tmp_json)
    if black:
        print('  roster now %d fighters; slot %d painted (gi %s, trim %s)'
              % (n, NEW, warm, cool))
    else:
        print('  roster kept at %d fighters, names corrected' % n)
    print('  checksum %04X -> %s' % (total, out))


OUT_ROM = 'dbz-cpc.md'
OUT_IPS = 'dbz-cpc.ips'


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    rep = int(sys.argv[sys.argv.index('--replace') + 1]) if '--replace' in sys.argv else None
    base = sys.argv[1]
    romdir = os.path.join(_here, 'rom')
    os.makedirs(romdir, exist_ok=True)
    out = os.path.join(romdir, OUT_ROM)
    main(base, out, replace=rep, black='--black' in sys.argv or rep is not None)
    sys.path.insert(0, os.path.join(DISASM, 'tools'))
    from ips_make import make
    ips = os.path.join(romdir, OUT_IPS)
    open(ips, 'wb').write(make(open(base, 'rb').read(), open(out, 'rb').read()))
    print('  %s' % out)
    print('  %s' % ips)
