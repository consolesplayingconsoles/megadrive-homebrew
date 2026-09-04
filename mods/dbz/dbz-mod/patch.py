#!/usr/bin/env python3
"""Make the second colour set selectable on the character-select screen.

The game already stores two palettes per fighter: bank A at $080064, and bank B
at $0801E4 which it only ever uses when both players pick the same character.
This patch gives each player a variant byte, flips it with a button on the
select screen, and teaches the palette loader to honour it. No new art: every
fighter already has both colour sets.

    colours.py <base-rom> rom/<out.md> [--button A|B]

C is the confirm button on that screen (it starts the fight), so the toggle
defaults to A. Built ROMs belong in rom/, which is not tracked.

How it hooks in, all size-neutral so no code moves:

  $003FE2  the pad read ends by copying two words into ram_E666/ram_E668. The
           second copy (6 bytes) becomes `jsr hook` (6 bytes); the hook does
           that copy, then the button check. This routine is called wherever
           pads are read, the select screen included.
  $00D1E2  P1's `lea $080064.l,a0` (6 bytes) becomes `jsr pick_p1` (6 bytes).
  $00D208  P2's, likewise.

On a flip the hook calls the game's own palette reload, so the change applies
straight away rather than waiting for the next screen.
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
import struct

PAL_A, PAL_B = facts.FIGHTER_BANK_A, facts.FIGHTER_BANK_B
POR_A, POR_B = facts.PORTRAIT_BANK_A, facts.PORTRAIT_BANK_B
POR_SITES_P1 = facts.PORTRAIT_SITES['P1']
POR_SITES_P2 = facts.PORTRAIT_SITES['P2']
LEA_P1       = facts.FIGHTER_SITES['P1'][0]
LEA_P2       = facts.FIGHTER_SITES['P2'][0]
HOOK_SITE    = facts.PAD_READ_TAIL
PAD_P1, PAD_P2 = facts.PAD_P1, facts.PAD_P2
BUTTON       = facts.BUTTON
SELECT_MODE  = facts.SELECT_MODE
PORTRAIT_SUB = facts.PORTRAIT_RELOAD
MODE_VAR     = facts.MODE_VAR
EA00         = facts.EA00
FREE_ARENAS  = [(0x1B7A0E, 0x1C0000), (0x07C624, 0x080000), (0x1C5159, 0x1C8000)]


def find_free(rom, size):
    """A run of untouched $FF long enough for our stubs.

    Not a constant: once another mod in the same build relocates a table into
    the arena, that address is no longer free, and writing stubs over it
    corrupts the ROM in a way that looks like a mystery at boot."""
    for lo, hi in FREE_ARENAS:
        run = 0
        for a in range(lo, hi):
            run = run + 1 if rom[a] == 0xFF else 0
            if run >= size + 2:
                return (a - run + 1 + 1) & ~1
    raise SystemExit('no free run of %d bytes for the stubs' % size)

# Four bytes of work RAM: two variants, two previous-button states, just above
# the stack base. Boot clears them once and nothing clears them per match.
VAR_P1, VAR_P2, PREV_P1, PREV_P2 = 0xFFFE10, 0xFFFE11, 0xFFFE12, 0xFFFE13


def w(v):
    return v & 0xFFFF

PAL_A, PAL_B = 0x080064, 0x0801E4          # fighter palettes, 32 bytes each
POR_A, POR_B = 0x03F55A, 0x03F6BA          # portrait palettes, same shape


# The face buttons live in $E666 / $E668, NOT the odd bytes next to them:
# verified on hardware with a probe that flashed the screen while a button was
# seen. $E667 bit 7 is start. Bit 4 = B, 5 = C, 6 = A (the game tests bit 6 all
# over the place, which is confirm).
PAD_P1, PAD_P2 = 0xFFE666, 0xFFE668
CHANGED      = 0xFF8000      # ram_8000, the reload flag

# Four bytes of work RAM: two variants, two previous-button states.
# These live just above the stack pointer's base ($FFFE00), a region boot clears
# once and nothing clears per match: any routine zeroing it would kill the
# stack. The earlier choice inside the $FFE000 game-state block was a likely
# candidate for a between-screens wipe.
VAR_P1, VAR_P2, PREV_P1, PREV_P2 = 0xFFFE10, 0xFFFE11, 0xFFFE12, 0xFFFE13







def quantise(r, g, b):
    """A Mega Drive colour word: 0000 BBB0 GGG0 RRR0, three bits per channel."""
    q = lambda c: min(7, max(0, round(c * 7 / 255)))
    return (q(b) << 9) | (q(g) << 5) | (q(r) << 1)


def unpack_pal(rom, base, slot):
    a = base + 32 * slot
    return [struct.unpack_from('>H', rom, a + 2 * i)[0] for i in range(16)]


def channels(word):
    return ((word & 0x00E) >> 1, (word & 0x0E0) >> 5, (word & 0xE00) >> 9)


def costume_indices(rom, bank_a, bank_b, slot):
    """Which indices are costume, asked of the ROM rather than assumed.

    The game recolours a fighter when both players pick him, and the indices it
    touches are precisely his outfit. That differs per screen: on the fighter
    sprite the gi is 4/5/6, on the portrait it is 14/8 while 4/5/6 are his hair.
    Warm entries are the gi, cool ones the trim, each ordered dark to light.
    """
    a = unpack_pal(rom, bank_a, slot)
    b = unpack_pal(rom, bank_b, slot)
    diff = [i for i in range(16) if a[i] != b[i]]
    lum = lambda i: sum(channels(a[i]))
    warm = sorted((i for i in diff if channels(a[i])[0] >= channels(a[i])[2]), key=lum)
    cool = sorted((i for i in diff if channels(a[i])[0] < channels(a[i])[2]), key=lum)
    return warm, cool


def sample(ramp, t):
    """A colour t of the way along a ramp given as dark-to-light stops."""
    if len(ramp) == 1:
        return ramp[0]
    pos = t * (len(ramp) - 1)
    lo = min(int(pos), len(ramp) - 2)
    f = pos - lo
    return tuple(round(ramp[lo][c] + f * (ramp[lo + 1][c] - ramp[lo][c])) for c in range(3))


def paint_ramps(rom, pal_bytes, warm, cool, gi_ramp, trim_ramp):
    for indices, ramp in ((warm, gi_ramp), (cool, trim_ramp)):
        for k, i in enumerate(indices):
            t = k / (len(indices) - 1) if len(indices) > 1 else 0.0
            struct.pack_into('>H', pal_bytes, 2 * i, quantise(*sample(ramp, t)))
    return pal_bytes


def index_of(spec, key):
    """Recolours name their targets ('gi_mid'); the index map uses numbers."""
    return key if spec.get('by_number') else facts.GOKU[key]


def recolour(rom, name):
    """Write a recolour into bank B, for both the fighter and the portrait."""
    from palettes import RECOLOURS
    spec = RECOLOURS[name]
    idx = spec['fighter']
    portrait_slot = rom[facts.PORTRAIT_SLOT_TABLE + idx]
    hit = []
    for bank_a, bank_b, slot in ((PAL_A, PAL_B, idx),
                                 (POR_A, POR_B, portrait_slot)):
        src, dst = bank_a + 32 * slot, bank_b + 32 * slot
        pal = bytearray(rom[src:src + 32])             # start from the normal set
        if 'gi' in spec:
            warm, cool = costume_indices(rom, bank_a, bank_b, slot)
            paint_ramps(rom, pal, warm, cool, spec['gi'], spec['trim'])
            hit.append((warm, cool))
        for key, rgb in spec.get('colours', {}).items():
            struct.pack_into('>H', pal, 2 * index_of(spec, key), quantise(*rgb))
        rom[dst:dst + 32] = pal
    return idx, portrait_slot, hit


# Groups of palette indices, isolated one press at a time. Ordered by what we
# still need to identify. Everything not in the current group renders black, so
# each press is a white silhouette of exactly those indices: readable without
# distinguishing any colours, by anyone.
ISOLATE_GROUPS = [[12, 13], [1, 9, 15], [0, 7, 10], [2, 3, 14], [4, 5, 6], [8, 11]]


def FIGHTER_slot_bytes(rom, idx):
    """A fighter's normal 16-colour palette, the starting point for a recolour."""
    a = PAL_A + 32 * idx
    return bytes(rom[a:a + 32])


from palettes import TUNINGS


def build(base, out, button='A', force=False, probe=False, showpad=False,
          redscreen=False, padcolour=False, whichbyte=False, btnflash=False,
          modeprobe=False, skin=None, isolate=False, tune=None):
    rom = bytearray(open(base, 'rb').read())
    mask = BUTTON[button]
    cycle_len = len(TUNINGS[tune]) if tune else len(ISOLATE_GROUPS)
    at = find_free(rom, 0x400)

    def emit(blob):
        nonlocal at
        addr = at
        rom[at:at + len(blob)] = blob
        at += len(blob) + (len(blob) & 1)
        return addr

    def toggle(pad, var, prev):
        """d0 = pad; on a fresh press of the button, flip this player's variant.

        Deliberately does NOT reload palettes here. The select screen uses those
        CRAM slots for the portrait art, so reloading the fighter palette on
        this screen corrupts the portraits. The flip is picked up by the game's
        own palette load when the fight starts.
        """
        if (isolate or tune) and var == VAR_P1:
            # count 0..len(groups)-1 and wrap
            wrap = b'\x42\x38' + struct.pack('>H', w(var))            # clr.b var
            flip = (b'\x52\x38' + struct.pack('>H', w(var)) +         # addq.b #1,var
                    b'\x0C\x38' + struct.pack('>H', cycle_len) +
                    struct.pack('>H', w(var)) +                        # cmpi.b #n,var
                    b'\x65' + bytes((len(wrap),)) +                    # bcs over the wrap
                    wrap)
        else:
            flip = (b'\x0A\x38\x00\x01' + struct.pack('>H', w(var)))  # eori.b #1,var
        # Repaint the portraits at once, but ONLY on the select screen: this is
        # the game's own reload, and running it elsewhere is what produced the
        # corrupted palettes earlier. ram_EA00 is saved and put back.
        repaint = (b'\x34\x38' + struct.pack('>H', w(EA00)) +        # move.w EA00,d2
                   b'\x42\x78' + struct.pack('>H', w(EA00)) +        # clr.w EA00
                   b'\x4E\xB9' + struct.pack('>I', PORTRAIT_SUB) +   # jsr portrait reload
                   b'\x31\xC2' + struct.pack('>H', w(EA00)))         # move.w d2,EA00
        if isolate or tune:
            # repaint unconditionally: we are looking at the
            # fight, and waiting for the next natural palette load would make
            # each press invisible.
            flip += b'\x4E\xB9' + struct.pack('>I', facts.FIGHTER_RELOAD)
        else:
            flip += (b'\x0C\x78' + struct.pack('>H', SELECT_MODE) +
                     struct.pack('>H', w(MODE_VAR)) +                 # cmpi.w #mode,E6A4
                     b'\x66' + bytes((len(repaint),)) +               # bne past it
                     repaint)
        if probe:      # diagnostic: also paint a palette entry, visible at once
            flip += b'\x31\xFC\x00\x0E' + struct.pack('>H', w(0xFFE454))
        # bne's displacement is measured from the byte after the instruction,
        # which is where `flip` starts, so it is exactly len(flip).
        tail = b'\x4A\x01' + b'\x66' + bytes((len(flip),)) + flip     # tst.b d1 ; bne .done
        head = (b'\x10\x38' + struct.pack('>H', w(pad)) +            # move.b pad,d0
                b'\x02\x00' + struct.pack('>H', mask) +              # andi.b #mask,d0
                b'\x12\x38' + struct.pack('>H', w(prev)) +           # move.b prev,d1
                b'\x11\xC0' + struct.pack('>H', w(prev)))            # move.b d0,prev
        return head + b'\x67' + bytes((len(tail),)) + tail            # beq .done

    if modeprobe:
        # Two answers in one ROM.
        # 1. On a B press, call the portrait reload with NO mode gate. If the
        #    portrait flips instantly, the mechanism is fine and my gate was
        #    simply testing the wrong mode value.
        # 2. While B is held, flash a colour that says what ram_E6A4 actually
        #    is on this screen: $18 red, $1C green, $20 blue, $24 white,
        #    anything else magenta.
        press = (b'\x10\x38' + struct.pack('>H', w(0xFFE666)) +
                 b'\x02\x00\x00\x10' +
                 b'\x12\x38' + struct.pack('>H', w(PREV_P1)) +
                 b'\x11\xC0' + struct.pack('>H', w(PREV_P1)))
        act = (b'\x0A\x38\x00\x01' + struct.pack('>H', w(VAR_P1)) +
               b'\x34\x38' + struct.pack('>H', w(EA00)) +
               b'\x42\x78' + struct.pack('>H', w(EA00)) +
               b'\x4E\xB9' + struct.pack('>I', PORTRAIT_SUB) +
               b'\x31\xC2' + struct.pack('>H', w(EA00)))
        guard = b'\x4A\x01' + b'\x66' + bytes((len(act),)) + act
        toggle_part = press + b'\x67' + bytes((len(guard),)) + guard

        def modecase(val, colour):
            return (b'\x0C\x78' + struct.pack('>H', val) +
                    struct.pack('>H', w(MODE_VAR)) +
                    b'\x66\x04' + b'\x00\x41' + struct.pack('>H', colour))
        paint = (b'\x23\xFC\xC0\x00\x00\x00\x00\xC0\x00\x04' +
                 b'\x41\xF9\x00\xC0\x00\x00' +
                 b'\x34\x3C\x00\x3F' + b'\x30\x81' + b'\x51\xCA\xFF\xFC')
        show = (b'\x72\x00' +
                modecase(0x18, 0x000E) + modecase(0x1C, 0x00E0) +
                modecase(0x20, 0x0E00) + modecase(0x24, 0x0EEE) +
                b'\x4A\x41' + b'\x66\x04' + b'\x00\x41\x0E\x0E' +
                paint)
        held = (b'\x10\x38' + struct.pack('>H', w(0xFFE666)) +
                b'\x02\x00\x00\x10' +
                b'\x67' + bytes((len(show),)) + show)
        body = toggle_part + held
    elif btnflash:
        # Non-destructive probe: leave the game's own colours alone, and only
        # repaint the screen while a candidate byte shows a face button.
        # $E666 -> red, $E667 -> blue, $E6AE -> green, $E6AF -> white.
        # The game stays playable, so the select screen is reachable.
        def cand(addr, colour):
            return (b'\x10\x38' + struct.pack('>H', w(addr)) +
                    b'\x02\x00\x00\x70' +
                    b'\x67\x04' +
                    b'\x00\x41' + struct.pack('>H', colour))
        paint = (b'\x23\xFC\xC0\x00\x00\x00\x00\xC0\x00\x04' +
                 b'\x41\xF9\x00\xC0\x00\x00' +
                 b'\x34\x3C\x00\x3F' +
                 b'\x30\x81' +
                 b'\x51\xCA\xFF\xFC')
        body = (b'\x72\x00' +
                cand(0xFFE666, 0x000E) + cand(0xFFE667, 0x0E00) +
                cand(0xFFE6AE, 0x00E0) + cand(0xFFE6AF, 0x0EEE) +
                b'\x4A\x41' +                                  # tst.w d1
                b'\x67' + bytes((len(paint),)) +                # beq: leave colours alone
                paint)
    elif whichbyte:
        # Three candidate pad bytes, one colour each, so the tester can say
        # which byte actually carries the buttons:
        #   $E666 -> red, $E667 -> blue, $E6AE (raw, as the read routine
        #   stores it) -> green. Mask $70 is "any of the three face buttons".
        def cand(addr, colour):
            return (b'\x10\x38' + struct.pack('>H', w(addr)) +   # move.b addr,d0
                    b'\x02\x00\x00\x70' +                       # andi.b #$70,d0
                    b'\x67\x04' +                                 # beq over
                    b'\x00\x41' + struct.pack('>H', colour))      # ori.w #colour,d1
        body = (b'\x72\x00' +                                     # moveq #0,d1
                cand(0xFFE666, 0x000E) + cand(0xFFE667, 0x0E00) +
                cand(0xFFE6AE, 0x00E0) +
                b'\x23\xFC\xC0\x00\x00\x00\x00\xC0\x00\x04' +
                b'\x41\xF9\x00\xC0\x00\x00' +
                b'\x34\x3C\x00\x3F' +
                b'\x30\x81' +
                b'\x51\xCA\xFF\xFC')
    elif padcolour:
        # Paint the whole screen a colour chosen by which button is held, so the
        # tester reads the bit mapping straight off the screen:
        #   bit 4 -> blue, bit 5 -> green, bit 6 -> red, nothing held -> black.
        def bit(n, colour):
            return (b'\x08\x00' + struct.pack('>H', n) +      # btst #n,d0
                    b'\x67\x04' +                             # beq over the ori
                    b'\x00\x41' + struct.pack('>H', colour))  # ori.w #colour,d1
        body = (b'\x10\x38\xE6\x67' +                        # move.b $e667.w,d0
                b'\x72\x00' +                                 # moveq #0,d1
                bit(4, 0x0E00) + bit(5, 0x00E0) + bit(6, 0x000E) +
                b'\x23\xFC\xC0\x00\x00\x00\x00\xC0\x00\x04' +
                b'\x41\xF9\x00\xC0\x00\x00' +
                b'\x34\x3C\x00\x3F' +                        # move.w #63,d2
                b'\x30\x81' +                                 # move.w d1,(a0)
                b'\x51\xCA\xFF\xFC')                        # dbra d2,-4
    elif redscreen:
        # The bluntest possible test that a hook executes: repaint the whole
        # colour RAM red, every frame, unconditionally. Either the screen turns
        # red or this code never runs. No judgement call for the tester.
        body = (b'\x23\xFC\xC0\x00\x00\x00\x00\xC0\x00\x04' +   # move.l #$C0000000,VDP_CTRL
                b'\x41\xF9\x00\xC0\x00\x00' +                       # lea $C00000.l,a0
                b'\x32\x3C\x00\x3F' +                                 # move.w #63,d1
                b'\x30\xBC\x00\x0E' +                                 # move.w #$000E,(a0)
                b'\x51\xC9\xFF\xFA')                                  # dbra d1,-6
    elif showpad:
        # Diagnostic with no conditions at all: every frame, drive the VDP
        # backdrop colour from player 1's button nibble. If the backdrop never
        # changes, this hook is not running. If it changes as buttons are
        # pressed, it runs AND we learn which bit is which button.
        body = (b'\x10\x38\xE6\x67' +                              # move.b $e667.w,d0
                b'\xE8\x08' +                                        # lsr.b #4,d0
                b'\x02\x40\x00\x07' +                              # andi.w #7,d0
                b'\x00\x40\x87\x00' +                              # ori.w #$8700,d0
                b'\x33\xC0\x00\xC0\x00\x04')                     # move.w d0,$C00004.l
    else:
        body = toggle(PAD_P1, VAR_P1, PREV_P1) + toggle(PAD_P2, VAR_P2, PREV_P2)

    hook = emit(b'\x48\xE7\xFF\xFE' +                                # movem.l d0-d7/a0-a6,-(sp)
                b'\x31\xF8\xE6\xE2\xE6\x68' +                     # the copy we displaced
                body +
                b'\x4C\xDF\x7F\xFF' +                               # movem.l (sp)+,d0-d7/a0-a6
                b'\x4E\x75')                                         # rts

    def picker(var, bank_a=PAL_A, bank_b=PAL_B):
        """a0 = palette bank for this player."""
        if force:                      # diagnostic: always bank B, no button
            return b'\x41\xF9' + struct.pack('>I', bank_b) + b'\x4E\x75'
        return (b'\x41\xF9' + struct.pack('>I', bank_a) +            # lea bank_a.l,a0
                b'\x4A\x38' + struct.pack('>H', w(var)) +            # tst.b var
                b'\x67\x06' +                                        # beq .done
                b'\x41\xF9' + struct.pack('>I', bank_b) +            # lea bank_b.l,a0
                b'\x4E\x75')                                         # rts

    if isolate or tune:
        # A table of palettes and a picker that indexes it with the button
        # counter, so a choice can be made in game instead of guessed here.
        # Fighter palette only: the portrait sites hold their slot in d0 across
        # the call, so those are left alone.
        table = bytearray()
        if tune:
            from palettes import RECOLOURS
            spec = RECOLOURS[tune]
            base = FIGHTER_slot_bytes(rom, spec['fighter'])
            for trim in TUNINGS[tune]:
                pal = bytearray(base)
                for key, rgb in list(spec['colours'].items()) + list(trim.items()):
                    struct.pack_into('>H', pal, 2 * index_of(spec, key), quantise(*rgb))
                table += pal
        else:
            for grp in ISOLATE_GROUPS:
                for i in range(16):
                    table += struct.pack('>H', 0x0EEE if i in grp else 0x0000)
        iso = emit(bytes(table))
        pick1 = emit(b'\x2F\x01' +                                   # move.l d1,-(sp)
                     b'\x41\xF9' + struct.pack('>I', iso) +          # lea iso.l,a0
                     b'\x42\x41' +                                   # clr.w d1
                     b'\x12\x38' + struct.pack('>H', w(VAR_P1)) +    # move.b counter,d1
                     b'\xEB\x49' +                                   # lsl.w #5,d1
                     b'\xD0\xC1' +                                   # adda.w d1,a0
                     b'\x22\x1F' +                                   # move.l (sp)+,d1
                     b'\x4E\x75')
        pick2 = emit(picker(VAR_P2))
    else:
        pick1, pick2 = emit(picker(VAR_P1)), emit(picker(VAR_P2))
    por1, por2 = emit(picker(VAR_P1, POR_A, POR_B)), emit(picker(VAR_P2, POR_A, POR_B))

    # size-neutral call sites
    rom[HOOK_SITE:HOOK_SITE + 6] = b'\x4E\xB9' + struct.pack('>I', hook)
    rom[LEA_P1:LEA_P1 + 6] = b'\x4E\xB9' + struct.pack('>I', pick1)
    rom[LEA_P2:LEA_P2 + 6] = b'\x4E\xB9' + struct.pack('>I', pick2)
    for site, stub in ([(a, por1) for a in POR_SITES_P1] +
                       [(a, por2) for a in POR_SITES_P2]):
        if struct.unpack_from('>I', rom, site + 2)[0] != POR_A:
            raise SystemExit('%06X is not the lea I expected' % site)
        rom[site:site + 6] = b'\x4E\xB9' + struct.pack('>I', stub)

    if skin:
        idx, pslot, hit = recolour(rom, skin)
        print('  %s written into bank B: fighter slot %d, portrait slot %d'
              % (skin, idx, pslot))
        for label, (warm, cool) in zip(('fighter', 'portrait'), hit):
            print('    %-8s gi %-14s trim %s'
                  % (label, str(warm), str(cool)))

    total = fix_checksum(rom)

    open(out, 'wb').write(rom)
    what = ('FORCED to bank B (diagnostic)' if force else
            'button %s toggles, + colour probe (diagnostic)' % button if probe else
            'button %s toggles' % button)
    print('%s; stubs at %06X..%06X; checksum %04X -> %s'
          % (what, hook, at - 1, total, out))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    btn = 'A'
    if '--button' in sys.argv:
        btn = sys.argv[sys.argv.index('--button') + 1].upper()
    build(args[0], args[1], btn, '--force' in sys.argv, '--probe' in sys.argv,
          '--showpad' in sys.argv, '--redscreen' in sys.argv,
          '--padcolour' in sys.argv, '--whichbyte' in sys.argv,
          '--btnflash' in sys.argv, '--modeprobe' in sys.argv,
          sys.argv[sys.argv.index('--skin') + 1] if '--skin' in sys.argv else None,
          '--isolate' in sys.argv,
          sys.argv[sys.argv.index('--tune') + 1] if '--tune' in sys.argv else None)
