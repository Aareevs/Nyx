#!/usr/bin/env python3
"""Draws the DMG window background (Tools/dmg/background.tiff, 1x + 2x).

The Nyx and Applications icons are placed over it by Finder (see
Tools/make-release.sh), so this only draws the panels, titles and the arrow.
Run it again after changing the design: python3 Tools/dmg/make-background.py
"""
import os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "..", "Resources", "Brand", "nyx-logo-source.png")
W, H = 660, 400
S = 2  # draw at 2x
INK, PANEL, CREAM = (23, 23, 27), (20, 20, 24), (243, 237, 224)

def font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size * S, index=index)
    except Exception:
        return ImageFont.load_default()

HELV = "/System/Library/Fonts/HelveticaNeue.ttc"
MONO = "/System/Library/Fonts/Menlo.ttc"

img = Image.new("RGB", (W * S, H * S), CREAM)
d = ImageDraw.Draw(img)

# Left panel with a soft glow behind the logo.
LP = 230
d.rectangle([0, 0, LP * S, H * S], fill=PANEL)
glow = Image.new("RGB", (W * S, H * S), PANEL)
gd = ImageDraw.Draw(glow)
cx, cy = LP * S // 2, H * S // 2
gd.ellipse([cx - 90 * S, cy - 90 * S, cx + 90 * S, cy + 90 * S], fill=(46, 40, 52))
glow = glow.filter(ImageFilter.GaussianBlur(60 * S))
img.paste(glow.crop((0, 0, LP * S, H * S)), (0, 0))
d = ImageDraw.Draw(img)
d.line([LP * S, 0, LP * S, H * S], fill=(0, 0, 0), width=2 * S)

logo = Image.open(LOGO).convert("RGBA")
logo = logo.crop(logo.getbbox())
lw = 190 * S
logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
img.paste(logo, ((LP * S - lw) // 2, (H * S - logo.height) // 2), logo)
d = ImageDraw.Draw(img)

# Right side: title, rule, subtitle.
X = LP + 36
d.text((X * S, 38 * S), "Nyx", font=font(HELV, 56, 1), fill=(14, 14, 16))
d.line([X * S, 118 * S, (W - 28) * S, 118 * S], fill=(120, 116, 108), width=S)
d.polygon([((X) * S, 113 * S), ((X + 6) * S, 118 * S), (X * S, 123 * S), ((X - 6) * S, 118 * S)], fill=(34, 34, 40))
d.text((X * S, 132 * S), "Menu bar  ·  Dynamic Island  ·  one app", font=font(MONO, 12), fill=(90, 86, 80))

# Drop target behind Applications (icon at x=545, y=225).
ax, ay, r = 545, 225, 56
dash = (205, 198, 184)
d.rounded_rectangle([(ax - r) * S, (ay - r) * S, (ax + r) * S, (ay + r) * S], radius=26 * S, fill=(235, 228, 213))
import math
# Dashed outline.
def dashed_round(box, rad, dash_len, gap, color, width):
    x0, y0, x1, y1 = box
    pts = []
    n = 400
    # perimeter samples of a rounded rect
    def arc(cx_, cy_, a0):
        return [(cx_ + rad * math.cos(math.radians(a0 + t * 90 / 20)), cy_ + rad * math.sin(math.radians(a0 + t * 90 / 20))) for t in range(21)]
    pts += arc(x1 - rad, y0 + rad, -90)
    pts += arc(x1 - rad, y1 - rad, 0)
    pts += arc(x0 + rad, y1 - rad, 90)
    pts += arc(x0 + rad, y0 + rad, 180)
    pts.append(pts[0])
    acc, on = 0.0, True
    for (a, b) in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        # alternate dash state by accumulated length
        steps = max(1, int(seg))
        for i in range(steps):
            acc += seg / steps
            if acc >= (dash_len if on else gap):
                acc, on = 0.0, not on
            if on:
                p = (a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps)
                d.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=color)
dashed_round(((ax - r) * S, (ay - r) * S, (ax + r) * S, (ay + r) * S), 26 * S, 10 * S, 7 * S, dash, 3 * S)

# Arrow with step squares between the two icons.
y = 225
for i in range(4):
    x = 382 + i * 15
    d.rectangle([x * S, (y - 5) * S, (x + 10) * S, (y + 5) * S],
                outline=(70, 66, 62), width=S, fill=(34, 34, 40) if i == 3 else None)
d.line([450 * S, y * S, 465 * S, y * S], fill=(14, 14, 16), width=2 * S)
d.polygon([(465 * S, (y - 6) * S), (475 * S, y * S), (465 * S, (y + 6) * S)], fill=(14, 14, 16))

# Bottom instruction.
d.line([X * S, 330 * S, (W - 28) * S, 330 * S], fill=(120, 116, 108), width=S)
d.text((X * S, 344 * S), "DRAG NYX ONTO APPLICATIONS TO INSTALL", font=font(MONO, 11), fill=(70, 66, 62))
d.text((X * S, 364 * S), "First launch: System Settings › Privacy & Security › Open Anyway", font=font(MONO, 9), fill=(120, 116, 108))

tmp = tempfile.mkdtemp()
p2 = os.path.join(tmp, "bg@2x.png")
p1 = os.path.join(tmp, "bg.png")
img.save(p2, dpi=(144, 144))
img.resize((W, H), Image.LANCZOS).save(p1, dpi=(72, 72))
subprocess.run(["tiffutil", "-cathidpicheck", p1, p2, "-out", os.path.join(HERE, "background.tiff")], check=True)
img.save(os.path.join(HERE, "preview.png"))
print("wrote", os.path.join(HERE, "background.tiff"))
