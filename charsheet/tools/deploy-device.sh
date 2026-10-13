#!/usr/bin/env bash
# Copies charsheet.pdx to a USB-connected Playdate and launches it.
# Build first (`make build`). Quit the Simulator first: it holds the serial port.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="${PLAYDATE_SDK_PATH:-}"
if [ -z "$SDK" ] && [ -f ~/.Playdate/config ]; then
  SDK="$(awk '$1 == "SDKRoot" { $1 = ""; sub(/^ +/, ""); print; exit }' ~/.Playdate/config)"
fi
PDUTIL="${SDK:-$HOME/Developer/PlaydateSDK}/bin/pdutil"
VOLUME="${PLAYDATE_VOLUME:-/Volumes/PLAYDATE}"

[ -d charsheet.pdx ] || { echo "charsheet.pdx not found; run 'make build' first" >&2; exit 1; }
[ -x "$PDUTIL" ] || { echo "pdutil not found at $PDUTIL; set PLAYDATE_SDK_PATH" >&2; exit 1; }

port() { ls /dev/cu.usbmodemPD* /dev/ttyACM* 2>/dev/null | head -n 1 || true; }
has_port() { [ -n "$(port)" ]; }

wait_for() { # wait_for <description> <test command...>
  local what="$1"; shift
  for _ in $(seq 1 30); do
    if "$@"; then return 0; fi
    sleep 1
  done
  echo "timed out waiting for $what" >&2
  exit 1
}

P="$(port)"
[ -n "$P" ] || { echo "no Playdate found; plug it in and unlock it" >&2; exit 1; }

echo "rebooting $P into disk mode"
"$PDUTIL" "$P" datadisk
wait_for "$VOLUME/Games" test -d "$VOLUME/Games"

echo "copying charsheet.pdx"
rm -rf "$VOLUME/Games/charsheet.pdx"
cp -R charsheet.pdx "$VOLUME/Games/"

if ! diskutil eject "$VOLUME"; then
  echo "eject failed (Defender DLP may block it); eject the PLAYDATE disk manually" >&2
fi
wait_for "the serial port" has_port
sleep 1

"$PDUTIL" "$(port)" run /Games/charsheet.pdx
echo "launched /Games/charsheet.pdx"
