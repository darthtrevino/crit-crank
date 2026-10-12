import math, sys, os
from PIL import Image, ImageDraw, ImageFont

# Generates the 1-bit Playdate launcher art. Usage: python make_launcher_art.py [outdir] [--preview]
OUT = next((a for a in sys.argv[1:] if not a.startswith("-")), os.path.join(os.path.dirname(__file__), "..", "source", "launcher"))
S = 4  # supersample
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"

def hexpts(cx, cy, r):
    return [(cx + r*math.cos(math.radians(-90+60*k)), cy + r*math.sin(math.radians(-90+60*k))) for k in range(6)]

def d20(d, cx, cy, r, lw, num=True, font_px=None):
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
        x0, y0, x1, y1 = d.textbbox((0, 0), "20", font=f, anchor="lt")
        gx, gy = sum(p[0] for p in T) / 3, sum(p[1] for p in T) / 3 + 0.04*r
        d.text((gx - (x0 + x1) / 2, gy - (y0 + y1) / 2), "20", font=f, fill=255, anchor="lt")

def crank(d, hx, hy, r, lw, angle=35):
    # hub on the die's right side, arm and knob
    hub = r*0.20
    a = math.radians(angle)
    L = r*0.80
    ex, ey = hx + L*math.cos(a), hy + L*math.sin(a)
    d.line([(hx, hy), (ex, ey)], fill=0, width=int(lw*2.6))
    d.ellipse([hx-hub, hy-hub, hx+hub, hy+hub], fill=0)
    d.ellipse([hx-hub*0.4, hy-hub*0.4, hx+hub*0.4, hy+hub*0.4], fill=255)
    kw, kl = r*0.15, r*0.40
    # knob perpendicular to the arm (pointing "out" toward viewer = down-right)
    d.rounded_rectangle([ex-kw, ey-kw*0.6, ex+kw, ey+kl], radius=kw, fill=0)

def burst(d, cx, cy, r0, r1, n, lw, skip=()):
    for k in range(n):
        deg = (360*k/n + 7) % 360
        if any(lo <= deg <= hi for lo, hi in skip):
            continue
        a = math.radians(deg)
        d.line([(cx+r0*math.cos(a), cy+r0*math.sin(a)), (cx+r1*math.cos(a), cy+r1*math.sin(a))], fill=0, width=lw)

def to1bit(img, size):
    return img.resize(size, Image.LANCZOS).point(lambda v: 255 if v > 140 else 0).convert("1")

def card():
    W, H = 350*S, 155*S
    im = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(im)
    # border
    d.rounded_rectangle([3*S, 3*S, W-4*S, H-4*S], radius=10*S, outline=0, width=3*S)
    cx, cy, r = 72*S, 72*S, 48*S
    burst(d, cx, cy, r*1.12, r*1.36, 16, 3*S, skip=((-1, 75),))
    d20(d, cx, cy, r, 3*S, font_px=17*S)
    crank(d, cx + r*0.87, cy + r*0.0, r, 3*S, angle=40)
    f = ImageFont.truetype(FONT, 42*S)
    tx = 152*S
    d.text((tx, 66*S), "CRIT", font=f, fill=0, anchor="ls")
    d.text((tx, 112*S), "CRANK", font=f, fill=0, anchor="ls")
    fs = ImageFont.truetype(FONT, 11*S)
    d.text((tx + 2*S, 134*S), "CRANK-POWERED 5E", font=fs, fill=0, anchor="ls")
    return to1bit(im, (350, 155))

def icon():
    # hand-tuned at native size for crispness
    im = Image.new("1", (32, 32), 1)
    d = ImageDraw.Draw(im)
    cx, cy, r = 11, 15, 11
    V = [(round(x), round(y)) for x, y in hexpts(cx, cy, r)]
    T = [(round(cx + 0.52*r*math.cos(math.radians(a))), round(cy + 0.52*r*math.sin(math.radians(a)))) for a in (-90, 30, 150)]
    # crank behind die
    pass
    d.polygon(V, fill=1, outline=0)
    d.line(V + [V[0]], fill=0, width=1)
    d.line(T + [T[0]], fill=0, width=1)
    for t, vs in ((T[0], (0, 1, 5)), (T[1], (1, 2, 3)), (T[2], (3, 4, 5))):
        for i in vs:
            d.line([t, V[i]], fill=0, width=1)
    # solid center facet
    d.polygon(T, fill=0)
    # crank: hub on right edge, arm down-right, knob
    d.line([(cx+r, cy), (26, cy)], fill=0, width=1)
    d.ellipse([23, cy-3, 29, cy+3], fill=0)
    d.point((26, cy), fill=1)
    d.line([(26, cy+3), (26, 25)], fill=0, width=2)
    d.rounded_rectangle([24, 25, 30, 30], radius=2, fill=0)
    return im

os.makedirs(OUT, exist_ok=True)
c = card(); c.save(os.path.join(OUT, "card.png"))
i = icon(); i.save(os.path.join(OUT, "icon.png"))
if "--preview" in sys.argv:
    c.convert("L").resize((700, 310), Image.NEAREST).save(os.path.join(OUT, "preview-card@2x.png"))
    i.convert("L").resize((256, 256), Image.NEAREST).save(os.path.join(OUT, "preview-icon@8x.png"))
