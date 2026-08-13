# Encounters Guide

A catch-'em-all toolkit for Gen1Recomp: a map-first wild-encounter guide
(START → PKMN MAP) plus a battle HUD that marks Pokémon you have already
caught, all read-only.

**Persona: the QoL Toolkit Builder.** Two read-only overlays and a screen
family over public APIs only — no permissions, no ROM-derived bytes, and a
single bundled `main.lua` built by `tools/bundle.py` from the readable
source at [github.com/illanrego/wills-mod](https://github.com/illanrego/wills-mod).

## Try it

```sh
python3 tools/modkit.py validate mods/examples/wills_mod --base imported
luajit mods/examples/wills_mod/tests/wills_mod_test.lua
```

Copy the entry up to `mods/` and enable it (`wills_mod = true` under `mods`
in `options.lua`, or the F10 manager). Then:

1. Press **START → PKMN MAP** — browse Kanto from the imported ROM's Town
   Map and inspect encounter-bearing locations.
2. Stand on tall grass — the **walking HUD** lists the area's LAND and
   WATER species with level ranges (modes AUTO / ALWAYS / OFF, sizes
   SMALL / MEDIUM / LARGE in the options menu or via the **H** key).
3. Enter a battle — a **Pokédex ball** appears beside each battler whose
   species is already registered in your Pokédex, in classic and wide
   battle layouts.

## What it demonstrates

| Seam | Where |
|---|---|
| `content.screens:register` | `main.lua` — a six-screen family (map → areas → area → source → method → species) |
| `hooks:wrap("ui.start_menu.items")` | `main.lua` — anchor a PKMN MAP row before SAVE |
| `hooks:wrap("render.hud")` | `main.lua` — a walking overlay in the HUD's own space |
| `hooks:wrap("battle.overlay")` | `main.lua` — draw in battle-canvas coordinates, both layouts |
| `hooks:wrap("ui.options.rows")` | `main.lua` — ENC. GUIDE HUD and ENC. GUIDE SIZE rows |
| `mod.ui.insertBefore` / `mod.ui.push` / `mod.ui.ListMenu` | `main.lua` — public UI helpers only |

## Reading, not reaching

Every fact this mod displays comes from public sources: `game.data`
(the merged view, including encounter tables the engine derived from the
player's own import), `game.save.pokedex` (the seen/owned tables), and
`game.save.options`. No `require("src.…")`, no permission declared — the
overlays read, they never write.

The entry ships as the bundled release build (`main.lua`), exactly the
artifact the distributed zip carries; `lib/*.lua` and `tools/bundle.py`
live in the source repo.

## Known

- v1.0.0 covers walking and Surf encounter tables only; fishing, static,
  gift, trade, and prize Pokémon are not represented.
- The guide reads data when opened; reopen it after enabling a mod that
  changes encounter tables.
- The battle HUD draws at final positions, so during the send-out slide
  the ball sits at its rest spot.

## Credits

- Gen1Recomp project — the public mod and UI APIs.
- pret/pokered — the original game data extraction reference.
