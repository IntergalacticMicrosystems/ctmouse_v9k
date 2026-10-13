#!/usr/bin/env python3
"""Print a screenraw dump (tNNN.txt) as 25 text lines from its start; '#' marks bit-15 cells."""
import sys
t = open(sys.argv[1]).read().split()
start = int(t[0].split('=')[1], 16)
w = [int(x, 16) for x in t[1:]]
for r in range(25):
    s = ''
    for c in range(80):
        v = w[(start + r * 80 + c) & 0x7FF]
        ch = (v & 0x7FF) - 100
        s += '#' if v & 0x8000 else (chr(ch) if 32 <= ch < 127 else ('.' if ch != -100 else ' '))
    print(s.rstrip())
