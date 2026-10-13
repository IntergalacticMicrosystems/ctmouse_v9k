#!/bin/sh
# Build a Victor 9000 single-sided DOS floppy image holding the given files (root directory).
# usage: mkdisk.sh out.img file|dir...   (directories: their regular files, not recursive)
# The image starts from blankss.img.gz (a blank SS disk formatted by Victor FORMAT, with the
# zone tables in the disk label that DOS needs) and files are added with vtg_image_util
# (Python, found via $VTG_DIR). Note: `vtg_image_util create` writes a label without the zone
# tables and DOS 2.11 then gives "Read fault error reading drive B", so it is not used.
# The .img is the raw logical-sector dump (1224 x 512 bytes) that MAME's victor9k_dsk loads.
VTG_DIR=${VTG_DIR:-/root/sync/bldmame1}
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { sed -n '2,3p' "$0"; exit 1; }
out=$1; shift
vtg() { PYTHONPATH="$VTG_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 -m vtg_image_util "$@"; }
gzip -dc "$HERE/blankss.img.gz" > "$out" || exit 1
for a in "$@"; do
	if [ -d "$a" ]; then list=$(find "$a" -maxdepth 1 -type f | sort); else list=$a; fi
	for f in $list; do
		vtg -q copy "$f" "$out:\\$(basename "$f" | tr a-z A-Z)" >/dev/null || exit 1
	done
done
vtg list "$out"
