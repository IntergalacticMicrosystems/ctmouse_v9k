#!/bin/sh
# Headless DOSBox smoke test for CTMOUSEV.EXE (plan section 9.4). Usage: tools/dosbox/run.sh [driver.exe]
# Needs nasm and dosbox. Default driver: ctmousev.exe in the repo root (make v9k).
#
# DOSBox is a PC: E000h is plain RAM (no 7201/8253/8259, INT 41h never fires), CRTC reads return
# RAM, F000h is ROM and DOS reports 5.0. So this tests the transient part only: option parsing,
# INT 33h classification (DOSBox's own driver has no 'MOUSE' signature), the no-mouse path,
# install with a simulated 'M', reload, /U and a refused /U, the INT 33h API answers through
# V9KMT.COM, and memory freed. It cannot test packets, the ISR, the cursor (never show it),
# 'M3'/'MZ' detection (every poll of the RAM "data register" returns the same byte), or real
# timing. The checks encode the behaviour the plan specifies (sections 3.2, 5.1-5.3, 6).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DRV=${1:-$REPO/ctmousev.exe}
WORK=${TMPDIR:-/tmp}/ctmv9k_dosbox_test
[ -f "$DRV" ] || { echo "no driver $DRV (make v9k)"; exit 2; }
rm -rf "$WORK"; mkdir -p "$WORK"
nasm -f bin "$HERE/harness.asm" -o "$WORK/TEST.COM"
nasm -f bin "$REPO/utility/v9kmt.asm" -o "$WORK/V9KMT.COM"
cp "$DRV" "$WORK/CTMOUSEV.EXE"
cat > "$WORK/test.conf" <<CONF
[sdl]
output=surface
[dosbox]
memsize=1
[autoexec]
mount c $WORK
c:
test
exit
CONF
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 120 dosbox -conf "$WORK/test.conf" -noconsole >/dev/null 2>&1 || true
[ -f "$WORK/OUT.TXT" ] || { echo "FAIL no OUT.TXT (harness did not run)"; exit 1; }
OUT=$(tr '\r' '\n' < "$WORK/OUT.TXT" | sed '/^ *$/d')
echo "$OUT"
echo "--- checks"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
chk() { if echo "$OUT" | grep -q -- "$1"; then ok "$2"; else bad "$2"; fi; }
# field N ("INT33", "INT41", "IMR", "free", "rc") logged after run R
f() { echo "$OUT" | grep "^#$1 " | sed -n "s/.*$2=\([0-9A-F:]*\).*/\1/p" | tail -1; }
sig() { echo "$OUT" | grep "^#$1 INT33=" | cut -c 20-24; }
eq() { if [ -n "$1" ] && [ "$1" = "$2" ]; then ok "$3"; else bad "$3 ('$1' vs '$2')"; fi; }
ne() { if [ -n "$1" ] && [ "$1" != "$2" ]; then ok "$3"; else bad "$3 (both '$1')"; fi; }

eq "$(f 1 rc)" 0001                    "1: no port -> errorlevel 1"
eq "$(f 1 INT33)$(f 1 INT41)" "$(f 0 INT33)$(f 0 INT41)" "1: no port -> vectors unchanged"
chk "No mouse detected"                "2: no-mouse message"
eq "$(f 2 rc)" 0002                    "2: no mouse -> errorlevel 2"
eq "$(f 2 INT33) $(f 2 INT41) $(f 2 IMR) $(f 2 free)" "$(f 0 INT33) $(f 0 INT41) $(f 0 IMR) $(f 0 free)" \
                                       "2: no mouse -> INT 33h/41h, IMR, memory unchanged"
case "$(f 3 rc)" in 03??) ok "3: simulated 'M' -> TSR install";; *) bad "3: TSR install (rc $(f 3 rc))";; esac
eq "$(sig 3)" MOUSE                    "3: 'MOUSE' signature before the INT 33h entry"
ne "$(f 3 INT41)" "$(f 0 INT41)"       "3: INT 41h hooked"
chk "MOUSE signature ok"               "4: V9KMT sees the signature"
chk "fn 0: AX=FFFF"                    "4: fn 0 AX=FFFFh"
chk "fn 24h: .*DX=5600 port A"         "4: fn 24h DH='V' DL=0 (port A)"
chk "fn 4Dh: .*CuteMouse"              "4: fn 4Dh string"
eq "$(f 5 rc)" 0000                    "5: reload over ours -> errorlevel 0"
eq "$(f 5 INT33)" "$(f 3 INT33)"       "5: reload keeps the INT 33h entry"
eq "$(f 6 rc)" 0002                    "6: refused /U -> errorlevel 2"
chk "nload failed"                     "6: refused /U message"
eq "$(f 6 INT33)" "$(f 5 INT33)"       "6: refused /U leaves INT 33h"
eq "$(f 7 rc)" 0000                    "7: /U -> errorlevel 0"
eq "$(f 7 INT33) $(f 7 INT41)" "$(f 0 INT33) $(f 0 INT41)" "7: /U restores INT 33h and 41h"
eq "$(f 7 free)" "$(f 0 free)"         "7: /U frees the resident block"
exit $fail
