# charsync

Brings D&D Beyond characters into [charsheet](../charsheet) on a Playdate. It's a command-line tool for macOS, Windows and Linux.

> D&D Beyond has no public API. charsync reads the same unofficial JSON feed the D&D Beyond site uses, which works only for characters whose privacy is set to **Public**. It may break if D&D Beyond changes the feed. Use it for your own characters.

## Build

Requires [Rust](https://rustup.rs).

```sh
cargo build --release   # -> target/release/charsync
```

## Use

Open charsheet on the Playdate, plug it in over USB, unlock it, then:

```sh
charsync import 27935516                                     # by id
charsync import https://www.dndbeyond.com/characters/27935516 # or URL
```

charsync launches charsheet if it isn't already open. Other commands:

| Command | What it does |
| --- | --- |
| `charsync import <id> --simulator` | Install into the Playdate Simulator instead (relaunch the game to see it) |
| `charsync import <id> --disk` | Fallback: copy via USB data-disk mode, eject, and relaunch |
| `charsync import <id> --out char.json` | Just convert (`--out -` prints to the terminal) |
| `charsync import --file ddb.json` | Convert a saved D&D Beyond JSON file instead of downloading |
| `charsync remove ddb27935516` | Remove an imported hero (`--simulator` for the Simulator) |
| `charsync ping` / `charsync ports` | Check the connection / list serial ports |

Global options: `--port <path>` picks the serial port, and `-v` logs serial traffic. The Simulator and `pdutil` lock the port, so close them first.

## What's converted

Ability scores (racial/feat/item bonuses, set scores, overrides), saves, skill proficiency/expertise, HP, AC (armor, shield, Unarmored Defense, bonuses), speed, Hit Die, spell slots (including multiclass and Pact Magic), equipped weapons (finesse/ranged, proficiency, magic bonuses), damaging and healing spells (prepared ones, cantrips scaled by level), and limited-use features with their short/long rest resets. Improved/Superior Critical and the halfling Lucky trait are detected too.

Utility spells and features with nothing to roll are left out.

## How it talks to the Playdate

The Playdate's USB serial console accepts `msg <text>`, which charsheet receives in `playdate.serialMessageReceived`. charsheet replies with `print()`. The compact character JSON goes over in acknowledged chunks of 180 bytes or fewer:

```
msg cs ping              -> cs pong 1
msg cs begin <bytes>     -> cs ready
msg cs data <seq> <text> -> cs ack <seq>
msg cs end               -> cs done <key> | cs err <reason>
msg cs remove <key>      -> cs removed <key>
```

Imports are stored in the game's `imports.json` datastore file, which is also what `--disk` and `--simulator` write to.
