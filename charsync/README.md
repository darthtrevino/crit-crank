# charsync

Brings D&D Beyond characters into [Crit Crank](../charsheet) on a Playdate. It's a command-line tool for macOS, Windows and Linux.

> D&D Beyond has no public API. charsync reads the same unofficial JSON feed the D&D Beyond site uses, which works only for characters whose privacy is set to **Public**. It may break if D&D Beyond changes the feed. Use it for your own characters.

## Download

Download the binary for your operating system from the [latest release](https://github.com/darthtrevino/crit-crank/releases/latest): `charsync-linux`, `charsync-macos` or `charsync-windows.exe`. On macOS and Linux, make the downloaded binary executable, then run it from its directory. The macOS binary is universal (Apple Silicon and Intel) but not notarized, so also clear the download quarantine flag or macOS will block it:

```sh
chmod +x charsync-macos                              # or charsync-linux
xattr -d com.apple.quarantine charsync-macos         # macOS only
```

The Linux binary is statically linked and runs on any x86_64 distribution.

## Use

Open Crit Crank on the Playdate, plug it in over USB, unlock it, then:

```sh
./charsync-macos import 27935516                                     # use charsync-linux on Linux
./charsync-macos import https://www.dndbeyond.com/characters/27935516
```

On Windows, run the downloaded executable in PowerShell:

```powershell
.\charsync-windows.exe import 27935516
```

charsync launches Crit Crank if it isn't already open. Other commands:

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

Ability scores (racial/feat/item bonuses, set scores, overrides), saves, skill proficiency/expertise, HP, AC (armor, shield, Unarmored Defense, bonuses), speed, Hit Die, spell slots (including multiclass and Pact Magic), equipped weapons (finesse/ranged, proficiency, magic bonuses), traits (fly/swim/climb/burrow speeds, senses such as darkvision, languages, damage resistances/immunities/vulnerabilities, condition immunities, and armor/weapon/tool proficiencies), damaging and healing spells (prepared ones, cantrips scaled by level), and limited-use features with their short/long rest resets. Improved/Superior Critical and the halfling Lucky trait are detected too. Spells and features also bring along their D&D Beyond description (as plain text, up to 400 characters), which shows on the pause screen and in the Rules viewer.

Utility spells and features with nothing to roll are left out.

## How it talks to the Playdate

The Playdate's USB serial console accepts `msg <text>`, which Crit Crank receives in `playdate.serialMessageReceived`. Crit Crank replies with `print()`. The compact character JSON goes over in acknowledged chunks of 180 bytes or fewer:

```
msg cs ping              -> cs pong 1
msg cs begin <bytes>     -> cs ready
msg cs data <seq> <text> -> cs ack <seq>
msg cs end               -> cs done <key> | cs err <reason>
msg cs remove <key>      -> cs removed <key>
```

Imports are stored in the game's `imports.json` datastore file, which is also what `--disk` and `--simulator` write to.

## License

MIT. See [LICENSE](../LICENSE).
