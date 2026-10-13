#!/usr/bin/env python3
"""Report and gate the resident size of a CuteMouse V9K build.

Reads the 'RESSZ' marker (size word, limit word) that ctmv9k.asm places in its
transient data. Exits 1 if the resident part exceeds LIMIT.
"""
import struct
import sys

data = open(sys.argv[1], 'rb').read()
i = data.find(b'RESSZ')
if i < 0:
    sys.exit('ressize: no RESSZ marker in ' + sys.argv[1])
size, limit = struct.unpack_from('<HH', data, i + 5)
print(f'resident {size} bytes ({size:04X}h), limit {limit:04X}h')
if size > limit:
    sys.exit(f'ressize: resident part exceeds LIMIT by {size - limit} bytes')
