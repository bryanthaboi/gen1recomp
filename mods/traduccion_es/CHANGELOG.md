# Changelog

All notable changes to this mod are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-08-06

### Added

- Automatic cartridge layer: the official Spanish script (2,585 dialogue
  labels) and the move/item/trainer-class/species name tables decode at
  load time from the EUR Red/Blue dump in the player's imports/ folder.
  The mod ships addresses and a byte->glyph charmap only
  (`rom/spec_es.lua`); the Spanish text always comes from the player's
  own cartridge.
- Standalone decoder (`rom/decoder.lua`), output-compatible with the
  engine's RomExtractor, with soft per-label failure.
- The full engine-string catalog hand-translated in `lang/strings.lua`
  (557 entries): battle flow, menus, options, PC boxes, link play, slots,
  the launcher and the mod manager. Status labels (VEN/QUE/DOR/CON/PAR,
  DEB) and the hand-ported cutscene literals in lang/dialogue.lua too.
- Cartridge-derived graphics: the accent tiles, the ":N" level tag, the
  "PS" HP label and the "Edicion Roja" title ribbon are decoded from the
  player's own dump at load time (via the importer's own ImageWriter
  recipes) into save/mod-derived/, so every glyph is pixel-identical to
  the Spanish hardware and no art ships with the mod.
