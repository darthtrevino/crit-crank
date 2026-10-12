---
name: playdate-simulator-harness
description: Take automated screenshots or run scripted input in the Playdate Simulator without touching the user's desktop. Use for visual verification, README/site screenshots, or reproducing UI bugs.
---

# Simulator test harness

The Simulator has no CLI automation, so the harness runs inside the game.

## Setup (temporary, never commit)
0. Take the Simulator lock first (`playdate-simulator` skill):
   `.github/skills/playdate-simulator/scripts/simlock.sh acquire`. If it's busy, stop and tell the user.
1. Back up the save data, since the harness will change it:
   `cp -R ~/Developer/PlaydateSDK/Disk/Data/com.christrevino.charsheet /tmp/cs-data-bak`
2. Create `charsheet/source/devshots.lua`. Its update hook steps through a script of actions, one per N frames: set page or selection, start a roll, open the pause menu.
3. In `main.lua`, add lines tagged `-- DEVTEMP`:
   - `import "devshots"`
   - expose the internals the harness needs, e.g. `__cs = { state = state, sheet = sheet }`
   - call the harness from `playdate.update`
4. Capture frames with
   `playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), "/tmp/shot_01.png")`.
   For the pause-menu image, use `getWorkingImage()` or the image passed to `setMenuImage`. Remember that only its left 200px are shown.
5. `make run`, then wait and view `/tmp/shot_*.png`.

## Teardown (required)
- Kill the Simulator with literal PIDs: `pgrep -f "Playdate Simulator"`, then `kill -9 <pid> <pid>`. `pkill` and `killall` aren't allowed, and a `kill $(...)` with an expanded variable may be rejected.
- Delete `devshots.lua` and every `-- DEVTEMP` line (`grep -rn DEVTEMP charsheet/source` must return nothing).
- Restore the save data from `/tmp/cs-data-bak`.
- Rebuild and lint to confirm a clean tree.
- Release the lock: `.github/skills/playdate-simulator/scripts/simlock.sh release`.

## Notes
- The Simulator holds the device's serial port while it runs. Quit it before deploying to hardware.
- Use a Pillow venv for post-processing (cropping, GIFs): `python3 -m venv /tmp/pilenv && /tmp/pilenv/bin/pip install pillow`.
