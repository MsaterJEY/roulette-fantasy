"""Placeholder pixel icons for cards and effects (16x16, transparent), one per id.

Run from the project folder:  python tools/make_icons.py
Writes assets/icons/<id>.png for every card id in data/cards.json, the effect 'free_block'
and the HUD icons (dice, shop, swords, ring, shard, cards, star, turn). Replace any file with real art (square, any size; shown with nearest filtering).
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icons"
K = (24, 16, 20, 255)  # outline
WHITE = (250, 246, 236, 255)
GOLD = (232, 188, 72, 255)
BLUE = (66, 134, 214, 255)
BLUE_D = (40, 88, 160, 255)
GREEN = (70, 190, 90, 255)
GREEN_D = (40, 130, 60, 255)
RED = (214, 60, 60, 255)
RED_D = (150, 30, 40, 255)
PURPLE = (150, 80, 200, 255)
SILVER = (200, 210, 225, 255)
BROWN = (120, 76, 40, 255)


def new():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def shield(d, fill, dark):
    d.polygon([(8, 1), (14, 3), (13, 9), (8, 14), (3, 9), (2, 3)], fill=fill, outline=K)
    d.line([(8, 2), (8, 13)], fill=dark)


def heart(d, x, y, fill):
    d.rectangle([x + 1, y, x + 2, y], fill=fill)
    d.rectangle([x + 4, y, x + 5, y], fill=fill)
    d.rectangle([x, y + 1, x + 6, y + 2], fill=fill)
    d.rectangle([x + 1, y + 3, x + 5, y + 3], fill=fill)
    d.rectangle([x + 2, y + 4, x + 4, y + 4], fill=fill)
    d.point((x + 3, y + 5), fill=fill)


def slash(d):
    d.ellipse([1, 1, 14, 14], outline=RED, width=2)
    d.line([(3, 12), (12, 3)], fill=RED, width=2)


def attack():
    img, d = new()
    d.line([(3, 12), (12, 3)], fill=SILVER, width=3)
    d.line([(4, 12), (13, 3)], fill=WHITE, width=1)
    d.line([(2, 9), (6, 13)], fill=GOLD, width=2)
    d.line([(1, 14), (3, 12)], fill=BROWN, width=2)
    return img


def defense():
    img, d = new()
    shield(d, BLUE, BLUE_D)
    d.line([(8, 4), (8, 11)], fill=WHITE)
    d.line([(5, 6), (11, 6)], fill=WHITE)
    return img


def heal(n):
    def make():
        img, d = new()
        if n == 1:
            heart(d, 4, 4, RED)
        else:
            heart(d, 1, 2, RED)
            heart(d, 8, 7, RED)
        d.rectangle([11, 1, 12, 6], fill=GREEN)
        d.rectangle([9, 3, 14, 4], fill=GREEN)
        return img
    return make


def gain_defense():
    img, d = new()
    shield(d, BLUE, BLUE_D)
    d.rectangle([7, 4, 8, 10], fill=GREEN)
    d.rectangle([5, 6, 10, 7], fill=GREEN)
    return img


def sparkle(d, x, y, c):
    d.line([(x, y - 3), (x, y + 3)], fill=c)
    d.line([(x - 3, y), (x + 3, y)], fill=c)
    d.point([(x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)], fill=c)


def cleanse(n):
    def make():
        img, d = new()
        sparkle(d, 8, 8, WHITE)
        if n > 1:
            sparkle(d, 3, 3, GOLD)
            sparkle(d, 12, 12, GOLD)
        else:
            d.point([(8, 8)], fill=GOLD)
        return img
    return make


def no_items():
    img, d = new()
    d.rectangle([4, 6, 11, 13], fill=BROWN, outline=K)  # bag
    d.rectangle([6, 3, 9, 6], outline=K)
    slash(d)
    return img


def ward_no_items():
    img, d = new()
    d.rectangle([3, 7, 10, 14], fill=BROWN, outline=K)  # bag, curse lifted
    d.rectangle([5, 4, 8, 7], outline=K)
    sparkle(d, 12, 4, WHITE)
    d.point([(12, 4)], fill=GREEN)
    return img


def no_shop():
    img, d = new()
    d.ellipse([3, 3, 12, 12], fill=GOLD, outline=K)  # coin
    d.rectangle([7, 5, 8, 10], fill=BROWN)
    slash(d)
    return img


def truce():
    img, d = new()
    d.line([(4, 1), (4, 15)], fill=BROWN, width=2)
    d.polygon([(5, 2), (14, 3), (12, 6), (14, 9), (5, 8)], fill=WHITE, outline=K)
    return img


def bad_luck():
    img, d = new()
    black = (34, 30, 40, 255)
    d.polygon([(3, 2), (6, 6), (10, 6), (13, 2), (13, 12), (3, 12)], fill=black)
    d.ellipse([3, 5, 13, 14], fill=black)
    d.rectangle([5, 8, 6, 9], fill=(250, 210, 60, 255))
    d.rectangle([10, 8, 11, 9], fill=(250, 210, 60, 255))
    d.point((8, 11), fill=(230, 120, 140, 255))
    return img


def blind():
    img, d = new()
    d.ellipse([1, 4, 14, 11], fill=WHITE, outline=K)
    d.ellipse([5, 5, 10, 10], fill=PURPLE)
    d.rectangle([7, 7, 8, 8], fill=K)
    d.line([(2, 14), (14, 1)], fill=K, width=2)
    return img


def free_block():
    img, d = new()
    shield(d, (120, 190, 255, 255), BLUE)
    d.polygon([(8, 4), (9, 7), (12, 7), (9, 9), (10, 12), (8, 10), (6, 12), (7, 9), (4, 7), (7, 7)], fill=GOLD)
    return img


def dice():
    img, d = new()
    d.rectangle([2, 2, 13, 13], fill=WHITE, outline=K)
    for x, y in [(4, 4), (10, 4), (7, 7), (4, 10), (10, 10)]:
        d.rectangle([x, y, x + 1, y + 1], fill=K)
    return img


def corners(inward):
    """Four L-shaped corner marks: at the edges (go full screen), or turned round near the
    middle (back to a window). Drawn for the top left and mirrored."""
    img, d = new()
    if inward:  # the corner points at the middle, the arms reach out
        arms = [(2, 5, 6, 6), (5, 2, 6, 6)]
    else:  # the corner sits at the edge, the arms reach in
        arms = [(1, 1, 5, 2), (1, 1, 2, 5)]
    for x0, y0, x1, y1 in arms:
        for fx in (False, True):
            for fy in (False, True):
                xs = (15 - x1, 15 - x0) if fx else (x0, x1)
                ys = (15 - y1, 15 - y0) if fy else (y0, y1)
                d.rectangle([xs[0], ys[0], xs[1], ys[1]], fill=WHITE)
    return img


def shop():
    img, d = new()
    d.rectangle([2, 6, 13, 14], fill=GOLD, outline=K)  # bag
    d.arc([5, 1, 10, 9], 180, 360, fill=K, width=2)
    d.rectangle([6, 9, 9, 11], fill=BROWN)
    return img


def swords():
    img, d = new()
    for a, b in (((2, 2), (12, 12)), ((13, 2), (3, 12))):
        d.line([a, b], fill=SILVER, width=2)
    d.line([(1, 12), (4, 15)], fill=GOLD, width=2)
    d.line([(14, 12), (11, 15)], fill=GOLD, width=2)
    return img


def ring():
    img, d = new()
    d.ellipse([3, 5, 12, 14], outline=GOLD, width=2)
    d.polygon([(7, 1), (9, 1), (11, 4), (8, 6), (5, 4)], fill=(120, 200, 255, 255), outline=K)
    return img


def shard():
    img, d = new()
    d.polygon([(8, 1), (13, 7), (8, 15), (3, 7)], fill=(120, 200, 255, 255), outline=K)
    d.line([(8, 2), (8, 14)], fill=(200, 240, 255, 255))
    return img


def cards():
    img, d = new()
    d.rectangle([2, 3, 9, 13], fill=(39, 48, 107, 255), outline=GOLD)
    d.rectangle([6, 2, 13, 12], fill=(39, 48, 107, 255), outline=GOLD)
    return img


def star():
    img, d = new()
    d.polygon([(8, 1), (10, 6), (15, 6), (11, 9), (13, 15), (8, 11), (3, 15), (5, 9), (1, 6), (6, 6)],
              fill=GOLD, outline=K)
    return img


def turn():
    img, d = new()
    d.ellipse([3, 3, 12, 12], fill=(255, 215, 106, 255), outline=K)
    d.ellipse([6, 6, 9, 9], fill=WHITE)
    return img


def blood_sword():
    img, d = new()
    d.line([(3, 12), (12, 3)], fill=(150, 15, 30, 255), width=3)
    d.line([(4, 12), (13, 3)], fill=(255, 90, 100, 255), width=1)
    d.line([(2, 9), (6, 13)], fill=(40, 30, 40, 255), width=2)
    d.line([(1, 14), (3, 12)], fill=(90, 20, 30, 255), width=2)
    d.point([(13, 6), (12, 8)], fill=(214, 60, 60, 255))  # drips
    return img


def arcane_sword():
    img, d = new()
    d.line([(3, 12), (12, 3)], fill=(110, 224, 255, 255), width=3)
    d.line([(4, 12), (13, 3)], fill=WHITE, width=1)
    d.line([(2, 9), (6, 13)], fill=GOLD, width=2)
    d.line([(1, 14), (3, 12)], fill=(46, 79, 160, 255), width=2)
    sparkle(d, 12, 11, (180, 240, 255, 255))
    return img


def thorn_bow():
    img, d = new()
    d.arc([2, 1, 12, 15], 280, 80, fill=BROWN, width=2)
    d.line([(9, 2), (9, 14)], fill=(150, 255, 150, 255))  # string
    d.line([(3, 8), (14, 8)], fill=(200, 180, 120, 255))  # arrow
    d.polygon([(14, 6), (15, 8), (14, 10)], fill=GREEN)
    return img


def flame_claw():
    img, d = new()
    for x in (3, 7, 11):
        d.line([(x, 2), (x + 2, 13)], fill=(255, 140, 40, 255), width=2)
        d.point((x + 1, 2), fill=(255, 230, 120, 255))
    d.line([(2, 14), (14, 14)], fill=RED_D, width=1)
    return img


def gear():
    img, d = new()
    d.rectangle((6, 1, 9, 14), fill=WHITE)
    d.rectangle((1, 6, 14, 9), fill=WHITE)
    for x, y in ((2, 2), (11, 2), (2, 11), (11, 11)):
        d.rectangle((x, y, x + 2, y + 2), fill=WHITE)
    d.ellipse((3, 3, 12, 12), fill=WHITE)
    d.ellipse((6, 6, 9, 9), fill=(0, 0, 0, 0))
    return img


ICONS = {
    "attack": attack, "defense": defense, "heal_1": heal(1), "heal_2": heal(2),
    "gain_defense": gain_defense, "cleanse_1": cleanse(1), "cleanse_all": cleanse(3),
    "no_items": no_items, "ward_no_items": ward_no_items, "no_shop": no_shop, "truce": truce, "bad_luck": bad_luck,
    "blind": blind, "free_block": free_block,
    # HUD: dice roll, shop, combat, rings, shards, hand size, minigame, turn marker
    "dice": dice, "shop": shop, "swords": swords, "ring": ring, "shard": shard, "cards": cards,
    "star": star, "turn": turn, "gear": gear, "fullscreen": lambda: corners(False), "windowed": lambda: corners(True),
    # character weapons (each character's Attack card)
    "blood_sword": blood_sword, "arcane_sword": arcane_sword, "thorn_bow": thorn_bow,
    "flame_claw": flame_claw,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in ICONS.items():
        make().save(OUT / f"{name}.png")
    print("wrote %d icons to %s" % (len(ICONS), OUT))


if __name__ == "__main__":
    main()
