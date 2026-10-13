# MAME victor9k test harness

Headless MAME `victor9k` for testing CTMV9K: boot DOS 2.11, type commands, read the screen as
text, dump memory, attach serial port A and/or B to a host pty at 1200 baud 7N1, and put files
on a second floppy.

Defaults (override with env): `MAME=/root/sync/bldmame1/mame`, `ROMS=/root/sync/bldmame1/roms`,
`FLOP1=/root/sync/mame-files/victor9k/disks/dos211.img` (a fresh copy is booted every run, so the
original is never written), `V9K_RUN=${TMPDIR:-/tmp}/v9kmame` (cfg, nvram, snapshots, pty names),
`VTG_DIR=/root/sync/bldmame1` (holds the `vtg_image_util` Python package).

## Files

- `run.sh`: starts MAME headless (`-video none -sound none -noplugins`, DISPLAY unset, SDL dummy driver; `-w` for a window), writes a fresh cfg with the pty
  slot settings, prints the pty paths.
- `screen.lua`: autoboot script; runs a command file (`-c`, see its header for all commands).
- `mkdisk.sh`: builds a Victor SS floppy image from files or a directory.
- `blankss.img.gz`: blank SS floppy formatted by Victor FORMAT (from the v9k_flop project).

## Typical run

```sh
tools/mame/mkdisk.sh /tmp/b.img ctmv9k.exe utility/v9kmt.com     # drive B:
cat > /tmp/t.cmd <<'X'
waittext >
waitidle 1
type DIR B:\n
waitidle 2
screen -
peek 104 4
exit
X
tools/mame/run.sh -f -p A -2 /tmp/b.img -c /tmp/t.cmd
```

`run.sh` options: `-p A|B|AB` pty ports, `-2 img` drive B:, `-c cmds`, `-f` no throttle,
`-w` open a window (WSLg works), `-k secs` hard kill (default 600). Extra MAME args go after `--`
(e.g. `-- -ramsize 256K`; the default is 128K).

Without `exit` in the command file, MAME keeps running (use it with a pty feeder); `-k` or
`kill` stops it. MAME ignores SIGTERM in this mode, hence `timeout -s KILL`.

## Command file (screen.lua)

`wait s`, `waittext str`, `waitidle [s]`, `type text` (`\n` RETURN, `\\` backslash),
`screen file|-`, `screenraw file|-`, `mem addr len file`, `peek addr len`, `poke addr bytes`,
`regs`, `items devtag`, `watchw addr len`, `watchr addr len`, `unwatch`, `snap`, `sh cmd` (os.execute;
end with `&` to background it, e.g. a pty feeder), `waitfile path [sec]` (wall clock, for syncing
with a host feeder that touches a flag file), `print text`, `exit`. Tests: `tools/mame/tests/run_test.sh`.
The natural keyboard sometimes drops a doubled letter (HOOK -> HOK) or keeps Shift for a digit after
a capital (V9KMT -> V(KMT): type lowercase and avoid doubled letters in commands.
Addresses and lengths are hex, linear (F0000 = F000:0000). Output lines start with `[v9k]`.

- Text screen: 2048 words at F0000, display start = CRTC R12:R13 (read from the MC6845 save
  state item `m_disp_start_addr`, not by writing the CRTC address register), 25 rows of 80,
  wrapping at 2048 words. The console font cell is ASCII + 100 (64h); bits 15-11 are attributes.
  Non-ASCII cells (the VICTOR logo, boxes) show as `.`.
- `snap` writes a PNG to `$V9K_RUN/snap/victor9k/` even with `-video none`.
- The graphics bitmap and font cells live in system RAM (MAME: byte address =
  `R12bit4 * 10000h + cell * 20h + row * 2`), so `mem` dumps them.
- `watchw` uses a Lua write tap. Given as the first command it is armed before the boot ROM
  runs. Device save items: `items :11a` (CRTC), `items :16e:cha`, `items :rs232a:pty`.

## Serial ports

`-p A` adds `-rs232a pty` (`-p B`: `-rs232b pty`) and writes into the cfg:

```xml
<port tag=":rs232a:pty:RS232_TXBAUD"   type="CONFIG" mask="255" defvalue="7" value="4" />
<port tag=":rs232a:pty:RS232_RXBAUD"   type="CONFIG" mask="255" defvalue="7" value="4" />
<port tag=":rs232a:pty:RS232_DATABITS" type="CONFIG" mask="255" defvalue="3" value="2" />
```

Encoding (`src/devices/bus/rs232/rs232.h`): baud 04h = 1200 (07h = 9600 default), data bits
02h = 7 (03h = 8 default), parity 00h = none and stop bits 01h = 1 are already the pty defaults
(`bus/rs232/pty.cpp` 56-60). The pty device's save items confirm it: `m_df_word_length = 7`, and
the bit timer runs at half a 1200-baud bit period.

The pty slave is not printed by MAME. `run.sh` finds it from `/proc/<mame pid>/fdinfo/<fd>`
(`tty-index:`) of the `/dev/ptmx` fds. A is opened before B, so the lower fd is A (verified: a
host write to the A pty moves only `:rs232a:pty` `m_tra_*`). The paths are printed
(`port A: /dev/pts/5`) and written to `$V9K_RUN/pty_a`/`pty_b`. Open them at 1200 7N1, e.g.
`serial.Serial(open(run + "/pty_a").read().strip(), 1200, bytesize=7)`. The pty has no modem lines,
so the mouse cannot see RTS. Host reads fail with "returned no data" once MAME exits.

## Timing

DOS 2.11 reaches `A:\>` about 13 emulated seconds after power-on: about 2 s wall clock with `-f`,
about 13 s throttled. With `-f`, host pty bytes are still consumed at the emulated 1200 baud.

## What does not work / caveats

- `ECHO X>AUX` at the DOS prompt sends nothing to either pty (DOS 2.11 AUX does not set up the
  7201 at 1200 7N1, or uses another device); only host to Victor was verified, which is the
  mouse direction.
- `vtg_image_util create` writes a disk label without the zone tables; DOS then reports
  "Read fault error reading drive B". `mkdisk.sh` starts from `blankss.img.gz` instead.
- Files are copied byte for byte: give text files CR LF line ends.
- `waittext` and `waitidle` give up after 60 s and 120 s of emulated time (`TIMEOUT` is logged).
- The `/root/sync/bldmame1/plugin.ini` enables `mcpplugin` (TCP control on port 12345);
  `run.sh` passes `-noplugins` and runs from `$V9K_RUN`, so it neither loads it nor clashes.

## Boot facts read with this harness

- 8259 (E0000h/E0001h), boot ROM at FFD0:0127: ICW1 = 17h, ICW2 = 20h, ICW4 = 01h, then IMR
  tests AAh/55h/FFh and specific EOIs 60h-67h. DOS (19E1:16F0) repeats ICW1 = 17h, ICW2 = 40h
  (IR1 = INT 41h), ICW4 = 01h, then IMR = FFh and B3h. ICW1 17h: bit 3 LTIM = 0, so
  **edge-triggered**, cascade off (single), ICW4 needed; ICW4 01h: 8086 mode, normal EOI (no AEOI),
  not buffered. Command: `watchw E0000 2` as the first line.
- At the DOS prompt: INT 41h vector (0:104h) = 0000:0000; IMR = B3h (IR1 masked); DOS toggles
  IMR B2h/B3h (IR0) around disk access.
