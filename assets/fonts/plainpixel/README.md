# Plain Pixel font

"Plain Pixel Font" by Douglas Vautour (Burpy Fresh) is licensed under
CC-BY 4.0: https://burpyfresh.itch.io

Version 0.009 (CJK character additions), unmodified. Characters for most
languages have a 5x11 base but can extend vertically; double-width
characters such as Hiragana and Katakana are 11x11.

Bundled so a translation mod can opt into TTF text rendering
(`mod.content.font:register("ttf", {})`; see the Translation support
section of docs/new-features.md) instead of drawing hundreds of glyph-page
tiles. The tile font extracted from the player's ROM stays the default.
