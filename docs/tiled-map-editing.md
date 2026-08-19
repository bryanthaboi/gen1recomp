# Tiled map editing (mod authoring)

`tools/tiled_export.py` turns the imported ROM cache into a
[Tiled](https://www.mapeditor.org) workspace, so maps can be edited in a
real map editor and exported back out as a mod. The original had no map
editor at all; the port's own map data is plain Lua, which is what makes
this a data path rather than an asset path.

Editing is done in our own Tiled build,
[bryanthaboi/tiled_gen1recomp](https://github.com/bryanthaboi/tiled_gen1recomp/releases),
which ships the `gen1-mod-export` extension the workspace relies on. Grab it
from that repo's releases; upstream Tiled opens the workspace but cannot
export a mod out of it.

```sh
python3 tools/tiled_export.py          # -> build/tiled/ (gitignored)
```

Then open `build/tiled/gen1.tiled-project` in that build of Tiled.

- **The overworld is one surface.** All 222 maps become `maps/*.tmj`, and
  `kanto.world` places the 36 connected overworld maps at their real
  connection offsets. That world is pre-loaded (seeded into the workspace's
  Tiled session), so opening any one overworld map draws its neighbors around
  it and you scroll and edit straight across the seams. Everything else is a
  double-click away in Tiled's project panel.
- **Extending Kanto wires both ends.** A connection lives on both maps, so
  hooking a new map onto a base map also emits the return connection as a
  patch on that base map, keeping its other directions intact. The return
  offset is derived, not guessed: all 78 vanilla reciprocal pairs satisfy
  `back.offset == -offset`.
- **A Tiled tile is a gen1 block.** Each of the 24 tilesets becomes a Tiled
  tileset whose tiles are its 32x32 blocks, composited from the 8x8 sheet,
  so a tile layer *is* the map's `blocks` array. Warps, signs and objects
  sit on the 16px cell grid in object layers, which is the grid the engine
  addresses them on.
- **Collision is visible.** View > Show Tile Collision Shapes draws the real
  walkability: a rectangle covers each cell whose feet tile is not in the
  tileset's `walkable` list, which is the rule `src/world/Map.lua` applies.
- **Maps are shown in their real colors.** Each map is atlased in the SGB
  palette it renders with, so Cerulean is blue and Lavender is purple in the
  editor exactly as in game. Vanilla resolves that through a cascade with
  interiors inheriting the last outdoor map, so the workspace mirrors the
  cascade and walks the warp graph to colour interiors. Changing a map's
  `palette` exports `palette = "..."` on the record, which beats the cascade,
  and the editor offers the real palette names as a dropdown.
- **New blocks and new tilesets.** `blocksets/*.tmj` show a tileset's blocks
  as raw 8x8 tiles, four by four, so new blocks can be composed there;
  per-tile flags on `tilesets/tiles_*.tsj` become `walkable`, `waterTiles`,
  `doorTiles` and the rest.
- **Export is a diff, not a fork of the data.** The `gen1-mod-export`
  extension (shipped in `tiled_gen1recomp`) writes either one map file or a whole
  loadable mod folder. An edited vanilla map diffs against the imported data
  and emits `mod.content.maps:patch` carrying *only* the fields that moved, so
  a mod covers the parts it changes and leaves the rest to the base game; a
  new map gets `:register` at an index of 1000 or above. An unchanged map
  exports nothing at all. Exports pass `tools/modkit.py validate` and `lint`.
- **Or the whole record, on request.** Ticking `exactExport` on a map switches
  it to `mod.content.maps:override`, pinning the map to exactly what the
  editor shows. It is off by default because an override wins outright over
  any other mod patching that map, where a patch composes.

No ROM-derived art travels into an exported mod: a tileset still drawing on
the player's own imported sheet references that path rather than shipping the
pixels, and only a sheet the author supplied is copied in.
