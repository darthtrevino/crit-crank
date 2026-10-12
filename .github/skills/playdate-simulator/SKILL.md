---
name: playdate-simulator
description: Rules for launching, sharing and quitting the Playdate Simulator. Only one agent session may use it at a time; take the lock first. Use before any `make run`, Simulator screenshot, or harness run.
---

# Using the Playdate Simulator

There is one Simulator per machine. It has one window, one serial port, and one
shared save directory (`~/Developer/PlaydateSDK/Disk/Data/com.christrevino.charsheet`).
Parallel sessions (worktrees) would overwrite each other's build, input and
saves. **Only one session may use the Simulator at a time.**

## 1. Take the lock first
```sh
.github/skills/playdate-simulator/scripts/simlock.sh acquire
```
- `acquired` or `already held by this checkout`: go ahead.
- `BUSY: held by …`: another session owns it. **Do not** launch, kill, or
  reload the Simulator, and don't touch the shared save data. Tell the user who
  holds it, then either wait and retry or skip the Simulator step (a clean
  `make build` and lint are still valid checks).
- Only run `simlock.sh steal` when the user explicitly says to.
- If the holder's worktree no longer exists, `acquire` clears the stale lock
  automatically.

`simlock.sh status` shows the holder and any running Simulator PIDs.

## 2. Use it
- Build and launch: `cd charsheet && make run`.
- If a Simulator is already running but you hold the lock, it's leftover from
  your session or a stale owner. Quit it (see below) before relaunching, so you
  know which build is loaded.
- **Never screenshot the user's desktop.** Capture the framebuffer from Lua; see
  the `playdate-simulator-harness` skill for scripted input and screenshots.
- Back up the save data before anything that changes it, and restore it after.

## 3. Quit and release (always, even on failure)
```sh
pgrep -f "Playdate Simulator"          # note the PIDs
kill <pid> <pid>                        # literal PIDs; no pkill/killall/$(...)
.github/skills/playdate-simulator/scripts/simlock.sh release
```
Release as soon as you're done with the Simulator, not at the end of the whole
task. Never leave the lock held when you hand control back to the user.

## Notes
- The lock lives at `/tmp/crit-crank-simulator.lock` (override with
  `SIMLOCK_DIR`). Ownership is keyed on the checkout's root path.
- The Simulator holds the device's serial port. The `playdate-device` skill and
  charsync need it quit first, so the same lock rules apply there.
