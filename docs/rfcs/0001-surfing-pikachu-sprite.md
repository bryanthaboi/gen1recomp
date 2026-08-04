# RFC 0001 — Port Yellow's `IsSurfingPikachuInParty` surf sprite

## Status

Proposed. Engine: `Player.lua`, `FieldDefaults.lua`,
`OverworldController.lua`, `RomExtractor.lua`, `PaletteFX.lua`. Tools:
`build_rom_data.py`, `extract/sprites.py`, `make_rom_manifest.py`,
`make_yellow_manifest.py`. Tests: `parity_surfing_pikachu_sprite.lua`,
`mod_world_tests.lua`.

**Regeneration required.** The manifest and sprite sheet update by
re-running `make_yellow_manifest.py` against a `pret/pokeyellow`
checkout, then re-importing the Yellow ROM.

## Motivation

Yellow's `IsSurfingPikachuInParty` + `LoadSurfingPlayerSpriteGraphics2`
(`home/map_objects.asm`, `home/overworld.asm`) swap the player's
overworld sheet to `SurfingPikachuSprite` (`gfx/sprites/
surfing_pikachu.2bpp`, a 16×96 walk sheet — not the minigame sheets)
when the party mon that knows SURF is a Pikachu. The recomp misses this
in two places:

1. **Extraction.** `SurfingPikachuSprite` is not in
   `SpriteSheetPointerTable` — loaded by its own `ld de,` like
   `RedBikeSprite`. The extractor never sees it, and the symbol is not
   in the Yellow manifest.
2. **Engine rule.** `field.playerSprites.surf` is one static
   (`SPRITE_SEEL`), cached at boot. No seam for "swap when the SURF-mon
   is a Pikachu."

## The decision it extends

No prior D-number. Extends the surf-field-move port in
`docs/behavior-porting-notes.md` (the `IsSurfingAllowed` exact port)
with the player-sprite swap vanilla runs alongside it.

## The exact API delta

Backward-compatible, additive-only.

### `field.playerSprites.surfPikachu`

New optional key alongside `walk`/`surf`/`bike`/`fly`, defaults to
`SPRITE_SURFING_PIKACHU`. Guarded in `Player.new` so before extraction
lands the ride keeps the Seel — no plain on-water Pikachu.

### `Player.surfPikachuSprite`

`Player.new` builds a second `SpriteRenderer` when the field resolves.
`pose()` picks it when `surfing and surfingPikachu`.

### `Player.surfingPikachu` (runtime)

Runtime-only boolean (not persisted); re-derived so a party change
between save and load is honored.

### `OverworldState:syncSurfingPikachu()`

Sets `player.surfingPikachu` from `partyKnows("SURF")`. Called at every
surf-state toggle: trySurf, dismount, flyTo, beginTeleportOut,
warpToHealPoint, forced-surf tile, setMap boot-restore.

### Importer — `SPRITE_SURFING_PIKACHU`

`make_yellow_manifest.py` adds `SurfingPikachuSprite` to
`YELLOW_EXTRA_SYMBOLS`. `make_rom_manifest.py`'s `sprite_metadata()`
gains a `surfPikachu` entry (guarded, so Red/Blue unchanged).
`RomExtractor.extractSprites` + `build_rom_data.py` + `extract/sprites.py`
each gain a parallel extract mirroring `RedBikeSprite`.

### `PaletteFX.spriteObp`

`SurfingPikachuSprite` joins `RedBikeSprite` in the no-bracket-index
special case, wearing the player's OBP palette so it colors in GBC mode.

## Migration note for existing mods

**Nothing.** `surf` still defaults to `SPRITE_SEEL`; `surfPikachu`
only resolves on a Yellow import after regeneration. No manifest or
`mod.save` shape changes. An eligibility hook that swaps a rental
SURF-mon still drives the sprite pick via `partyKnows`.

## Parity tests

- **No-mod** (`mod_world_tests.lua`): `surf == "SPRITE_SEEL"`,
  `surfPikachu == "SPRITE_SURFING_PIKACHU"` seeded at boot. The 19229-check
  `world & maps v2` suite stays green.
- **Mod-API** (`parity_surfing_pikachu_sprite.lua`): `syncSurfingPikachu`
  + `Player:pose` across four party shapes (12/12). The existing
  `parity_cinnabar_east_surf.lua` (24/24) stays green.

## Deprecation etiquette

Nothing deprecated. Additive: a new `field.playerSprites` key, a new
runtime flag, a new engine method, a new sprite id.