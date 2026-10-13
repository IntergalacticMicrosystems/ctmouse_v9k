#!/usr/bin/env python3
"""Check t07 dumps (tests 7/17) against the v9kmouse cursor oracle.
usage: analyze_gfx.py OUTDIR LOG
gNNN.bin = 40000-byte bitmap, rNNN.bin = resident bytes 0-FFh (resdump.py layout).
Background: the reference dump (step 0) with its cursor words taken from the first later dump
whose cursor does not overlap them, so it does not depend on the driver's save buffer.
Every dump must equal render(background, granpos - hotspot, driver masks), or the background
itself when the cursor is off screen or hidden (nocursorcnt != 0)."""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, HERE)
import v9kmouse as vm
from resdump import decode

out, log = sys.argv[1], sys.argv[2]
labels = dict(re.findall(r'step (\d{3}) (.*)', open(log).read()))
steps = sorted(int(k) for k in labels)
txt = open(log).read()
w0 = re.search(r'f0000: (\w\w) (\w\w)', txt)
r12 = int(re.search(r'm_disp_start_addr = (\w+)', txt).group(1), 16) >> 8
base = int(w0.group(2) + w0.group(1), 16) & 0x7FF
bseg = (0x1000 if r12 & 0x10 else 0) + 2 * base
off = bseg * 16 - 0x3000                     # gen_t07.py dumps from 3000h
print('R12=%02x word0 base=%03x bitmap_seg=%04x (dump offset %x)' % (r12, base, bseg, off))
assert r12 & 0x20 and 0 <= off <= 0x1000, 'not in graphics mode or bitmap outside the dump window'
dumps, res = {}, {}
for i in steps:
    g, r = os.path.join(out, 'g%03d.bin' % i), os.path.join(out, 'r%03d.bin' % i)
    if os.path.exists(g) and os.path.exists(r):
        dumps[i] = vm.screen_from_bytes(open(g, 'rb').read()[off:off + 40000])
        res[i] = decode(open(r, 'rb').read())


def expect(bg, r):
    s = list(bg)
    gx, gy = r['granpos'][0] - r['hot'][0], r['granpos'][1] - r['hot'][1]
    saved = []
    if r['hidecnt'] == 0:
        saved = vm.render(s, gx, gy, r['smask'], r['cmask'], mirrored=True)
    return s, gx, gy, {k for k, _ in saved}


bg = list(dumps[steps[0]])
_, _, _, refset = expect(bg, res[steps[0]])
for j in steps[1:]:
    _, _, _, sj = expect(bg, res[j])
    if not (sj & refset):
        for k in refset:
            bg[k] = dumps[j][k]
        print('background: step 0 with its %d cursor words from step %d' % (len(refset), j))
        break
ok = bad = 0
seen_gx, seen_gy, hidden = set(), set(), 0
for i in steps:
    e, gx, gy, cur = expect(bg, res[i])
    d = dumps[i]
    diff = [k for k in range(len(d)) if d[k] != e[k]]
    r = res[i]
    tag = 'gx=%d gy=%d hot=%s pos=%s gc=%d,%d hide=%d' % (gx, gy, r['hot'], r['granpos'],
                                                         r['gc_x'], r['gc_y'], r['hidecnt'])
    if not cur:
        hidden += 1
    if diff:
        bad += 1
        inside = sum(1 for k in diff if k in cur)
        print('FAIL %03d %-18s %s: %d words differ (%d in cursor area), first %s' % (
            i, labels[str(i).zfill(3)] if str(i).zfill(3) in labels else '', tag, len(diff), inside,
            ['s%d y%d %04x!=%04x' % (k // 400, k % 400, d[k], e[k]) for k in diff[:4]]))
    else:
        ok += 1
        if cur:
            seen_gx.add(gx); seen_gy.add(gy)
    if os.environ.get('V'):
        print('     %03d %-18s %s %s' % (i, labels.get('%03d' % i, ''), tag, 'ok' if not diff else ''))
print('%d dumps: %d equal to the oracle, %d differ; %d with no cursor drawn (== background)' %
      (len(steps), ok, bad, hidden))
print('gx covered:', sorted(x for x in seen_gx if x < 32 or x > 760))
print('gy covered:', sorted(y for y in seen_gy if y < 32 or y > 360))
