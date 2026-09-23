# Mystery Dungeon sprite importer

Open **IMPORTERS → Pokémon Mystery Dungeon**, select a **Pokémon Mystery Dungeon:
Red Rescue Team USA/Australia** `.gba` dump, and wait for the sprites pack to finish.
The supported dump is 32 MiB, MD5 `2100cf6f17e12cd34f1513647dfa506b`.
Blue Rescue Team and other regions/revisions are not supported.

The importer produces 423 transparent PNG sheets: every monster sprite set in
Red Rescue Team, including Unown and Deoxys forms, Munchlax, the decoy, statue,
and cutscene Rayquaza. It assembles every pose from its tile fragments, applying
the original offsets, flips, species palettes, per-piece palette overrides,
and depth ordering. Portraits, maps, and audio
are outside this importer's scope. No ROM or extracted art is checked into the repo.

Like the Link to the Past importer, this installs a versioned asset pack under
`asset_packs/pmd_red/sprites` in the game's save directory. It records the source
ROM hash and yields progress while assembling sheets. Errors stop the import;
the pack manifest is published only after all sprites have been written.

## Mod access

Declare the pack in `manifest.json`:

```json
"required_assets": [
  { "importer": "pmd_red", "pack": "sprites", "version": ">=1.0.0" }
]
```

```lua
local entry = assert(mod.packs:entry("pmd_red", "sprites", "bulbasaur"))
local png = assert(mod.packs:read("pmd_red", "sprites", "bulbasaur"))
local animation = assert(mod.packs:metadata("pmd_red", "sprites", "bulbasaur"))
```

`mod.packs:entries(...)` lists stable lowercase species/form IDs, PNG dimensions,
pose count (`frames`), and `sprite` layout metadata. `sprite` contains
`monsterId` (PMD's internal ID), `dexNumber`, `paletteId`, `frameWidth`,
`frameHeight`, `frameColumns`, `anchorX`, `anchorY`, and `directions`.
Every pose occupies a uniformly sized cell in row-major order, with a shared
anchor so differently sized poses do not jump around. Color index zero is transparent.

Animation metadata lives in one Lua sidecar per species, loaded on demand by
`mod.packs:metadata`. This avoids loading every monster's animations to list
the pack and keeps each file within LuaJIT's constant limit.

`animations[animationId + 1][directionId + 1]` gives a one-based index into
`sequences`. Native animation and direction IDs are zero based. Directions are
south, southeast, east, northeast, north, northwest, west, southwest. Each
sequence frame is `{pose, ticks, offsetX, offsetY, shadowX, shadowY, flags}`:
`pose` is a **one-based sheet cell**, ticks are at 60 Hz, and offsets are signed
pixels relative to the anchor. Looping is a playback choice; PMD's terminator
does not itself specify whether an animation loops. Animation 0 is the walking
cycle; the example holds its first pose when stationary. All other animations
retain their native numeric IDs.

For mods using the engine renderer (`engine_internals` permission):

```lua
local PmdSprite = require("src.import.pmd.Sprite")
local renderer = PmdSprite.new(entry, animation)
renderer:step(isMoving) -- once per 60 Hz logic tick
renderer:draw(px, py, cameraX, cameraY, facing, 0, false)
```

`PmdSprite.definition(entry)` also provides a regular true-color sprite
definition suitable for the Gen 1/2 sprites registry. The helper uses the
existing renderer, including palette-mode handling and composite-frame clipping.

## Follower example

`mods/mystery_dungeon_follower` is **Mystery Dungeon Follower**. It supports Red,
Blue, Yellow, Gold, Silver, Crystal, FireRed, and LeafGreen. Enable it after
importing the pack. It follows party slot 1, changes sheets when the lead changes,
and hides when that slot is empty, fainted, or an egg, or while surfing/biking.
It uses the lead's Unown form and FireRed/LeafGreen's respective Deoxys forms.
The pack has no shiny palette variants; shiny leads use the original PMD palette.

Gen 1/2 use their existing follower controllers. Gen 3 has an optional follower
outside the event-object ID table, with its own movement trail, map reset, and
normal field depth sorting. The `world.follower.spawn` hook takes `(next, game,
world)` and returns whether a companion should exist. With no mod hook, vanilla
spawn rules apply, including no follower in Gen 2/3.

## Verification and source evidence

Run the focused headless tests:

```sh
luajit tests/engine/pmd_sprites.lua
luajit tests/engine/game3_follower.lua
luajit tests/engine/mystery_dungeon_follower.lua
luajit tests/engine/importers_asset_packs.lua
```

Full ROM decode/composite verification accepts `PMD_ROM=/path/to/baserom.gba` on
the first test. Full PNG/metadata export and readback uses a separate save identity:

```sh
love tests/pmd_import /absolute/path/to/repo /absolute/path/to/baserom.gba
```

The in-game driver is `tests/drivers/mystery_dungeon_follower.lua`; its identity
must have the relevant game cache, the imported PMD pack, and the example enabled.

Research was grounded in the Pokémon research MCP's `pmd-red` checkout:
`src/monster_files_table.c`, `src/data/ax/*.h`, `include/structs/axdata.h`,
`src/sprite.c`, `src/monster_sbin_palet.c`, `src/pokemon.c`, and
`include/structs/str_pokemon.h`. The built `pmd_red.map` supplies `gMonsterFiles`
at `0x08510018` and `gMonsterData` at `0x08357B98`. Regenerate the names and pose
counts with `python3 tools/gen_pmd_sprite_catalog.py /path/to/pmd-red`.
