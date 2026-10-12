#!/usr/bin/env bash
# Play a Lua snippet in the Playdate Simulator so the user can hear it.
#
#   audition.sh <snippet.lua> [seconds]
#
# The snippet is appended to a temporary copy of main.lua, so it can call the
# game's local sound functions (playHorn, playTrombone, playLand, ...) and
# define new synths. It runs 1s after boot. The script takes the Simulator
# lock, backs up and restores the save data, and quits the Simulator after
# [seconds] (default 8). The repo checkout is never modified.
set -euo pipefail

snippet=${1:?usage: audition.sh <snippet.lua> [seconds]}
secs=${2:-8}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
sdk=${PLAYDATE_SDK_PATH:-$HOME/Developer/PlaydateSDK}
sim="$sdk/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator"
data="$sdk/Disk/Data/com.christrevino.charsheet"
lock="$root/.github/skills/playdate-simulator/scripts/simlock.sh"

"$lock" acquire | grep -q 'acquired\|already held' || { "$lock" status; exit 1; }
if pgrep -f "Playdate Simulator" >/dev/null; then
	echo "A Simulator is already running; quit it first." >&2
	"$lock" release; exit 1
fi

tmp=$(mktemp -d /tmp/audition.XXXXXX)
backup="$tmp/data"
[ -d "$data" ] && cp -R "$data" "$backup"

cleanup() {
	for pid in $(pgrep -f "Playdate Simulator" || true); do kill -9 "$pid" 2>/dev/null || true; done
	sleep 1
	if [ -d "$backup" ]; then rm -rf "$data"; cp -R "$backup" "$data"; fi
	rm -rf "$tmp"
	"$lock" release >/dev/null
}
trap cleanup EXIT

cp -R "$root/charsheet/source" "$tmp/source"
{
	printf '\n-- audition snippet\npd.timer.performAfterDelay(1000, function()\n'
	cat "$snippet"
	printf '\nend)\n'
} >> "$tmp/source/main.lua"
"$sdk/bin/pdc" "$tmp/source" "$tmp/audition.pdx" 2>&1 | grep -v 'Unrecognized file types\|^Copying' || true

"$sim" "$tmp/audition.pdx" >/dev/null 2>&1 & disown
echo "Playing for ${secs}s..."
sleep "$secs"
echo "Done."
