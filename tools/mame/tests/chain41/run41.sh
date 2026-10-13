#!/bin/sh
# CHAIN41 test runner: run41.sh test.cmd [run.sh options]
# Env: V9K_RUN (work dir), CTM0 / CTM1 (CHAIN41=0 / =1 builds; default: repo ctmousev.exe for both),
#      CFG = a | b | ab | none: CONFIG.SYS on drive A: loading PORTA/PORTB at 1200 7N1 (default a).
#      bits(6) is deliberate: PORTA 2.4/PORTB 2.3 write WR3 = A1h for bits(7) (D7D6 = 10 = 6 bits
#      in z80sio.cpp) and 61h (7 bits) for bits(6).
# Drive B: CTM0.EXE, CTM1.EXE, V9KMT.COM, SERRD.COM, A41.COM. In the command file @RUN@, @HERE@,
# @REPO@ are substituted; start host feeders with "sh ... & echo $! >> @RUN@/pids" (killed at end).
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
RUN=${V9K_RUN:-${TMPDIR:-/tmp}/v9kmame41}
export V9K_RUN=$RUN VTG_DIR=${VTG_DIR:-/root/sync/bldmame1}
t=$1; shift
name=$(basename "$t" .cmd)
mkdir -p "$RUN/disk"
rm -f "$RUN"/done* "$RUN/pids"
for f in serrd a41; do nasm -f bin -o "$RUN/disk/$f.com" "$HERE/$f.asm" || exit 1; done
cp "${CTM0:-$REPO/ctmousev.exe}" "$RUN/disk/ctm0.exe"
cp "${CTM1:-$REPO/ctmousev.exe}" "$RUN/disk/ctm1.exe"
cp "$REPO/utility/v9kmt.com" "$RUN/disk/"
"$REPO/tools/mame/mkdisk.sh" "$RUN/b.img" "$RUN/disk" >/dev/null || exit 1
cp /root/sync/mame-files/victor9k/disks/dos211.img "$RUN/a.img"
cfg=
case ${CFG:-a} in *a*) cfg="device = porta.exe baud(1200) bits(6) stop(1) parity(none)\r\n" ;; esac
case ${CFG:-a} in *b*) cfg="${cfg}device = portb.exe baud(1200) bits(6) stop(1) parity(none)\r\n" ;; esac
if [ -n "$cfg" ]; then
	printf "$cfg" > "$RUN/config.sys"
	PYTHONPATH=$VTG_DIR python3 -m vtg_image_util -q copy "$RUN/config.sys" "$RUN/a.img:\\CONFIG.SYS" >/dev/null || exit 1
fi
sed -e "s|@RUN@|$RUN|g" -e "s|@REPO@|$REPO|g" -e "s|@HERE@|$HERE|g" "$t" > "$RUN/$name.cmd"
FLOP1=$RUN/a.img "$REPO/tools/mame/run.sh" -2 "$RUN/b.img" -c "$RUN/$name.cmd" "$@" > "$RUN/$name.log" 2>&1
[ -f "$RUN/pids" ] && kill $(cat "$RUN/pids") 2>/dev/null
grep -v '^\[v9k\] sh \|^\[v9k\]	W \|ALSA\|-video none\|^\s*$' "$RUN/$name.log"
exit 0
