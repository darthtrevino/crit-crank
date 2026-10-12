#!/usr/bin/env bash
# Lints the game's Lua with luacheck (config: .luacheckrc).
set -euo pipefail
cd "$(dirname "$0")/.."
"${LUACHECK:-luacheck}" source "$@"
