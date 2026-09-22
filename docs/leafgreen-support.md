# LeafGreen support

LeafGreen USA 1.0 and 1.1 use the existing `game3` engine. Import either clean
ROM in the launcher, select Leaf Green, and play. `--game=leafgreen` and `--game=lg`
select the same game. FireRed and LeafGreen have separate caches and save slots.
Other regions and modified ROMs are not added to the accepted hash list.

## Import architecture

`src/import/gba/versions.lua` retains FireRed 1.0 as its baseline. `select()`
applies a generated LeafGreen 1.0 symbol-address profile to both table values
and callback-address keys, preserving table identities. Explicit addresses in
older extractors resolve through `Versions.address()` at read time. Addresses
read from the ROM are already edition-specific and must not be translated.

RevisionView normalizes each 1.1 ROM to its own edition's 1.0 layout before
extraction. LeafGreen is never converted into FireRed content. The generated
files contain addresses and relocation metadata, not ROM assets.

Regenerate from matching pret builds:

```sh
make -C ../pokefirered -j8 compare_firered compare_firered_rev1 compare_leafgreen compare_leafgreen_rev1
python3 tools/gen_leafgreen_profile.py ../pokefirered
python3 tools/gen_firered_revision.py ../pokefirered --game leafgreen
```

The edition-profile generator resolves local symbols by object file and name,
not name alone. The three title-particle symbols have explicit FireRed-to-
LeafGreen aliases. LeafGreen's leaf animation and streaks use their own runtime
behavior. Deoxys stats come from each ROM's form-specific stat table. NPC trades
and Oak's name choices select the edition at runtime.

Ending a Gen 3 mounted session drops its engine/UI module caches and mod facades
so scripts, menus and other memoized data reload from the next cartridge.

## Verification

`luajit tests/game3_leafgreen_test.lua` checks both LeafGreen revisions against
local pret builds, relocated data, edition switching, origin IDs and NPC trades.
`tests/drivers/game3_leafgreen.lua` checks the imported cache, title, encounters,
Deoxys, saving/loading, and same-process switching when FireRed is also imported.
Use an isolated `POKEPORT_IDENTITY` for driver runs.

The shared payload packer includes both manifests and both generated profiles:

```sh
bash scripts/pack_love.sh --output /tmp/frlg.love --listing /tmp/frlg-listing.txt --dry-run
```
