#!/usr/bin/env python3
"""Check t05 dumps (tests 5/6). usage: analyze_text.py OUTDIR LOG
For each dump: the expected cursor cell = (start + (Y/16)*80 + X/10) & 7FFh from the resident
granpos and the CRTC start in the screenraw header. Checks: that cell has bit 15 set, it is the
only cell with bit 15 set among all 2048 words, the driver's cursor@ agrees, and between two
consecutive dumps with no console output in between, exactly the old and the new cell differ,
each by 8000h (exact restore). Also lists CRTC writes made from the driver's segment."""
import os, re, sys, struct
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from resdump import decode

out, logf = sys.argv[1], sys.argv[2]
log = open(logf).read()
labels = dict(re.findall(r'step (\d{3}) (.*)', log))
seg = re.search(r'000cc: (\w\w) (\w\w) (\w\w) (\w\w)', log)
dseg = '%s%s' % (seg.group(4), seg.group(3))


def load(i):
    t = open(os.path.join(out, 't%03d.txt' % i)).read().split()
    start = int(t[0].split('=')[1], 16)
    words = [int(w, 16) for w in t[1:]]
    return start, words, decode(open(os.path.join(out, 'r%03d.bin' % i), 'rb').read())


fails = 0
prev = None
for k in sorted(labels):
    i = int(k)
    start, w, r = load(i)
    X, Y = r['granpos']
    cell = (start + (Y // 16) * 80 + X // 10) & 0x7FF if r['hidecnt'] == 0 else None
    rev = [j for j in range(2048) if w[j] & 0x8000]
    exp = [cell] if cell is not None else []
    ok = rev == exp
    note = '' if ok else ' unexpected reverse cells %s' % ['%03x' % j for j in rev if j != cell]
    moved = not labels[k].startswith(('DIR', 'V9KMT', 'CLS'))
    if prev and moved:
        ps, pw, prev_rev = prev
        diff = [j for j in range(2048) if w[j] != pw[j]]
        allowed = set(prev_rev) | set(exp)
        if ps != start or not set(diff) <= allowed or any((w[j] ^ pw[j]) != 0x8000 for j in diff):
            ok = False
            note += ' restore: diff %s allowed %s' % (['%03x:%04x>%04x' % (j, pw[j], w[j]) for j in diff[:6]], ['%03x' % j for j in sorted(allowed)])
        else:
            note += ' restore exact (%d cells toggled)' % len(diff)
    print('%s %03d %-30s start=%03x X=%d Y=%d hide=%d cell=%s%s rev=%s%s' % (
        'ok  ' if ok else 'FAIL', i, labels[k], start, X, Y, r['hidecnt'],
        '%03x' % cell if cell is not None else '-', ' (wrapped)' if cell is not None and cell < start else '',
        ['%03x' % j for j in rev[:4]], note))
    fails += not ok
    prev = (start, w, rev)
crtc = re.findall(r'W (e800[01])=(\w\w) pc=(\w{4}):(\w{4})', log)
mine = [c for c in crtc if c[2] == dseg]
print('CRTC writes: %d total, %d from the driver segment %s: %s' % (
    len(crtc), len(mine), dseg, sorted({(a, v) for a, v, _, _ in mine})))
print('FAILS:', fails)
