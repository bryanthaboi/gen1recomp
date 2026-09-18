# FireRed Help

With **OPTION → BUTTON MODE → HELP** (the retail default), press **Q/E**
(or controller **L/R**) to open Help. A selects, B returns, and L/R closes.
Directional keys navigate; left/right page through long lists. The first-use
welcome is dismissed with A. LR and L=A modes retain their existing behavior.

The importer reads all 177 question/answer entries, context lists, basic terms,
intro text, and background tiles/palette from the user's ROM. No extracted game
text or art is shipped in source. `help/pack.lua` is a required FireRed cache file.
The help extractor supports clean FireRed 1.0 and Rev 1; the overall game's
existing importer still requires FireRed 1.0.

The overlay intercepts input before the simulation runs and renders instead of
the underlying screen while open. Field, scripts, battles, RNG, menus, and
fanfare callbacks pause. BGM streams at half volume and restores on closing.
The normal menu stack stays intact. Story flags gate questions, and the welcome
flag persists in saves. Battle context remains active inside battle submenus.
Script specials set, back up, restore, enable, and disable Help contexts.

The native 240×160 layout uses the ROM font and help background tiles. Numbered
steps and type-effectiveness symbols use the font's extended glyph bank.
Answers that exceed the panel can be scrolled with up/down.

Importing previously overwrote `scripting/flags_table.lua` with empty definitions
when a local pret checkout was absent. The importer now writes only its cache
and falls back to the bundled constants.

## Verification

Run from the project root:

```sh
luajit tests/game3_help_test.lua
luajit tests/game3_flags_extract_preserve_test.lua
luajit tests/game3_help_rom_test.lua /path/to/firered.gba
```

The optional ROM test checks both extraction and cache serialization. Navigation
and integration tests cover input ownership, pause/resume, progress filtering,
context selection, persistence, script specials, scrolling, and audio restoration.
Actual drawing calls were also rendered offline using the imported ROM atlases;
this is not an in-game visual test.

Targeted event-flag, text-color, audio, pause/exit, save/trainer-card and cache-contract
regressions pass. `game3_start_menu_cursor_test.lua` and `game3_main_menu_test.lua`
have identical failures on the unmodified `grandpas-garage` commit ff18f605.
