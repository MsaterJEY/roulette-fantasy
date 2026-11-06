"""The minigame window's art: an old map on parchment, with torn edges, and a compass.

Run from the project folder:  python tools/make_parchment.py
Writes assets/ui/parchment.png and assets/ui/compass.png. Replace either with real art.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"
W, H = 1120, 744  # twice the window's size
INK = (92, 58, 26)


def clouds(scale, seed):
    """Soft grey noise, `scale` pixels to a blob."""
    random.seed(seed)
    small = Image.new("L", (W // scale + 2, H // scale + 2))
    small.putdata([random.randint(0, 255) for _ in range(small.width * small.height)])
    return small.resize((W, H), Image.BICUBIC)


def torn_edge():
    """The sheet's outline: a rectangle with a wobbling, nibbled edge."""
    random.seed(4)
    pts = []
    m = 14

    def side(a, b, steps):
        for i in range(steps):
            t = i / steps
            x = a[0] + (b[0] - a[0]) * t + random.uniform(-5, 5)
            y = a[1] + (b[1] - a[1]) * t + random.uniform(-5, 5)
            pts.append((x, y))

    side((m, m), (W - m, m), 70)
    side((W - m, m), (W - m, H - m), 46)
    side((W - m, H - m), (m, H - m), 70)
    side((m, H - m), (m, m), 46)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(1.2))


def coast(d, cx, cy, r, seed):
    """A made-up island's outline."""
    random.seed(seed)
    pts = []
    for i in range(60):
        a = i / 60 * math.tau
        rr = r * (1 + 0.28 * math.sin(a * 3 + seed) + 0.14 * math.sin(a * 7 + seed * 2) + random.uniform(-0.05, 0.05))
        pts.append((cx + math.cos(a) * rr * 1.3, cy + math.sin(a) * rr))
    d.line(pts + pts[:1], fill=INK + (70,), width=3)


def parchment():
    base = Image.new("RGB", (W, H), (231, 203, 152))
    grain = clouds(3, 1)
    blotch = clouds(90, 2)
    tint = Image.merge("RGB", [g.point(lambda v, k=k: int(255 - (255 - v) * k)) for g, k in
                               ((blotch, 0.1), (blotch, 0.13), (blotch, 0.18))])
    base = ImageChops.multiply(base, tint)
    fine = Image.merge("RGB", [grain.point(lambda v: int(255 - (255 - v) * 0.1))] * 3)
    base = ImageChops.multiply(base, fine)

    # the map, faint under the writing
    art = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    for x in range(140, W, 210):
        d.line([(x, 30), (x, H - 30)], fill=INK + (22,), width=2)
    for y in range(120, H, 170):
        d.line([(30, y), (W - 30, y)], fill=INK + (22,), width=2)
    coast(d, 960, 150, 90, 3)
    coast(d, 1000, 560, 110, 5)
    coast(d, 150, 620, 90, 7)
    for i in range(16):  # a dotted route between them
        t = i / 15
        x = 240 + (870 - 240) * t
        y = 610 - 120 * math.sin(t * math.pi) - 60 * t
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=INK + (46,))
    base.paste(art, (0, 0), art)

    # burnt edges
    mask = torn_edge()
    inner = mask.filter(ImageFilter.GaussianBlur(22))
    burn = Image.new("RGB", (W, H), (96, 54, 22))
    edge = inner.point(lambda v: min(255, int(v * 1.05)))
    sheet = Image.composite(base, burn, edge)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(sheet, (0, 0), mask)
    return out


def compass():
    s = 192
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    d.ellipse([10, 10, s - 10, s - 10], outline=INK + (255,), width=6)
    d.ellipse([26, 26, s - 26, s - 26], outline=(150, 104, 44, 255), width=3)
    for i in range(4):  # the short points, then the long ones over them
        a = math.radians(45 + i * 90)
        tip = (c + math.cos(a) * 60, c + math.sin(a) * 60)
        d.polygon([tip, (c + math.cos(a + 1.57) * 12, c + math.sin(a + 1.57) * 12),
                   (c + math.cos(a - 1.57) * 12, c + math.sin(a - 1.57) * 12)], fill=(150, 104, 44, 255))
    for i in range(4):
        a = math.radians(i * 90)
        tip = (c + math.cos(a) * 88, c + math.sin(a) * 88)
        left = (c + math.cos(a + 1.57) * 17, c + math.sin(a + 1.57) * 17)
        right = (c + math.cos(a - 1.57) * 17, c + math.sin(a - 1.57) * 17)
        d.polygon([tip, left, (c, c)], fill=INK + (255,))
        d.polygon([tip, right, (c, c)], fill=(214, 164, 72, 255))
    d.ellipse([c - 9, c - 9, c + 9, c + 9], fill=(214, 164, 72, 255), outline=INK + (255,), width=3)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    parchment().resize((840, 558), Image.LANCZOS).save(OUT / "parchment.png", optimize=True)
    compass().save(OUT / "compass.png", optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
