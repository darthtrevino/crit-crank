---
name: charsync-import
description: Import or debug a D&D Beyond character in Crit Crank with the charsync CLI, or extend the converter for new D&D Beyond fields. Use when a user wants "my real character" on the device or a conversion looks wrong.
---

# charsync: D&D Beyond to Playdate

## Run
```sh
cd charsync
cargo run --release -- import <id-or-url>               # over USB serial (game must be open and the device unlocked)
cargo run --release -- import <id> --simulator          # write into the Simulator's Data dir, then relaunch the game
cargo run --release -- import <id> --out -              # print converted JSON only, no device needed
cargo run --release -- import --file ddb.json --out -   # offline, from a saved D&D Beyond JSON
```
The character must be **Public** on D&D Beyond. The feed is unofficial (`character-service.dndbeyond.com/character/v5/character/<id>`).

## Debugging a conversion
1. Save the raw JSON: `curl -s https://character-service.dndbeyond.com/character/v5/character/<id> > /tmp/ddb.json`.
2. Run `--file /tmp/ddb.json --out -` and compare with the D&D Beyond sheet: ability scores, AC, HP, attack and damage bonuses, slots.
3. Fix the logic in `src/ddb.rs`. Add a unit test there with a trimmed JSON fixture, then run `cargo test`.
4. If the output schema changes, update `src/model.rs` **and** the reader in `charsheet/source/importer.lua` together, and keep older import files loading.

## Gotchas
- Close the Simulator and `pdutil` first, because they hold the serial port.
- Descriptions are HTML, converted to plain text of at most 400 chars for the pause screen. Escape `*` and `_` (double them) so Playdate text doesn't treat them as formatting.
- `-v` logs serial traffic. Device replies start with `cs `.
- Before committing: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`.
