#!/bin/sh
# Boot the MAME victor9k headless with DOS 2.11 and optional pty serial ports.
# usage: run.sh [-p A|B|AB] [-2 flop2.img] [-c cmds] [-f] [-w] [-k secs] [-- extra mame args]
#   -p   serial port(s) to attach to a host pty, 1200 baud 7N1 (default: none)
#   -2   second floppy (drive B:), e.g. built by mkdisk.sh; used in place (MAME writes to it)
#   -c   command file for screen.lua (see its header); without it the machine just runs
#   -f   fast: -nothrottle (boot to A:\> takes ~2 s instead of ~13 s)
#   -w   open a window (-video auto) instead of -video none
#   -k   kill MAME after this many wall-clock seconds (default 600)
# Env: MAME, ROMS, FLOP1 (default dos211.img; a fresh copy is booted each run), V9K_RUN (work dir).
# The pty paths are printed and written to $V9K_RUN/pty_a and $V9K_RUN/pty_b.
MAME=${MAME:-/root/sync/bldmame1/mame}
ROMS=${ROMS:-/root/sync/bldmame1/roms}
FLOP1=${FLOP1:-/root/sync/mame-files/victor9k/disks/dos211.img}
RUN=${V9K_RUN:-${TMPDIR:-/tmp}/v9kmame}
HERE=$(cd "$(dirname "$0")" && pwd)
PORTS= FLOP2= CMDS= THROTTLE= VIDEO="-video none" KILL=600
while getopts p:2:c:fwk: o; do
	case $o in
	p) PORTS=$OPTARG ;; 2) FLOP2=$OPTARG ;; c) CMDS=$OPTARG ;;
	f) THROTTLE=-nothrottle ;; w) VIDEO="-window" ;; k) KILL=$OPTARG ;;
	*) sed -n '3,12p' "$0"; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
[ "$1" = "--" ] && shift

mkdir -p "$RUN/cfg" "$RUN/nvram" "$RUN/snap"
rm -f "$RUN/pty_a" "$RUN/pty_b"
cp "$FLOP1" "$RUN/flop1.img"

# slot settings (bus/rs232/rs232.h): baud 04h = 1200, databits 02h = 7, parity 00h = none, stopbits 01h = 1
ports= args=
for p in A B; do
	case $PORTS in *$p*) ;; *) continue ;; esac
	t=$(echo $p | tr AB ab)
	args="$args -rs232$t pty"
	for f in RS232_TXBAUD:7:4 RS232_RXBAUD:7:4 RS232_DATABITS:3:2; do
		ports="$ports
            <port tag=\":rs232$t:pty:${f%%:*}\" type=\"CONFIG\" mask=\"255\" defvalue=\"$(echo $f | cut -d: -f2)\" value=\"${f##*:}\" />"
	done
done
cat > "$RUN/cfg/victor9k.cfg" <<CFG
<?xml version="1.0"?>
<mameconfig version="10">
    <system name="victor9k">
        <input>$ports
        </input>
    </system>
</mameconfig>
CFG

[ -n "$FLOP2" ] && args="$args -flop2 $(realpath "$FLOP2")"
[ -n "$CMDS" ] && { export V9K_CMDS=$(realpath "$CMDS"); args="$args -autoboot_script $HERE/screen.lua"; }

cd "$RUN" || exit 1
# shellcheck disable=SC2086
timeout -s KILL "$KILL" "$MAME" victor9k -rompath "$ROMS" -cfg_directory "$RUN/cfg" \
	-nvram_directory "$RUN/nvram" -snapshot_directory "$RUN/snap" -noplugins -skip_gameinfo \
	$VIDEO -sound none $THROTTLE -flop1 "$RUN/flop1.img" $args "$@" &
tpid=$!

# pty discovery: MAME holds one /dev/ptmx fd per pty port, opened in device order (A before B);
# /proc/<pid>/fdinfo gives the slave index.
if [ -n "$PORTS" ]; then
	n=0
	until pid=$(pgrep -P $tpid) || [ $n -gt 50 ]; do sleep 0.1; n=$((n + 1)); done
	n=0
	while [ $n -lt 50 ]; do
		idx=$(for fd in /proc/$pid/fd/*; do
			[ "$(readlink "$fd")" = /dev/ptmx ] && echo "${fd##*/} $(sed -n 's/^tty-index:\s*//p' /proc/$pid/fdinfo/${fd##*/})"
		done 2>/dev/null | sort -n | cut -d' ' -f2)
		[ -n "$idx" ] && break
		sleep 0.1; n=$((n + 1))
	done
	for p in A B; do
		case $PORTS in *$p*) ;; *) continue ;; esac
		i=$(echo "$idx" | head -1); idx=$(echo "$idx" | tail -n +2)
		t=$(echo $p | tr AB ab)
		echo "/dev/pts/$i" > "$RUN/pty_$t"
		echo "port $p: /dev/pts/$i"
	done
fi
wait $tpid
