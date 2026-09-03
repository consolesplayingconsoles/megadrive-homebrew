# datalink — Mega Drive data channel

Repurposes the console's controller port as a parallel data bus so a Pico can
stream data into a running ROM. Port 2 is the permanent data port (port 1 stays
free for a real pad). This is the transport the other homebrew builds on.

## Hardware

A Pico drives the DE-9 controller lines through two BSS138 level shifters. Both
shifter references must be powered: HV rail from the console's +5V (pin 5), LV
rail from the Pico's 3V3. Ground is common (pin 8 to Pico GND).

Confirmed GPIO to port mapping (verified with `porttest`):

| Pico GPIO | DE-9 pin | Console read bit | Role in data channel |
|-----------|----------|------------------|----------------------|
| GP3 | 1 | bit0 | payload bit 0 |
| GP4 | 2 | bit1 | payload bit 1 |
| GP5 | 3 | bit2 | payload bit 2 |
| GP6 | 4 | bit3 | payload bit 3 |
| GP7 | 6 | bit4 | CTRL flag |
| GP8 | 9 | bit5 | CLK (self-clock) |
| GP2 | 7 | bit6 | SELECT (console output, unused in v0) |

The ROM reads port 2 at `0xA10005` (data) and `0xA1000B` (direction). A line
pulled low reads as 0, released (high) reads as 1, so the Pico sets each bit
directly (no inversion).

Wire colors are non-standard and specific to this cable. Trust the GPIO to bit
mapping, not the colors.

## Protocol (v0)

Self-clocked: the Pico toggles CLK (bit5) on every transfer. The ROM latches the
other bits on each CLK edge. One transfer carries a 4-bit payload plus the CTRL
flag.

Per transfer:
* CTRL = 1: framing symbol. Payload id `0x1` = START, `0x2` = END.
* CTRL = 0: data nibble. Two nibbles (high first) rebuild one byte.

Message frame:

```
START  ->  [opcode byte]  ->  [payload bytes...]  ->  END
```

The first byte after START is the **opcode** (instruction id), so the format
expands without touching the transport. Defined so far:

| Opcode | Meaning | Payload |
|--------|---------|---------|
| 0x01 | print text | ASCII bytes |
| 0x02 | render graphic | 1 id byte (0 = smiley, 1 = heart) |

Pace is roughly 40 ms per transfer, slow enough that the 60fps ROM catches every
edge and you watch the text arrive letter by letter. Faster paces need the ROM to
poll tighter than vsync.

## The ROM

The data channel receiver. Decodes the protocol above and shows the live bits,
the current opcode, the last byte, the received text, and rendered graphics. The
text line wipes dynamically (clears exactly what was shown, no leftovers).

Its Pico sender (`pico_sender.py`) is interactive: type in the Thonny console and
it transmits. Type plain text to print it, or `/g 0` / `/g 1` to render a graphic.

## Build and run

From the homebrew root (SGDK Docker image, no local toolchain):

```
./build.sh                 # datalink is the default -> tools/datalink/out/cpc-player.bin
```

Then run the Pico sender and type:

```
# in Thonny, on the Pico wired to port 2
tools/datalink/pico_sender.py
cpc> hello mega drive      -> prints on screen
cpc> /g 0                  -> renders the smiley
cpc> /g 1                  -> renders the heart
```
