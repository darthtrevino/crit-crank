## Why

<!-- What problem does this solve, or what does it add? -->

## What changed

<!-- Key design decisions and how the pieces fit together. -->

## Checklist

All of these must pass before merging. Mark items that don't apply as N/A.

- [ ] **Lua lint** passes: `charsheet/tools/lint.sh` (luacheck on Lua 5.4)
- [ ] **Game builds** cleanly: `cd charsheet && make build` prints no `pdc` warnings
- [ ] **Rust checks** pass: `cd charsync && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
- [ ] **Docs are up to date**: `README.md`, `charsheet/README.md`, `charsync/README.md` and `AGENTS.md` describe the new behavior
- [ ] **Docsite is up to date**: `site/index.html`, `site/demo.js` and the screenshots in `site/assets/` match the game (preview with `cd site && python3 -m http.server`)
- [ ] **Tested** in the Simulator or on a device (screenshots for UI changes)
- [ ] New Lua globals are listed in `charsheet/.luacheckrc`
- [ ] Character JSON changes are made in both `charsync/src/model.rs` and the game's reader, and older imported files still load
- [ ] No secrets, `charsync/target/` or built `*.pdx` committed
