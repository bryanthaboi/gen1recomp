You may not need this directory at all: scaffold with
`--pixel-font` (or uncomment the `register("ttf", {})` line in main.lua)
and text renders through the engine's bundled Plain Pixel TTF, which
covers Latin, kana and CJK out of the box.  A glyph sheet is only for a
translation that wants the hand-drawn GB look.

Put your glyph sheet here.

A page is a PNG of 8x8 cells, 16 per row by default, black on white. Codes
run left to right and top to bottom starting at the page's `base`, so the
first cell is `base`, the second `base + 1`, and so on.

`assets/generated/font.png` in the player's cache is the vanilla sheet at
the same scale; open it alongside yours to match weight and baseline.

Declare the sheet in `lang/font.lua` and map sequences to codes in
`lang/charmap.lua`.
