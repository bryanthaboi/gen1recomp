#!/usr/bin/env python3
"""Write Switch and Xbox launcher icons from assets/logo/gen1recomp_cover.png.

Square tiles are a direct resize. Wide tiles and the splash keep the whole
mark by fitting the cover to the tile height and extending its left and right
edge columns, so the gradient continues instead of letterboxing a flat color.
"""

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COVER = os.path.join(ROOT, "assets", "logo", "gen1recomp_cover.png")

SQUARE = {
    os.path.join(ROOT, "ports", "uwp", "Assets", "StoreLogo.png"): (50, 50),
    os.path.join(ROOT, "ports", "uwp", "Assets", "Square44x44Logo.png"): (44, 44),
    os.path.join(ROOT, "ports", "uwp", "Assets", "SmallTile.png"): (71, 71),
    os.path.join(ROOT, "ports", "uwp", "Assets", "Square150x150Logo.png"): (150, 150),
    os.path.join(ROOT, "ports", "uwp", "Assets", "LargeTile.png"): (310, 310),
}

WIDE = {
    os.path.join(ROOT, "ports", "uwp", "Assets", "WideTile.png"): (310, 150),
    os.path.join(ROOT, "ports", "uwp", "Assets", "SplashScreen.png"): (620, 300),
}

SWITCH_ICON = os.path.join(ROOT, "ports", "switch", "assets", "icon.jpg")


def load_cover():
    if not os.path.isfile(COVER):
        raise SystemExit("missing icon source: " + COVER)
    return Image.open(COVER).convert("RGB")


def fit_square(cover, size):
    return cover.resize(size, Image.Resampling.LANCZOS)


def fit_wide(cover, size):
    width, height = size
    side = cover.resize((height, height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", size)
    x = (width - height) // 2
    canvas.paste(side, (x, 0))
    if x > 0:
        left = side.crop((0, 0, 1, height)).resize((x, height), Image.Resampling.NEAREST)
        right_w = width - x - height
        right = side.crop((height - 1, 0, height, height)).resize(
            (right_w, height), Image.Resampling.NEAREST)
        canvas.paste(left, (0, 0))
        canvas.paste(right, (x + height, 0))
    return canvas


def main():
    cover = load_cover()
    for path, size in SQUARE.items():
        fit_square(cover, size).save(path, "PNG")
        print("wrote", os.path.relpath(path, ROOT))
    for path, size in WIDE.items():
        fit_wide(cover, size).save(path, "PNG")
        print("wrote", os.path.relpath(path, ROOT))
    icon = fit_square(cover, (256, 256))
    icon.save(SWITCH_ICON, "JPEG", quality=90, optimize=True, progressive=False)
    print("wrote", os.path.relpath(SWITCH_ICON, ROOT))


if __name__ == "__main__":
    main()
