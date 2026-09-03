#!/usr/bin/env python3
"""Nemesis decompressor - enough of it to pull art out of a Sonic disassembly.

Nemesis is the Huffman-ish codec Sonic 1/2/3 use for most of their tile art.
Output is 4bpp Mega Drive tiles: 32 bytes each, 8 rows of 8 pixels, one nibble
per pixel.

Format, briefly:
  - A word header. Bit 15 set means XOR mode (each row is XORed with the
    previous one); the low 15 bits are the tile count.
  - A code table, terminated by 0xFF. Entries map a variable-length bit code to
    "write this palette index N times".
  - A bitstream read most-significant-bit first. Six set bits in a row is an
    inline escape: the run is spelled out literally instead of via the table.
"""

import struct


class _Bits(object):
    def __init__(self, data, pos):
        self.d = data
        self.pos = pos
        self.bit = 0

    def peek(self, n):
        """Next n bits, MSB first, without consuming them."""
        v = 0
        p, b = self.pos, self.bit
        for _ in range(n):
            if p >= len(self.d):
                v = (v << 1)            # ran dry; pad with zeros
            else:
                v = (v << 1) | ((self.d[p] >> (7 - b)) & 1)
            b += 1
            if b == 8:
                b = 0
                p += 1
        return v

    def skip(self, n):
        self.bit += n
        self.pos += self.bit >> 3
        self.bit &= 7


def decompress(data, offset=0):
    """Returns (tiles_bytes, tile_count). tiles_bytes is tile_count*32 bytes."""
    header = struct.unpack_from(">H", data, offset)[0]
    xor_mode = bool(header & 0x8000)
    tile_count = header & 0x7FFF
    pos = offset + 2

    # --- code table ---
    table = {}                                  # (code_len, code) -> (idx, run)
    pal_index = 0
    while True:
        b = data[pos]; pos += 1
        if b == 0xFF:
            break
        if b & 0x80:
            pal_index = b & 0x0F
            b = data[pos]; pos += 1
            if b == 0xFF:
                break
        run = ((b >> 4) & 0x07) + 1
        code_len = b & 0x0F
        code = data[pos]; pos += 1
        table[(code_len, code)] = (pal_index, run)

    # --- bitstream ---
    bits = _Bits(data, pos)
    total_rows = tile_count * 8
    out = bytearray()
    prev_row = 0
    row = 0
    nibbles = 0
    rows_done = 0

    while rows_done < total_rows:
        if bits.peek(6) == 0x3F:
            # Inline escape: 6 set bits, then a 3-bit run and a 4-bit index.
            bits.skip(6)
            run = bits.peek(3) + 1; bits.skip(3)
            idx = bits.peek(4); bits.skip(4)
        else:
            for code_len in range(1, 9):
                code = bits.peek(code_len)
                hit = table.get((code_len, code))
                if hit is not None:
                    bits.skip(code_len)
                    idx, run = hit
                    break
            else:
                raise ValueError("no matching Nemesis code at row %d" % rows_done)

        for _ in range(run):
            row = ((row << 4) | idx) & 0xFFFFFFFF
            nibbles += 1
            if nibbles == 8:                    # a full 8-pixel row
                if xor_mode:
                    row ^= prev_row
                    prev_row = row
                out += struct.pack(">I", row)
                row = 0
                nibbles = 0
                rows_done += 1
                if rows_done == total_rows:
                    break

    return bytes(out), tile_count


def tile_to_pixels(tiles, index):
    """One 8x8 tile as 8 rows of 8 palette indices."""
    base = index * 32
    rows = []
    for y in range(8):
        r = []
        for x in range(4):
            b = tiles[base + y * 4 + x]
            r.append((b >> 4) & 0xF)
            r.append(b & 0xF)
        rows.append(r)
    return rows


if __name__ == "__main__":
    import sys
    art, n = decompress(open(sys.argv[1], "rb").read())
    print("%d tiles (%d bytes)" % (n, len(art)))
