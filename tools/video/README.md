# tools/video: DOSBox test of the V9K video layer

`ctmv9k-video.inc` (repo root) is the Victor 9000 video layer from plan sections 4.1-4.5:
`drawcursor`, `restorescreen`, `checkifseen` (pixel units), `v9k_gcursor` / `v9k_grestore`
(the strip renderer), `v9k_txtaddr` (text cell address, replaces `gettxtoffset`),
`v9k_getrid` (render target id, used by MODEGUARD), `v9k_detect_mode`, and the macros
`V9K_UDATA`, `V9K_DEFMASKS`, `V9K_GRANX` and `V9K_MIRRORCOPY`. The header of the include lists
the glue that `ctmv9k.asm` needs.

## Run

```sh
tools/video/check.py [--workdir DIR] [--no-run] [--seed N] [--inc DIR]
```

Needs `jwasm`, `dosbox` and python3. It builds `VTEST.COM` from `vtest.asm` (which includes the
real `ctmv9k-video.inc` with `V9K_TESTCRTC`, so R12:R13 come from a variable, and with
`V9K_SCRSEG` pointing at fake screen RAM), writes the test matrix to `CMDS.BIN`, and runs
DOSBox headless (`SDL_VIDEODRIVER=dummy`, `TEST.BAT` = `VTEST` + `EXIT`). Then it replays the
same commands on a Python model of the routines and compares every dump in `OUT.BIN` (about
67 MB). Exit code 0 means everything passed. A run takes about 4 s. `--inc DIR` builds against
another copy of the include; it was used for the mutation check below.

DOSBox has no Victor hardware, so:

- The bitmap is a 40000-byte buffer at `1000h + 2*base`. `base` is chosen from CS so that
  the buffer lies above the program.
- The fake screen RAM after it holds the column-major cell layout (cell = base + c*25 + r,
  with attribute bits 15-11 set) so that `v9k_detect_mode` can run its layout check.
- The real CRTC access in `v9k_getrid` (E000:8000/8001 under pushf/cli/popf) is not run here.
  It was checked by code review and still needs a test in MAME.

## Model

The model in `check.py` reproduces drawcursor, restorescreen, MODEGUARD, detect, txtaddr and
granx. Every graphics draw uses `v9kmouse.render` (masks in fn 9 order, so `V9K_MIRRORCOPY` is
tested too) and is also checked against the independent `v9kmouse.render_pixels`. Every
restore uses `v9kmouse.restore`. The default arrow is the upstream CuteMouse DefArea in fn 9
order, compared with the asm's pre-mirrored `V9K_DEFMASKS`.

## Test matrix (seed 9)

| Area | Content |
|---|---|
| graphics sweep | 1000 positions with a random 16x16 AND/XOR mask (hot spot 7,-2), in random order (each draw moves the cursor from the previous one). gx = -16..16 and 783..800 plus 100, 397 and 555, crossed with gy in {-16,-15,-8,-1,0,1,200,383,384,390,399,400}. Also gy = -15..0 and 384..399 crossed with gx in {-15,-9,-1,0,7,8,400,784,785,791,799}. Full bitmap dump and state record (cursor@, gc_x/gc_y, gc_rows, gc_lr) after each draw. Every 5th: the same position again unforced (no change) and forced. Every 3rd: hide and dump (restore). |
| default arrow | 6 positions, including 799,399 |
| fn 10h box | 120 positions around a box at (100,100)-(200,150) |
| MODEGUARD | R12 switched to text, the bitmap base moved (screen word 0), the font bank bit 4 switched: no draw, and the background is discarded, not restored. After switching back, drawing resumes. Detect discards the background when the id changes. |
| detect | graphics with bit 4 = 1 and = 0, attribute bits in word 0, each of the 4 layout samples wrong and then fixed, an unsampled word wrong (the heuristic passes, as designed), base 799 (> 798), text |
| text cursor | 5 start addresses (0, 510h, 7F0h, 7FFh, 6B0h) x 8 cells, including wrap at 2048, plus hide. The update box. A cell changed by the console is not restored. The restore after a console scroll goes to the drawn address. MODEGUARD (bit 4) in text mode. Masks FFFF/8000 and 77FF/7700. |
| txtaddr | 63 (start, X, Y) cases, including X = 795, 799 and the wrap, plus the guard (graphics R12 while in text mode -> CF) |
| V9K_GRANX | X = 0..2559 in text mode, Y axis untouched, graphics mode untouched |

Result: 1929 draw/hide calls. Compared 1670 full bitmap dumps, 54 screen RAM dumps, 1592 state
records, 64 text addresses and 4160 granularity values. **All OK.**

Mutation check: each of these single changes to the include made the test fail:

- xor fill
- restore offset
- text wrap mask
- right edge bound
- strip-50 check
- restore guard
- one layout sample
- granx axis test

## Assembled sizes (real CRTC path, `-0`)

| Routine | Bytes |
|---|---|
| `v9k_gcursor` (renderer, including the "unchanged" check and the mode guard) | 233 |
| `v9k_grestore` | 36 |
| **renderer + restore** | **269** |
| `v9k_detect_mode` + `v9k_lchk` table | 91 + 16 |
| `v9k_getrid` (CRTC read + id, shared with guard and txtaddr) | 62 |
| **mode detect total** | **169** |
| `checkifseen` | 47 |
| `drawcursor` | 83 |
| `restorescreen` | 38 |
| `v9k_txtaddr` | 42 |
| part 2 total (all procs + table) | 648 |
| `V9K_GRANX` (inline in @savecutpos) | 18 |
| `V9K_MIRRORCOPY` (inline in fn 9) | 16 |
| `V9K_UDATA` (uninitialized) | 9 |

To get these numbers, assemble a wrapper that defines the driver variables and includes both
parts, then read the "Procedures" table of the listing (`jwasm -Fl`).
