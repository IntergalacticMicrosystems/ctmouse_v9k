#!/usr/bin/env python3
"""Decode a CTMOUSEV resident dump (bytes from TSRstart, >= 100h long).
Offsets from ctmousev.asm: spritebuf 1Eh (64 bytes), V9K_UDATA at 5Eh (v9k_rid, gc_x, gc_y,
gc_rows, gc_lr, granx10), SaveArea 68h: mickey8, senscoeff, sensval, startscan, endscan,
hotspot 78h, screenmask 7Ch, cursormask 9Ch, nocursorcnt BCh, rangemax BEh, upleft C2h,
lowright C6h, pos CAh, granpos CEh."""
import struct, sys

def s16(d, o): return struct.unpack_from('<h', d, o)[0]

def decode(d):
    w = lambda o: s16(d, o)
    return dict(rid=w(0x5E) & 0xFFFF, gc_x=w(0x60), gc_y=w(0x62), gc_rows=d[0x64], gc_lr=d[0x65],
                granx10=d[0x66], mickey8=(w(0x68), w(0x6A)), startscan=w(0x74) & 0xFFFF,
                endscan=w(0x76) & 0xFFFF, hot=(w(0x78), w(0x7A)),
                smask=list(struct.unpack_from('<16H', d, 0x7C)),
                cmask=list(struct.unpack_from('<16H', d, 0x9C)),
                hidecnt=d[0xBC], rangemax=(w(0xBE), w(0xC0)), pos=(w(0xCA), w(0xCC)),
                granpos=(w(0xCE), w(0xD0)))

if __name__ == '__main__':
    for f in sys.argv[1:]:
        if f.startswith('hex:'):
            d = bytes.fromhex(f[4:])
        else:
            d = open(f, 'rb').read()
        r = decode(d)
        print({k: (v if k not in ('smask', 'cmask') else ' '.join('%04x' % x for x in v)) for k, v in r.items()})
