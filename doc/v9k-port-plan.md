# CuteMouse for the Victor 9000: port plan

Status: being implemented phase by phase (section 10 records progress). Source of truth for the hardware is
`/root/sync/Victor9000-Software/mouse/` (`MOUSE_DRIVER.md`, `MOUSE.asm`). Emulation reference: the
MAME source tree at `/root/sync/bldmame1/src` (`devices/machine/z80sio.cpp` models the uPD7201,
`mame/act/victor9k.cpp` the machine). MAME assets: ROMs in `/root/sync/bldmame1/roms/victor9k`, disks in
`/root/sync/mame-files/victor9k/disks/` (section 9.2). Line numbers below are
for `ctmouse.asm` at commit 1d93f1e (5118 lines). Offsets come from a real build of that commit
(`%echo` of label differences, because `jwasm -Fl` aborts on this file).

## 1. Summary and goals

Build `CTMOUSEV.EXE`, a CuteMouse 2.1b4 derivative for the Victor 9000 / Sirius 1:

- serial Microsoft mouse (3-byte, 1200 baud 7N1), plus the Logitech 3-button and the MS wheel
  4th byte, on 7201 channel A or B (chosen on the command line, no default);
- the full CuteMouse INT 33h service layer, with coordinates in 0-799 x 0-399 in both video modes;
- a software text cursor and a 16x16 graphics cursor drawn into the 800x400 column-major bitmap;
- a drop-in for MOUSE.DEV/MOUSE.COM clients: PICASSO.EXE (`'MOUSE'` signature, fns 0-3, 7-9) and
  igc (fns 0, 1, 2, 5, 10);
- a resident size no larger than MOUSE.DEV's 3104 bytes; the target is about 2.6 KB including
  the PSP (section 7);
- runs on MS-DOS 2.11 and 3.1, needs an 8088 only, and can be unloaded with `/U`.

`ctmouse.asm` and the PC build stay byte-identical. `asmlib/` stays shared.

Baseline (PC build, measured): `TSRend - TSRstart` = 0C3Eh = **3134 bytes resident**, PSP
included. Uninitialized data fills PSP 1Eh-103h exactly, initialized data starts at 104h, and the
transient part is 0C3Eh-1212h plus messages (5863-byte .bin).

## 2. Disposition of `ctmouse.asm`

KEEP = copy unchanged (apart from deleting dead `if` branches). ADAPT = same structure, edited.
REPLACE = new Victor code in the same place. DROP = delete. Sizes are resident bytes in the PC
build.

| Lines | Section | Action | Reason |
|---|---|---|---|
| 1-36 | header, `CTMVER`/`CTMRELEASE`/`driverversion` | ADAPT | release string `2.1b4-V9K`; keep 705h |
| 41-47 | feature switches | ADAPT | keep `FASTER_CODE`/`OVERFLOW_PROTECT`/`FOOLPROOF`; delete `USE28`, `USERIL`, `PS2DEBUG`; add `USE_MSYS=0`, `USE_WHEEL=1`, `MODEGUARD=1`, `CHAIN41`, `HWCURSOR=0` |
| 51-69 | includes, `PIC1_OCW2`/`PIC1_IMR` | ADAPT | delete `bios/area0.def` (56), `count2x.mac` (62, prints only the I/O port), `mcb.def` (63, UMB only), `uart.def` (70), the PIC equates (68-69); add the V9K equates (section 3.1) |
| 72-122 | `USE_286`/`USE_386`, `_ARG_xx_`, `PUSHALL` | ADAPT | keep only the 8086 branch (93-121); add a build error if `@CPU and 4` |
| 124-131 | `nl`, `eos`, `POINT` | KEEP | |
| 132-181 | `PS2serv` macro + `PS2DEBUG` INT 29h tracing | DROP | no INT 15h |
| 183-203 | segments, `TSRstart`, `org 100h`, `TSRavail` | KEEP | |
| 205-273 | uninitialized data (`spritebuf` 211, SaveArea, ClearArea, `wheel` 269-270) | ADAPT | `spritebuf` (48 B at 1Eh) becomes the 64-byte graphics save buffer at 1Eh-5Dh; the state after it moves up 16 bytes (section 4.4); `wheel`/`wheelUIR` stay (`USE_WHEEL`, default 1) |
| 275-308 | RIL register shadow / `crtc` | DROP | the CRTC is at a fixed address |
| 310-313 | `oldint33`, `oldIRQaddr` | KEEP | `oldIRQaddr` holds the old INT 41h; add `oldIMR` (byte) |
| 316-369 | `DefArea` defaults | ADAPT | `mickey8` <8,8>, `startscan`/`endscan` FFFFh/8000h, arrow masks stored pre-mirrored (bit 0 = leftmost) |
| 371-384 | `granumask`, `textbuf`, `cursor@`, locks | KEEP | `videoseg` = F000h (text), bitmap seg (graphics) or 0 (no cursor) |
| 386-422 | `REGSET`, `vdata1/2`, `RGROUPDEF`, `videoregs@` | DROP | EGA/VGA register sets (~48 B) |
| 427-472 | `IRQhandler` (8250 LSR/RBR, `out 20h`) | REPLACE | `int41_isr` (section 3.3) |
| 474-602 | `enablePS2`, `disablePS2`, `setRateTSR`, `PS2handler` | DROP | 120 B |
| 604-712 | `enableUART`, `disableUART` | REPLACE | `enable7201`/`disable7201` (section 3.4), patched into `enableproc`/`disableproc` as today |
| 714-800 | `MSLTproc` | KEEP | MS/Logitech/wheel decoder (97 B); the wheel variant (`MSLTCODE3` = 2, patched at line 3950 after the PnP `'M','Z'` ID) stays |
| 802-851 | `MSMproc` | DROP → `if USE_MSYS` | 55 B; default off because it needs 8N1 port setup and a Mouse Systems mouse sends no PnP ID to detect |
| 853-882 | `reverseY`, `swapbuttons` | KEEP | `reverseY` is only reached from MSM/PS2, so it goes under `USE_MSYS` |
| 883-976 | `mouseupdate` | KEEP | wheel block 903-921 stays (`USE_WHEEL`) |
| 977-1110 | `updateposition` | ADAPT | delete the `USE_286` branches; the text-mode X granularity of 10 replaces `and al,granumask` at 1106 (section 4.3) |
| 1112-1146 | `updatebutton` | KEEP | |
| 1151-1521 | INT 10h handler + RIL F0-F7, FA | DROP | there is no INT 10h; 66 B, plus the RIL code that is already compiled out |
| 1524-1597 | `drawcursor` | ADAPT | hardware cursor path 1566-1585 goes under `HWCURSOR` (default 0: software cursor only); text height `si,8` (1546) → 16; mode guard |
| 1599-1637 | `restorescreen` | ADAPT | graphics branch calls `v9k_grestore`; `restorevregs` goes; discard (not restore) the saved background if the render target changed (4.1) |
| 1639-1794 | `graphcursor` | REPLACE | V9K strip renderer (section 4.4) |
| 1796-1832 | `restorevregs`, `updatevregs` (INT 10h F4/F5 at 1821), `restoresprite` | DROP | |
| 1834-2089 | `copysprite`, `makerow`, EGA GC save (2057-2089) | REPLACE | merged into the V9K renderer |
| 2091-2126 | `getgroffset` | DROP | folded into the renderer |
| 2128-2159 | `gettxtoffset` (BIOS `VIDEO_width`/`VIDEO_pageoff`) | REPLACE | CRTC start + row*80 + col, wrapped (section 4.2) |
| 2161-2213 | `checkifseen` | ADAPT | rewrite in pixel units (no `bitmapshift`, `scanline`) |
| 2218-2224 | `setupvideo` | KEEP | |
| 2226-2514 | `softreset_21` (BIOS mode table 2248-2482) | ADAPT | keep 2238-2246 and 2484-2514 (defaults, ranges, centre); REPLACE 2248-2482 with `v9k_detect_mode` (section 4.1) |
| 2516-2572 | `disabledrv_1F` | ADAPT | today `disableproc` (2536) runs **before** the ownership check (2550ff). Reorder: under `cli` check INT 33h and INT 41h segment **and** offset first; only then `disable7201` and restore vectors (3.4) |
| 2574-2615 | 18, 19, 00 | KEEP | |
| 2617-2654 | `enabledriver_20` | ADAPT | delete the INT 10h hook 2633-2652 |
| 2656-2768 | 03, 05, 06, 0B | KEEP | including the BH wheel counters |
| 2769-2789 | 11 `wheelAPI_11` | KEEP | `nullfunc` only if built with `USE_WHEEL` = 0 |
| 2790-2826 | 15, 1B | KEEP | |
| 2827-2842 | 1E `videopage_1E` (reads 0:462h) | ADAPT | always BX = 0 |
| 2844-2889 | 01, 02, `cursorstatus` | KEEP | |
| 2890-2938 | 07, 08 | ADAPT | FOOLPROOF only orders the endpoints: also clamp to 0-799 / 0-399 (~12 B, 4.3) |
| 2939-2975 | 04, `refreshcursor` | KEEP | |
| 2976-3038 | 09 `graphcursor_09`, `redrawcursor` | ADAPT | mirror each mask word while copying it (section 4.4) |
| 3039-3081 | 0A `textcursor_0A` (INT 10h AH=1 at 3059) | ADAPT | BX ≠ 0 falls back to the software cursor (documented deviation); CRTC R10/R11 only under `HWCURSOR` |
| 3082-3157 | 10, 16 | KEEP | |
| 3158-3186 | 17 `restorestate_17` | ADAPT | clamp the restored `rangemin`/`rangemax` like fn 7/8 |
| 3187-3369 | 0D, 0E, 14, 0C, 0F, 1A, `senscalc`, 13, `nullfunc` | KEEP | |
| 3370-3432 | `handler33table`, `handler33`, `rethandler` | ADAPT | insert `db 'MOUSE'` immediately before `handler33` (3410) |
| 3434-3577 | 23, 24, 26, 27, 31, 32, 4D, 6D | KEEP/ADAPT | 24: CL = 1 (IR1), CH = 2, port in DX (section 6); 26: constants 799/399 instead of `scanline`/`bitmapshift` |
| 3578-3613 | 28 (USE28, INT 10h) | DROP | |
| 3615-3638 | 2A | KEEP | |
| 3642-3648 | `msversion`, `IDstring`, `TSRend` | ADAPT | `IDstring` = `'CuteMouse V9K '` so the PC and V9K drivers cannot mistake each other |
| 3651-3678 | `.const` message include, `S_mousetype`, `options`, `OPT_*` | ADAPT | new option bits (section 5) |
| 3680-3849 | `real_start` | ADAPT | new install flow (section 5.2) |
| 3851-4003 | `setupdriver` | ADAPT | delete the VGA check 3857-3881 (INT 10h 1A00h); keep left-hand, button count and handler patching; save the old INT 41h |
| 4005-4123 | `searchCOM`, `COMloop`, `checkUART` | DROP | no COM search or UART probing |
| 4125-4267 | `detectmouse` (8250, `BIOS_timer` 46Ch) | REPLACE | 7201 init + 'M'/'3' detection (section 5.2) |
| 4269-4529 | `checkPS2`, `setRate`, `flushKBD`, `outKBD` | DROP | |
| 4531-4589 | `setCOMport` (0:400h), `setIRQ` | DROP | |
| 4591-4638 | `getCuteMouse`, `mousedrv` | ADAPT | call the old INT 33h only if it has the `'MOUSE'` signature; keep the exact-layout test (fn 4Dh offset = this build's `IDstring`, 4606) as the condition for in-place replacement (5.2) |
| 4640-4826 | option parsers, `OPTABLE` (4750-4768), `commandline` | ADAPT | new option table |
| 4827-4846 | `sayASCIIZ` | KEEP | INT 21h AH=02h |
| 4848-4885 | `unloadTSR` | ADAPT | today it falls into `EXITENABLE` (fn 20h) even after a failed fn 1Fh: after a refusal do not re-enable or touch INT 41h (5.3) |
| 4887-4937 | `prepareTSR` | ADAPT | in-place TSR only; delete the MCB/PSP copy for a relocated block |
| 4939-5091 | XMS (`if 0`), `SaveStrategy`, `RestoreStrategy`, `AllocUMB` | DROP | no UMB/XMS; INT 21h 5802h/5803h are DOS 5+ |
| 5093-5116 | `FreeMem` | KEEP | INT 21h 49h |

### 2.1 Inventory of PC-only touch points (all must go or be replaced)

| Kind | Lines |
|---|---|
| `int 10h` | 1821, 3059, 3596, 3598, 3605, 3860; vector get/set 2556, 2567, 2635; the handler itself 1165-1232 |
| `int 15h` | 151 (`PS2serv`), called at 489, 491, 512, 514, 527, 4293, 4295, 4296, 4314, 4316, 4344, 4382, 4453 |
| `int 11h` | 4288 |
| `int 29h` | 137-170 (`PS2DEBUG`) |
| `int 2Fh` | 4958, 4964 (XMS, inside `if 0`) |
| `in`/`out` | 444 (PIC EOI), 451, 455 (8250 IRQ), 631-666 (enableUART + IMR 662/666), 681-700 (disableUART), 1322-1332, 1506 (RIL), 1578, 1582 (CRTC cursor), 1874, 1877 (copysprite), 2003-2052 (makerow GC), 2063-2083 (GC backup), 4074-4118 (checkUART), 4145-4263 (detectmouse), 4482, 4515, 4526 (KBD, `if 0`) |
| BIOS data area (seg 0 / 40:xx) | 2116, 2139-2156, 2252-2310, 2392-2407, 2838-2839, 4183-4220 (`BIOS_timer`), 4478-4518 (`if 0`), 4549 (0:400h) |
| Video segments B800h/B000h/A000h | 2371, 2384, 1862, 1989, 2118, 2425-2426; A000h UMB tests 5028, 5055 |
| `USE_286` | 72, 79-122, 554, 578, 749, 757, 1020, 1034, 1059, 1079, 2147, 2397 |
| `USERIL` | 45, 275-308, 411-422, 1153-1163, 1174-1181, 1208-1229, 1234-1519, 1569-1573, 2254-2260, 2307-2347, 3862-3882 |
| `USE28` | 44, 3539-3543, 3578-3613 |
| `PS2DEBUG` | 47, 134-149, 153-173 |
| `OPT_*` | defined 3667-3677; used 3710-3769, 3897-3898, 3909-3910, 4015-4016, 4032-4033, 4244, 4318-4319, 4367-4368, 4651-4652, 4750-4767, 5024-5025 |
| Install-time code patches (keep the mechanism) | `call_ mouseproc` 467, `call_ disableproc` 2536, `jmp_ enableproc` 2653, `fixnear` 3939-3945, `fixcode MSLTCODE1-3` 3950-3961, `mouseinfo` 3455/3632/3737/3761 |

## 3. Hardware layer

### 3.1 Equates (all offsets in segment `IO_SEG` = E000h unless noted)

| Name | Address | Use |
|---|---|---|
| `PIC_OCW` | E000:0000 | 8259 OCW2; `PIC_EOI_IR1` = 61h (specific EOI, level 1) |
| `PIC_IMR` | E000:0001 | IMR; IR1 = bit 1 (mask 02h) |
| `PIT_CNT0` / `PIT_CNT1` | E000:0020 / 0021 | baud clock of 7201 channel A / B |
| `PIT_CTRL` | E000:0023 | 36h = counter 0, 76h = counter 1 (LSB+MSB, mode 3, binary) |
| `BAUD_COUNT` | 65 (0041h) | MOUSE.DEV value. viclibc2 assumes a 1.2288 MHz clock and uses 64; 65 gives 1182 or 1202 baud, so either clock is within 2% |
| `SIO_DATA_A` / `_B` | E000:0040 / 0041 | 7201 data |
| `SIO_CTRL_A` / `_B` | E000:0042 / 0043 | 7201 control (pointer byte, then value) |
| `CRTC_ADDR` / `CRTC_DATA` | E000:8000 / 8001 | HD46505 (= E800:0000/0001) |
| `SCREEN_SEG` | F000h | 2048 screen words: bits 10-0 font cell, 15-11 attributes, bit 15 = reverse (`v9kdiag/rom/ram_test.asm` `ATTR_REV`) |
| `IVT_INT41` | 0000:0104h | INT 41h vector (8259 base 40h + IR1) |
| VIA ORA / DDRA | E800:0041 / 0043 | bits 0-1 select the internal baud clock (viclibc2 `ser_hw_init_via`). MOUSE.DEV does not touch them and neither will we (see risks) |

7201 values: WR0 commands 18h channel reset, 10h reset ext/status, 30h error reset, 38h end of
interrupt (channel A register only, covers both channels). WR1 = 10h (Rx interrupt on every
character; Tx and ext interrupts off). WR2A = 14h. WR3 = 41h (Rx 7 bits, Rx enable, no
auto-enables). WR4 = 44h (x16, 1 stop, no parity). WR5 = E8h (DTR, Tx 8 bits, Tx enable, RTS off)
or EAh (RTS on). RR0: bit 0 Rx character available, bit 1 interrupt pending (channel A only),
bit 2 Tx empty, bit 3 DCD, bit 7 break. RR1: bit 4 parity, bit 5 overrun, bit 6 framing error
(`serial_hw.c` lines 83-93).

### 3.2 Initialisation (transient, polled, before INT 41h is hooked)

Port select: `ctrl = SIO_CTRL_A + port`, `data = SIO_DATA_A + port`.

1. `cli` (steps 1-5; pointer pairs as in 3.5). Read `ctrl` twice: a dummy RR0 read resets a
   register pointer that an interrupted program left set (viclibc2 `ser_init`).
2. `ctrl` ← 18h (channel reset of our channel only. Never reset the other one).
3. `PIT_CTRL` ← 36h/76h, then `PIT_CNTn` ← 41h, 00h.
4. `SIO_CTRL_A` ← 02h, 14h (WR2A, shared by both channels: the same value MOUSE.DEV and Kermit use).
5. `ctrl` ← 04h,44h; 03h,41h; 05h,E8h (RTS off: mouse unpowered); 10h; 01h,00h (no interrupts
   yet). `sti`.
6. Hold RTS off for 300 ms, timed with INT 21h AH=2Ch, and keep draining `data` while RR0 bit 0
   is set (MOUSE.DEV uses 65535 reads, roughly 0.4-0.5 s on a 5 MHz 8088). Bound this wait **and**
   the detection wait with an iteration cap as well, in case the DOS clock does not advance. Elapsed
   time = (now - start) in hundredths across the second/minute/hour fields, plus 8,640,000 if
   negative (midnight).
7. `ctrl` ← 05h,EAh (RTS on: the mouse powers up and sends `'M'`, a Logitech mouse `'M3'`).
8. Detection (section 5.2). On success the resident `enable7201` (called through fn 0 → fn 20h)
   finishes the job; there is no second power cycle.

`init` is never run from INT 33h. That fixes MOUSE.DEV bug 1: fn 0 with BX = 0 does not
power-cycle the mouse or call INT 21h.

### 3.3 ISR (`int41_isr`, INT 41h, entered with IF = 0)

`MSLTproc` stays a pure decoder. `mouseupdate` is split at line 944 into `mouseaccount`
(`updateposition`/`updatebutton`, IF = 0, ORs the event bits into a `pendevents` byte) and
`mousenotify` (the UIR call and `refreshcursor`, which STI). Everything that orders bytes runs
with IF = 0 **before** any EOI or chain. Only `mousenotify` runs afterwards, so a chained handler
that enables interrupts cannot get packets decoded out of order.

```
cld                          ; as CuteMouse line 431: the draw code uses stosw/movsw
push ds, es, PUSHALL ; ds = cs ; es = IO_SEG
mov  bx, ctrl                ; immediate patched at install (like IO_address today)
@@drain:                     ; our Rx FIFO holds up to 3 bytes: empty it completely
test byte es:[bx], 1         ; RR0 of our channel: Rx char available?
jz   @@drained
mov  byte es:[bx], 1         ; select RR1 (IF = 0, so the pointer pair is atomic)
mov  ah, es:[bx]             ; RR1 errors of the character at the FIFO top
test ah, 70h                 ; parity/overrun/framing
jnz  @@bad
mov  al, es:[bx-2]           ; data byte
call MSLTproc                ; decode; on a completed packet -> mouseaccount
jmp  @@drain
@@bad: mov byte es:[bx], 30h ; error reset BEFORE popping: the reset clears RR1 for the
mov  al, es:[bx-2]           ;  top character, so pop afterwards or the next bad byte
mov  [IOdone], 0             ;  reads as good (review finding); resync on the next sync byte
jmp  @@drain
@@drained:
mov  byte es:[bx], 30h       ; clear a special-receive condition left with an empty FIFO
                             ;  (an error latched while WR1 = 0 could hold INT asserted)
if CHAIN41                   ; default 0 until phase 3 (section 10)
  test byte es:[SIO_CTRL_A], 2 ; RR0A bit 1: any interrupt still pending, any channel
  jz   @@eoi                 ; ours is drained, so a pending one belongs to the other channel
  cmp  [chain_ok], 0 ; je @@eoi
  pushf ; call far [oldIRQaddr] ; owner services channel B/A and sends both EOIs
  jmp  @@notify
endif
@@eoi: 7201 EOI (WR0A = 38h) ; 8259 specific EOI 61h
@@notify: call mousenotify   ; loops while pendevents != 0; nested calls skip (UIRunlock)
jmp  rethandler              ; POPALL, pop es, pop ds, iret
```

- MAME `z80sio.cpp` 681-700 sets RR0A bit 1 for **any** pending interrupt on either channel and
  clears it only when none remain. A second byte in our FIFO keeps our own Rx interrupt pending
  (`advance_rx_fifo`, about 1900-1945), which is why the drain loop must come before the bit-1 test.
- With `CHAIN41` = 0 the behaviour is MOUSE.DEV's plus the RR0 check, the drain loop and the error
  reset. A foreign interrupt on the other channel is EOI'd and lost, as with MOUSE.DEV (bug 9). That
  is acceptable for phase 2.
- `chain_ok` (with `CHAIN41`) is set at install only if the old INT 41h vector is non-zero, does not
  point into the driver, and its first byte is not `IRET` (CFh). A chain into a stub that never sends
  EOI would leave IR1 in service and block the lower-priority interrupts.
- **The 8259 trigger mode** (measured in MAME with a Lua write tap on E0000h, phase 2 tooling):
  both the boot ROM and DOS 2.11 write ICW1 = 17h (LTIM = 0, **edge-triggered**, single, ICW4
  needed), ICW2 = 40h (IR1 = INT 41h), ICW4 = 01h; at the DOS prompt the IMR is B3h and the
  INT 41h vector is 0000:0000. Edge mode means a second channel's pending interrupt is not
  re-signalled after one EOI unless the 7201 INT line drops and rises again, which it does when
  the first channel's EOI (WR0A = 38h) lets the next pending source drive INT.

### 3.4 Resident enable/disable (fn 20h / 1Fh, and fn 0 through 20h)

- `enable7201`: `cli`; write `IVT_INT41` directly (no INT 21h inside INT 33h); drain our RR0/data;
  `ctrl` ← 01h,10h; `PIC_OCW` ← 61h; `PIC_IMR` &= FDh; `IOdone` = 0; `sti`. The specific EOI
  before unmasking copies MOUSE.asm line 1350: it clears an IR1 left in service or pending from
  before the hook, which would otherwise block IR1 (and the lower levels) after the unmask. It is
  idempotent and cheap, so fn 0 costs no I/O delay.
- `disable7201` (called only after the ownership check below): `cli`; `ctrl` ← 01h,00h; restore
  the INT 41h vector from `oldIRQaddr`; restore IMR bit 1 from `oldIMR` **only if** the vector we
  hand back is the one we found at install. If another INT 41h owner appeared in between, it may
  rely on IR1, and re-masking would cut it off. In that case IR1 is left unmasked. `sti`. RTS stays on
  for fn 1Fh as used by a reload. `/U` drops RTS afterwards (section 12).
- `disabledrv_1F` order: (1) `cli`; (2) INT 33h **and** INT 41h vectors must equal our
  segment:offset exactly; otherwise AX = FFFFh and return with **no** hardware or vector change;
  (3) only then hide the cursor, `disable7201`, restore vectors, set `disabled?`.

### 3.5 7201 register-pointer discipline

Every control access other than a plain RR0 read is a pointer write followed by a read or write,
on the same port. Each pair runs with IF = 0: inside the ISR implicitly, elsewhere as
`pushf`/`cli` … `popf` so the caller's IF is kept. This covers the WR2A write and the WR0A = 38h
EOI, which go through **channel A's** control port even when the mouse is on B, so they can collide
with the other channel's driver. The driver cannot repair a foreign transaction that it interrupts
(a pointer already written on the other channel's port by a program with IF = 1). The cooperation
it expects from a driver on the other channel: perform its own pointer/value pairs with interrupts
disabled (viclibc2 does: `ser_read_status_atomic`, serial.c 243), and not write WR2A to a different
value while we are resident. Document this in the README.

### 3.6 Open hardware questions

- WR2A bits 2-5: 14h (MOUSE.DEV, Kermit) vs DOS 10h. Check the NEC data sheet and `z80sio.cpp`;
  keep 14h, which is proven on hardware. Baud counter 64 vs 65: measure framing errors with both.
- 8259 ICW1 trigger mode (3.3) and the real chip's RR0A bit 1. VIA clock select is assumed
  internal; add `VIA_ORA &= FCh` behind a switch if a port is dead.

## 4. Video layer

### 4.1 Mode detection (`v9k_detect_mode`, called from fn 0/21h/20h via `@setvideo`)

`cli`; `CRTC_ADDR` ← 0Ch, `ah` = `CRTC_DATA` (R12); 0Dh, `al` = R13; `sti`. The HD46505 on the
Victor returns R12/R13 on reads, and MOUSE.DEV relies on this.

- R12 bit 5 = 0: **text**. `videoseg` = F000h, `granumask` Y = FFF0h, X granularity 10 (special
  case, section 4.3), cell height 16.
- R12 bit 5 = 1: **graphics**. `base` = word F000:0000 & 7FFh;
  `bitmap_seg` = (R12 bit 4 ? 1000h : 0) + 2*base. **Layout check** (a heuristic: a few samples
  cannot prove 1250 consecutive column-major cells): `base + 1249 ≤ 2047`, and for screen word
  w = r*50 + c, (word & 7FFh) = base + c*25 + r, sampled at w = 1 (base+25), 50 (base+1),
  49 (base+49*25) and 1249 (base+1249). If any test fails, `videoseg` = 0 and no cursor is drawn,
  instead of scribbling over an unknown layout (MOUSE.DEV bug 8). Granularity is 1/1.
- In both modes: `screenwidth` = 800, `screenheight` = 400, ranges 0-799/0-399, centre (400,200).
- `MODEGUARD` (about 30 bytes) covers drawing **and** restoring. The *render target id* is
  R12 bits 5-4 plus `bitmap_seg` (graphics) or 0 (text). Reset records it. Every draw stores it
  with the saved background. Before a draw: if the current R12 bits 5-4 differ from the reset
  value, skip drawing. Before a restore (hide, move, reset, unload): if the current id differs from
  the one stored with the background, **discard** the background (mark not drawn) instead of
  writing it back. A bit-5-only check would miss a font-bank (bit 4) switch. Apps must still call
  fn 0 after switching mode, as MOUSE.DEV requires (PICASSO does), but a forgotten reset no
  longer corrupts the screen.

### 4.2 Text cell address (replaces `gettxtoffset`)

`start` = ((R12 & 07h) << 8) | R13, read at draw time because the console scrolls by moving it.
`word` = (start + (Y/16)*80 + X/10) AND 07FFh, `DI` = 2*word in F000h. The wrap mask fixes
MOUSE.DEV bug 7. Y/16 is a shift; X/10 is one `div` (X ≤ 799).

### 4.3 Granularity

CuteMouse's `granumask` is an AND mask applied to the low byte (line 1106), so it only works for
power-of-two cells. In text mode X has to round to multiples of 10. MOUSE.DEV does this, and igc
divides by 10 itself. Add `granX10` (byte flag) and, at `@savecutpos`, for the X axis in text mode
use `ax = (ax/10)*10` (`div`/`mul` by a byte constant, about 18 bytes). Y keeps the mask (F0h).
As lines 1105-1107 already do, `pos` stays unrounded and only `granpos` gets the rounded value.
**Bounds**: `@savecutpos` (1095-1106) clamps to `rangemin`/`rangemax`, and FOOLPROOF fn 7/8
(2890-2938) only orders the endpoints. A negative range would therefore reach the unsigned `div`
and overflow it (MOUSE.DEV bug 11). So fn 7, fn 8 and fn 17h (restore state) clamp `rangemin` and
`rangemax` to 0-799 / 0-399 (about 12 bytes), and `pos` can then never be negative.

### 4.4 Cursors

**Software text cursor** (CuteMouse's existing path, lines 1587-1597): save the word, write
`(w AND startscan) XOR endscan`. The defaults are AND FFFFh and XOR 8000h (reverse video, the
same values igc sets). `restorescreen` already restores only if the cell is unchanged (1625-1633),
so a console scroll does not leave stale images.

**Hardware text cursor**: compile switch `HWCURSOR`, default **0**. The 6845 cursor belongs to the
console, and owning R10/R11/R14/R15 properly (saving and restoring shape and position, the
drawn-state marker at 1566-1583, the interaction with hide/reset/unload) costs more than it is
worth for a cursor igc does not use. With `HWCURSOR` = 0, fn 0Ah with BX ≠ 0 stores the request and
uses the software cursor with the current masks. This is a documented deviation from the MS API
(decided, section 12). With `HWCURSOR` = 1 (not built): R10/R11 = CL/DL & 1Fh; R14/R15 = full 14-bit start +
row*80 + col (no 7FFh mask, because the 6845 compares the whole MA); save R14/R15 at the first draw
and write them back on hide.

**Graphics cursor** (`v9k_gcursor`, replaces 1639-2126):

- Masks: fn 9 copies the 32 user words and mirrors each one (16× `shr ax,1`/`rcl dx,1`, about
  20 bytes) into `screenmask`/`cursormask`. `DefArea` holds the arrow already mirrored. The fn 9
  "shape unchanged" comparison (2991-3011) mirrors before comparing, or is removed. SaveArea
  (fn 16h/17h) then holds mirrored masks, which is internal state and fine.
- Position: `gx = X - hotspot.X`, `gy = Y - hotspot.Y` (signed). Not seen if `gx ≤ -16`,
  `gx ≥ 800`, `gy ≤ -16` or `gy ≥ 400`. This test is part of `checkifseen` in pixel units, together
  with the fn 10h exclusion box.
- `strip = gx SAR 4` (-1..49), `sh = gx AND 15`, rows r0 ≤ r < r1 with `r0 = max(0,-gy)` and
  **exclusive** `r1 = min(16, 400-gy)`.
- Per row r, with `m` = AND mask word and `c` = XOR mask word:
  `andL = (m << sh) | ((1<<sh)-1)`, `andR = (m >> (16-sh)) | (FFFFh << sh)`,
  `xorL = c << sh`, `xorR = c >> (16-sh)` (for `sh` = 0 the right word is skipped). Use CL shifts.
  `off = strip*800 + (gy+r)*2`. The left word goes to `[off]` if `strip ≥ 0`, the right word to
  `[off+800]` if `strip+1 ≤ 49`.
- **Left-edge fix** (MOUSE.DEV bug 3): `strip` = -1 (gx in -15..-1) means only the right word is
  drawn, with the same shifted masks, so the visible columns are the correct ones. Rows above the
  top or below the bottom are skipped by `r0`/`r1`; there are no dead `cmp ax,0` tests.
- Save buffer: 16 rows × 2 words = **64 bytes**, replacing `spritebuf` (`org PSP_TSR-3*16`,
  1Eh-4Dh). Keep the origin at **1Eh**: the buffer becomes 1Eh-5Dh, `SaveArea`/`mickey8` moves from
  4Eh to **5Eh**, and the rest of the uninitialized state shifts up 16 bytes (16 resident bytes).
  Do **not** move the origin down to 0Eh: PSP 0Ah-15h hold the INT 22h/23h/24h vectors DOS restores
  at exit (`psp.def`). 18h-2Bh (JFT) and 2Ch (env) are reused, as today. (As built: the 9 bytes of
  renderer/detect state `V9K_UDATA` follow the buffer, so `SaveArea` is at 68h, not 5Eh; still
  nothing below 1Eh. Layout is checked from the binary by `tools/ressize.py`, not by `.errnz`.) Next to it go
  `gc_off` (word), `gc_r0`, `gc_rows`, `gc_lr` (bit 0 left valid, bit 1 right valid) and the
  render target id (4.1). Restore writes back exactly the saved words.
- Cost on a 5 MHz 8088: about 16 rows × ~120 clocks ≈ 0.4 ms per draw plus the same for restore,
  well inside the 8.3 ms byte time at 1200 baud.

### 4.5 Mode change

There is no INT 10h to hook. fn 0 and fn 21h re-run detection, and fn 20h does too through
`setupvideo`. Document that applications must call fn 0 (or 21h) after changing the CRTC mode and
hide the cursor before they switch. `MODEGUARD` (draw and restore, 4.1) is the safety net.

## 5. Command line and transient part

### 5.1 Syntax

```
CTMOUSEV /SA | /SB [/3] [/L] [/R[h[v]]]      CTMOUSEV /U      CTMOUSEV /?      (bare A or B also accepted)
```

`/SA`/`/SB` = serial port A or B, reusing CuteMouse's `/S` slot. **There is no default**: without a
port the driver prints the usage screen and exits 1, as MOUSE.COM does. `/U` and `/?` need no port. A bare `A`/`B` word is
also accepted, for `MOUSE A` habits. `/3` forces 3-button MS mode, `/L` is left-handed, `/R[h[v]]`
is unchanged (`_resolution`, `senscalc`), `/U` unloads, `/?` shows help, and `/M` (Mouse Systems)
exists only with `USE_MSYS`.

Dropped: `/P /V /O /W /N /Y` (PC-only) and `/B`. `/B` would read as "port B" here; refusing to
install over an existing driver is the default behaviour (5.2). Exit codes: 0 installed or
unloaded, 1 usage (incl. no port given) or refusal, 2 no mouse or failed unload.

### 5.2 Install and reload

Parse the command line first: no `/SA`/`/SB` (and not `/U`/`/?`) → usage screen, exit 1, nothing
touched. Then **classify INT 33h** (INT 21h 35h). Never call a stray vector: on the Victor it is often null or
garbage (igc `mouse.c` 72-74).
- Null, or offset < 5: no driver. No `'MOUSE'` 5 bytes before the entry: an unknown handler. Warn
  that it will be replaced, as MOUSE.COM does, and never call it.
- `'MOUSE'` present: preset ES:DI = 0 and call fn 4Dh (MOUSE.DEV ignores AL > 16). **Ours** only if
  DI equals this build's `IDstring` offset and the string matches. This is CuteMouse's exact-layout
  test (`getCuteMouse`, line 4606) and the condition for copying a new image over the resident one;
  a name match alone is not enough. Other `'MOUSE'` drivers (MOUSE.DEV/COM, or an older CTMOUSEV
  layout): "already installed", exit 1. `mousedrv` only ever calls an "ours" vector.

**Transaction 1, fresh install** (no driver or unknown handler):
1. Save the INT 41h vector and `oldIMR`; compute `chain_ok`.
2. Hardware init (3.2) and **detection**: for up to 2.0 s (bounded as in 3.2 step 6), poll RR0
   bit 0 with WR1 = 0 and read up to 4 bytes, using `detectmouse`'s PnP logic (4234-4250): `'M'` = Microsoft,
   `'M','3'` = Logitech 3-button, `'M','Z'` = wheel (mouse type 83h: `MSLTCODE3` = 2, `wheelmask`,
   `wheelflags`, and the banner adds "(wheel present)" via `S_wheel`, as the PC build does). Any traffic at all counts as present, as in
   MOUSE.COM. Silence prints "No mouse detected on serial port X", does WR1 = 0 and a channel reset
   (RTS drops) and exits 2. Nothing was hooked, so nothing else changes.
3. `setupdriver`: patches, stores the old INT 41h in the image, copies the image in place, then calls
   fn 0 with the existing far-return trick (fn 0 → fn 20h → `enable7201`).
4. INT 33h ← `handler33` (25h), print "Installed at serial port X in Microsoft/Logitech mode [(wheel present)]", close
   handles 0-19 (3Eh), free the environment (49h), INT 21h 31h with DX = (TSRend-TSRstart+15)/16.

**Transaction 2, reload over ours** (the "Resident part reset to" path, 3768-3776):
- **Same port**: skip init and detection, because the resident driver already proved a mouse.
  Prepare all patches first, then call fn 1Fh **immediately before** the copy. If fn 1Fh refuses
  (foreign owner), exit 2 with the old driver untouched and still running. Otherwise copy and fn 0.
- **Other port**: init and detect on the new channel (polled, WR1 = 0, nothing hooked) while the old
  driver keeps running on its channel. Never reset the channel the old driver is using. (Caveat from
  review: a *channel A* reset also resets the 7201's shared interrupt logic, so moving from B to A
  may drop one pending byte of the old driver; it resyncs on the next sync byte, and the old
  driver is replaced moments later, so this is accepted and not worked around; the README advises
  `/U` first when the old port must keep working until the switch. Unproven on silicon.) On failure,
  WR1 = 0 and a reset of the *new* channel only, exit 2: the old driver is still working. On success,
  fn 1Fh, then copy and fn 0, as for the same port.

The cursor stays hidden (`nocursorcnt` = 1) until an application calls fn 1, so the reused PSP area
(DOS 2.x keeps the JFT at 18h and SS:SP at 2Eh) is only written after the TSR exit. Keep it that
way: nothing below 5Eh except the save buffer, and nothing at all below 1Eh.

### 5.3 Unload (`/U`)

`getCuteMouse` (exact-layout test) → fn 1Fh, which checks ownership first (3.4). **Refused**:
print "unload failed", exit 2, and do **not** fall into `EXITENABLE`. Today `unloadTSR` (4848-4885)
calls fn 20h unconditionally, which would re-hook INT 41h over the new owner. **Accepted**:
restore INT 33h from the returned ES:BX, `FreeMem` (49h on the resident PSP segment), then a
channel reset (RTS off, section 12), exit 0.

### 5.4 INT 21h functions used (all DOS 2.0+)

02h (char out), 25h/35h (vectors), 2Ch (time), 31h (TSR), 3Eh (close), 49h (free env and unload),
4Ch (exit). `.exit` is 4Ch. Not used: 48h/58h (UMB), 5802h/5803h (DOS 5), 62h (DOS 3),
INT 2Fh, INT 10h, INT 15h.

## 6. Compatibility notes

- **PICASSO**: `'MOUSE'` 5 bytes right before the INT 33h entry (`handler33`). It uses fns
  0, 1, 2, 3, 7, 8, 9 with pixel coordinates and the column-major bitmap. All are covered, and fn 9
  hot spots are signed (MOUSE.DEV default is -1,-1; CuteMouse default 0,0 is fine).
- **igc**: uses fn 0 with BX = 1 (fine, fn 0 never re-initialises the hardware), fn 10 BX = 0
  FFFFh/8000h, fn 5 BX = 0/1 (same as CuteMouse, which also has 2 = middle), positions /10, /16.
- **AH ≠ 0**: CuteMouse ignores INT 33h calls with AH ≠ 0 (line 3413); MOUSE.DEV ignores AH (CBW).
  Low risk; note it in the README.
- **`port_index` at entry+0A9Ch** (igc `mouse.c` line 30). CuteMouse's entry `handler33` sits near
  the end of the image, so entry+0A9Ch is outside the TSR. **Unchanged igc reads a word from beyond
  the image**, gets a value that is not 0/1, and reports the port as unknown. That only disables its
  guard against offering the serial file server on the mouse port, but it is wrong. Reproducing the
  offset would need an entry stub plus about 500 bytes of padding. Instead, fn 24h keeps BX = 0705h,
  CH = 2, CL = 1 (IR1) and also returns **DL = port (0 = A, 1 = B), DH = 'V' (56h)**. igc presets
  DX = 0, calls fn 24h and uses DL when DH = 'V', falling back to the 0A9Ch read for MOUSE.DEV/COM.
  **Decided** (user): this interface, and the igc patch is a release dependency of the port.
- Default mickey ratio 8/8 (MOUSE.DEV) instead of 8/16 (applied; the first build kept 8/16). Acceleration is CuteMouse's sensitivity
  curve and double-speed threshold (**decided**), not MOUSE.DEV's |d|>2 doubling (which has bug 2).
  `/R` tunes it.
- Program name **`CTMOUSEV.EXE`** (decided). INT FBh (MOUSE.DEV's private API) is not implemented:
  it has no known client.

## 7. Memory budget (resident, bytes): a target, not a result

| Component | PC (measured) | V9K target | Notes |
|---|---|---|---|
| PSP + uninitialized overlay | 260 | 300 | save buffer +16 (4.4), `oldIMR`, `gc_*`, render id, `pendevents`; `crtc` gone, `wheel` kept |
| Initialized data | 150 | 110 | RIL tables (~48) gone; + port, `bitmap_seg`, `granX10`, `chain_ok` |
| Serial ISR | 50 | 100 | drain loop, RR1 error reset, two EOIs, `CHAIN41` (+~15) |
| PS/2 code | 120 | 0 | |
| 7201 enable/disable + ownership checks | 84 | 90 | direct IVT writes, EOI before unmask, conditional IMR restore |
| `MSLTproc` | 97 | 97 | |
| `MSMproc` | 55 | 0 | (+55 with `USE_MSYS`) |
| `reverseY`..`updatebutton` | 284 | 315 | wheel kept, X/10 +18, account/notify split +10 |
| INT 10h handler | 66 | 0 | |
| `drawcursor` + `restorescreen` | 154 | 150 | no hardware cursor (`HWCURSOR` = 0) |
| Render-target guard (`MODEGUARD`) | 0 | 30 | draw and restore (4.1) |
| Graphics renderer + restore | 577 | 300 | the least certain figure |
| Mode detect + layout check | 325 | 170 | 4 samples + bound (4.1) |
| `checkifseen` | 60 | 50 | pixel units |
| fns 1F, 18, 19, 00, 20 | 119 | 100 | no INT 10h hook |
| Services 03-1E | 456 | 500 | fn 9 mirroring; range clamps in 7/8/17h (+12); fn 11h and BH wheel counters kept |
| Table + `handler33` + 23-6D + signature | 240 | 250 | `'MOUSE'`, fn 24h DX |
| ID strings | 16 | 20 | |
| **Total** | **3134** | **≈2585** | ≈ 162 paragraphs (wheel +35); ceiling 3104 (0C20h) |

MOUSE.DEV is 3104 bytes without a PSP and MOUSE.COM 3360 with one. Phase 2 assembles the hardware
layer and records **actual** sizes. The renderer estimate is revised from those numbers before
phase 4 starts. Size reporting and gate: `ctmv9k.asm` stores a `RESSZ` marker (`dw TSRend-TSRstart`,
`dw LIMIT`) in its transient data and `tools/ressize.py` (run by `make v9k`) reads it from the built
`.bin` and fails above `LIMIT`. (Phase 0 finding: the assembler's `if`/`%echo` see pass-1 addresses,
3108, while the final size is 3134, so a source-level gate is unreliable.) `LIMIT` = 0C40h in
phase 0 (the byte-identical fork is 0C3Eh) and 0C20h from phase 1 on. The same marker carries
`TSRdata`/`TSRavail` and the script fails if the initialized data would overlap the entry `jmp`:
the original `if (TSRdata lt TSRavail) / ORG TSRavail` guard does not fire under JWasm (phase 1
shrank the uninitialized data to 102h and the build hung).

## 8. Build changes

```make
V9KFLAGS=-c -bin -0          # independent of ASFLAGS, the V9K build is 8086-only

v9k: ctmousev.exe

ctmousev.exe: ctmv9k-en.msg ctmv9k.asm bin2exe
	$(AS) $(V9KFLAGS) -D\?LANG=ctmv9k-en -Foctmousev.bin ctmv9k.asm
	./bin2exe -s 512 ctmousev.bin ctmousev.exe

PC_BASE=1d93f1e              # pinned baseline commit, not HEAD
verify-pc: ctmouse.exe        # PC build must stay byte-identical to the pinned baseline
	git show $(PC_BASE):ctmouse.exe > ctmouse.ref
	cmp ctmouse.exe ctmouse.ref || { rm -f ctmouse.ref; exit 1; }
	rm -f ctmouse.ref
```

The recipe must fail when `cmp` fails. A trailing `; rm` would mask its status.

- `clean`: add `ctmousev.exe`. `alllang` and the `%.exe` pattern rule stay as they are. The explicit
  rule wins for `ctmousev.exe`, and nobody should ask for `ctmv9k-en.exe`.
- `ctmv9k-en.msg`: same `%include ?LANG.msg` mechanism and macros, with its own labels (banner,
  `Syntax`, errors, `E_mousedev`, `E_nomouse`, `S_port`, `S_inMS`/`S_inLT`, ...). `S_wheel` stays. The PS/2, COM
  and VGA strings go. English only at first.
- `ctmousev.bin` is already a valid .COM image (`org 100h`). Ship the .EXE for consistency, and
  optionally also `CTMOUSEV.COM`.
- `ctmouse.asm`, `ctm-*.msg` and `asmlib/` are never edited. `make verify-pc` is the gate for every
  phase. Update `CLAUDE.md`/README with the new target when phase 0 lands.

## 9. Test plan

### 9.1 Tools to write

- `tools/v9kmouse.py` (host, Python 3): opens MAME's pty (`MamePtyConnection` from
  `viclibc2/serial/python`, or pyserial). It encodes MS packets
  (`0x40|L<<5|R<<4|(dy>>6&3)<<2|(dx>>6&3)`, `dx&63`, `dy&63`) and the Logitech 4th byte (`0x20` =
  middle, sent with **every** packet while the middle button is held: `MSLTproc` treats a sync
  byte arriving right after byte 3 as a middle-button release; the wheel byte is bit 4 = middle,
  bits 3-0 = signed wheel nibble, always present in `MZ` mode). Modes: `--hello` (repeat `'M'`/`'M3'`/`'MZ'`: the pty cannot see RTS), `--script` (deterministic
  move/press/sleep), `--burst` (several bytes back to back, to fill the FIFO), `--garbage` (resync),
  `--interactive`. It also holds the per-pixel cursor oracle for test 17.
- `utility/v9kmt.asm` (NASM .COM, INT 21h output only: `mousetst.asm` uses INT 10h and will not
  run on the Victor). It checks the signature like igc, then loops printing fn 3, fn 5/6 counts, fn
  0Bh, fn 24h (incl. DL/DH), fn 4Dh string, and exercises fns 7/8/9/0Ah/10h/16h/17h/1Fh/20h on keys.
- DOSBox harness: copy `/root/sync/Victor9000-Software/mouse/dosbox_test/harness.asm` + `run.sh`
  (INT 08h hook that pokes RR0 bit 0 and a data byte into E000:0042/0040 to simulate a mouse).

### 9.2 MAME `victor9k`

Assets: MAME build `/root/sync/bldmame1/mame`, ROMs `/root/sync/bldmame1/roms/victor9k`, a
working config `/root/sync/bldmame1/cfg/victor9k.cfg` (it sets rs232a to terminal/sync_io, so use
a copy), and disk images in `/root/sync/mame-files/victor9k/disks/`. DOS 2.11 candidates that carry
PORTA.EXE/PORTB.EXE (checked with `strings`): `dos211-2.img` (PORTA 2.4), `dos211-american-hd.img`
(PORTA 2.4), `disk264-dos211Hj.img` and `dos211-brit-nohd.img` (PORTA 2.1/2.3), `dos211.img`.
DOS 3.1: `dos31-orig-disk1.img`. **Use `dos211.img`: the user confirmed it boots and carries PORTA.EXE.**

```sh
cp -r /root/sync/bldmame1/cfg $SCRATCH/cfg
/root/sync/bldmame1/mame victor9k -rompath /root/sync/bldmame1/roms -cfg_directory $SCRATCH/cfg \
    -flop1 /root/sync/mame-files/victor9k/disks/dos211.img -flop2 work.img -rs232a pty
```

(Use `-rs232b pty` for port B.) Set the pty to **1200 baud, 7 data bits, no parity, 1 stop** in the
slot configuration menu, which stores `:rs232a:pty:RS232_TXBAUD`/`RS232_RXBAUD` = 04h,
`RS232_DATABITS` = 02h, `RS232_PARITY` = 00h, `RS232_STOPBITS` = 01h (`bus/rs232/pty.cpp` 56-60,
`rs232.h`) in the copied cfg. The defaults are 9600 8N1. 7N1 matters: an 8N1 frame puts a 0 data
bit where the 7201 expects the stop bit, which gives framing errors. The host feeder finds the pty
with `find_mame_pty()` from `/root/sync/bldmame1/scripts/victor9k_serial_test.py` (lines 68-110:
`pgrep mame`, then the pts slaves that are not a controlling terminal). It opens the pty with
pyserial, as `SerialTester` does (lines 118-141), but with `bytesize=SEVENBITS` at 1200. The pty
does not carry modem-control lines (lines 268-276), hence `--hello`. (Implemented: `tools/mame/run.sh`
finds the ptys from MAME's `/dev/ptmx` fds via `/proc/<pid>/fdinfo` `tty-index`; the newest-pts
heuristic is ambiguous with two pty ports. Port A is the lower fd. Text cells are ASCII + 64h.)
Scenarios:


| # | Test | Pass criterion |
|---|---|---|
| 1 | install on A with `--hello`, then on B | banner names the port; fn 24h DL = 0/1 |
| 2 | no port argument; then install with no host script | usage + errorlevel 1; "No mouse detected", errorlevel 2, INT 41h/IMR unchanged |
| 3 | scripted moves/clicks | fn 3 positions and buttons, fn 5/6 counts/positions, fn 0Bh mickeys exact |
| 4 | `--garbage`; bursts that leave 2-3 bytes queued in the FIFO per interrupt | resync; no lost or reordered bytes (drain loop) |
| 5 | text cursor at the DOS prompt, then `dir` scrolls | no stale reverse cells; follows the CRTC start; wraps at 2048 words |
| 6 | fn 0Ah BX = 1 | software cursor used (deviation, `HWCURSOR` = 0); console cursor untouched |
| 7 | PICASSO: cursor at all four edges, hot spot X > cursor X | correct left-edge columns (bug 3), no corruption right/bottom |
| 8 | igc (patched per section 6): click, double-click, port shown | same behaviour as with MOUSE.COM |
| 9 | `/U` then reinstall; install twice (same port, then other port) | memory freed (48h FFFFh before/after); same port = reload without detection |
| 10 | Logitech `M3` + middle button; `MZ` wheel mouse (4th byte); `/3`; `/L` | button bits correct; "(wheel present)"; fn 11h, fn 3 BH and fn 5/6 BX = -1 wheel counters |
| 11 | fn 0Fh CX = 0; fn 7/8 with negative or >799/>399 ranges; fn 17h with such a saved state; then motion and fn 4 | clamped to the screen, no divide fault (bug 11) |
| 12 | mode change (text ↔ graphics, and a font-bank R12 bit 4 switch) with the cursor visible, then hide and fn 0 | saved background discarded, not written into the new screen |
| 13 | failed reload: reload on the other port with no mouse there | exit 2; the old driver still works on its port |
| 14 | refused unload: a test TSR hooks INT 41h (or 33h) after us, then `/U` | "unload failed", our vectors, IMR and the other owner untouched, no fn 20h re-hook |
| 15 | fn 0Ch/14h handlers that call fn 1/2/0 from inside the callback while packets keep arriving | no deadlock, no stale image, cursor level consistent |
| 16 | **INT 41h sharing** (`CHAIN41` = 1): PORTA.EXE/PORTB.EXE (DOS 2.11) loaded for the other port, traffic on both at once | both receive everything. viclibc2 `sertest` cannot serve here: it is polled and never hooks INT 41h (serial_hw.c 194, serial.c 24) |
| 17 | graphics oracle: draw at gx = -15..15 and 785..799 (all 16 shifts), gy edges, both font banks (R12 bit 4); dump the bitmap via the MAME debugger | matches a host Python per-pixel model of AND/XOR and of restore |

### 9.3 Real hardware

A Victor 9000 with a Microsoft-compatible serial mouse wired per MOUSE.DOC (TD, RD, RTS on Sirius
pin 4, GND; RTS powers the mouse). Run under MS-DOS 2.11 and 3.1, on both ports, with PORTA.EXE/PORTB.EXE
(or PORTA.DEV/PORTB.DEV under DOS 3.1) active on the other port. Repeat tests 1, 2, 5, 7-10, 12
and 16. Measure the baud counter
(64 vs 65) and the `'M'` timing after RTS rises. WR2A and the real RR0A bit 1 are settled only here.

### 9.4 What DOSBox can and cannot do

It can test: option parsing (incl. no port), INT 33h classification (DOSBox's own driver has no
signature), the no-mouse path, install with a simulated `'M'`, TSR size, reload, `/U` and refused
`/U` (simulated 13/14). It cannot test: E000h is plain RAM, there is no 7201/8253/8259/INT 41h,
CRTC reads return RAM, DOS reports 5.0, and F000h is ROM, so **never show the cursor**.

## 10. Phases

Every phase ends with `make v9k verify-pc` passing and the `%echo` resident size recorded in the
commit message.

| Phase | Work | Ends with |
|---|---|---|
| 0 | Fork `ctmouse.asm` → `ctmv9k.asm`, `ctm-en.msg` → `ctmv9k-en.msg`, Makefile targets, size marker + `tools/ressize.py` gate, `LIMIT` = 0C40h | identical driver under a new name; resident 3134 (done, c9000ee) |
| 1 (done, e8c926b, resident 1838) | Strip: PS/2, INT 10h/RIL, USE28, PS2DEBUG, USE_286, UMB/XMS, COM search/UART probe, `setCOMport`/`setIRQ`; `USE_MSYS` (0) / `USE_WHEEL` (1); video stubbed (`videoseg` = 0); BIOS reads gone; `LIMIT` → 0C20h | assembles; no `in`/`out`, no `int 1[015]h` left; size recorded |
| 2 (done, 9e8fc38 + fixes 11a37b4/4c32f1b, resident 2128 before video) | Hardware layer with `CHAIN41` = 0: equates, ISR with drain loop and error reset, account/notify split, `enable7201`/`disable7201`, ownership-first fn 1Fh, pointer discipline, init + bounded detection, install/reload transactions, fixed `/U`, `/SA /SB`, `'MOUSE'`, fn 24h DX, range clamps, messages, `v9kmt.com`, `v9kmouse.py`, DOSBox harness | DOSBox tests; MAME 1-4, 9-11, 13-15 (no cursor); **actual sizes recorded, renderer budget revised** |
| 3 | INT 41h sharing: `CHAIN41` = 1, `chain_ok`, conditional IMR restore; trace the 8259 ICW1 in the MAME debugger | MAME 16 with **PORTA.EXE**/PORTB.EXE from the DOS 2.11 disk as the fixture; keep the switch off by default if it fails |
| 4 (done with 5, 27d8c05) | Text video: mode detect, render-target id, cell address with wrap, X/10, software cursor, fn 0Ah fallback, pixel `checkifseen`, fn 26h constants | MAME 5, 6, 8 (patched igc), 12 (text part) |
| 5 (done, ed47f50 + 27d8c05, resident 2588 total) | Graphics: layout check, strip renderer and restore, fn 9 mirroring, pre-mirrored defaults, `MODEGUARD` on restore | MAME 7, 12, 17 (PICASSO, oracle); size ≤ 0C20h |
| 6 | Release: igc change merged (section 6), README/CLAUDE.md, `HWCURSOR`/RTS decisions applied | real-hardware run (9.3) |

### 10.1 Findings while implementing (2026-10-12)

- The 7201 delivers bit 7 = 1 in 7-bit mode (MAME `z80sio.cpp` ~2475; MOUSE.asm 876 masks with 3Fh).
  The ISR and the detection poll mask with 7Fh. Without it every motion byte read as a large
  negative value and `M3`/`MZ` were never recognised.
- Victor DOS leaves INT 33h at FFFF:FFFF at boot; it is classified as "no driver".
- fn 0Bh returns mickeys after CuteMouse's acceleration curve (|d| ≤ 4 unchanged, 5-11 → d·|d|/4,
  ≥ 12 → ×3), not the raw sum; the MAME tests model that.
- MAME's natural keyboard sometimes drops doubled letters or leaves Shift on; test scripts type
  lowercase.
- Tests 5, 6, 7, 17 pass in MAME (`tools/mame/tests/video`: 117/117 bitmap dumps equal the oracle
  under PICASSO at all 16 shifts on both edges and all corners; the text cursor follows the CRTC
  start across 11 scrolls incl. the 2048-word wrap; fn 0Ah BX=1 never writes R10/R11/R14/R15).
  Test 12 passes but PICASSO hides the cursor before switching, so the MODEGUARD discard path is
  only covered by the DOSBox oracle test. The Victor BIOS scroll copies the bottom row's column-0
  attribute into the new line, so a cursor parked there during a scroll leaves a reverse cell
  (documented in the README; not a driver bug). Font bank R12 bit 4 = 1 is untested in MAME.
- PORTA.EXE/PORTB.EXE are polled CONFIG.SYS drivers (WR1 = 0, never touch INT 41h or the IMR), so
  they coexist with the default build; `bits(7)` writes WR3 = A1h, which MAME decodes as 6 bits.

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Chaining (RR0A bit 1, 8259 trigger mode, an old handler without EOI) | lost interrupts or a hang | `CHAIN41` off until phase 3 proves it; `chain_ok` heuristics; ICW1 traced, not assumed |
| A foreign driver interrupted mid pointer pair, or writing WR2A | wrong 7201 register written | cannot be repaired by us; documented cooperation (3.5) |
| CRTC R12/R13 read semantics (HD46505 variant) | wrong mode/start | MOUSE.DEV already depends on it on real hardware |
| Graphics layouts other than PICASSO's | no cursor, or a false positive of the heuristic | layout check (4.1) turns the cursor off; document |
| Renderer larger than 300 bytes | size over target | phase 2 measurements; the 0C20h gate stays hard |
| Fork drift from upstream CuteMouse fixes | maintenance | keep banner names, order and labels so `diff ctmouse.asm ctmv9k.asm` stays readable |
| Mouse needs more than 300 ms RTS-off | no `'M'` | the delay is a constant; any later traffic still counts as detection |

## 12. Decisions

All open questions were decided by the user on 2026-10-12:

- Wheel support kept (`USE_WHEEL` = 1); Mouse Systems stays a compile switch, default off.
- No default port: `/SA`, `/SB` or a bare `A`/`B` is required to install.
- igc is patched to read the port from fn 24h (DL = port, DH = 'V'); release dependency.
- Program name `CTMOUSEV.EXE`.
- No INT FBh private API.
- CuteMouse's own sensitivity curve.
- **Hardware text cursor dropped** (`HWCURSOR` = 0): fn 0Ah with BX != 0 falls back to the software
  cursor. The 6845 cursor is the console's only cursor, the save/restore state would cost 60-80
  bytes, and no known client uses it.
- **`/U` drops RTS** (mouse powered off, port quiet): a channel reset after `disable7201` in the
  transient unloader, ~6 bytes. Reload keeps RTS on.

## 13. Concerns with the given decisions

1. **Port selection** (decision 3): superseded by the user. There is no default port, and
   `/SA`/`/SB` is required, like MOUSE.COM. This avoids the A-versus-B ambiguity between
   MOUSE.DOC and the MOUSE.DEV binary.
2. **Mode detection only at reset** (decision 5): agreed, but only with the render-target guard on
   both draw and restore, and the layout check (4.1).
3. **Text granularity 10x16** (decision 5) breaks the power-of-two `granumask` and needs range
   clamps to keep the `div` safe (4.3).
4. **Hardware text cursor** (decision 5, "optional"): recommend `HWCURSOR` = 0 (4.4, 12).
   The software default differs from MOUSE.DEV's hardware default; igc sets fn 10 explicitly.
5. **Chaining INT 41h** (decision 4): the riskiest item, so it has its own phase and switch (`CHAIN41`).
6. **Fork instead of ifdef** (decision 1): agreed. A shared include for the service layer
   (2574-3639) would touch `ctmouse.asm`, so it is out of scope.
7. **Wheel** (decision 2): reversed by the user. It is kept on by default, at about 35 resident bytes.
   **Mouse Systems** stays a switch, default off: it needs 8N1 and sends no PnP ID to detect.
8. **Footprint** (decision 7): ≈2.6 KB (wheel kept) is a target. The 3104-byte gate is the hard limit.
