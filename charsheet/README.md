# charsheet

A D&D 5e character sheet for Playdate. Pick a stat, attack, or spell and spin the crank to roll the dice.

## Build & run

```sh
make run      # compile with pdc and open in the Playdate Simulator
make build    # compile only -> charsheet.pdx
```

To play on hardware, sideload `charsheet.pdx` (Simulator → Device → Upload Game, or play.date sideload).

## Controls

| Input | Action |
| --- | --- |
| ⬅️ / ➡️ | Change page (Ability, Saves, Skills, Actions, Status, Dice) |
| ⬆️ / ⬇️ | Select a row (hold to repeat) |
| Crank | Turn to pick up and spin the 3D dice (faster cranking = faster spin); stop and they land showing the result |
| Ⓐ | Quick roll (for when the crank is docked) |
| Ⓑ | Cycle the next d20 roll: normal → advantage → disadvantage |
| Crank / Ⓐ / Ⓑ on a Status counter | Adjust it (crank clockwise = up; Ⓐ −1, Ⓑ +1) |
| On the Dice page | Use "Build a pool": crank, Ⓐ or Ⓑ on a die row (d4–d20) or the Modifier changes its count; select "Roll pool" to roll it all (e.g. 2d6+1d4+2), Ⓑ there clears the pool |
| Menu → Hero | Switch character, prebuilt or imported (remembered between launches) |
| Menu → Short Rest | Restore short-rest features (Second Wind, Action Surge, Channel Divinity) |
| Menu → Long Rest | Full HP, all spell slots and features, regain half your Hit Dice (min 1) |

## Rules handled

- Ability checks, saving throws, skills (● proficient, ◉ expertise), initiative, death saves
- Attack rolls, then a separate damage roll for each attack
- A critical hit on an attack doubles the damage dice of the next damage rolls (marked `x2`) until the next d20 roll. Brenna crits on a 19–20 (Champion).
- A natural 20 on any d20 roll outside the Dice page sounds an air horn; a natural 1 gets a sad trombone
- Advantage/disadvantage resets after each d20 roll
- Halfling Lucky (Pip) automatically rerolls natural 1s on d20 rolls
- Status page tracks current HP, Hit Dice, spell slots, and limited-use features per character (saved between launches)
- Rolling a spell spends a slot of its level and rolling a limited feature spends a use. Multi-roll actions (attack + damage) spend once per cast. If none are left you get a warning, but the roll still happens.
- Second Wind and Spend Hit Die heal your current HP when the dice land. Spend Hit Die needs a Hit Die left and missing HP.
- Dice page: build a custom pool (up to 12 dice plus a ±20 modifier, saved between launches), plus quick rolls: d4–d100, 2d6, 4d6 drop lowest, 8d6

## Importing D&D Beyond characters

The [`charsync`](../charsync) desktop tool (Rust, macOS/Windows/Linux) downloads a **public** D&D Beyond character, converts it, and sends it to the Playdate over USB while charsheet is running:

```sh
cd charsync && cargo build --release
./target/release/charsync import https://www.dndbeyond.com/characters/27935516
```

The hero is selected straight away and stays in the Hero menu. Importing the same character again updates it (its HP, slots and uses are kept). See [charsync/README.md](../charsync/README.md) for the other options (Simulator, USB disk mode, removing a hero).

## Code layout

- `source/characters.lua`: prebuilt characters (data only; add new ones here)
- `source/importer.lua`: imported characters (validation, storage) and the USB serial import protocol
- `source/resources.lua`: tracked resources (HP, Hit Dice, slots, feature uses) and rest rules
- `source/sheet.lua`: works out modifiers and bonuses and builds the rows for each page
- `source/dice.lua`: dice notation parser and roller (`3d4+3`, `4d6kh3`, advantage, crits)
- `source/dice3d.lua`: flat-shaded 3D polyhedra (d4–d20) with quaternion spin and slerp landing
- `source/ui.lua`: drawing (header, tabs, list, dice tray, toasts)
- `source/main.lua`: input, crank roll logic, resource spending, rests, sound, saving, and the main loop
