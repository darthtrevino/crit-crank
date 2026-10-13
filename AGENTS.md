# AGENTS.md

Guidance for AI coding agents working on Crit Crank. Read this before you change anything.

## Layout

- `charsheet/`: the Playdate game, in Lua (SDK 3.x). The entry point is `source/main.lua`.
  - `sheet.lua` builds the pages and rows.
  - `ui.lua` draws them (fonts live in `UI.fonts`).
  - `dice.lua` / `dice3d.lua` handle rolls and the 3D renderer.
  - `resources.lua` covers HP, slots, rests and saved state.
  - `rules.lua` holds the rule text for the pause screen and the Rules viewer.
  - `characters.lua` has the prebuilt heroes; `importer.lua` takes in heroes from charsync.
  - `launcher/` holds the 1-bit card and icon art.
- `charsync/`: Rust CLI. `ddb.rs` converts D&D Beyond JSON, `model.rs` is the game's character JSON, `transport.rs` handles USB serial and data-disk, and `main.rs` is the CLI.
- `site/`: static GitHub Pages site. No build step: plain HTML, CSS and ES modules. `sim/*.js` is a JavaScript port of the game (one module per Lua file) that draws 1-bit onto a 400×240 canvas; keep it in step with game behavior changes. `docs.html` is the full manual.

## Commands

A root `Taskfile.yml` wraps these (`task check`, `task sim`, `task device`, …; see `task --list`).

| Task | Command |
| --- | --- |
| Build game | `cd charsheet && make build` (or `pdc source charsheet.pdx`) |
| Run in Simulator | `cd charsheet && make run` (or `task sim`, which takes the lock) |
| Deploy to device | `task device` (`charsheet/tools/deploy-device.sh`) |
| Lua lint | `charsheet/tools/lint.sh` (needs `luacheck` on **Lua 5.4**; it crashes on 5.5. Set `LUACHECK=` to point at the binary) |
| Rust | `cd charsync && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test` |
| Site preview | `cd site && python3 -m http.server` |

CI (`.github/workflows/ci.yml`) runs lint, the game build and the Rust checks on PRs and on `main`. Keep all of them green. `pages.yml` deploys `site/` as-is. `release.yml` runs on a `v*` tag: it stamps the version into `pdxinfo`, builds, and attaches `crit-crank.pdx.zip` plus Linux (static musl), macOS (universal, signed and notarized; needs the secrets listed in README) and Windows `charsync` binaries to a GitHub Release. The site links to `releases/latest/download/crit-crank.pdx.zip`.

## Invariants

- **Don't rename the bundle.** Keep `bundleID` `com.christrevino.charsheet`, the pdx name `charsheet.pdx`, and the `charsheet/` folder. Saved data, the device path `/Games/charsheet.pdx`, and charsync all depend on them. The display name "Crit Crank" lives only in `pdxinfo` and the docs.
- New Lua globals must be added to `charsheet/.luacheckrc`.
- When character JSON changes, update `model.rs` and the game's reader in step, and keep older imported files loading.
- Never commit secrets, `charsync/target/`, or built `*.pdx`.
- Don't copy copyrighted audio or art; synthesize sounds with `playdate.sound`.

## Playdate Lua gotchas

- The `+=`, `-=` and other compound operators are Playdate extensions. luacheck accepts them only through `.luacheckrc`.
- In `drawText`, `*` and `_` are bold and italic markers. Double them (`**`, `__`) to print them literally, especially in user and D&D Beyond text.
- `playdate.setMenuImage` shows only the left 200px of a 400×240 image, and it can't animate: the game is suspended while the system menu is open. Long text goes in the Rules viewer.
- The screen is 1-bit: draw art in black and white (no grey), and dither if needed.
- `pdc` warnings matter; a clean build prints nothing.

## Working with the user's hardware

See the skills in `.github/skills/`: `playdate-simulator`, `playdate-device`, `playdate-simulator-harness`, `charsync-import`, `one-bit-assets`, `sound-design` (Simulator auditions and a slider tuner for sounds), `simulator-recording` (scripted Simulator GIF/MP4 attached to PRs).

- **One session at a time on the Simulator.** Take the lock with `.github/skills/playdate-simulator/scripts/simlock.sh acquire` before `make run`, and release it when done. If it's busy, don't launch or kill the Simulator.

- **Never screenshot the user's desktop.** Capture the Simulator's framebuffer from Lua, or the device over serial.
- The Simulator and `pdutil` hold the serial port, so close them before using charsync or serial scripts.
- Process kills must use literal PIDs (`kill <pid>`); `pkill` and `killall` aren't allowed.
- Microsoft Defender DLP on the dev Mac may block `diskutil eject` on the PLAYDATE volume. If it does, ask the user to eject.

## Commits

Use small, focused commits with imperative subjects. PRs follow `.github/pull_request_template.md`; tick off its checklist, including the docs and docsite. Every PR with an app feature or bug fix needs a Simulator recording in its Recording section (`simulator-recording` skill). Run lint, the build and the tests before committing. Agent commits include the session's `Co-authored-by` trailer.
