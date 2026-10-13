---
name: one-bit-assets
description: Create or edit 1-bit Playdate art (launcher card/icon, in-game images, site screenshots) with Pillow. Use when adding images to charsheet/source or site/assets.
---

# 1-bit image assets

- Playdate images are pure black and white. Save PNGs in mode `"1"`, or as `"L"` with only 0 and 255 values. Grey gets dithered unpredictably by `pdc`.
- Launcher sizes: `card.png` is 350×155 and `icon.png` is 32×32 (`charsheet/source/launcher/`). `pdxinfo` uses `imagePath=launcher`.
- `card-highlighted/` and `icon-highlighted/` hold the frames (`1.png`, `2.png`, …) that loop while the game is selected in the launcher. `card-highlighted/animation.txt` sets the frame order and holds. Their rest frames must match `card.png`/`icon.png` pixel for pixel. Run with `--preview` to get a GIF.
- `charsheet/tools/make_launcher_art.py` regenerates the launcher art. Edit and rerun it; don't hand-edit the PNGs.
- Get Pillow from a throwaway venv, not system pip:
  `python3 -m venv /tmp/pilenv && /tmp/pilenv/bin/pip install pillow`.
- Text: use the Playdate system fonts in `charsheet/source/fonts/` (Panic's license, not MIT) or draw pixel glyphs. Disable antialiasing by drawing on a mode-`"1"` image.
- Upscale for the web with `Image.NEAREST` only, and give it the `.pixel` class (`image-rendering: pixelated`) in `site/`.
- Make site screenshots and GIFs with the `playdate-simulator-harness` skill, then crop and assemble them with Pillow (`save(..., save_all=True, duration=..., loop=0)` for GIFs).
- Check results by viewing the PNG, never by screenshotting the desktop.
