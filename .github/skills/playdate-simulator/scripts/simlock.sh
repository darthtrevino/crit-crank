#!/bin/sh
# Machine-wide lock so only one agent session drives the Playdate Simulator.
# Usage: simlock.sh acquire|release|status|steal
set -eu

LOCK="${SIMLOCK_DIR:-/tmp/crit-crank-simulator.lock}"
OWNER="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

holder() { cat "$LOCK/owner" 2>/dev/null || echo "unknown"; }

sim_pids() { pgrep -f "Playdate Simulator" 2>/dev/null | tr '\n' ' ' || true; }

case "${1:-status}" in
acquire)
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s\n%s\n' "$OWNER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$LOCK/owner"
    echo "acquired by $OWNER"
    exit 0
  fi
  H="$(head -1 "$LOCK/owner" 2>/dev/null || true)"
  if [ "$H" = "$OWNER" ]; then
    echo "already held by this checkout"
    exit 0
  fi
  if [ -n "$H" ] && [ ! -d "$H" ]; then
    echo "stale lock (worktree $H is gone); taking it over"
    rm -rf "$LOCK"
    exec "$0" acquire
  fi
  echo "BUSY: held by:"
  holder
  echo "simulator pids: $(sim_pids)"
  exit 1
  ;;
release)
  H="$(head -1 "$LOCK/owner" 2>/dev/null || true)"
  if [ -z "$H" ]; then
    echo "not held"
  elif [ "$H" = "$OWNER" ]; then
    rm -rf "$LOCK"
    echo "released"
  else
    echo "held by $H, not this checkout; not releasing" >&2
    exit 1
  fi
  ;;
steal)
  rm -rf "$LOCK"
  exec "$0" acquire
  ;;
status)
  if [ -d "$LOCK" ]; then
    echo "held by:"
    holder
  else
    echo "free"
  fi
  echo "simulator pids: $(sim_pids)"
  ;;
*)
  echo "usage: $0 acquire|release|status|steal" >&2
  exit 2
  ;;
esac
