---
name: simulator-recording
description: Record a scripted Playdate Simulator session as a GIF/MP4 and attach it to a pull request. Required for every PR that adds an app feature or fixes an app bug; also use when the user asks for a recording, demo or video.
---

# Simulator recording for PRs

Every PR that adds a feature or fixes a bug **in the app** (`charsheet/`, or the
web demo when it mirrors game behavior) must have a Simulator recording in its
`## Recording` section showing the new behavior. Docs, CI, charsync-only and
tooling PRs don't need one.

The recording comes from the game's own framebuffer, never from the user's
desktop. A temporary `devrec.lua` wraps `playdate.update`, plays scripted
input (buttons and crank), and writes every frame to `/tmp/critcrank-rec/`.

Run everything from the repo root, after setting:
```sh
R=.github/skills/simulator-recording/scripts/record.sh
```

## 1. Set up
1. Take the Simulator lock (`playdate-simulator` skill). If it's busy, stop and
   tell the user rather than skipping the recording.
2. `$R install`: backs up the save data (which the scripted input will
   change) to a fresh `mktemp` directory, copies `templates/devrec.lua` to
   `charsheet/source/devrec.lua`, and appends `import "devrec" -- DEVTEMP` to
   `main.lua`. It refuses to run if an earlier backup was never restored; run
   `$R uninstall` (Simulator quit) to restore that one first.
3. Edit the `SCRIPT` table in `charsheet/source/devrec.lua` to show the change.
   Steps: `{ "wait", frames }`, `{ "press", "a" }`, `{ "hold", "down", frames }`,
   `{ "crank", degPerFrame, frames }`, `{ "dock", bool }`, `{ "call", fn }`.
   Button presses go to the top pushed input handler (e.g. the Rules viewer)
   or the `playdate.*ButtonDown` globals; crank input feeds `getCrankChange`
   or the handler's `cranked`. Start with a ~1s wait, end with ~2-3s on the
   result, and keep it under ~20s. If the starting state matters (character,
   page, HP), set it with a `call` step or edit the backed-up save data.

## 2. Record
```sh
$R prep && (cd charsheet && make run) && $R wait 120
```
Frames are captured per game frame, so the recording plays at true speed even
if the Simulator runs slowly while writing PNGs.

## 3. Encode and check
```sh
$R encode /tmp/critcrank-rec.gif     # 1-bit GIF, 2x nearest-neighbour, deduped frames
$R encode /tmp/critcrank-rec.mp4     # needs ffmpeg; use for long clips (>10 MB GIF)
```
Optional args: `fps` (default 30) and `scale` (default 2). Look at a few frames
(`/tmp/critcrank-rec/f*.png`) before uploading to make sure it shows the change.

## 4. Tear down (always, even on failure)
- Quit the Simulator with literal PIDs: `pgrep -f "Playdate Simulator"`, then
  `kill -9 <pid> <pid>` (a plain `kill` can leave it running). Check `pgrep`
  comes back empty.
- `$R uninstall`: restores the save data exactly as it was (deleting it if
  there was none), removes the backup, and deletes `devrec.lua` and every
  `DEVTEMP` line. It refuses to restore while the Simulator is running, since
  the game saves on quit.
- Release the lock, then rebuild and lint to confirm a clean tree.

## 5. Attach to the PR
After the PR exists (create it first if needed):
```sh
.github/skills/simulator-recording/scripts/attach-to-pr.sh /tmp/critcrank-rec.gif [PR] "Rolling Second Wind"
```
It uploads the file as a GitHub user attachment (via `gh auth token`) and puts
it under the PR body's `## Recording` heading, replacing the template's
placeholder, or appends that section. PR defaults to the current branch's PR.
GIFs render inline; MP4s render as a player. Run it again to add more clips.
Never commit recordings to the repo.
