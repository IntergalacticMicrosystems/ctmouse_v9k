#!/usr/bin/env python3
"""Check t12 (test 12): driver writes to screen RAM vs the CRTC mode, and the text screens after
PICASSO. usage: analyze_t12.py OUTDIR LOG"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from resdump import decode
out, logf = sys.argv[1], sys.argv[2]
log = open(logf).read()
seg = re.search(r'000cc: (\w\w) (\w\w) (\w\w) (\w\w)', log)
dseg = (seg.group(4) + seg.group(3)).lower()
r12, addr, timeline, drv = 0, None, [], []
for m in re.finditer(r'W (\w{5})=(\w\w) pc=(\w{4}):(\w{4}) t=([\d.]+)', log):
    a, v, cs, t = m.group(1), int(m.group(2), 16), m.group(3).lower(), float(m.group(5))
    if a == 'e8000':
        addr = v
    elif a == 'e8001' and addr == 12 and cs != dseg:
        if (v ^ r12) & 0x30:
            timeline.append((t, v, cs))
        r12 = v
    elif a.startswith('f0') and cs == dseg:
        drv.append((t, a, v, r12))
print('R12 mode changes (t, R12, CS):', [('%.2f' % t, '%02x' % v, c) for t, v, c in timeline])
print('driver writes to F0000-F0FFF: %d; while R12 bit 5 = 1 (graphics): %d' % (
    len(drv), sum(1 for d in drv if d[3] & 0x20)))
for d in drv:
    print('   t=%.3f %s=%02x R12=%02x' % d)
def scr(i):
    t = open(os.path.join(out, 't%03d.txt' % i)).read().split()
    start = int(t[0].split('=')[1], 16); w = [int(x, 16) for x in t[1:]]
    r = decode(open(os.path.join(out, 'r%03d.bin' % i), 'rb').read())
    X, Y = r['granpos']
    cell = (start + (Y // 16) * 80 + X // 10) & 0x7FF if r['hidecnt'] == 0 else None
    return start, w, r, cell, [j for j in range(2048) if w[j] & 0x8000]
for i in (0, 4, 5, 6):
    start, w, r, cell, rev = scr(i)
    print('step %03d start=%03x pos=%s hide=%d videoseg-cell=%s rev=%s' % (
        i, start, r['granpos'], r['hidecnt'], '%03x' % cell if cell is not None else '-', ['%03x' % j for j in rev]))
