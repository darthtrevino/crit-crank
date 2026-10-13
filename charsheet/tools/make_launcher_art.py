import math, sys, os
from PIL import Image, ImageDraw, ImageFont

# Generates the 1-bit Playdate launcher art. Usage: python make_launcher_art.py [outdir] [--preview]
OUT = next((a for a in sys.argv[1:] if not a.startswith("-")), os.path.join(os.path.dirname(__file__), "..", "source", "launcher"))
S = 4  # supersample
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"

def hexpts(cx, cy, r):
    return [(cx + r*math.cos(math.radians(-90+60*k)), cy + r*math.sin(math.radians(-90+60*k))) for k in range(6)]

def d20(d, cx, cy, r, lw, num=True, font_px=None, label="20"):
    V = hexpts(cx, cy, r)
    T = [(cx + 0.58*r*math.cos(math.radians(a)), cy + 0.58*r*math.sin(math.radians(a))) for a in (-90, 30, 150)]
    d.polygon(V, fill=255)
    d.line(V + [V[0]], fill=0, width=lw, joint="curve")
    d.line(T + [T[0]], fill=0, width=lw, joint="curve")
    for t, vs in ((T[0], (0, 1, 5)), (T[1], (1, 2, 3)), (T[2], (3, 4, 5))):
        for i in vs:
            d.line([t, V[i]], fill=0, width=lw)
    for p in V + T:
        d.ellipse([p[0]-lw/2, p[1]-lw/2, p[0]+lw/2, p[1]+lw/2], fill=0)
    if num:
        d.polygon(T, fill=0)
        f = ImageFont.truetype(FONT, font_px)
        # center the glyph ink (not the font metrics) on the facet's centroid
        x0, y0, x1, y1 = d.textbbox((0, 0), label, font=f, anchor="lt")
        gx, gy = sum(p[0] for p in T) / 3, sum(p[1] for p in T) / 3 + 0.04*r
        d.text((gx - (x0 + x1) / 2, gy - (y0 + y1) / 2), label, font=f, fill=255, anchor="lt")

def crank(d, hx, hy, r, lw, angle=35, part="all"):
    # hub on the die's right side, arm and knob
    hub = r*0.20
    a = math.radians(angle)
    L = r*0.80
    ex, ey = hx + L*math.cos(a), hy + L*math.sin(a)
    if part in ("all", "arm"):
        d.line([(hx, hy), (ex, ey)], fill=0, width=int(lw*2.6))
        kw, kl = r*0.15, r*0.40
        # knob perpendicular to the arm (pointing "out" toward viewer = down-right)
        d.rounded_rectangle([ex-kw, ey-kw*0.6, ex+kw, ey+kl], radius=kw, fill=0)
    if part in ("all", "hub"):
        d.ellipse([hx-hub, hy-hub, hx+hub, hy+hub], fill=0)
        d.ellipse([hx-hub*0.4, hy-hub*0.4, hx+hub*0.4, hy+hub*0.4], fill=255)

def burst(d, cx, cy, r0, r1, n, lw, skip=(), offset=7):
    for k in range(n):
        deg = (360*k/n + offset) % 360
        if any(lo <= deg <= hi for lo, hi in skip):
            continue
        a = math.radians(deg)
        d.line([(cx+r0*math.cos(a), cy+r0*math.sin(a)), (cx+r1*math.cos(a), cy+r1*math.sin(a))], fill=0, width=lw)

def to1bit(img, size):
    return img.resize(size, Image.LANCZOS).point(lambda v: 255 if v > 140 else 0).convert("1")

CRANK_REST = 40
ROLL = ["3", "17", "8", "12", "5", "19", "1", "14", "9", "16", "11", "6"]

def card(angle=CRANK_REST, label="20", rays="rest"):
    W, H = 350*S, 155*S
    im = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(im)
    # border
    d.rounded_rectangle([3*S, 3*S, W-4*S, H-4*S], radius=10*S, outline=0, width=3*S)
    cx, cy, r = 72*S, 72*S, 48*S
    if rays == "rest":
        burst(d, cx, cy, r*1.12, r*1.36, 16, 3*S, skip=((-1, 75),))
    elif rays == "twinkle":
        burst(d, cx, cy, r*1.08, r*1.26, 16, 3*S, skip=((-1, 75),), offset=7 + 360/32)
    hx, hy = cx + r*0.87, cy
    # the arm swings behind the die when it points left; the hub stays on top
    crank(d, hx, hy, r, 3*S, angle=angle, part="arm")
    d20(d, cx, cy, r, 3*S, font_px=17*S, label=label)
    if angle % 360 == CRANK_REST:
        crank(d, hx, hy, r, 3*S, angle=angle, part="arm")
    crank(d, hx, hy, r, 3*S, angle=angle, part="hub")
    f = ImageFont.truetype(FONT, 42*S)
    tx = 152*S
    # a white halo keeps the title readable when the knob swings past it
    halo = dict(font=f, fill=0, anchor="ls", stroke_width=2*S, stroke_fill=255)
    d.text((tx, 66*S), "CRIT", **halo)
    d.text((tx, 112*S), "CRANK", **halo)
    fs = ImageFont.truetype(FONT, 11*S)
    d.text((tx + 2*S, 134*S), "CRANK-POWERED 5E", font=fs, fill=0, anchor="ls")
    return to1bit(im, (350, 155))

def card_highlighted():
    # one crank turn while the die ticks through faces, then a nat 20 that twinkles
    step = 360 / len(ROLL)
    frames = [card(CRANK_REST + step*(k+1), n, rays=None) for k, n in enumerate(ROLL[:-1])]
    frames += [card(CRANK_REST + 360, ROLL[-1], rays=None), card(), card(rays="twinkle")]
    n = len(ROLL)
    seq = ", ".join(str(k) for k in range(1, n+1))
    anim = (f"frames = {seq}, {n+1}x8, {n+2}x3, {n+1}x3, {n+2}x3, {n+1}x20\n")
    return frames, anim
def icon(angle=90):
    # hand-tuned at native size for crispness
    im = Image.new("1", (32, 32), 1)
    d = ImageDraw.Draw(im)
    cx, cy, r = 11, 15, 11
    V = [(round(x), round(y)) for x, y in hexpts(cx, cy, r)]
    T = [(round(cx + 0.52*r*math.cos(math.radians(a))), round(cy + 0.52*r*math.sin(math.radians(a)))) for a in (-90, 30, 150)]
    # the crank turns edge-on to the viewer, so its sideways swing is foreshortened
    hx, Lx, Ly = 26, 3, 10
    ex = round(hx + Lx*math.cos(math.radians(angle)))
    ey = round(cy + Ly*math.sin(math.radians(angle)))
    # crank arm and knob sit behind the die
    d.line([(hx, cy), (ex, ey)], fill=0, width=2)
    d.rounded_rectangle([ex-2, ey, ex+4, ey+5], radius=2, fill=0)
    d.polygon(V, fill=1, outline=0)
    d.line(V + [V[0]], fill=0, width=1)
    d.line(T + [T[0]], fill=0, width=1)
    for t, vs in ((T[0], (0, 1, 5)), (T[1], (1, 2, 3)), (T[2], (3, 4, 5))):
        for i in vs:
            d.line([t, V[i]], fill=0, width=1)
    # solid center facet
    d.polygon(T, fill=0)
    # crank: shaft from the die to the hub
    d.line([(cx+r, cy), (hx, cy)], fill=0, width=1)
    d.ellipse([hx-3, cy-3, hx+3, cy+3], fill=0)
    d.point((hx, cy), fill=1)
    return im

def icon_highlighted():
    return [icon(90 + 45*(k+1)) for k in range(8)]

def save_frames(folder, frames, anim=None):
    path = os.path.join(OUT, folder)
    os.makedirs(path, exist_ok=True)
    for f in os.listdir(path):
        os.remove(os.path.join(path, f))
    for k, im in enumerate(frames, 1):
        im.save(os.path.join(path, f"{k}.png"))
    if anim:
        with open(os.path.join(path, "animation.txt"), "w") as fh:
            fh.write(anim)

os.makedirs(OUT, exist_ok=True)
c = card(); c.save(os.path.join(OUT, "card.png"))
i = icon(); i.save(os.path.join(OUT, "icon.png"))
cards, anim = card_highlighted()
save_frames("card-highlighted", cards, anim)
icons = icon_highlighted()
save_frames("icon-highlighted", icons)
if "--preview" in sys.argv:
    c.convert("L").resize((700, 310), Image.NEAREST).save(os.path.join(OUT, "preview-card@2x.png"))
    i.convert("L").resize((256, 256), Image.NEAREST).save(os.path.join(OUT, "preview-icon@8x.png"))
    big = [f.convert("L").resize((700, 310), Image.NEAREST) for f in cards]
    big[0].save(os.path.join(OUT, "preview-card-highlighted@2x.gif"), save_all=True, append_images=big[1:], duration=50, loop=0)
    sheet = Image.new("L", (32*8*4, 32*4), 255)
    for k, f in enumerate(icons):
        sheet.paste(f.convert("L").resize((128, 128), Image.NEAREST), (128*k, 0))
    sheet.save(os.path.join(OUT, "preview-icon-highlighted@4x.png"))
