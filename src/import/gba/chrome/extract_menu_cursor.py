#!/usr/bin/env python3
"""Extract FRLG menu selector pip (gText_SelectorArrow2 / charmap 0xEF) from ROM font.

FireRed USA 1.0: sFontNormalLatinGlyphs @ 0x1FF300, 64 bytes/glyph.
Also accepts pret latin_normal.png (same glyphs) when ROM path omitted.

Usage:
  python3 extract_menu_cursor.py baseroms/firered.gba
  python3 extract_menu_cursor.py   # bake from sevii/gba/chrome/fonts/latin_normal*.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]  # sevii/gba
FONT_DIR = ROOT / "chrome" / "fonts"
OUT = FONT_DIR / "menu_cursor_right.png"
GLYPH = 0xEF
FONT_BASE = 0x1FF300
GLYPH_BYTES = 64


def bake_from_sheets() -> None:
    fg = Image.open(FONT_DIR / "latin_normal_fg.png").convert("RGBA")
    sh = Image.open(FONT_DIR / "latin_normal_shadow.png").convert("RGBA")
    col, row = GLYPH % 16, GLYPH // 16
    box = (col * 16, row * 16, col * 16 + 16, row * 16 + 16)
    fg_g, sh_g = fg.crop(box), sh.crop(box)
    fg_c, sh_c = (98, 98, 98, 255), (213, 213, 205, 255)
    out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            sp, fp = sh_g.getpixel((x, y)), fg_g.getpixel((x, y))
            if isinstance(sp, tuple) and sp[0] > 20:
                out.putpixel((x, y), sh_c)
            if isinstance(fp, tuple) and fp[0] > 20:
                out.putpixel((x, y), fg_c)
    out.save(OUT)
    print(f"ok  {OUT} (from latin_normal FG/shadow sheets, glyph 0x{GLYPH:02X})")


def dump_rom_glyph(rom_path: Path) -> None:
    data = rom_path.read_bytes()
    off = FONT_BASE + GLYPH * GLYPH_BYTES
    blob = data[off : off + GLYPH_BYTES]
    bin_path = FONT_DIR / "menu_cursor_right.fwlat.bin"
    bin_path.write_bytes(blob)
    print(f"ok  {bin_path} ({len(blob)} bytes @ ROM 0x{off:X})")


def main() -> int:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 1:
        rom = Path(sys.argv[1])
        if not rom.is_file():
            print(f"missing ROM {rom}", file=sys.stderr)
            return 1
        dump_rom_glyph(rom)
    bake_from_sheets()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
