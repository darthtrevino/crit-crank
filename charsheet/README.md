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
| ⬅️ / ➡️ | Change page (Ability, Saves, Skills, Actions, Dice) |
| ⬆️ / ⬇️ | Select a row (hold to repeat) |
| Crank | Turn to pick up and spin the 3D dice (faster cranking = faster spin); stop and they land showing the result |
| Ⓐ | Quick roll (for when the crank is docked) |
| Ⓑ | Cycle the next d20 roll: normal → advantage → disadvantage |
| Menu → Hero | Switch prebuilt character (remembered between launches) |

## Rules handled

- Ability checks, saving throws, skills (● proficient, ◉ expertise), initiative, death saves
- Attack rolls, then a separate damage roll for each attack
- A critical hit on an attack doubles the damage dice of the next damage rolls (marked `x2`) until the next d20 roll. Brenna crits on a 19–20 (Champion).
- Advantage/disadvantage resets after each d20 roll
- Halfling Lucky (Pip) automatically rerolls natural 1s on d20 rolls
- Dice page: d4–d100, 2d6, 4d6 drop lowest, 8d6

## Code layout

- `source/characters.lua`: prebuilt characters (data only; add new ones here)
- `source/sheet.lua`: works out modifiers and bonuses and builds the rows for each page
- `source/dice.lua`: dice notation parser and roller (`3d4+3`, `4d6kh3`, advantage, crits)
- `source/dice3d.lua`: flat-shaded 3D polyhedra (d4–d20) with quaternion spin and slerp landing
- `source/ui.lua`: drawing (header, tabs, list, dice tray)
- `source/main.lua`: input, crank roll logic, sound, and the main loop
