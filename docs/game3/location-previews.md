# Location Previews

Entering a FireRed map section that owns a preview now shows the retail
full-screen artwork and location-name window during the warp transition, and
the Town Map GUIDE panel shows the retail artwork and flavour text instead of
the hand-authored placeholders. Before this, only a handful of sections had
art, and none of it came from the ROM.

## What the ROM provides

`src/import/gba/map_preview_extract.lua` reads two tables straight from the
user's dump and bakes them into the cache:

| Table | Source | Contents |
| --- | --- | --- |
| `sMapPreviewScreenData` | `src/map_preview_screen.c` | 28 entries: `mapsec`, `type`, `flagId`, `tilesptr`, `tilemapptr`, `palptr` |
| `sMapsecName_*` | `src/region_map.c` | 109 display names for mapsec 88..196 |
| `sDungeonInfo` | `src/region_map.c` | 19 dungeon GUIDE entries: name + pre-wrapped flavour text |

`src/import/gba/region_map_tables.lua` locates `sMapPreviewScreenData` by
validating the pinned offset from `versions.lua` and only then falling back to a
bounded ±0x8000 scan. Validation is structural, not a magic byte match: every
one of the 28 entries must have a mapsec in range, a type of 0 or 1, three
in-range ROM pointers, and satisfy the shipped invariant that the palette block
is physically the first 0x40 bytes of the tile block.

Artwork is deduplicated by its `tiles:tilemap:palette` key, so 28 entries bake
21 images. Pattern Bush and the six Tanoby chambers reuse another section's art,
exactly as the retail table does. Each image is 240×160 RGBA at 4bpp using
palette banks 13 and 14.

`src/import/gba/bg_bake.lua` holds the shared 4bpp BG baking helpers
(`bgr555ToRgb8`, `decodeTile4bpp`, `loadPalBanks`, `bakeBgRgba`); the Berry Pouch
extractor was refactored onto them.

### Cache files

```
<root>/map_preview/manifest.lua        entries, by_mapsec index, name-window colours
<root>/map_preview/<mapsec>.rgba       240x160 RGBA artwork, deduplicated
<root>/region_map/names.lua            mapsec 88..196 display names
<root>/region_map/dungeon_info.lua     sDungeonInfo name + flavour text
```

`versions.lua` `CACHE_VERSION` is bumped when any of these change shape.

## Two ROM quirks the importer tolerates

* `MPS_ROCKET_WAREHOUSE` (mapsec 178) and Berry Forest (mapsec 176) share
  `flagId = 2231`, so the first one the player visits marks both as seen. The
  six Tanoby chambers likewise share one flag. This is retail behaviour.
* The Tanoby chamber mapsec is spelled `MAPSEC_DILFORD_CHAMBER` (not
  `DILFORD`) in the name table.

## Runtime behaviour

`src/ui/game3/map_preview_screen.lua` ports `Task_RunMapPreviewScreenForest`.
Only `MPS_TYPE_FOREST` sections (8 of them) take over the screen; the other 20
are `MPS_TYPE_CAVE` and only change the warp fade colour. The artwork and the
name window are composited into one canvas so they fade out together, matching
the retail BG0/BLDALPHA blend.

* Hold: 120 frames on a first visit, 40 on a revisit. Caves key off their own
  world-map flag; forests key off the transient `sHasVisitedMapBefore` global
  that `ScrCmd_setworldmapflag` refreshes (`MapPreviewScreen.setVisitedFlag`
  captures the pre-visit state).
* Fade-out: 48 frames.

Wiring:

* `src/core/game3/map.lua` — a changed section with a forest preview wins over
  the map-name popup (mirrors `overworld.c` state 12). Suppressed for seamless
  warps.
* `src/core/game3/gfx.lua` — a running preview suppresses `MapNamePopup`.
* `src/core/game3/warp.lua` — `warpFadeModes` applies
  `WarpFadeOutScreen`/`WarpFadeInScreen`: a section change into a cave-preview
  map forces `FADE_TO_BLACK`, otherwise `MapTransitionIsEnter`/`IsExit` decide
  white-vs-black using `MAP_TYPE_UNDERGROUND`.
* `src/core/game3/scripting/ops_a.lua` — `setworldmapflag` feeds the visit flag.
* `src/ui/game3/hud.lua` — ticks and dismisses the screen on menu open.
* `src/core/game3/dataset.lua` — installs the cache during hydrate.
* `src/ui/game3/region_map.lua` — GUIDE panel geometry, tint ramp and delayed
  text now follow the retail timings; ROM names and dungeon text overlay the
  hand-authored `map_sections_extract.SECTIONS` / `region_map_extract` fallbacks
  via `ensureGenerated()`.

## Verification

Run from the project root:

```sh
luajit tests/game3_map_preview_extract_test.lua
luajit tests/game3_town_map_test.lua
luajit tests/run_engine.lua
luacheck src -q --codes --only 0 1 511
```

`tests/game3_map_preview_extract_test.lua` covers the pinned offsets, the
BGR555→RGB8 conversion, the manifest/screen logic against a synthetic cache
(so it runs without a ROM), and — when a FireRed dump is present at the repo
root — the full extraction: 28 entries, 8 forest / 20 cave, 21 deduplicated
240×160×4 artworks, 109 verified mapsec names, 19 dungeon entries, the shared
2231 flag, and Pattern Bush reusing Viridian Forest's artwork.

The `tests/game3_*` suites are run manually; they are not wired into a CI
workflow. Extraction was additionally checked against a real FireRed 1.0 dump
(all 28 entries and 109 names decode, `sMapsecName_*` pointers match
`sRegionMapSectionIdToName`). Timing was reasoned against pret source; no
in-game visual capture has been performed.
