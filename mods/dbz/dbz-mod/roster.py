#!/usr/bin/env python3
"""Roster mod kit: dump the fighter roster to JSON, and build a patched ROM.

    roster.py dump  <rom> <roster.json>
    roster.py build <base-rom> <roster.json> <out.md>

Characters are described entirely in the JSON. Adding one is adding an entry:
the builder resizes and, when a table outgrows its original slot, relocates it
into free ROM space, repoints the code that reads it, widens the select-screen
cursor bounds and fixes the header checksum.

Assets are reused: `assets_from` names the stock fighter whose animation record
a new fighter borrows, so a new entry costs no art.
"""
import os, sys

# The disassembly is a submodule: facts about the stock game live there, and
# this file only says what it changes. DBZ_DISASM overrides the location.
_here = os.path.dirname(os.path.abspath(__file__))
DISASM = None
for _c in (os.environ.get('DBZ_DISASM'),
           os.path.join(_here, '..', 'dbzbr-disasm'),
           os.path.join(_here, '..', '..', '..', '..', 'dbzbr-disasm')):
    if _c and os.path.isdir(os.path.join(_c, 'tools')):
        DISASM = os.path.abspath(_c)
        sys.path.insert(0, os.path.join(DISASM, 'tools'))
        break
if DISASM is None:
    raise SystemExit('cannot find the dbzbr-disasm submodule; set DBZ_DISASM')

import facts
from facts import rd16, rds16, follow, fix_checksum
import sys, json, struct, hashlib
from text import FONT

MOVES_PER_CHAR = facts.MOVES_PER_CHAR
sys.path.insert(0, 'tools')
from text import FONT

# ---- the roster's fixed points in the stock ROM --------------------------
NAME_PTRS   = 0xA038    # N self-relative words -> names
NAME_END    = 0xA0EA    # names run up to here
REC_PTRS    = 0xA0EA    # N self-relative words -> per-character records
REC_END     = 0xA100
MOVESET     = 0xA9A2    # 18 bytes per fighter: 9 (move index, command) pairs
MOVESET_END = 0xAA68
MOVE_PTRS   = 0xA150    # 74 self-relative words -> move names
MOVE_COUNT  = 74
NAME2_PTRS  = 0x3A752   # second copy of the names, for the other screen
NAME2_END   = 0x3A812

LEA_NAME   = [0x9156]           # lea NAME_PTRS(pc), a0
LEA_REC    = [0x9820]
LEA_MOVES  = [0x91EE, 0x99C0]
LEA_NAME2  = [0x397A4, 0x397CA]
BOUND_BYTES = [0x9A93, 0x9AA1]  # both hold the last fighter index

STOCK_COUNT = 11










# Big free runs, used for blocks that a trampoline can reach from anywhere.
FAR_ARENA = [(0x1B7A0E, 0x1C0000), (0x07C624, 0x080000), (0x1C5159, 0x1C8000)]
REACH = 0x7F00          # keep clear of the signed-word limit

ENC = {}
for tile, ch in FONT.items():
    if ch and ch not in ENC:
        ENC[ch] = tile
DEFAULT_ATTR = 0x1000            # tilemap attribute bits carried by a plain glyph


def common_attr(rom, ptrs, n):
    """The attribute bits most name glyphs use in this ROM (JP differs from EU)."""
    seen = {}
    for i in range(n):
        a = ptrs + 2 * i + rds16(rom, ptrs + 2 * i)
        while True:
            w = rd16(rom, a)
            if w == 0xFFFF:
                break
            seen[w & ~0x7FF] = seen.get(w & ~0x7FF, 0) + 1
            a += 2
    return max(seen, key=seen.get) if seen else DEFAULT_ATTR




def read_name(rom, a, attr=DEFAULT_ATTR):
    """Glyphs the font knows become letters. Anything else becomes an escape:
    {XXX} for an unmapped tile carrying the usual attributes, {XXXX} for a whole
    word whose attributes differ. Either way a name survives a round trip."""
    out = []
    while True:
        w = rd16(rom, a)
        if w == 0xFFFF:
            return ''.join(out)
        t = w & 0x7FF
        c = FONT.get(t)
        if (w & ~0x7FF) != attr:
            out.append('{%04X}' % w)
        else:
            out.append(c if c else '{%03X}' % t)
        a += 2


def encode_name(s, attr=DEFAULT_ATTR):
    out, i = bytearray(), 0
    while i < len(s):
        if s[i] == '{' and s[i + 5:i + 6] == '}':
            w = int(s[i + 1:i + 5], 16); i += 6
        elif s[i] == '{' and s[i + 4:i + 5] == '}':
            w = attr | int(s[i + 1:i + 4], 16); i += 5
        else:
            t = ENC.get(s[i])
            if t is None:
                raise SystemExit('cannot encode %r in %r: glyph unknown' % (s[i], s))
            w = attr | t; i += 1
        out += struct.pack('>H', w)
    out += b'\xff\xff'
    return bytes(out)


def move_name(rom, L, idx):
    e = L['MOVE_PTRS'] + 2 * idx
    t = e + rds16(rom, e)
    return read_name(rom, t + 2, common_attr(rom, e, 1)), rd16(rom, t) & 0x7FF




def dump(rom_path, out_path):
    rom = open(rom_path, 'rb').read()
    L = facts.layout(rom)
    n = L['n']
    name_ptrs, name2_ptrs = L['NAME_PTRS'], L['NAME2_PTRS']
    rec_ptrs, moveset = L['REC_PTRS'], L['MOVESET']
    attr = common_attr(rom, name_ptrs, n)
    attr2 = common_attr(rom, name2_ptrs, n)
    recs, chars = {}, []
    for i in range(n):
        pn = name_ptrs + 2 * i
        name = read_name(rom, pn + rds16(rom, pn), attr)
        pr = rec_ptrs + 2 * i
        rec = pr + rds16(rom, pr)
        base = recs.setdefault(rec, i)
        row = rom[moveset + 18 * i: moveset + 18 * (i + 1)]
        p2 = name2_ptrs + 2 * i
        chars.append({
            'name': name,
            'name_short': read_name(rom, p2 + rds16(rom, p2), attr2),
            'assets_from': base,
            'moves': [[row[2 * j], row[2 * j + 1]] for j in range(MOVES_PER_CHAR)],
        })
    doc = {
        'base_rom_sha1': hashlib.sha1(rom).hexdigest(),
        'name_attr': attr, 'name_short_attr': attr2,
        'move_names': [dict(zip(('name', 'cost'), move_name(rom, L, i)))
                       for i in range(L['MOVE_COUNT'])],
        'characters': chars,
    }
    json.dump(doc, open(out_path, 'w'), indent=1)
    print('%d characters -> %s' % (len(chars), out_path))


# ---- build ---------------------------------------------------------------
def scan_gaps(rom, lo, hi, minrun=8):
    """Runs of $00/$FF filler, usable for small blocks and trampolines."""
    out, run, start = [], 1, lo
    for i in range(lo + 1, hi + 1):
        if i < hi and rom[i] == rom[i - 1] and rom[i] in (0x00, 0xFF):
            run += 1
        else:
            if run >= minrun and rom[i - 1] in (0x00, 0xFF):
                out.append([start, i])
            start, run = i, 1
    return out


def traced_bytes(rom_len):
    """Instruction extents from build/trace.json, so gaps never eat real code."""
    try:
        tr = json.load(open('build/trace.json'))
    except (IOError, ValueError):
        return []
    return sorted(tr['starts'])


class Space:
    """Places blocks, preferring the slot a block already lives in.

    Three tiers, because the 68000 addressing the engine uses is short-reach:
    a slot it still fits in; a nearby gap, for anything referenced by a
    self-relative word or a `lea d16(pc)`; or the far arena, reachable only
    through a trampoline that re-reads the address as an absolute long.
    """
    def __init__(self, rom):
        code = traced_bytes(len(rom))
        self.gaps = []
        if code is None:
            print('  note: no trace in the disassembly, so filler gaps are off.'
                  '\n        Regenerate it there (tools/trace.py) to get them back.')
        else:
            import bisect
            for s0, e0 in (scan_gaps(rom, 0x2000, 0x12000) +
                           scan_gaps(rom, 0x32000, 0x42000)):
                i = bisect.bisect_left(code, s0)   # drop anything holding code
                if i < len(code) and code[i] < e0:
                    continue
                self.gaps.append([s0, e0])
        self.reclaimed = []                      # slots we emptied ourselves
        self.far = [list(r) for r in FAR_ARENA]
        self.moved = []

    @property
    def near(self):
        return self.reclaimed + self.gaps        # provably free first

    def free_slot(self, start, end):
        self.reclaimed.append([start, end])

    def _take(self, pool, size, near_to=None):
        for r in pool:
            s, e = r
            a = s + (s & 1)
            if e - a < size:
                continue
            if near_to is not None and abs(a - near_to) > REACH:
                continue
            r[0] = a + size
            return a
        return None

    def place(self, rom, blob, slot, slot_end, what, near_to=None):
        if len(blob) <= slot_end - slot:
            rom[slot:slot + len(blob)] = blob
            return slot, False
        self.free_slot(slot, slot_end)
        at = self._take(self.near, len(blob), near_to)
        far = False
        if at is None:
            at = self._take(self.far, len(blob))
            far = True
        if at is None:
            raise SystemExit('no room for %s (%d bytes)' % (what, len(blob)))
        rom[at:at + len(blob)] = blob
        self.moved.append((what, slot, at, len(blob), far))
        return at, far

    def trampoline(self, rom, site, reg, target, what):
        """Replace `lea d16(pc),aN` with `bsr.w stub`; the stub does the lea
        as an absolute long, which reaches anywhere in the ROM."""
        at = self._take(self.near, 8, near_to=site)
        if at is None:
            raise SystemExit('no room for a trampoline near %06X (%s)' % (site, what))
        struct.pack_into('>H', rom, at, 0x41F9 | (reg << 9))   # lea xxx.l, aN
        struct.pack_into('>I', rom, at + 2, target)
        struct.pack_into('>H', rom, at + 6, 0x4E75)            # rts
        d = at - (site + 2)
        if not -0x8000 <= d < 0x8000:
            raise SystemExit('trampoline for %06X out of reach' % site)
        struct.pack_into('>H', rom, site, 0x6100)              # bsr.w
        struct.pack_into('>h', rom, site + 2, d)


def stub_of(rom, site):
    """If this site is already a trampoline, the stub it jumps to."""
    if rd16(rom, site) != 0x6100:
        return None
    stub = site + 2 + rds16(rom, site + 2)
    return stub if (rd16(rom, stub) & 0xF1FF) == 0x41F9 else None


def lea_reg(rom, site):
    """Destination register, whether the site is still a lea or a trampoline."""
    stub = stub_of(rom, site)
    op = rd16(rom, stub if stub is not None else site)
    if (op & 0xF1FF) not in (0x41FA, 0x41F9):
        raise SystemExit('%06X is not a lea site' % site)
    return (op >> 9) & 7


def point_at(space, rom, site, target, what):
    """Repoint one site: in place when the target is in reach, otherwise through
    a trampoline. An existing stub is reused rather than leaked."""
    stub = stub_of(rom, site)
    if stub is not None:
        struct.pack_into('>I', rom, stub + 2, target)
        return
    d = target - (site + 2)
    if -0x8000 <= d < 0x8000:
        struct.pack_into('>h', rom, site + 2, d)
    else:
        space.trampoline(rom, site, lea_reg(rom, site), target, what)


def selfrel(table_addr, targets):
    return b''.join(struct.pack('>h', t - (table_addr + 2 * i))
                    for i, t in enumerate(targets))


def build(base_path, roster_path, out_path):
    rom = bytearray(open(base_path, 'rb').read())
    doc = json.load(open(roster_path))
    chars = doc['characters']
    n = len(chars)
    if n < 1 or n > 128:
        raise SystemExit('roster size %d out of range' % n)
    for c in chars:
        if len(c['moves']) != MOVES_PER_CHAR:
            raise SystemExit('%s: needs exactly %d moves' % (c['name'], MOVES_PER_CHAR))
        for m, cmd in c['moves']:
            if not 0 <= m < 0x100:
                raise SystemExit('%s: move index %d out of range' % (c['name'], m))

    src = bytes(rom)
    L = facts.layout(src)
    stock = L['n']
    rec_of = L['recs']        # animation records stay put; a new fighter borrows one
    for c in chars:
        if not 0 <= c['assets_from'] < stock:
            raise SystemExit('%s: assets_from must name a stock fighter' % c['name'])
    space = Space(src)

    def name_block(where, cap, what, key='name', attr=DEFAULT_ATTR):
        blobs = [encode_name(c.get(key) or c['name'], attr) for c in chars]
        table_len = 2 * n
        off, body = table_len, b''
        targets = []
        for b in blobs:
            targets.append(off); body += b; off += len(b)
        # targets are relative to the block start, fixed up once placed
        def assemble(at):
            return selfrel(at, [at + t for t in targets]) + body
        probe = assemble(where)
        at, _ = space.place(rom, probe, where, cap, what)
        if at != where:
            rom[at:at + len(probe)] = assemble(at)
        return at

    attr = doc.get('name_attr', common_attr(src, L['NAME_PTRS'], stock))
    attr2 = doc.get('name_short_attr', common_attr(src, L['NAME2_PTRS'], stock))
    a_names = name_block(L['NAME_PTRS'], L['NAME_END'], 'name table', 'name', attr)
    a_names2 = name_block(L['NAME2_PTRS'], L['NAME2_END'], 'second name table',
                          'name_short', attr2)

    recs = [rec_of[c['assets_from']] for c in chars]
    probe = selfrel(L['REC_PTRS'], recs)
    # entries are self-relative, so this table has to stay near the records
    a_recs, far = space.place(rom, probe, L['REC_PTRS'], L['REC_END'], 'record table',
                              near_to=recs[0])
    if far:
        raise SystemExit('record table could not stay within reach of its records')
    if a_recs != REC_PTRS:
        rom[a_recs:a_recs + len(probe)] = selfrel(a_recs, recs)

    ms = bytearray()
    for c in chars:
        for m, cmd in c['moves']:
            ms += bytes((m & 0xFF, cmd & 0xFF))
    a_moves, _ = space.place(rom, bytes(ms), L['MOVESET'], L['MOVESET_END'], 'move-set table')

    for s in L['LEA_NAME']:  point_at(space, rom, s, a_names, 'name table')
    for s in L['LEA_NAME2']: point_at(space, rom, s, a_names2, 'second name table')
    for s in L['LEA_REC']:   point_at(space, rom, s, a_recs, 'record table')
    for s in L['LEA_MOVES']: point_at(space, rom, s, a_moves, 'move-set table')
    for b in L['BOUND_BYTES']:
        rom[b] = n - 1

    # the boot code sums $000200..end and hangs at $000506 on mismatch
    total = fix_checksum(rom)

    open(out_path, 'wb').write(rom)
    for what, was, now, size, far in space.moved:
        print('  relocated %-18s %06X -> %06X (%d bytes)%s'
              % (what, was, now, size, ', via trampoline' if far else ''))
    print('%d characters, checksum %04X -> %s' % (n, total, out_path))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == 'dump':
        dump(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        raise SystemExit(__doc__)
