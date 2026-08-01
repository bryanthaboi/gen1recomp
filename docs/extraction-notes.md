# ROM Extraction Notes

There are two ROM-only extraction paths:

- The packaged app uses `src/import/RomImporter.lua` and
  `src/import/RomExtractor.lua` on first boot.
- Developers can run `tools/build_data.py --rom <path> [--clean]` to generate
  data in the source tree for audit and parity work.

Both paths read only the supplied ROM and the checked-in
`tools/rom_manifest.json`. Neither invokes RGBDS, Git, or a disassembly.

## Validation

Only the canonical US Pokemon Red ROM is supported. SHA-1 is checked before
any cached output is removed or written.

## Decoded Data

| Area | ROM data |
| --- | --- |
| world | map headers, block maps, connections, warps, signs, objects |
| tiles | tileset graphics, blocksets, collision, door and warp tile lists |
| text | 2,584 text command streams and RAM/number substitutions |
| Pokemon | names, stats, evolutions, learnsets, Dex data, compressed pictures |
| battle | moves, detailed animations, OAM frames/tiles, effects, type chart, palettes, trainer parties/AI/pictures |
| inventory | item names, prices, key-item flags, TM/HM data |
| encounters | grass and water wild tables |
| UI | fonts, icons, title/intro, trainer card, town map, slots, field effects |
| audio | music, SFX and cry headers, channel programs, wave instruments |

The Python and Lua picture decompressors implement the Gen 1 `pic` format.
Graphics are converted to RGBA PNGs. OAM artwork uses transparent color 0;
battle pictures use edge-connected white matting so white interior details
remain visible.

The in-app importer stores three audio ROM banks as a 48 KiB
`programs.bin`. `src/core/ChipAudio.lua` interprets the channel bytecode and
synthesizes music as a queueable stream; SFX and cries are synthesized on
demand. This avoids shipping or generating a large WAV/OGG tree.

## Metadata Boundary

Names, dimensions, enum ordering, Lua script hooks, and hand-ported field
behavior do not survive compilation in a form the Lua runtime can infer.
Those relationships are bundled in `rom_manifest.json`. The manifest stores
no dialogue strings, images, audio samples, or ROM bytes.

`tools/make_rom_manifest.py` and `tools/verify_rom_data.py` are developer audit
tools. They are not used by the packaged game.

## EUR (Spanish) Manifests

The Spanish releases (Edicion Roja/Azul) are rebuilds of the US ROMs: every
data bank keeps its US layout, while the far-text banks and any bank holding
translated bytes are re-laid-out, so symbol addresses move.
`tools/make_es_manifest.py` derives `rom_manifest_red_es.json` and
`rom_manifest_blue_es.json` from the shipped US manifests, re-resolving every
symbol (and the inline audio header addresses) from the shift-matching
einstein95/pokered-es disassembly's `.sym` files, and re-parsing only the
language-dependent metadata: the charmap/font charmap (accented characters),
text dynamic-substitution commands, preset names, credits, trade nicknames,
town-map names, the title ribbon metrics, and the metric Pokedex layout
(`dexUnits`/`dexUnitLabels` -- EUR dex entries store decimeters/hectograms,
one byte shorter than the US feet/inches layout).

To regenerate: clone and build https://github.com/einstein95/pokered-es
(`make red blue`, RGBDS 1.x), then run
`python3 tools/make_es_manifest.py --pokered-es /path/to/pokered-es`.
`tools/verify_rom_data.py --define _BLUE` audits the Blue variants.
