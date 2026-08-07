# Traducción Española

Plays the game in Spanish by decoding the official EUR script out of the
player's own Spanish Red/Blue cartridge dump at load time — the mod ships
addresses, never Nintendo's text. Its persona: the translation Nintendo
already wrote, applied to the recomp without redistributing a byte of it.

Try it:

```sh
python3 tools/modkit.py validate mods/traduccion_es --base imported
luajit mods/traduccion_es/tests/traduccion_es_test.lua
POKEPORT_DEV=1 scripts/run.sh
```

## How to play in Spanish

1. Import your US Red or Blue ROM as usual (the base game data).
2. Copy your Spanish EUR dump (`Pokemon - Edicion Roja` or
   `Edicion Azul`, `.gb`/`.gbc`) into the `imports/` folder in the save
   directory — the same folder ROM imports already use.
3. Enable **Traducción Española** in the mod manager and restart.

Dialogue, move names, item names and trainer classes come straight from
your cartridge (2,585 lines of official script). Engine-authored text
(battle messages, menus, options, PC boxes, link play, the mod manager)
is fully hand-translated in `lang/strings.lua` — 557 lines; the handful
left untouched are brand names and words identical in Spanish. Accented
characters, the ":N" level tag, the "PS" HP label and the "Edición
Roja" title ribbon are decoded from your cartridge at load time —
pixel-identical to the Spanish hardware, with no art shipped in the
mod.

## Layout

- `manifest.json` — identity, `LANGUAGE` category, engine range
- `main.lua` — cartridge layer first, then the `lang/` catalogs on top
- `rom/spec_es.lua` — dialogue label addresses, name tables and the
  byte→glyph charmap, derived from the einstein95/pokered-es
  shift-matching disassembly (regenerate with `tools/build_spec.py`)
- `rom/decoder.lua` — standalone Gen-1 text decoder, output-compatible
  with the engine's extractor
- `lang/` — the hand-editable catalogs; anything filled in here wins
  over the cartridge layer (see `TRANSLATING.md`)
