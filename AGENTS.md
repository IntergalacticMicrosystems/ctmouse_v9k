# AGENTS.md

Instructions for any coding agent (Claude Code, Codex, Grok Build, ...) working in this repository.
Read at the start of every session, so keep it short: one line per fact.

Before the final message of any task that changed repo files or ran the project's
build/test/run commands, emit one `AGENTS.md proposal` block or the line
`AGENTS.md: no change proposed.` See "Continuous improvement" below.

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
make v9k          # ctmousev.exe, the Victor 9000 driver (ctmousev.asm + ctmousev-en.msg)
make verify-pc    # PC build must be byte-identical to the pinned PC_BASE commit (gate for every V9K change)
make alllang      # ctm-<lang>.exe for every ctm-*.msg
make clean        # removes .bin/.exe intermediates (keeps bin2exe)
make distclean    # also removes bin2exe and all ctm-*.exe
```

`make v9k` runs `tools/ressize.py`, which reads the `RESSZ` marker (resident size, `LIMIT`) from
`ctmousev.bin` and fails the build when the resident part exceeds `LIMIT`. The assembler's own
`if`/`%echo` cannot be used for this: they see pass-1 addresses, which are short of the final size.

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

## Victor 9000 port

The port is a fork: `ctmousev.asm` + `ctmousev-en.msg` build `ctmousev.exe`; `ctmouse.asm`, `ctm-*.msg`
and `asmlib/` are never edited (`make verify-pc`). The design, hardware map, dispositions of every
section of `ctmouse.asm`, phases and test plan are in `doc/v9k-port-plan.md`; read it before
changing `ctmousev.asm`. Hardware references live outside the repo in
`/root/sync/Victor9000-Software/mouse/` (annotated MOUSE.DEV disassembly) and the MAME source.
Keep section banners, label names and ordering aligned with `ctmouse.asm` so the two files diff
readably.

## Working rules

- Prefer the simplest solution that works. If a simpler approach exists, propose it first.
- Do not change behaviour outside the task's scope without saying so.
- Before reporting done: if Build/Test above are real commands (not placeholders), run them and
  quote any failure verbatim. Say which checks were not run.

## Lessons learned

- (none yet)

## Continuous improvement

**When:** after a top-level task (not a subagent, not a question, not search-only work) that
changed repo files or ran the project's build/test/run commands. Applying an approved AGENTS.md
change does not itself trigger another retrospective.

**Review** what this task taught about this project: a command, flag, path or setup step found
by trial and error; a tool, library or hardware quirk that cost time; a convention the user
stated or corrected; a line in this file that proved wrong, stale or redundant.

**Filter.** Propose only a fact that is useful on a future task in this repo, not already in
this file, and not obvious from the README, manifest or file names (a buried gotcha is fine).
A user correction is always eligible, even if it is now visible in code. Filling or fixing a
Project placeholder is eligible when the fact is known. Never record global style preferences,
secrets, or one-off task details. At most one proposal per task; prefer `change` or `remove`
over `add`. The first lesson replaces the "(none yet)" line.

**Propose, then stop.** End the final message with exactly one of:

```
AGENTS.md proposal
Section: <Project | Working rules | Lessons learned>
Action: <add | change | remove>
Replaces: <exact existing line; "(none)" for add>
Line: <exact new line; "(none)" for remove>
Why: <one sentence: what happened that makes this worth keeping>
```

or the single line `AGENTS.md: no change proposed.` Do not wait within the turn.

**Approval.** Edit this file only when the user directly answers the proposal (yes / apply /
revised wording). A new task, "ok" followed by other work, or silence means skip: do not edit
and do not re-ask. Apply exactly the approved text, in the named section (merge, do not append
at the bottom). Never re-propose a rejected item unless new evidence appears.

**Size.** Lessons learned holds at most 40 entries and Project at most 10 lines, one line each.
If a proposal would exceed that, include a removal in the same proposal. If a project needs
more, the overflow belongs in the README, not here.
