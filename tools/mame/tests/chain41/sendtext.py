#!/usr/bin/env python3
"""Write text to a MAME pty at 1200 7N1 (the other port's traffic for the CHAIN41 test).
sendtext.py PTY [TEXT] [--lines N] [--eof] [--gap S]
  TEXT    escapes allowed ('HELLO\\r\\n'); --lines N appends N lines 'Lnnnn ABC..Z\\r\\n' (32 bytes)
  --eof   append ^Z (SERRD stops on it; not counted)
Prints the byte count and the 16-bit sum (SERRD N/S and A41 N/S must match); env DONE=path
is created when the bytes have drained."""
import os, sys, termios, tty, time, argparse
ap = argparse.ArgumentParser()
ap.add_argument("pty"); ap.add_argument("text", nargs="?", default="")
ap.add_argument("--lines", type=int, default=0); ap.add_argument("--eof", action="store_true")
ap.add_argument("--gap", type=float, default=0.0)
a = ap.parse_args()
fd = os.open(a.pty, os.O_RDWR | os.O_NOCTTY)
tty.setraw(fd)
try:                        # MAME's pty slot settings decide the framing; this is cosmetic
    at = termios.tcgetattr(fd)
    at[4] = at[5] = termios.B1200
    at[2] = (at[2] & ~termios.CSIZE) | termios.CS7
    termios.tcsetattr(fd, termios.TCSANOW, at)
except termios.error as e:
    print("termios: %s (ignored)" % e, file=sys.stderr)
data = a.text.encode().decode("unicode_escape").encode("latin1")
for i in range(a.lines):
    data += b"L%04d ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n" % i
print("N=%04X S=%04X (%d bytes)" % (len(data), sum(data) & 0xFFFF, len(data)), flush=True)
if a.eof: data += b"\x1a"
if a.gap:
    for b in data: os.write(fd, bytes([b])); time.sleep(a.gap)
else:
    os.write(fd, data)
termios.tcdrain(fd)
time.sleep(0.5)
print("sent", flush=True)
if os.environ.get("DONE"): open(os.environ["DONE"], "w").write("ok\n")
