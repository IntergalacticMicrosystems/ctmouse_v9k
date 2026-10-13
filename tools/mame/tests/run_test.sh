#!/bin/sh
# Run one MAME test command file: tools/mame/tests/run_test.sh name.cmd [run.sh options]
# Builds drive B: from ctmv9k.exe, utility/v9kmt.com and tools/mame/tests/disk/* (if present),
# substitutes @RUN@ (V9K_RUN), @REPO@ (repo root) and @FEED@ (v9kmouse.py) in the command file,
# and writes the MAME output to $V9K_RUN/<name>.log.
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
RUN=${V9K_RUN:-${TMPDIR:-/tmp}/v9kmame}
export V9K_RUN=$RUN
t=$1; shift
name=$(basename "$t" .cmd)
mkdir -p "$RUN"
rm -f "$RUN"/flag_*
EXE=${CTMV9K_EXE:-$REPO/ctmv9k.exe}
extra=; [ -d "$HERE/disk" ] && extra="$HERE/disk"
"$REPO/tools/mame/mkdisk.sh" "$RUN/b.img" "$EXE" "$REPO/utility/v9kmt.com" $extra >/dev/null || exit 1
sed -e "s|@RUN@|$RUN|g" -e "s|@REPO@|$REPO|g" -e "s|@FEED@|python3 $REPO/tools/v9kmouse.py|g" \
	"$HERE/$name.cmd" > "$RUN/$name.cmd"
"$REPO/tools/mame/run.sh" -2 "$RUN/b.img" -c "$RUN/$name.cmd" "$@" 2>&1 | tee "$RUN/$name.log" \
	| grep -v '^\[v9k\] sh '
[ -f "$RUN/feed.pid" ] && kill "$(cat "$RUN/feed.pid")" 2>/dev/null
exit 0
