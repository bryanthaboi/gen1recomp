# FireRed object interaction text

A-button interactions now use original ROM metatile behaviors, independently of
translated movement collision. This restores the 28 shared furniture/sign scripts:
bookshelves, shop shelves, food, computers, televisions, cabinets, kitchens,
dressers, snacks, paintings, machines, telephones, posters, bins, cups, windows,
lights, tools, video games, blueprints, burglary debris and building/Indigo signs.
The wall Town Map script is also extracted. Existing PC handling remains available.

The source of truth is pret/pokefirered's `GetInteractedMetatileScript` in
`src/field_control_avatar.c`, `data/scripts/flavor_text.inc`, and the user's ROM.
The importer discovers the original bytecode and text rather than embedding game
strings in source. Script extraction was checked against both US ROM revisions;
the full importer still uses its existing FireRed 1.0 support.

Map-specific background scripts and NPCs take precedence over generic furniture.
Background events respect their original facing and elevation constraints; TVs
and building signs require facing north. Dynamic metatile changes are respected.
The school notebook, S.S. Anne captain's book and rival's bookshelf are verified
through their existing map-specific scripts.

Cache version 93 adds `data/generated/gba/objects/pack.lua`, containing the shared
scripts, text, and original behavior tables for all tileset pairs. Fresh imports
produce it automatically. The local test import was upgraded without touching
saves. Restart the game to load the new code/cache.

This restores descriptive object text. Specialized interactive screens such as
the questionnaire, wireless monitor, battle records and Trainer Tower time monitor
are outside this change.

## Verification

Run with LuaJIT from the repository root:

```sh
luajit tests/game3_object_interactions_test.lua
luajit tests/game3_object_interactions_rom_test.lua '/path/to/FireRed.gba'
luajit tests/game3_object_interactions_cache_test.lua '/path/to/cache/firered'
```

The cache integration test audits all 425 imported layouts (1,578 furniture cells),
exercises 25 furniture behaviors found on those maps via `Field.interact`, and
checks three map-specific book scripts. The ROM test executes all 28 shared text
scripts and verifies the wall Town Map script is present. Unit checks cover facing,
elevation, delayed bundle loading, map bounds, and metatile overrides.
