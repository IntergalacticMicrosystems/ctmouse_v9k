#!/usr/bin/env python3
"""check.py - DOSBox test of ctmv9k-video.inc against the tools/v9kmouse.py cursor oracle.

  tools/video/check.py [--workdir DIR] [--no-run]

Builds VTEST.COM (jwasm, the real include with a fake CRTC), writes CMDS.BIN (the test matrix),
runs DOSBox headless, then replays the same commands on a Python model of drawcursor /
restorescreen / v9k_detect_mode / v9k_txtaddr / V9K_GRANX that uses v9kmouse.render/restore for
every graphics cursor, and compares each dump in OUT.BIN. Exit code 0 = all pass.
"""
import argparse
import os
import random
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'tools'))
import v9kmouse as vm  # noqa: E402

(OP_END, OP_CRTC, OP_POKE, OP_DETECT, OP_SETUPG, OP_SETMASK, OP_DEFMASK, OP_HOT, OP_BOX, OP_DRAW,
 OP_DUMPBMP, OP_DUMPSCR, OP_TMASK, OP_GRANX, OP_TXTADDR, OP_STATE, OP_LOADBMP) = range(17)

# CuteMouse default arrow, fn 9 order (bit 15 = leftmost), from ctmouse.asm DefArea
ARROW_AND = [0x3FFF, 0x1FFF, 0x0FFF, 0x07FF, 0x03FF, 0x01FF, 0x00FF, 0x007F,
             0x003F, 0x001F, 0x01FF, 0x00FF, 0x30FF, 0xF87F, 0xF87F, 0xFCFF]
ARROW_XOR = [0x0000, 0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00,
             0x7F80, 0x7C00, 0x6C00, 0x4600, 0x0600, 0x0300, 0x0300, 0x0000]


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v

# ------------------------------------------------------------------------------------------------
# command list


class Cmds:
    def __init__(self):
        self.list = []

    def add(self, op, a=0, b=0, c=0, d=0, payload=None, tag=''):
        self.list.append((op, a & 0xFFFF, b & 0xFFFF, c & 0xFFFF, d & 0xFFFF, payload, tag))

    def bytes(self):
        out = b''
        for op, a, b, c, d, payload, _ in self.list:
            out += struct.pack('<5H', op, a, b, c, d)
            if payload is not None:
                out += struct.pack('<32H', *payload)
        return out + struct.pack('<5H', 0, 0, 0, 0, 0)


def build(rng):
    c = Cmds()
    c.add(OP_SETUPG)
    c.add(OP_DUMPSCR, tag='setup screen RAM')
    c.add(OP_LOADBMP, 0x1234)
    c.add(OP_DETECT, tag='detect graphics (bit 4)')
    c.add(OP_DUMPBMP, tag='bitmap pattern')

    # --- graphics edge sweep, random masks given in fn 9 order (V9K_MIRRORCOPY)
    am = [rng.randrange(0x10000) for _ in range(16)]
    xm = [rng.randrange(0x10000) for _ in range(16)]
    c.add(OP_SETMASK, payload=am + xm)
    hx, hy = 7, -2
    c.add(OP_HOT, hx, hy)
    gxs = list(range(-16, 17)) + list(range(783, 801)) + [100, 397, 555]
    gys_a = [-16, -15, -8, -1, 0, 1, 200, 383, 384, 390, 399, 400]
    pos = [(gx, gy) for gx in gxs for gy in gys_a]
    for gy in list(range(-15, 1)) + list(range(384, 400)):
        for gx in (-15, -9, -1, 0, 7, 8, 400, 784, 785, 791, 799):
            pos.append((gx, gy))
    rng.shuffle(pos)
    for i, (gx, gy) in enumerate(pos):
        c.add(OP_DRAW, gx + hx, gy + hy, 0, 0, tag='draw gx=%d gy=%d' % (gx, gy))
        c.add(OP_DUMPBMP, tag='after draw gx=%d gy=%d' % (gx, gy))
        c.add(OP_STATE, tag='state gx=%d gy=%d' % (gx, gy))
        if i % 5 == 0:
            c.add(OP_DRAW, gx + hx, gy + hy, 0, 0, tag='same position, not forced')
            c.add(OP_STATE, tag='state same position')
            c.add(OP_DRAW, gx + hx, gy + hy, 1, 0, tag='same position, forced')
            c.add(OP_DUMPBMP, tag='after forced redraw gx=%d gy=%d' % (gx, gy))
        if i % 3 == 0:
            c.add(OP_DRAW, 0, 0, 0, 1, tag='hide')
            c.add(OP_DUMPBMP, tag='after hide (restore) gx=%d gy=%d' % (gx, gy))
            c.add(OP_STATE, tag='state after hide')
    c.add(OP_DRAW, 0, 0, 0, 1)
    c.add(OP_DUMPBMP, tag='hidden at end of sweep')

    # --- default arrow (pre-mirrored V9K_DEFMASKS), hot spot 0,0
    c.add(OP_DEFMASK)
    c.add(OP_HOT, 0, 0)
    for gx, gy in ((0, 0), (5, 3), (17, 99), (790, 395), (799, 399), (400, 200)):
        c.add(OP_DRAW, gx, gy, 0, 0)
        c.add(OP_DUMPBMP, tag='arrow at %d,%d' % (gx, gy))
    c.add(OP_DRAW, 0, 0, 0, 1)

    # --- fn 10h exclusion box
    c.add(OP_SETMASK, payload=am + xm)
    c.add(OP_HOT, 3, 4)
    c.add(OP_BOX, 100, 100, 200, 150)
    for gx in range(80, 215, 9):
        for gy in (80, 84, 85, 86, 120, 150, 151, 160):
            c.add(OP_DRAW, gx + 3, gy + 4, 0, 0)
            c.add(OP_DUMPBMP, tag='box test gx=%d gy=%d' % (gx, gy))
    c.add(OP_BOX, 0, 0, -32768, -32768)

    # --- MODEGUARD
    c.add(OP_DRAW, 300, 100, 0, 0)
    c.add(OP_DUMPBMP, tag='guard: drawn')
    c.add(OP_CRTC, 0x0000)                       # app switched to text without fn 0
    c.add(OP_DRAW, 320, 110, 0, 0, tag='guard: text R12')
    c.add(OP_DUMPBMP, tag='guard: no draw, background discarded')
    c.add(OP_STATE, tag='guard: state')
    c.add(OP_CRTC, 0x3000)
    c.add(OP_DRAW, 320, 110, 0, 0)
    c.add(OP_DUMPBMP, tag='guard: back, drawn over the ghost')
    c.add(OP_POKE, 0, 1, 1, tag='bitmap base moved')
    c.add(OP_DRAW, 330, 120, 0, 0)
    c.add(OP_DUMPBMP, tag='guard: base moved, discarded')
    c.add(OP_POKE, 0, 0, 1)
    c.add(OP_DRAW, 330, 120, 0, 0)
    c.add(OP_DUMPBMP, tag='guard: base back, drawn')
    c.add(OP_CRTC, 0x2000)                       # font bank (bit 4) switch
    c.add(OP_DRAW, 0, 0, 0, 1)
    c.add(OP_DUMPBMP, tag='guard: hide after bit-4 switch discards')
    c.add(OP_CRTC, 0x3000)
    c.add(OP_DRAW, 340, 130, 0, 0)
    c.add(OP_DRAW, 0, 0, 0, 1)
    c.add(OP_DUMPBMP, tag='guard: normal hide')

    # --- mode detection
    c.add(OP_DRAW, 250, 250, 0, 0)
    c.add(OP_CRTC, 0x2000)
    c.add(OP_DETECT, tag='detect graphics, bit 4 = 0 (id changed: background dropped)')
    c.add(OP_CRTC, 0x3000)
    c.add(OP_DRAW, 260, 250, 0, 0, tag='draw with stale videoseg: guard must skip it')
    c.add(OP_DETECT, tag='detect graphics, bit 4 = 1')
    c.add(OP_DUMPBMP, tag='detect discarded the background, ghost stays')
    c.add(OP_POKE, 0, 0xF800, 1)
    c.add(OP_DETECT, tag='detect: attribute bits in word 0')
    for w, good in ((1, 25), (50, 1), (49, 49 * 25), (1249, 1249)):
        c.add(OP_POKE, w, good + 1, 1)
        c.add(OP_DETECT, tag='detect: word %d wrong -> no cursor' % w)
        c.add(OP_POKE, w, good, 1)
        c.add(OP_DETECT, tag='detect: word %d fixed' % w)
    c.add(OP_POKE, 2, 0, 1)
    c.add(OP_DETECT, tag='detect: unsampled word 2 wrong (heuristic passes)')
    c.add(OP_POKE, 0, 799, 0)
    c.add(OP_DETECT, tag='detect: base 799 > 798 -> no cursor')
    c.add(OP_POKE, 0, 0, 1)
    c.add(OP_DETECT, tag='detect: graphics again')

    # --- text mode
    c.add(OP_CRTC, 0x0510)
    c.add(OP_DETECT, tag='detect text')
    c.add(OP_TMASK, 0xFFFF, 0x8000)
    tpos = [(0, 0), (10, 0), (790, 0), (0, 16), (400, 192), (790, 384), (0, 384), (450, 384)]
    for start in (0x000, 0x510, 0x7F0, 0x7FF, 0x6B0):
        c.add(OP_CRTC, start)
        for x, y in tpos:
            c.add(OP_DRAW, x, y, 0, 0)
            c.add(OP_DUMPSCR, tag='text start=%03X X=%d Y=%d' % (start, x, y))
            c.add(OP_STATE, tag='text state')
        c.add(OP_DRAW, 0, 0, 0, 1)
        c.add(OP_DUMPSCR, tag='text hide start=%03X' % start)
    c.add(OP_TMASK, 0x77FF, 0x7700)
    c.add(OP_BOX, 380, 180, 420, 200)
    for x, y in ((370, 176), (360, 160), (420, 192), (430, 192), (380, 208)):
        c.add(OP_DRAW, x, y, 0, 0)
        c.add(OP_DUMPSCR, tag='text box X=%d Y=%d' % (x, y))
    c.add(OP_BOX, 0, 0, -32768, -32768)
    c.add(OP_CRTC, 0x0100)
    c.add(OP_DRAW, 200, 32, 0, 0)
    c.add(OP_POKE, (0x100 + 2 * 80 + 20) & 0x7FF, 0x1234, 0, tag='console writes the cell')
    c.add(OP_DRAW, 0, 0, 0, 1)
    c.add(OP_DUMPSCR, tag='text: changed cell not restored')
    c.add(OP_DRAW, 200, 32, 0, 0)
    c.add(OP_CRTC, 0x0150)                       # console scrolled by one line
    c.add(OP_DRAW, 0, 0, 0, 1)
    c.add(OP_DUMPSCR, tag='text: restore at the drawn address after a scroll')
    c.add(OP_DRAW, 300, 48, 0, 0)
    c.add(OP_CRTC, 0x1150)                       # bit 4 set: other render target
    c.add(OP_DRAW, 310, 48, 0, 0)
    c.add(OP_DUMPSCR, tag='text guard: no draw, discarded')
    c.add(OP_STATE, tag='text guard state')
    c.add(OP_CRTC, 0x0150)
    c.add(OP_DRAW, 0, 0, 0, 1)

    # --- text cell address
    for start in (0x000, 0x001, 0x3FF, 0x510, 0x7B0, 0x7F0, 0x7FF, 0x0700, 0x05FF):
        for x, y in ((0, 0), (9, 15), (10, 16), (795, 399), (790, 384), (123, 200), (799, 0)):
            c.add(OP_CRTC, start)
            c.add(OP_TXTADDR, x, y, tag='txtaddr start=%03X X=%d Y=%d' % (start, x, y))
    c.add(OP_CRTC, 0x2000)
    c.add(OP_TXTADDR, 10, 16, tag='txtaddr guard (graphics R12 in text mode)')

    # --- granularity
    c.add(OP_GRANX, 10, 2560, 0, tag='granx X text')
    c.add(OP_GRANX, 10, 800, 2, tag='granx Y untouched')
    c.add(OP_GRANX, 0, 800, 0, tag='granx X graphics')
    return c

# ------------------------------------------------------------------------------------------------
# model


class Model:
    def __init__(self):
        self.crtc = 0
        self.scr = [0] * 2048
        self.bmp = vm.blank()
        self.base = self.bmpseg = self.scrseg = 0
        self.am, self.xm, self.mir = [0] * 16, [0] * 16, False   # fn 9 order
        self.hx = self.hy = 0
        self.ul, self.lr = (0, 0), (-32768, -32768)
        self.tand, self.txor = 0xFFFF, 0x8000
        self.rid = 0
        self.videoseg = 0
        self.grany = 0xFFFF
        self.granx10 = 0
        self.drawn = None
        self.cursor_at = 0xFFFF
        self.gc = (0, 0, 0, 0)              # gx, gy, rows, lr

    def getrid(self):
        r12 = self.crtc >> 8
        rid = r12 & 0x30
        if r12 & 0x20:
            rid = ((self.scr[0] & 0x7FF) * 2 + 1 + (0x1000 if r12 & 0x10 else 0)) & 0xFFFF
        return rid

    def detect(self):
        rid = self.getrid()
        if rid != self.rid:
            self.drawn, self.cursor_at = None, 0xFFFF
        self.rid = rid
        if not rid & 1:
            self.videoseg, self.grany, self.granx10 = self.scrseg, 0xFFF0, 10
            return
        self.grany, self.granx10 = 0xFFFF, 0
        base = self.scr[0] & 0x7FF
        ok = base <= 798 and all((self.scr[w] & 0x7FF) == base + d
                                 for w, d in ((1, 25), (50, 1), (49, 1225), (1249, 1249)))
        self.videoseg = rid - 1 if ok else 0

    def seen(self, x, y, w, h):
        if y + h <= 0 or y >= 400 or x + w <= 0 or x >= 800:
            return False
        return (y > self.lr[1] or y + h <= self.ul[1] or x > self.lr[0] or x + w <= self.ul[0])

    def restore(self):
        d, self.drawn = self.drawn, None
        if d is None:
            return
        self.cursor_at = 0xFFFF
        if self.getrid() != self.rid:
            return
        if self.grany == 0xFFFF:
            vm.restore(self.bmp, d['saved'])
        elif self.scr[d['word']] == d['new']:
            self.scr[d['word']] = d['old']

    def txtaddr(self, x, y):
        start = ((self.crtc >> 8) & 7) << 8 | (self.crtc & 0xFF)
        return 2 * ((start + (y // 16) * 80 + x // 10) & 0x7FF)

    def draw(self, x, y, force, hidden):
        if self.videoseg == 0:
            return
        if hidden:
            return self.restore()
        if self.grany == 0xFFFF:
            gx, gy = s16(x - self.hx), s16(y - self.hy)
            if not self.seen(gx, gy, 16, 16) or self.getrid() != self.rid:
                return self.restore()
            if self.drawn and self.gc[:2] == (gx, gy) and not force:
                return
            self.restore()
            if self.videoseg != self.bmpseg:
                raise RuntimeError('test would draw outside the test bitmap')
            ref = self.bmp[:]
            vm.render_pixels(ref, gx, gy, self.am, self.xm)     # independent per-pixel model
            saved = vm.render(self.bmp, gx, gy, self.am, self.xm, mirrored=self.mir)
            if ref != self.bmp:
                raise RuntimeError('oracle render != render_pixels at %d,%d' % (gx, gy))
            strip, sh = gx >> 4, gx & 15
            r0 = max(0, -gy)
            rows = min(16 - r0, 400 - (gy + r0))
            lr = (1 if gx >= 0 else 0) | (2 if sh and gx < 784 else 0)
            self.drawn = {'saved': saved}
            self.cursor_at = (strip * 800 + (gy + r0) * 2) & 0xFFFF
            self.gc = (gx, gy, rows, lr)
        else:
            if not self.seen(x, y, 10, 16) or self.getrid() != self.rid:
                return self.restore()
            di = self.txtaddr(x, y)
            if di == self.cursor_at and not force:
                return
            self.restore()
            w = di // 2
            old = self.scr[w]
            new = (old & self.tand) ^ self.txor
            self.scr[w] = new
            self.drawn = {'word': w, 'old': old, 'new': new}
            self.cursor_at = di

    def state(self):
        gx, gy, rows, lr = self.gc
        return (self.cursor_at, self.videoseg, self.rid, self.grany, self.granx10, lr, rows,
                gx & 0xFFFF, gy & 0xFFFF)

# ------------------------------------------------------------------------------------------------


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        if self.pos + n > len(self.data):
            raise EOFError('OUT.BIN ends at %d, need %d more' % (len(self.data), n))
        b = self.data[self.pos:self.pos + n]
        self.pos += n
        return b


def replay(cmds, data):
    m = Model()
    rd = Reader(data)
    stats = {'bmp': 0, 'scr': 0, 'state': 0, 'txtaddr': 0, 'granx': 0, 'draws': 0}
    fails = []

    def fail(tag, msg):
        fails.append('%s: %s' % (tag, msg))

    for op, a, b, c, d, payload, tag in cmds.list:
        if op == OP_CRTC:
            m.crtc = a
        elif op == OP_POKE:
            m.scr[a] = (b + (m.base if c else 0)) & 0xFFFF
        elif op in (OP_DETECT, OP_STATE):
            if op == OP_DETECT:
                m.detect()
            got = struct.unpack('<8H', rd.take(16))
            g = (got[0], got[1], got[2], got[3], got[4] & 0xFF, got[4] >> 8, got[5], got[6], got[7])
            want = m.state()
            # gc_* are only defined while a graphics cursor is drawn
            n = 9 if (m.drawn and m.grany == 0xFFFF) else 5
            stats['state'] += 1
            if g[:n] != want[:n]:
                fail(tag, 'state %s, want %s' % (' '.join('%04X' % v for v in g[:n]),
                                                 ' '.join('%04X' % v for v in want[:n])))
        elif op == OP_SETUPG:
            m.base, m.bmpseg, m.scrseg = struct.unpack('<3H', rd.take(6))
            m.crtc = 0x3000
        elif op == OP_SETMASK:
            m.am, m.xm, m.mir = payload[:16], payload[16:], False
        elif op == OP_DEFMASK:
            m.am, m.xm, m.mir = ARROW_AND, ARROW_XOR, False
        elif op == OP_HOT:
            m.hx, m.hy = s16(a), s16(b)
        elif op == OP_BOX:
            m.ul, m.lr = (s16(a), s16(b)), (s16(c), s16(d))
        elif op == OP_DRAW:
            stats['draws'] += 1
            m.draw(s16(a), s16(b), c, d)
        elif op == OP_DUMPBMP:
            got = vm.screen_from_bytes(rd.take(40000))
            stats['bmp'] += 1
            if got != m.bmp:
                diff = [i for i in range(len(got)) if got[i] != m.bmp[i]]
                i = diff[0]
                fail(tag, '%d words differ, first strip %d y %d: got %04X want %04X'
                     % (len(diff), i // 400, i % 400, got[i], m.bmp[i]))
                m.bmp = got                              # resync, keep going
        elif op == OP_DUMPSCR:
            got = list(struct.unpack('<2048H', rd.take(4096)))
            stats['scr'] += 1
            if tag == 'setup screen RAM':
                m.scr = got
                exp = [(m.base + (w % 50) * 25 + w // 50) | (((w * 7) & 0x1F) << 11)
                       if w < 1250 else (w * 13) & 0xFFFF for w in range(2048)]
                if got != exp:
                    fail(tag, 'fake screen RAM layout differs from the generator')
            elif got != m.scr:
                diff = [i for i in range(2048) if got[i] != m.scr[i]]
                fail(tag, 'words %s differ (got %s want %s)' % (
                    diff[:4], ['%04X' % got[i] for i in diff[:4]], ['%04X' % m.scr[i] for i in diff[:4]]))
                m.scr = got
        elif op == OP_TMASK:
            m.tand, m.txor = a, b
        elif op == OP_GRANX:
            got = struct.unpack('<%dH' % b, rd.take(2 * b))
            want = [(x // 10) * 10 if (a and c == 0) else x for x in range(b)]
            stats['granx'] += b
            if list(got) != want:
                bad = [x for x in range(b) if got[x] != want[x]]
                fail(tag, '%d values wrong, first X=%d -> %d' % (len(bad), bad[0], got[bad[0]]))
        elif op == OP_TXTADDR:
            di, cf = struct.unpack('<2H', rd.take(4))
            stats['txtaddr'] += 1
            guard = m.getrid() != m.rid
            if guard:
                if not cf:
                    fail(tag, 'mode guard not reported')
            elif cf or di != m.txtaddr(a, b):
                fail(tag, 'DI=%04X CF=%d, want %04X' % (di, cf & 1, m.txtaddr(a, b)))
        elif op == OP_LOADBMP:
            w = a
            for i in range(20000):
                w = (w * 25173 + 13849) & 0xFFFF
                m.bmp[i] = w
    if rd.pos != len(data):
        fails.append('OUT.BIN has %d extra bytes' % (len(data) - rd.pos))
    return stats, fails


def run_dosbox(work, cmds, inc=REPO):
    com = os.path.join(work, 'VTEST.COM')
    lst = os.path.join(work, 'vtest.lst')
    subprocess.run(['jwasm', '-q', '-c', '-bin', '-0', '-I' + inc, '-Fl=' + lst, '-Fo' + com,
                    os.path.join(HERE, 'vtest.asm')], check=True)
    with open(os.path.join(work, 'CMDS.BIN'), 'wb') as f:
        f.write(cmds.bytes())
    out = os.path.join(work, 'OUT.BIN')
    if os.path.exists(out):
        os.remove(out)
    with open(os.path.join(work, 'TEST.BAT'), 'w') as f:
        f.write('VTEST\r\nEXIT\r\n')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    subprocess.run(['timeout', '300', 'dosbox', '-c', 'mount c ' + work, '-c', 'c:', '-c', 'TEST.BAT',
                    '-c', 'exit'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--workdir', default=os.environ.get('TMPDIR', '/tmp') + '/ctmv9k_video_test')
    ap.add_argument('--no-run', action='store_true', help='only check an existing OUT.BIN')
    ap.add_argument('--seed', type=int, default=9)
    ap.add_argument('--inc', default=REPO, help='directory holding ctmv9k-video.inc (mutation tests)')
    args = ap.parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    cmds = build(random.Random(args.seed))
    if not args.no_run:
        run_dosbox(args.workdir, cmds, args.inc)
    out = os.path.join(args.workdir, 'OUT.BIN')
    if not os.path.exists(out):
        sys.exit('FAIL no OUT.BIN (VTEST.COM did not run)')
    with open(out, 'rb') as f:
        data = f.read()
    try:
        stats, fails = replay(cmds, data)
    except EOFError as e:
        sys.exit('FAIL %s' % e)
    for msg in fails[:40]:
        print('FAIL', msg)
    print('%d draw/hide calls; compared %d bitmap dumps, %d screen RAM dumps, %d state records, '
          '%d text addresses, %d granularity values: %s'
          % (stats['draws'], stats['bmp'], stats['scr'], stats['state'], stats['txtaddr'],
             stats['granx'], 'all ok' if not fails else '%d FAILED' % len(fails)))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
