#!/usr/bin/env bash
# Record the Playdate Simulator with the devrec.lua harness and encode a GIF/MP4.
# Usage:
#   record.sh install            back up the save data, copy devrec.lua in, tag main.lua
#   record.sh prep               clear the frame directory
#   record.sh wait [seconds]     wait for the harness to write done.png (default 120)
#   record.sh encode OUT [fps] [scale]   frames -> OUT (.gif via Pillow, .mp4 via ffmpeg)
#   record.sh uninstall          remove devrec.lua and DEVTEMP lines, restore the save data
#                                (quit the Simulator first)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SKILL="$ROOT/.github/skills/simulator-recording"
SRC="$ROOT/charsheet/source"
FRAMES="/tmp/critcrank-rec"
PY="/tmp/pilenv/bin/python"
DATA="$HOME/Developer/PlaydateSDK/Disk/Data/com.christrevino.charsheet"
PTR="/tmp/critcrank-rec.backup" # holds the path of the current save backup

backup() {
	if [ -f "$PTR" ]; then
		echo "an unrestored save backup exists ($(cat "$PTR")); run record.sh uninstall first" >&2
		exit 1
	fi
	B="$(mktemp -d /tmp/cs-data-bak.XXXXXX)"
	# $B/data is absent when there was no save directory; restore then deletes it.
	[ -d "$DATA" ] && cp -R "$DATA" "$B/data"
	echo "$B" >"$PTR"
	echo "save data backed up to $B"
}

restore() {
	[ -f "$PTR" ] || { echo "no save backup to restore"; return; }
	if pgrep -f "Playdate Simulator" >/dev/null; then
		echo "quit the Simulator before restoring the save data" >&2
		exit 1
	fi
	B="$(cat "$PTR")"
	rm -rf "$DATA"
	[ -d "$B/data" ] && cp -R "$B/data" "$DATA"
	rm -rf "$B" "$PTR"
	echo "save data restored"
}

case "${1:-}" in
install)
	backup
	cp "$SKILL/templates/devrec.lua" "$SRC/devrec.lua"
	grep -q 'import "devrec"' "$SRC/main.lua" || printf '\nimport "devrec" -- DEVTEMP\n' >>"$SRC/main.lua"
	echo "installed $SRC/devrec.lua; edit its SCRIPT table, then: record.sh prep && (cd charsheet && make run)"
	;;
prep)
	rm -rf "$FRAMES"
	mkdir -p "$FRAMES"
	echo "frames -> $FRAMES"
	;;
wait)
	limit="${2:-120}"
	for _ in $(seq "$limit"); do
		if [ -f "$FRAMES/done.png" ]; then
			echo "done: $(find "$FRAMES" -name 'f*.png' | wc -l | tr -d ' ') frames"
			exit 0
		fi
		sleep 1
	done
	echo "timed out after ${limit}s waiting for $FRAMES/done.png" >&2
	exit 1
	;;
encode)
	out="${2:?usage: record.sh encode OUT.gif|OUT.mp4 [fps] [scale]}"
	fps="${3:-30}"
	scale="${4:-2}"
	case "$out" in
	*.mp4)
		command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg) or encode a .gif" >&2; exit 1; }
		ffmpeg -loglevel error -y -framerate "$fps" -i "$FRAMES/f%05d.png" \
			-vf "scale=iw*$scale:ih*$scale:flags=neighbor" -c:v libx264 -pix_fmt yuv420p "$out"
		;;
	*.gif)
		if ! "$PY" -c 'import PIL' 2>/dev/null; then
			rm -rf /tmp/pilenv
			python3 -m venv /tmp/pilenv && /tmp/pilenv/bin/pip install -q pillow
		fi
		"$PY" "$SKILL/scripts/encode_gif.py" "$FRAMES" "$out" "$fps" "$scale"
		;;
	*) echo "OUT must end in .gif or .mp4" >&2; exit 1 ;;
	esac
	ls -lh "$out"
	;;
uninstall)
	restore
	rm -f "$SRC/devrec.lua"
	if grep -rln DEVTEMP "$SRC" >/dev/null 2>&1; then
		grep -rl DEVTEMP "$SRC" | while read -r f; do sed -i '' '/DEVTEMP/d' "$f"; done
	fi
	# drop the blank line `install` left at the end of main.lua
	python3 -c 'import sys; p = sys.argv[1]; s = open(p).read(); open(p, "w").write(s.rstrip("\n") + "\n")' "$SRC/main.lua"
	if grep -rn DEVTEMP "$SRC"; then echo "DEVTEMP lines remain" >&2; exit 1; fi
	git -C "$ROOT" diff --quiet -- charsheet/source/main.lua || echo "warning: main.lua still differs from HEAD" >&2
	echo "uninstalled"
	;;
*)
	sed -n '2,9p' "$0"
	exit 1
	;;
esac
