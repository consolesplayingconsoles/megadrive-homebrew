# CPC DATA LINK -- Pico sender (MicroPython). Runs on the Pico wired to the
# Mega Drive controller PORT 2. Interactive: type in the Thonny console and it
# transmits to the datalink ROM.
#
# Bus roles (open-drain, value 1 = high = logic 1, value 0 = low = logic 0):
#   bits 0-3 = GP3,GP4,GP5,GP6  payload nibble / control id
#   bit 4    = GP7              CTRL flag: 1 = framing symbol, 0 = data nibble
#   bit 5    = GP8              CLK: toggled every transfer (self-clocked)
#
# Frame: START -> opcode byte -> payload bytes -> END, each byte = 2 nibbles.
#
# Type at the prompt:
#   any text        -> print it on the Mega Drive
#   /g <id>         -> render graphic <id>  (0 = smiley, 1 = heart)

from machine import Pin
import time

PAYLOAD_GP = [3, 4, 5, 6]          # bits 0..3
pay = [Pin(g, Pin.OPEN_DRAIN, value=1) for g in PAYLOAD_GP]
ctrl = Pin(7, Pin.OPEN_DRAIN, value=1)   # bit4
clk  = Pin(8, Pin.OPEN_DRAIN, value=1)   # bit5

CTRL_START = 0x1
CTRL_END   = 0x2
OP_PRINT   = 0x01
OP_RENDER  = 0x02

_clk = 1

def _xfer(is_ctrl, nib):
    global _clk
    for i in range(4):
        pay[i].value((nib >> i) & 1)   # set payload nibble
    ctrl.value(1 if is_ctrl else 0)    # set CTRL flag
    time.sleep_ms(5)                   # let the lines settle
    _clk ^= 1                          # toggle CLK last -> "new transfer"
    clk.value(_clk)
    time.sleep_ms(35)                  # hold so the ROM (60fps) catches it

def _byte(b):
    _xfer(False, (b >> 4) & 0xF)       # high nibble
    _xfer(False, b & 0xF)              # low nibble

def send(opcode, data):
    _xfer(True, CTRL_START)
    _byte(opcode)
    for b in data:
        _byte(b)
    _xfer(True, CTRL_END)

print("CPC data link ready. type text, or '/g 0' / '/g 1' for a graphic.")
while True:
    line = input("cpc> ")
    if not line:
        continue
    if line.startswith("/g"):
        try:
            gid = int(line[2:].strip() or "0")
        except ValueError:
            print("  usage: /g <id>")
            continue
        send(OP_RENDER, bytes([gid & 0xFF]))
        print("  rendered graphic", gid)
    elif line.startswith("/text "):
        msg = line[6:]
        send(OP_PRINT, msg.encode())
        print("  sent:", msg)
    else:
        send(OP_PRINT, line.encode())
        print("  sent:", line)
