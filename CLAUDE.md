# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CuteMouse v2.1b4, a DOS mouse driver (TSR) written in 16-bit x86 assembly, converted from TASM to
JWasm and made 8086/8088-compatible. The repo's goal is a port to the Victor 9000 (non-IBM-compatible
DOS machine). No Victor-specific code exists yet; everything is still IBM PC hardware (8250 UART,
8259 PIC, INT 15h PS/2, BIOS data area at 40:xx, CGA/EGA/VGA video memory).

GPL-2 project. `bin2exe.c` is MIT (from booterify).

## Build

Tools: GNU make, `jwasm` (v2.12+; v2.17 is installed), `gcc`. Open Watcom (`wlink`, `exe2bin`) is
at `/opt/watcom/binl64`; `nasm` and `dosbox` are also installed.

```sh
make              # builds bin2exe, then ctmouse.exe (English messages)
make alllang      # ctm-<lang>.exe for every ctm-*.msg
make clean        # removes .bin/.exe intermediates (keeps bin2exe)
make distclean    # also removes bin2exe and all ctm-*.exe
```

Pipeline: `jwasm -c -bin -0 -D?LANG=ctm-en -Foctmouse.bin ctmouse.asm` produces a flat .COM-style
binary, then `./bin2exe -s 512 ctmouse.bin ctmouse.exe` wraps it in an MZ header. `-0` targets the
8086; switch to `-2` in `ASFLAGS` for 286 code (enables `pusha`/`popa` via `USE_286`).

`ctmouse.exe` is committed. A clean build must be byte-identical to it unless you intentionally
changed the driver; use `cmp` to check.

There are no automated tests. Verification means running the built driver in DOSBox or real hardware
and exercising INT 33h (e.g. with `utility/mousetst.com`).

`utility/Makefile` is currently broken (`clean` target at line 65 is missing its colon) and expects
Watcom `wlink` for comtest/protocol and `nasm` for mousetst. Build individual utilities by hand if needed.

## Source layout

- `ctmouse.asm` (~5100 lines) is the whole driver. Language strings come from `ctm-<lang>.msg`,
  pulled in via `%include ?LANG.msg` with `?LANG` set on the jwasm command line.
- `asmlib/` holds the TASM-era macro/definition library (`asm.mac`, `macro.mac`, `dos/*.mac`,
  `hard/uart.def`, `bios/area0.def`, ...). Include paths are lowercase and relative to the repo root
  (case-sensitive FS fix).
- `utility/` holds standalone DOS tools: `comtest` (COM port detection), `protocol` (serial protocol
  analyzer), `mousetst` (NASM, INT 33h test client).
- `doc/` is the upstream documentation. `doc/jwasm.txt` is required reading before touching
  assembler syntax: it lists the TASM to JWasm differences and workarounds used throughout the source
  (hand-encoded `db` for `xchg`/`sbb` operand order, `::` global labels, no `testflag`/`setflag`,
  no multi-arg `push`/`pop`, `even` pads with 0FCh so `db 0` is used instead, etc).

## Driver architecture (ctmouse.asm)

Single `.model tiny` DGROUP; `org 100h`, `start: jmp real_start`. The file is ordered
resident-first, transient-last:

1. **Resident (TSR) part**, `TSRstart` to `TSRend` (~line 200 to ~3650): uninitialized and
   initialized data, IRQ handlers (PS/2 via INT 15h callback, serial via UART IRQ, Microsoft/Logitech
   and Mouse Systems packet decoders), cursor drawing (text and graphics modes, with video register
   save/restore), the INT 10h hook, and the INT 33h dispatcher with one routine per function (section
   banners are `; NN - description`). Data must stay below `TSRavail`/`TSRdata` limits; there is an
   `if (TSRdata lt TSRavail)` build-time check.
2. **Transient part** after `TSRend` (`.const`/`.data`/`real_start`): the `.msg` strings, command
   line parsing, COM port and PS/2 detection, UART probing, installation (copies the resident block
   to a fresh conventional or UMB/XMS block, patches the PSP, terminates via TSR), and unload (`/U`).

Compile-time feature switches are at the top of the file: `FASTER_CODE`, `OVERFLOW_PROTECT`,
`FOOLPROOF`, `USE28`, `USERIL` (EGA register interface, marked `-X-`), and `PS2DEBUG` (prints
INT 15h traffic through INT 29h). `USE_286`/`USE_386` derive from `@CPU`, i.e. from the jwasm `-0`/`-2`
flag, and gate the `PUSHALL`/`POPALL` macros and the `_ARG_xx_` stack offsets.

Registers' stack-frame offsets (`_ARG_AX_` etc.) differ between the 8086 and 286 builds. Any new code
reading caller registers must use those equates, never literal offsets.

## Porting notes

When adding Victor 9000 support keep the IBM paths buildable; prefer a compile-time switch in the
style of `USERIL`, or a separate `.asm`/`.msg` target in the Makefile. Hardware touch points to
replace are the UART I/O in the serial IRQ path, PIC mask/EOI (`PIC1_OCW2`/`PIC1_IMR`), the INT 15h
PS/2 calls (`PS2serv` macro), BIOS data area reads from `area0.def`, and the video memory/CRTC code
in the cursor drawing sections.
