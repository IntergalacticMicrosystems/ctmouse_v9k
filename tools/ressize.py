#!/usr/bin/env python3
"""Report and gate the resident size and data layout of a CuteMouse V9K build.

Reads the 'RESSZ' marker that ctmousev.asm places in its transient data:
  dw TSRend-TSRstart   resident bytes (PSP included)
  dw LIMIT             hard ceiling
  dw TSRdata-TSRstart  start of initialized data
  dw TSRavail-TSRstart first byte after the entry jmp (103h)
The assembler's own if/%echo/.err see unreliable pass values on this file, so
both checks are done here, from the built binary. Exits 1 on a violation.
"""
import struct
import sys

data = open(sys.argv[1], 'rb').read()
i = data.find(b'RESSZ')
if i < 0:
    sys.exit('ressize: no RESSZ marker in ' + sys.argv[1])
size, limit, tsrdata, tsravail = struct.unpack_from('<HHHH', data, i + 5)
print(f'resident {size} bytes ({size:04X}h), limit {limit:04X}h, '
      f'initialized data at {tsrdata:04X}h (entry jmp ends at {tsravail:04X}h)')
if size > limit:
    sys.exit(f'ressize: resident part exceeds LIMIT by {size - limit} bytes')
if tsrdata < tsravail:
    sys.exit('ressize: initialized data overlaps the entry jmp: '
             'pad the uninitialized data so TSRdata >= TSRavail')
