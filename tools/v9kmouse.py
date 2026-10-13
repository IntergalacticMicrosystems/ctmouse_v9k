#!/usr/bin/env python3
"""v9kmouse.py - host-side serial mouse simulator and cursor oracle for the CTMOUSEV port.

Feeds Microsoft-protocol mouse bytes (1200 baud 7N1) into MAME's victor9k rs232 pty, and holds the
per-pixel graphics cursor oracle of doc/v9k-port-plan.md section 4.4 (test 17).

Protocols (--proto, or set by --hello / the script command "hello"):
  ms   plain 2-button Microsoft ('M'), 3 bytes per packet; the middle button is not sent.
  ms3  Microsoft with CTMOUSEV /3: a packet with no motion and no L/R change toggles the middle
       button (MSLTCODE2 patched to JNZ). So "move 0 0" is skipped in this mode.
  lt   Logitech 3-button ('M3'): while M is held every packet carries a 4th byte 20h; the release
       is sent as a packet with a 4th byte 00h. CuteMouse treats a packet *without* a 4th byte
       (the next sync byte arriving after byte 3) as "middle released", so the 4th byte cannot be
       sent only on middle changes.
  mz   MS wheel ('MZ'): every packet has a 4th byte = M<<4 | (wheel & 0Fh), wheel signed -8..7.

Packet: b1 = 40h | L<<5 | R<<4 | ((dy>>6)&3)<<2 | ((dx>>6)&3), b2 = dx&3Fh, b3 = dy&3Fh,
dx/dy signed -128..127 (+dy = down). Larger moves are split.

--port PATH opens a tty/pty (pyserial if installed, else os/termios); a non-tty path is written
as a raw byte file; "-" prints the bytes as hex on stdout. Without --port the MAME pty is found
from the tty-index of mame's /dev/ptmx fds (--pty-index picks rs232a/b),
falling back to find_mame_pty() of bldmame1/scripts/victor9k_serial_test.py.
"""
import argparse
import glob
import os
import random
import subprocess
import sys
import time

# ---------------------------------------------------------------------------------------------
# output port

def _controlling_ttys():
    ttys = set()
    for proc_dir in glob.glob('/proc/[0-9]*'):
        try:
            with open(os.path.join(proc_dir, 'stat')) as f:
                stat = f.read()
            fields = stat[stat.rfind(')') + 2:].split()
            tty_nr = int(fields[4])
            major, minor = (tty_nr >> 8) & 0xFF, tty_nr & 0xFF
            if 136 <= major <= 143:
                ttys.add('/dev/pts/%d' % ((major - 136) * 256 + minor))
        except (OSError, ValueError, IndexError):
            continue
    return ttys


def mame_ptys():
    """pts slaves of running mame processes, from the tty-index of their /dev/ptmx fds, in fd
    order (= open order; with -rs232a pty -rs232b pty normally A first)."""
    out = []
    try:
        pids = subprocess.run(['pgrep', 'mame'], capture_output=True, text=True).stdout.split()
    except FileNotFoundError:
        pids = []
    for pid in pids:
        try:
            fds = sorted(int(f) for f in os.listdir('/proc/%s/fd' % pid))
        except OSError:
            continue
        for fd in fds:
            try:
                if not os.readlink('/proc/%s/fd/%d' % (pid, fd)).endswith('ptmx'):
                    continue
                with open('/proc/%s/fdinfo/%d' % (pid, fd)) as f:
                    for line in f:
                        if line.startswith('tty-index:'):
                            out.append('/dev/pts/' + line.split()[1])
            except OSError:
                continue
    return out


def find_mame_pty(index=0):
    """MAME's pty: the index-th ptmx of a mame process; else (no access to /proc/pid/fd) the
    newest /dev/pts slave that is nobody's controlling terminal, as victor9k_serial_test.py."""
    ptys = mame_ptys()
    if ptys:
        if len(ptys) > 1:
            print('MAME ptys: %s; using %s (--pty-index)' % (' '.join(ptys), ptys[min(index, len(ptys) - 1)]),
                  file=sys.stderr)
        return ptys[min(index, len(ptys) - 1)]
    try:
        r = subprocess.run(['pgrep', 'mame'], capture_output=True, text=True)
        if r.returncode != 0 or not r.stdout.strip():
            return None
    except FileNotFoundError:
        pass
    ctl = _controlling_ttys()
    try:
        if sys.stdin.isatty():
            ctl.add(os.ttyname(sys.stdin.fileno()))
    except OSError:
        pass
    cands = []
    for pts in glob.glob('/dev/pts/[0-9]*'):
        if pts not in ctl:
            try:
                cands.append((os.stat(pts).st_mtime, pts))
            except OSError:
                pass
    return max(cands)[1] if cands else None


class Port:
    """write(bytes) to a pty (7N1 1200), a plain file, or a hex dump on stdout."""

    def __init__(self, path, verbose=False):
        self.verbose = verbose
        self.ser = self.fd = self.file = None
        self.hex = path == '-'
        if self.hex:
            return
        if os.path.exists(path) and os.path.realpath(path).startswith('/dev/'):
            try:
                import serial
                self.ser = serial.Serial(path, 1200, bytesize=serial.SEVENBITS,
                                         parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                                         xonxoff=False, rtscts=False, dsrdtr=False, timeout=0)
                return
            except Exception as e:                      # no pyserial, or its tcsetattr failed
                if not isinstance(e, ImportError):
                    print('pyserial: %s; using os/termios' % e, file=sys.stderr)
            # A pty ignores the line settings (MAME frames at its slot setting), and Linux
            # sometimes refuses to re-apply them (EINVAL on a second open), so this is best effort.
            import termios
            import tty
            self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
            try:
                tty.setraw(self.fd)
                a = termios.tcgetattr(self.fd)
                a[2] = (a[2] & ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)) | termios.CS7
                a[4] = a[5] = termios.B1200
                termios.tcsetattr(self.fd, termios.TCSANOW, a)
            except termios.error as e:
                print('termios: %s (ignored)' % e, file=sys.stderr)
        else:
            self.file = open(path, 'ab')

    def write(self, data):
        data = bytes(data)
        if self.verbose or self.hex:
            print(' '.join('%02X' % b for b in data), flush=True)
        if self.ser:
            self.ser.write(data)
            self.ser.flush()
        elif self.fd is not None:
            os.write(self.fd, data)
        elif self.file:
            self.file.write(data)
            self.file.flush()

    def close(self):
        for o in (self.ser, self.file):
            if o:
                o.close()
        if self.fd is not None:
            os.close(self.fd)

# ---------------------------------------------------------------------------------------------
# encoder

HELLO_PROTO = {'M': 'ms', 'M3': 'lt', 'MZ': 'mz'}


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


class Mouse:
    def __init__(self, port, proto='ms'):
        self.port, self.proto = port, proto
        self.L = self.R = self.M = 0

    def packet(self, dx=0, dy=0, wheel=0, mchange=False):
        """One packet; dx/dy -128..127, wheel -8..7 (mz only)."""
        b1 = 0x40 | self.L << 5 | self.R << 4 | ((dy >> 6) & 3) << 2 | ((dx >> 6) & 3)
        pkt = [b1, dx & 0x3F, dy & 0x3F]
        if self.proto == 'lt' and (self.M or mchange):
            pkt.append(0x20 if self.M else 0x00)
        elif self.proto == 'mz':
            pkt.append(self.M << 4 | (wheel & 0x0F))
        return pkt

    def send(self, dx=0, dy=0, wheel=0, mchange=False):
        out = []
        while True:
            sx, sy, sw = clamp(dx, -128, 127), clamp(dy, -128, 127), clamp(wheel, -8, 7)
            out += self.packet(sx, sy, sw, mchange)
            mchange = False
            dx, dy, wheel = dx - sx, dy - sy, wheel - sw
            if not (dx or dy or wheel):
                break
        self.port.write(out)

    def move(self, dx, dy):
        if self.proto == 'ms3' and dx == 0 and dy == 0:
            return                                      # would toggle the middle button
        self.send(dx, dy)

    def button(self, name, state):
        name = name.upper()
        if name not in ('L', 'R', 'M'):
            raise ValueError('button must be L, R or M')
        if getattr(self, name) == state:
            return
        setattr(self, name, state)
        if name != 'M':
            self.send()
        elif self.proto == 'ms3':
            self.send()                                 # empty packet = middle toggle
        elif self.proto in ('lt', 'mz'):
            self.send(mchange=True)
        else:
            print('warning: middle button ignored in proto ms', file=sys.stderr)

    def wheel(self, n):
        if self.proto != 'mz':
            print('warning: wheel needs proto mz', file=sys.stderr)
            return
        self.send(wheel=n)

    def hello(self, ident):
        ident = ident.upper()
        self.proto = HELLO_PROTO[ident]
        self.port.write(ident.encode())

# ---------------------------------------------------------------------------------------------
# modes

def run_hello(port, ident, args):
    m = Mouse(port)
    print('sending %r every 200 ms, Ctrl-C to stop' % ident, file=sys.stderr)
    n = 0
    while args.count == 0 or n < args.count:
        m.hello(ident)
        n += 1
        time.sleep(0.2)


def run_script(port, fname, proto, gap, held=''):
    m = Mouse(port, proto)
    for b in held.upper():                              # state left by an earlier run (not sent)
        setattr(m, b, 1)
    with open(fname) as f:
        for lineno, line in enumerate(f, 1):
            w = line.split('#', 1)[0].split()
            if not w:
                continue
            cmd, a = w[0].lower(), w[1:]
            try:
                if cmd == 'move':
                    m.move(int(a[0]), int(a[1]))
                elif cmd in ('press', 'release'):
                    m.button(a[0], cmd == 'press')
                elif cmd == 'wheel':
                    m.wheel(int(a[0]))
                elif cmd == 'sleep':
                    time.sleep(int(a[0]) / 1000)
                    continue
                elif cmd == 'hello':
                    m.hello(a[0] if a else 'M')
                elif cmd == 'proto':
                    m.proto = a[0]
                elif cmd == 'raw':
                    port.write(bytes(int(h, 16) for h in a))
                else:
                    raise ValueError('unknown command')
            except (IndexError, ValueError, KeyError) as e:
                sys.exit('%s:%d: %s: %s' % (fname, lineno, line.strip(), e))
            time.sleep(gap)


def run_burst(port, n, proto, rng):
    """N packets in one write, small alternating moves, last button state released."""
    m = Mouse(port, proto)
    out = []
    sx = sy = 0
    for i in range(n):
        m.L = i & 1
        dx, dy = rng.randint(-5, 5) or 1, rng.randint(-5, 5) or 1
        out += m.packet(dx, dy)
        sx, sy = sx + dx, sy + dy
    m.L = 0
    out += m.packet(1, 1)
    port.write(out)
    print('burst: %d packets, %d bytes, net motion %+d,%+d, %d left presses/releases'
          % (n + 1, len(out), sx + 1, sy + 1, n // 2), file=sys.stderr)


def run_garbage(port, n, proto, rng, gap):
    """Valid packets with random non-sync bytes (00-3Fh) and truncated packets in between.
    Net motion of the valid packets is printed so the client's position can be checked;
    garbage bytes that land right after a sync byte do corrupt that packet (by design)."""
    m = Mouse(port, proto)
    sx = sy = 0
    for _ in range(n):
        kind = rng.random()
        if kind < 0.25:
            port.write([rng.randint(0, 0x3F) for _ in range(rng.randint(1, 3))])
        elif kind < 0.35:
            port.write(m.packet(3, 3)[:rng.randint(1, 2)])    # truncated packet
        else:
            dx, dy = rng.randint(-20, 20), rng.randint(-20, 20)
            port.write(m.packet(dx, dy))
            sx, sy = sx + dx, sy + dy
        time.sleep(gap)
    print('net motion of the complete packets: %+d,%+d (a truncated packet or garbage that '
          'follows a sync byte adds its own motion)' % (sx, sy), file=sys.stderr)


def run_interactive(port, proto, step):
    import termios
    import tty
    m = Mouse(port, proto)
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    print('arrows/hjkl move, [ ] step, z x c toggle L R M, + - wheel, q quit\r')
    keys = {'\x1b[A': (0, -1), '\x1b[B': (0, 1), '\x1b[C': (1, 0), '\x1b[D': (-1, 0),
            'k': (0, -1), 'j': (0, 1), 'l': (1, 0), 'h': (-1, 0)}
    btn = {'z': 'L', 'x': 'R', 'c': 'M'}
    try:
        tty.setraw(fd)
        while True:
            k = os.read(fd, 8).decode(errors='ignore')
            if k in ('q', '\x03'):
                break
            if k in keys:
                m.move(keys[k][0] * step, keys[k][1] * step)
            elif k in btn:
                b = btn[k]
                m.button(b, not getattr(m, b))
            elif k in '+-' and k:
                m.wheel(1 if k == '+' else -1)
            elif k in '[]' and k:
                step = max(1, step // 2) if k == '[' else min(127, step * 2)
            print('step %d  L%d M%d R%d\r' % (step, m.L, m.M, m.R))
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

# ---------------------------------------------------------------------------------------------
# transcription of CuteMouse MSLTproc (ctmouse.asm 714-800), used to check the encoder

class MSLTDecoder:
    """mode: ms (MSLTCODE1/3 = ret, CODE2 = jmp), ms3 (CODE2 = jnz), lt (CODE3 = mov cl,3),
    mz (CODE3 = mov cl,2, wheelmask 0Fh). Totals and button state as mouseupdate sees them."""

    def __init__(self, mode):
        self.mode, self.iodone, self.b1, self.x = mode, 0, 0, 0
        self.dl = 0                                     # bit 1 = L, bit 0 = R, bit 2 = M
        self.sx = self.sy = self.wheel = 0

    @property
    def buttons(self):
        return {'L': self.dl >> 1 & 1, 'R': self.dl & 1, 'M': self.dl >> 2 & 1}

    def _update(self, chg, dx, dy, wheel):
        self.dl ^= chg
        self.sx += dx
        self.sy += dy
        if self.mode == 'mz':
            self.wheel += (wheel ^ 8) - 8               # signed nibble

    def _button3(self, b):
        cl = 3 if self.mode == 'lt' else 2
        wheel, chg = b & 0x0F, ((b >> cl) ^ self.dl) & 4
        if wheel or chg:                                # FASTER_CODE exit
            self._update(chg, 0, 0, wheel)

    def feed(self, b):
        cx = self.iodone
        if b & 0x40:
            self.iodone, self.b1 = 1, b
            if self.mode in ('lt', 'mz') and cx == 3:   # no 4th byte: middle released
                self._button3(0)
            return
        if cx == 0:
            return
        self.iodone += 1
        if cx == 1:
            self.x = b
        elif cx >= 3:
            self.iodone = 0
            if self.mode in ('lt', 'mz'):
                self._button3(b)
        else:
            s8 = lambda v: (v & 0xFF) - 0x100 * (v >> 7 & 1)
            dx = s8((self.b1 & 3) << 6 | self.x)
            dy = s8((self.b1 >> 2 & 3) << 6 | b)
            chg = ((self.b1 >> 4) ^ self.dl) & 3
            if self.mode == 'ms3' and not (chg or dx or dy):
                chg |= 4                                # empty packet toggles middle
            self._update(chg, dx, dy, 0)


def selftest_encoder():
    ok = True
    rng = random.Random(2)

    class Sink:
        def __init__(self):
            self.data = []

        def write(self, d):
            self.data += list(d)

    for mode in ('ms', 'ms3', 'lt', 'mz'):
        sink = Sink()
        m = Mouse(sink, mode)
        ex = ey = ew = 0
        bad = 0
        dec = MSLTDecoder(mode)
        for step in range(400):
            k = rng.random()
            if k < 0.5:
                dx, dy = rng.randint(-300, 300), rng.randint(-300, 300)
                m.move(dx, dy)
                if not (mode == 'ms3' and dx == 0 and dy == 0):
                    ex, ey = ex + dx, ey + dy
            elif k < 0.85:
                b = rng.choice('LRM' if mode != 'ms' else 'LR')
                m.button(b, rng.random() < 0.5)
            elif mode == 'mz':
                n = rng.randint(-20, 20)
                m.wheel(n)
                ew += n
            for byte in sink.data:
                dec.feed(byte)
            sink.data = []
            want = {'L': m.L, 'R': m.R, 'M': m.M if mode != 'ms' else 0}
            if (dec.sx, dec.sy, dec.wheel, dec.buttons) != (ex, ey, ew, want):
                bad += 1
        print('%-4s encoder vs MSLTproc model, proto %s' % ('ok' if not bad else 'FAIL', mode))
        ok &= not bad
    return ok

# ---------------------------------------------------------------------------------------------
# graphics cursor oracle (plan 4.4)
#
# Bitmap model: 800x400, column-major, 50 strips of 16 pixels; a strip is 400 words (800 bytes),
# one word per row, bit 0 = leftmost pixel. screen[strip*400 + y] is the word at byte offset
# strip*800 + y*2 from bitmap_seg. Masks are given in fn 9 order (bit 15 = leftmost pixel)
# unless mirrored=True (the driver's internal, pre-mirrored form).

WIDTH, HEIGHT, STRIPS = 800, 400, 50


def blank(value=0):
    return [value] * (STRIPS * HEIGHT)


def screen_from_bytes(data):
    """Little-endian 40000-byte dump (e.g. from the MAME debugger) -> word list."""
    return [data[i] | data[i + 1] << 8 for i in range(0, STRIPS * HEIGHT * 2, 2)]


def mirror16(w):
    return int('{:016b}'.format(w & 0xFFFF)[::-1], 2)


def render(screen, gx, gy, and_mask, xor_mask, mirrored=False):
    """Draw the cursor with its top-left pixel at (gx, gy) = (X - hotX, Y - hotY), exactly as
    the V9K strip renderer does. Modifies screen; returns the save list for restore()."""
    if not mirrored:
        and_mask = [mirror16(w) for w in and_mask]
        xor_mask = [mirror16(w) for w in xor_mask]
    saved = []
    if gx <= -16 or gx >= WIDTH or gy <= -16 or gy >= HEIGHT:
        return saved
    strip, sh = gx >> 4, gx & 15                        # strip -1..49
    r0, r1 = max(0, -gy), min(16, HEIGHT - gy)          # r1 exclusive
    for r in range(r0, r1):
        m, c = and_mask[r] & 0xFFFF, xor_mask[r] & 0xFFFF
        y = gy + r
        if strip >= 0:
            i = strip * HEIGHT + y
            andl = ((m << sh) | ((1 << sh) - 1)) & 0xFFFF
            saved.append((i, screen[i]))
            screen[i] = (screen[i] & andl) ^ ((c << sh) & 0xFFFF)
        if sh and strip + 1 <= STRIPS - 1:
            i = (strip + 1) * HEIGHT + y
            andr = (m >> (16 - sh)) | ((0xFFFF << sh) & 0xFFFF)
            saved.append((i, screen[i]))
            screen[i] = (screen[i] & andr) ^ (c >> (16 - sh))
    return saved


def restore(screen, saved):
    for i, w in reversed(saved):
        screen[i] = w


def render_pixels(screen, gx, gy, and_mask, xor_mask):
    """Independent per-pixel reference (fn 9 mask order): pixel = (pixel AND a) XOR c."""
    for r in range(16):
        y = gy + r
        for j in range(16):
            x = gx + j
            if 0 <= x < WIDTH and 0 <= y < HEIGHT:
                i, b = (x >> 4) * HEIGHT + y, x & 15
                a = (and_mask[r] >> (15 - j)) & 1
                c = (xor_mask[r] >> (15 - j)) & 1
                p = (((screen[i] >> b) & 1) & a) ^ c
                screen[i] = (screen[i] & ~(1 << b)) | (p << b)


def pixel(screen, x, y):
    return (screen[(x >> 4) * HEIGHT + y] >> (x & 15)) & 1


def selftest():
    ok = True

    def check(name, cond):
        nonlocal ok
        print('%-4s %s' % ('ok' if cond else 'FAIL', name))
        ok &= bool(cond)

    ones, zeros = [0xFFFF] * 16, [0] * 16

    def changed(s, base):
        return {i: w for i, w in enumerate(s) if w != base[i]}

    s = blank(); render(s, 0, 0, [0] + ones[1:], [0x8000] + zeros[1:])
    check('gx=0 gy=0: leftmost pixel -> bit 0 of word 0', changed(s, blank()) == {0: 0x0001})

    s = blank(); render(s, -1, 0, ones, [0xC000] + zeros[1:])
    check('gx=-1 (strip -1): only cursor column 1 shows, at x=0', changed(s, blank()) == {0: 0x0001})

    s = blank(); render(s, -15, 5, ones, [0xFFFF] + zeros[1:])
    check('gx=-15: one visible column at x=0, row 5', changed(s, blank()) == {5: 0x0001})

    s = blank(); render(s, 799, 399, ones, [0xFFFF] * 16)
    check('gx=799 gy=399: single pixel, strip 49 bit 15, no strip 50',
          changed(s, blank()) == {49 * 400 + 399: 0x8000})

    s = blank(); render(s, 8, -15, ones, zeros[:15] + [0xFFFF])
    check('gx=8 gy=-15: row 15 -> y 0, strip 0 = FF00, strip 1 = 00FF',
          changed(s, blank()) == {0: 0xFF00, 400: 0x00FF})

    s = blank(0xFFFF); render(s, 4, 0, [0] + ones[1:], zeros)
    check('AND clear at gx=4: strip 0 = 000F, strip 1 = FFF0',
          changed(s, blank(0xFFFF)) == {0: 0x000F, 400: 0xFFF0})

    s = blank(); sv = render(s, 784, 384, ones, ones)
    check('gx=784 (sh 0, strip 49): 16 words, no right word', len(sv) == 16 and s[49 * 400 + 384] == 0xFFFF)

    check('off-screen gx=-16 / gx=800 / gy=-16 / gy=400 draw nothing',
          all(render(blank(), gx, gy, ones, ones) == [] for gx, gy in
              ((-16, 0), (800, 0), (0, -16), (0, 400))))

    # exhaustive edge sweep against the per-pixel model, plus restore
    rng = random.Random(1)
    bad = 0
    gxs = list(range(-17, 18)) + list(range(782, 801)) + [rng.randrange(16, 780) for _ in range(5)]
    gys = [-16, -15, -8, -1, 0, 1, 200, 383, 384, 385, 398, 399, 400]
    am = [rng.randrange(0x10000) for _ in range(16)]
    xm = [rng.randrange(0x10000) for _ in range(16)]
    base = [rng.randrange(0x10000) for _ in range(STRIPS * HEIGHT)]
    for gx in gxs:
        for gy in gys:
            a, b = base[:], base[:]
            sv = render(a, gx, gy, am, xm)
            render_pixels(b, gx, gy, am, xm)
            if a != b:
                bad += 1
            restore(a, sv)
            if a != base:
                bad += 1
    check('strip renderer == per-pixel model and restore == original (%d positions)'
          % (len(gxs) * len(gys)), bad == 0)
    return ok

# ---------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--hello', nargs='?', const='M', choices=['M', 'M3', 'MZ'],
                   help="repeat the PnP id every 200 ms (MAME's pty carries no RTS)")
    g.add_argument('--script', metavar='FILE',
                   help='lines: move dx dy | press/release L|R|M | wheel n | sleep ms | '
                        'hello M|M3|MZ | proto ms|ms3|lt|mz | raw hex..')
    g.add_argument('--burst', type=int, metavar='N', help='N packets in one write')
    g.add_argument('--garbage', type=int, nargs='?', const=200, metavar='N',
                   help='N items: valid packets mixed with random non-sync bytes')
    g.add_argument('--interactive', action='store_true')
    g.add_argument('--selftest', action='store_true', help='check the cursor oracle')
    ap.add_argument('--port', help='pty/tty path, plain file, or - for hex on stdout')
    ap.add_argument('--pty-index', type=int, default=0,
                    help='auto-detect: which MAME pty (0 = first opened, normally rs232a)')
    ap.add_argument('--proto', default='ms', choices=['ms', 'ms3', 'lt', 'mz'])
    ap.add_argument('--gap', type=float, default=0.03, help='seconds between script/garbage items')
    ap.add_argument('--count', type=int, default=0, help='--hello: stop after N ids (0 = forever)')
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--held', default='', metavar='LRM',
                    help='--script: buttons already held by an earlier run (each run starts '
                         'with all released otherwise)')
    ap.add_argument('--step', type=int, default=8, help='--interactive: move step')
    ap.add_argument('-v', '--verbose', action='store_true', help='also print bytes sent')
    args = ap.parse_args()

    if args.selftest:
        sys.exit(0 if (selftest() & selftest_encoder()) else 1)

    path = args.port or find_mame_pty(args.pty_index)
    if not path:
        sys.exit('no --port given and no MAME pty found')
    print('port: %s' % path, file=sys.stderr)
    port = Port(path, args.verbose)
    rng = random.Random(args.seed)
    try:
        if args.hello:
            run_hello(port, args.hello, args)
        elif args.script:
            run_script(port, args.script, args.proto, args.gap, args.held)
        elif args.burst is not None:
            run_burst(port, args.burst, args.proto, rng)
        elif args.garbage is not None:
            run_garbage(port, args.garbage, args.proto, rng, args.gap)
        else:
            run_interactive(port, args.proto, args.step)
    except KeyboardInterrupt:
        pass
    finally:
        port.close()


if __name__ == '__main__':
    main()
