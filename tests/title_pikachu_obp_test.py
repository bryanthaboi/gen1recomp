#!/usr/bin/env python3
"""Title rOBP0=$E0: eye OAM shade 1 to white, shades 2 and 3 kept."""

from pathlib import Path
from unittest import TestCase, main
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_rom_data as b  # noqa: E402
from PIL import Image  # noqa: E402


class TitleObp0Test(TestCase):
    def test_light_becomes_white_dark_kept(self):
        img = Image.new("RGBA", (4, 1), (0, 0, 0, 0))
        img.putpixel((0, 0), b.GB_SHADES[1])
        img.putpixel((1, 0), b.GB_SHADES[2])
        img.putpixel((2, 0), b.GB_SHADES[3])
        img.putpixel((3, 0), b.GB_SHADES[0])
        b._apply_title_obp0(img)
        self.assertEqual(img.getpixel((0, 0)), b.GB_SHADES[0])
        self.assertEqual(img.getpixel((1, 0)), b.GB_SHADES[2])
        self.assertEqual(img.getpixel((2, 0)), b.GB_SHADES[3])
        self.assertEqual(img.getpixel((3, 0)), b.GB_SHADES[0])

    def test_transparent_untouched(self):
        img = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
        b._apply_title_obp0(img)
        self.assertEqual(img.getpixel((0, 0))[3], 0)


if __name__ == "__main__":
    main()
