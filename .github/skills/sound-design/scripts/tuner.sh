#!/bin/sh
# Serve the repo root and print the sound tuner URL. Ctrl-C to stop.
#   .github/skills/sound-design/scripts/tuner.sh [port]
set -e
PORT="${1:-8766}"
cd "$(git rev-parse --show-toplevel)"
echo "Horn tuner: http://127.0.0.1:$PORT/.github/skills/sound-design/tuner/horn.html"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
