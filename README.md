# ctmouse_v9k
Work on a port to Victor 9000 DOS and hardware

## CTMOUSEV: CuteMouse for the Victor 9000 / Sirius 1

`make v9k` builds `ctmousev.exe` from `ctmv9k.asm`, `ctmv9k-video.inc` and `ctmv9k-en.msg`. It is a
CuteMouse 2.1b4 derivative for the Victor 9000's own hardware (uPD7201 serial, 8259 at E000:0000,
HD46505 CRTC, 800x400 column-major bitmap) and needs only an 8088 and MS-DOS 2.0+. The design is in
`doc/v9k-port-plan.md`.

```
CTMOUSEV /SA | /SB [/3] [/L] [/R[h[v]]]     install on serial port A or B (bare A or B also works)
CTMOUSEV /U                                 unload (powers the mouse off: RTS drops)
CTMOUSEV /?                                 help
```

- Microsoft serial mice (1200 baud 7N1), Logitech 3-button (`M3`) and Microsoft wheel (`MZ`) mice
  are detected automatically; `/3` forces 3-button mode for a plain MS mouse, `/L` is left-handed,
  `/R` sets the sensitivity. There is no default port: without `/SA` or `/SB` the usage is printed.
- Exit codes: 0 installed or unloaded, 1 usage or refusal (already installed, unknown option),
  2 no mouse detected or unload refused.
- Coordinates are pixels, 0-799 x 0-399, in both text and graphics mode. The text cursor is a
  software reverse-video cell (10x16 granularity); fn 0Ah with BX != 0 (hardware cursor request)
  is accepted but still draws the software cursor. The graphics cursor is drawn into the bitmap
  that the CRTC start address and font bank select; applications must call INT 33h fn 0 (or 21h)
  after changing the display mode, as with MOUSE.DEV.
- Compatible with MOUSE.DEV/MOUSE.COM clients: the 5-byte `MOUSE` signature precedes the INT 33h
  entry, and fn 24h additionally returns DL = port (0 = A, 1 = B), DH = 'V' for programs that need
  the port (igc uses this). INT 33h calls with AH != 0 are ignored (CuteMouse behaviour).
- Known console interaction: the Victor BIOS scroll routine copies the attribute of the bottom
  row's column 0 into the new line, so a mouse cursor parked on that cell while the console scrolls
  leaves a reverse-video cell the driver does not own (seen in MAME, test 5). Move the cursor or
  hide it (fn 2) before long scrolling output.
- Resident size is about 2.5 KB including the PSP (MOUSE.DEV: 3.0 KB); `tools/ressize.py` gates it.
- Reinstalling over a running CTMOUSEV reloads it in place (same port: no re-detection). Moving the
  mouse from port B to A resets 7201 channel A, which also touches the chip's shared interrupt
  logic; unload first (`/U`) if the old port must keep working until the switch. Another
  INT 41h owner installed after the driver makes `/U` refuse, as it should.
- The other 7201 channel can be used by polled software while the driver is loaded; Victor's
  PORTA.EXE/PORTB.EXE device drivers are polled and coexist. Another **interrupt-driven** owner of
  INT 41h (a program that enables 7201 receive interrupts on the other channel) is not supported by
  the default build: the driver EOIs every INT 41h itself, and because the 8259 is edge-triggered
  and the 7201 INT line stays high while any source is pending, both the mouse and the other owner
  stop until a reboot. `make v9k-chain41` builds `ctmousev-chain41.exe`, which chains to the previous
  INT 41h owner; it works in MAME and awaits confirmation on real hardware. Polled users must perform
  their pointer/value register pairs with interrupts disabled and must not change WR2A; the 7201
  end-of-interrupt goes through channel A's control port even when the mouse is on B.

Test tooling: `tools/dosbox/run.sh` (headless DOSBox smoke test), `tools/mame/` (headless MAME
`victor9k` harness: boot, type, dump screen/memory, drive B: images), `tools/v9kmouse.py` (serial
mouse feeder for MAME's pty and the graphics-cursor oracle), `tools/video/` (renderer oracle test),
`utility/v9kmt.com` (INT 33h test client that runs on the Victor).

# CuteMouse

CuteMouse is a small open source DOS mouse driver, developed from 1997 to 2009 by Nagy Daniel, Eric Auer, and many others. The project is hosted on [SourceForge](https://cutemouse.sourceforge.net) and released under the terms of the GNU General Public License (GPL).

This repository hosts a version of CuteMouse v2.1b4 converted to compile with Jwasm 2.12 on a modern Linux or Mac OS host. Beside requiring a DOS environment to be compiled, the original version was incompatible with 8088/8086 CPUs since it used a few 286 instructions. I have fixed this incompatibility to make the driver compatible with every x86 CPU.

## License

* CuteMouse ant this repository as a whole are distributed under the terms of the GPL version 2. See the `copying` file for more details. 
* `bin2exe.c` is a modified version of the `bin2exe` utility included in [booterify](https://github.com/raphnet/booterify), developed by Raphaël Assenat and distributed under the MIT License.

