---
name: sound-design
description: Design, tune and audition Crit Crank's synthesized sounds (dice ticks, landings, the nat-20 air horn, the nat-1 trombone, rest chimes) with playdate.sound, and keep the web demo's Web Audio port in step. Use when a sound is added or the user says a sound is weak, tinny, harsh, too quiet or "doesn't sound right".
---

# Sound design

All sounds are synthesized in `charsheet/source/main.lua` with `playdate.sound`
(never sample copyrighted audio). The web demo mirrors them in
`site/sim/sound.js` with Web Audio. Change both together.

## Tuner: let the user dial it in

For the nat-20 horn, a slider page plays the web port with live settings:

```sh
.github/skills/sound-design/scripts/tuner.sh    # serves the repo root on :8766
```
Run it as an attached async command and open
`http://127.0.0.1:8766/.github/skills/sound-design/tuner/horn.html` in the
browser canvas. Its defaults come from `HORN` in `sound.js`, and the page
remembers the user's last settings in localStorage (Reset returns to `HORN`). It covers hit cadence, hit tone, hold before the drop,
drop tone, drop slide time and drop hold time, and prints a `HORN` table.
Copy the user's values into `HORN` in both `main.lua` and `site/sim/sound.js`,
then confirm on the Simulator with `audition.sh` (`playHorn()`). Stop the
server afterwards. New tunable sounds should follow the same pattern: one
settings table, the same in Lua and JS, and `sound.js` accepting overrides.

## Audition loop: let the user hear it

Sound is judged by ear, so iterate with the user rather than guessing:

1. Write a Lua snippet to a temp file. It's appended to a temporary copy of
   `main.lua`, so it can call the game's locals (`playHorn()`, `playTrombone()`,
   `playLand(result)`, `playTick()`) or build a candidate synth inline.
2. Play it in the Simulator:
   ```sh
   .github/skills/sound-design/scripts/audition.sh /tmp/candidate.lua [seconds]
   ```
   The script takes the Simulator lock (it stops if another session holds it),
   backs up and restores the save data, builds to a temp dir, plays, quits the
   Simulator and releases the lock. The checkout is never modified.
3. For A/B comparisons, play the current sound first, then the candidate after
   a gap: `playHorn()` then `pd.timer.performAfterDelay(2500, function() ... end)`.
   Tell the user which is A and which is B.
4. Ask with `ask_user` (choices like "B is better", "Replay", "Keep tweaking").
   Change one or two things per round and say what changed in numbers
   ("hits every 165ms", "drop 0.6 semitone").
5. When the user is happy, move the candidate into `main.lua`, port it to
   `sound.js`, and run `audition.sh` with just the game call (e.g. `playHorn()`)
   to confirm the real code sounds the same.

The Simulator plays through the Mac's speakers. The Playdate's own speaker is
small and weak below ~400 Hz, so ask the user to try anything bass-dependent
on the device too.

## playdate.sound notes

- `synth.new(wave)`; `synth:setADSR(a, d, s, r)` (seconds; sustain is a level).
  `synth:setEnvelopeCurvature(1)` gives exponential, natural-sounding fades.
- `synth:playNote(hz, volume, seconds)`. Volumes are amplitudes (0 to 1) and add
  up across voices, so keep the sum of a chord under about 0.8.
- ADSR is per synth. For blasts of different shapes (short hits and a long
  tail), make a separate set of synths per shape instead of re-setting ADSR.
- Pitch bends: `synth:setFrequencyMod(lfo)` with `lfo:setDepth(0)`, then move
  `lfo:setCenter(halfSteps)` from a `pd.timer` (use `pd.easingFunctions` for
  curves). Half-steps from a ratio: `12 * log2(ratio)`.
- Timing: `pd.timer.performAfterDelay(ms, fn)`.
- Effects go on a `pd.sound.channel`: `twopolefilter` (low-pass to tame fizz,
  high-pass to thin out), `overdrive` (grit, but harsh on the small speaker).

## Making sounds fuller or less tinny

- Tinny usually means it's all high harmonics. Add a voice an octave down for
  body, and low-pass around 4 kHz to take off the fizz.
- Weak usually means the notes fade too soon. Give hits a short attack, a high
  sustain and a short release, rather than a decay that starts at once.
- Width comes from a detuned unison pair (a few Hz apart), not from more volume.
- Saws are brassy, squares are hollow and buzzy, triangles are soft.

## Web port (site/sim/sound.js)

- `note({ wave, freq, vol, len, a, d, s, r, at, dest })` mirrors
  `synth:playNote` with an ADSR, and returns the oscillator for automation.
  Use the same volumes as the Lua.
- Pitch bends: automate `osc.detune` in cents (100 per half-step), e.g.
  `setTargetAtTime(-60, t, 0.05)` for a quick ease-out slide.
- Check the web version in a browser too; it plays through `master` (0.5 gain).

## Current sounds

| Sound | Lua | Shape |
| --- | --- | --- |
| Dice tick | `playTick` | short square blip, random pitch |
| Landing | `playLand` | triangle; high for crits, low for fumbles |
| Nat 20 | `playHorn` | 3 hits + long blast on F#5 with an F#4 body; holds, slides down, holds. Settings in `HORN` |
| Nat 1 | `playTrombone` | Bb-A-Ab-G saw through a low-pass, vibrato on the last note |

Dice-pool rolls (Dice page) don't play the horn or trombone.
