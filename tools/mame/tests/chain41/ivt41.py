#!/usr/bin/env python3
"""ivt41.py DUMP : decode the CTMOUSEV resident state from a memory dump of 0:0..A0000
(screen.lua "mem 0 a0000 file"): INT 41h/33h vectors, IMR is not in the dump; finds the
IRQhandler's 'call far [oldIRQaddr]' (FF 1E) and 'cmp [chain_ok],0' (80 3E .. .. 00) operands."""
import sys, struct
d = open(sys.argv[1], "rb").read()
def vec(n): o, s = struct.unpack_from("<HH", d, n * 4); return s, o
s41, o41 = vec(0x41); s33, o33 = vec(0x33)
print("INT 41h = %04X:%04X  INT 33h = %04X:%04X" % (s41, o41, s33, o33))
base = s41 * 16
code = d[base + o41: base + o41 + 0x80]
i = code.find(b"\x9c\xff\x1e")                   # pushf; call far [mem]
if i < 0 and s33 not in (0, 0xFFFF):            # INT 41h not ours: look in the INT 33h segment
    base = s33 * 16
    code = d[base: base + 0x1000]
    i = code.find(b"\x9c\xff\x1e")
    if i >= 0: print("(INT 41h is not CTMOUSEV's; decoding the INT 33h segment %04X)" % s33)
if i < 0: print("no chain call found (CHAIN41=0 or not CTMOUSEV)"); sys.exit()
a = struct.unpack_from("<H", code, i + 3)[0]
os_, ss_ = struct.unpack_from("<HH", d, base + a)
print("oldIRQaddr @%04X = %04X:%04X" % (a, ss_, os_))
j = code.rfind(b"\x80\x3e", 0, i)
if 0 <= j < i and i - j < 0x20:
    c = struct.unpack_from("<H", code, j + 2)[0]
    print("chain_ok   @%04X = %d" % (c, d[base + c]))
if ss_ or os_:
    b = d[ss_ * 16 + os_]
    print("old handler first byte = %02X" % b)
