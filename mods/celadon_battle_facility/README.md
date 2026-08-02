# Celadon Battle Facility

A tiered gauntlet ladder on Celadon City's west lawn. Consecutive battles with
no healing between rounds, opponents scaled to your party's average level, and
Bronze / Silver / Gold tiers that unlock in sequence.

## Heads up: this disables online play

`Handshake.onlineAllowed` returns false whenever *any* mod is loaded, so
enabling this (or any other mod) turns off online link play for that session.
Disable it in the F10 manager and relaunch to go back online.

## Why Celadon

Walkability was mapped at cell resolution across every Kanto city before a
single block was placed. Celadon is the only oversized city map — 25x18
blocks, where every other city is 20x18 — and block rows 7-11 / columns 1-9
are a contiguous field of lawn, the largest genuinely unused space in Kanto.
It fits thematically too: Celadon already hosts the Game Corner, so
"win tokens, trade them for prizes" is an idiom this city established.

## Where the building went

A 4x2 footprint at block rows 9-10, columns 2-5 — cells x 4-11, y 18-21, with
doors at cells (6,21) and (8,21).

Two nearby spots look better on a map and are not:

- The centre of the lawn has an NPC standing at cell (8,17).
- Anything touching block row 7 columns 4-5 walls off the Celadon Dept.
  Store, whose warps at (8,13) and (10,13) are entered from below.

Signage is baked into the tileset art rather than drawn as objects, so
copying a nearby building wholesale is a trap: block 17 draws **GYM** and
block 115 draws **MART**. The footprint uses 126 in place of the Dept.
Store's 115 for exactly that reason, and the test suite asserts neither sign
block ever lands in the footprint.

## Verification

```sh
# unit suite -- placement, warp topology, and that Celadon is otherwise untouched
luajit mods/celadon_battle_facility/tests/celadon_battle_facility_test.lua

# in-engine round trip -- walk in, walk out, confirm the walls are solid
POKEPORT_DRIVER=mods/celadon_battle_facility/tests/door_roundtrip_driver.lua love .

python3 tools/modkit.py validate mods/celadon_battle_facility --base imported
python3 tools/modkit.py lint mods/celadon_battle_facility
```

No LuaJIT on Windows? LÖVE embeds LuaJIT 2.1 and can stand in as the
interpreter — point a shim at `lovec.exe` with a one-file game directory that
clears `_G.love` and `loadfile`s the script, then set `MODKIT_LUAJIT` to it.

## How it plays

Talk to the greeter. She offers the tiers hardest-first, so a GOLD run is one
prompt away rather than three. Each tier is a fixed number of battles back to
back with **no healing between rounds** -- your party is restored only when the
run ends, win or lose.

| Tier | Rounds | Level bonus | Payout |
|---|---|---|---|
| BRONZE | 3 | +0 | 1 BATTLE PT |
| SILVER | 5 | +3 | 3 BATTLE PT |
| GOLD | 7 | +6 | 5 BATTLE PT |

Opponents are built at your party's **average level** plus the tier's bonus,
with the final round of each tier two levels above the rest. The rosters carry
placeholder levels that never reach a battle -- the scaling runs on the
engine's `trainer.party` hook, so it holds no matter how the fight is reached.

Spend BATTLE PT at the counter, and check the archivist's board for tier
clears and your best run.

## Design notes

Two things the block data alone would not have caught, both found by looking
at the rendered result:

- Copying a neighbouring building wholesale imports its **signage**, because
  the text is baked into the tileset art rather than drawn as an object. The
  first draft put a second "GYM" on the lawn; the second said "MART".
- The lobby was originally 10x9 blocks -- 20x18 cells against a 10x9-cell
  screen, so the entire cast sat off-camera. It is 7x6 now, and the NPCs are
  on the first row the camera does not clip.

## Status

Complete. 340 unit checks plus three in-engine drivers, all passing.
