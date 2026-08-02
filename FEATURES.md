# Fork features

Features added on top of [bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)
in this fork. Upstream's own additions are documented in
[docs/new-features.md](docs/new-features.md); this file covers only what is
ours.

Updated at the completion of every feature.

| Feature | Kind | Version | Status | Lives in |
|---|---|---|---|---|
| [Celadon Battle Facility](#celadon-battle-facility) | Mod | 1.0.1 | Shipped | [mods/celadon_battle_facility/](mods/celadon_battle_facility/) |
| ROM files gitignored | Repo hygiene | — | Shipped | [.gitignore](.gitignore) |

---

## Celadon Battle Facility

A three-tier gauntlet ladder in a new building on Celadon City's west lawn.
Consecutive battles with no healing between rounds, opponents scaled to your
party's average level, a token currency, a prize counter, and a records board.

**Branch:** `feature/celadon-battle-facility`

| Tier | Rounds | Level bonus | Payout |
|---|---|---|---|
| BRONZE | 3 | +0 | 1 BATTLE PT |
| SILVER | 5 | +3 | 3 BATTLE PT |
| GOLD | 7 | +6 | 5 BATTLE PT |

Each tier unlocks only once the one before it is cleared.

### What it touches

- **Celadon City** — eight lawn blocks at block rows 9-10, columns 2-5, plus
  two appended warps. Nothing else about the city moves, and the suite asserts
  it.
- **New content** — one interior map, three trainer classes, one item, one
  screen, four map scripts, three script commands.

### Engine seams used

| Need | Mechanism |
|---|---|
| Edit a vanilla map | `content.maps:patch` over the live base |
| New interior | `content.maps:register` on the FACILITY tileset |
| Gauntlet loop | `map_scripts` with `label` / `jump_if_false` |
| Party scaling | the `trainer.party` hook |
| Progress | `mod.save:get/set` |
| Trainer art | `basePic`, borrowing a vanilla portrait |
| Prizes | `choice` + `give_item` / `take_item` |
| Records | `content.screens` + `push_screen` |

### Verification

```sh
luajit mods/celadon_battle_facility/tests/celadon_battle_facility_test.lua
POKEPORT_DRIVER=mods/celadon_battle_facility/tests/door_roundtrip_driver.lua love .
POKEPORT_DRIVER=mods/celadon_battle_facility/tests/challenge_driver.lua love .
POKEPORT_DRIVER=mods/celadon_battle_facility/tests/lobby_driver.lua love .
python3 tools/modkit.py validate mods/celadon_battle_facility --base imported
python3 tools/modkit.py lint mods/celadon_battle_facility
```

340 unit checks, three in-engine drivers. The engine suite is unchanged.

---

## ROM files gitignored

`.gitignore` covered `data/generated/` and `assets/generated/` but not the ROM
itself, so a `git add -A` in a working tree with a `.gb` beside `main.lua`
would have committed a copyrighted ROM to a public repo. `*.gb`, `*.gbc` and
`*.sav` are now ignored.

Worth upstreaming.

---

## Conventions for the next feature

What made the first one go smoothly, so the next follows the same shape:

1. **Prefer a mod to an engine change.** 40 registries and ~60 events cover
   most ideas. Reach into `src/` only when no seam exists. One cost to know:
   `Handshake.onlineAllowed` returns false whenever *any* mod is loaded, so
   every mod disables online link play. Anything that must keep netplay has to
   live in the engine instead.
2. **One branch per feature**, named `feature/<name>`, off `dev`. PR into this
   fork's `dev`; keep `upstream/dev` merges separate so the history stays
   readable.
3. **Verify against the data, then against the render.** Map data will not
   tell you that a block carries baked-in signage (17 is "GYM", 115 "MART",
   113/114 "POKe"), that your room is four screens wide, or that a building
   has no roofline. All three cost a rewrite on the first feature. Render the
   candidate blocks and screenshot the result before believing the layout.
   `tools/` has no block viewer; a dozen lines of Pillow over
   `assets/generated/tilesets/*.png` plus the `blocks` table does the job.
4. **Ship a unit suite and at least one driver.** The suite catches structure
   (`ScriptRunner.validate` finds bad labels and unknown verbs for free); the
   driver catches behaviour.
5. **Never ship ROM-derived content.** `modkit lint` checks this. Original
   assets, `basePic`, or an `assets_transforms` recipe over the player's own
   cache — never extracted bytes.
6. **Update this file** when the feature lands.

### Running the tests on Windows

There is no LuaJIT binary for Windows (CI installs it via apt). LÖVE embeds
LuaJIT 2.1 and can stand in: point a one-file game directory's `main.lua` at
the script, clear `_G.love` so the harness installs its own stub, and set
`MODKIT_LUAJIT` at that shim for `modkit validate`.
