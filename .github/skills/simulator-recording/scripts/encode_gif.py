"""Turn devrec frames into a small, looping 1-bit GIF.

Usage: encode_gif.py FRAMES_DIR OUT.gif [fps] [scale]
Identical consecutive frames are merged into one longer frame.
"""

import sys
from pathlib import Path

from PIL import Image

frames_dir, out = Path(sys.argv[1]), sys.argv[2]
fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
scale = int(sys.argv[4]) if len(sys.argv) > 4 else 2

paths = sorted(frames_dir.glob("f*.png"))
if not paths:
    sys.exit(f"no frames in {frames_dir}")

frame_ms = 1000.0 / fps
images, durations = [], []
prev = None
for p in paths:
    im = Image.open(p).convert("L").point(lambda v: 255 if v >= 128 else 0).convert("1")
    data = im.tobytes()
    if data == prev:
        durations[-1] += frame_ms
        continue
    prev = data
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    images.append(im.convert("P"))
    durations.append(frame_ms)

# GIF delays are in 10 ms units; carry the rounding error forward so the
# total length stays true to the recording.
ticks, err = [], 0.0
for d in durations:
    t = max(2, round((d + err) / 10))
    err += d - t * 10
    ticks.append(t * 10)

images[0].save(out, save_all=True, append_images=images[1:], duration=ticks, loop=0, optimize=True)
print(f"{out}: {len(paths)} frames -> {len(images)} unique, {sum(ticks) / 1000:.1f}s")
