---
name: playdate-device
description: Deploy Crit Crank to a USB-connected Playdate, drive it with button presses over serial, and capture its screen. Use when testing on real hardware or when the user says "put it on the device".
---

# Playdate device: deploy, drive, screenshot

## Find the tools
- `pdutil` is in `$PLAYDATE_SDK_PATH/bin/pdutil` (usually `~/Developer/PlaydateSDK/bin/pdutil`). It is **not** on PATH.
- The serial port is `/dev/cu.usbmodemPD*` on macOS and `/dev/ttyACM*` on Linux. If nothing shows up, ask the user to plug in and unlock the device.
- Only one process can hold the port at a time. Quit the Simulator and stop any `pdutil` or `charsync` sessions first.

## Deploy a build
`task device` (or `charsheet/tools/deploy-device.sh` after a build) does all of this. The manual steps:
```sh
cd charsheet && make build
P=$(ls /dev/cu.usbmodemPD* | head -1); PDUTIL=~/Developer/PlaydateSDK/bin/pdutil
$PDUTIL $P datadisk                       # device reboots into USB disk mode
# wait for /Volumes/PLAYDATE/Games to appear (poll ~1s, up to 30s)
rm -rf /Volumes/PLAYDATE/Games/critcrank.pdx
cp -R critcrank.pdx /Volumes/PLAYDATE/Games/
diskutil eject /Volumes/PLAYDATE         # if DLP/Defender blocks this, ask the user to eject
# wait for the serial port to come back, then:
$PDUTIL $P run /Games/critcrank.pdx
```
The device path must stay `/Games/critcrank.pdx`; don't rename the bundle.

## Drive it and capture the screen
Use `scripts/pdserial.py`, which needs only the Python standard library:
```sh
python3 .github/skills/playdate-device/scripts/pdserial.py "btn down" "btn a" "btn menu"
python3 .github/skills/playdate-device/scripts/pdserial.py --screen /tmp/dev.png   # then view the PNG
```
- Buttons: `btn a|b|up|down|left|right|menu`. There's no crank-angle command, so use Ⓐ quick roll instead.
- The device echoes `msg` lines back. When the game replies over serial, prefix lines with `cs ` so the replies can be told apart from the echo.
- **Never screenshot the user's desktop.** Use `--screen` instead.

## Saved data
Game data lives at `/Data/com.christrevino.charsheet/` on the device (visible in datadisk mode). Back it up before experiments that overwrite saves.
