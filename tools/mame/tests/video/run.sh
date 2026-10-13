#!/bin/sh
# Video tests (plan 9.2 tests 5/6/7/12/17): tools/mame/tests/video/run.sh name.cmd [run.sh options]
# Drive B: = ctmv9k.exe, utility/v9kmt.com and PICASSO (EXE/CHR/SCR/STANDARD.PAT from $RAT).
# Substitutes @RUN@ @REPO@ @FEED@ like ../run_test.sh; MAME gets -p A -f and 512K RAM.
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
RAT=${RAT:-/root/sync/Victor9000-Development-Private/disassembly/RAT}
RUN=${V9K_RUN:-${TMPDIR:-/tmp}/v9kmame}
export V9K_RUN=$RUN
name=$(basename "$1" .cmd); shift
mkdir -p "$RUN/$name"
rm -f "$RUN"/flag_* "$RUN/$name"/*
"$REPO/tools/mame/mkdisk.sh" "$RUN/b.img" "${CTMV9K_EXE:-$REPO/ctmv9k.exe}" "$REPO/utility/v9kmt.com" \
	"$RAT/PICASSO.EXE" "$RAT/PICASSO.CHR" "$RAT/PICASSO.SCR" "$RAT/STANDARD.PAT" "$RAT/GETSCRN.COM" >/dev/null || exit 1
sed -e "s|@RUN@|$RUN|g" -e "s|@OUT@|$RUN/$name|g" -e "s|@REPO@|$REPO|g" \
	-e "s|@FEED@|python3 $REPO/tools/v9kmouse.py|g" "$HERE/$name.cmd" > "$RUN/$name.cmd"
"$REPO/tools/mame/run.sh" -f -p A -2 "$RUN/b.img" -c "$RUN/$name.cmd" "$@" -- -ramsize 512K 2>&1 \
	| tee "$RUN/$name.log" | grep -v '^\[v9k\] sh '
[ -f "$RUN/feed.pid" ] && kill "$(cat "$RUN/feed.pid")" 2>/dev/null
exit 0
