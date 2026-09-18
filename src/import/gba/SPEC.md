# Sevii game3 — frozen spec

Runtime for FRLG scripts inside the mod while on `SEVII_*` maps.
Host Gen1/Gen2 elsewhere. Do **not** cast ops into Gold/Red VMs.

See plan `sevii_gen3_script_vm` for narrative; this file is the implementation contract.

## Pret reference

Local mirror (do not vendor into the game repo): `/home/autumn/src/pokefirered`
Use for Oak speech (`src/oak_speech.c`, `data/text/new_game_intro.inc`), naming,
title graphics, and MapEvents — prefer this over ad-hoc web fetches.

## ScriptContext fields

| Field | Notes |
|-------|--------|
| `stack` / depth ≤ 20 | call/return |
| `mode` | stopped / bytecode / native |
| `comparisonResult` | 0/1/2 |
| `data[0..3]` | loadword slot 0 = msgbox text key |
| `stringVars[1..3]` | STR_VAR_1..3 from buffer* |
| `specialVars` | 0x8000–0x8014 only; wipe on halt/unload; never save |
| `lockSnapshots` / `lockKind` | single vs all |
| `activeMoves[localId]` | async movement; done on step_end 0xFE |
| `status` | shutdown / running / waiting |

## Special vars (volatile)

`0x800C` FACING, `0x800D` RESULT, `0x800F` LAST_TALKED, …

## Lock targeting

- `lock` (0x6A): snapshot LAST_TALKED only
- `lockall` (0x69): all active localIds
- matching `release` / `releaseall`

## Text

IR segments; `0xFA` scroll, `0xFB` paragraph, `0xFD nn` placeholders, `0xFF` EOS.
Box stays until `closemessage` or `release*`.

## Movement

No length header; terminate at `0xFE`. LocalId `0xFF` = player.

## callnative / special

Allowlist or safe-skip + log. Never crash.

Allowlisted (host adapters, yield via `waitstate` / native poll):

| special | host |
|---------|------|
| `HealPlayerParty` (0x00) | `adapters.nurseHeal` |
| `ShowPokemonStorageSystemPC` (0x3C) | `adapters.openPc` |
| `PlayerPC` / `CreatePCMenu` | `adapters.openPc` |
| PC turn on/off anim | no-op |

`MSGBOX_YESNO` / `yesnobox`: stay message then `adapters.askYesNo`
(Gen2 YES/NO or Gen1 HEAL/CANCEL); writes `VAR_RESULT` (1/0).

Nurse heal overlay: FRLG Network Center machine is one tile east of the
Gen2 pokecenter OAM layout, so the host adapter shifts `healAnim.px` by +16.

## Extract-first (Gen1/Gen2 model)

Primary content path:

```text
FRLG ROM → MapEvents + script/text/movement BFS
         → sevii/extract/v1/scripts/{events,scripts,text,movements}.lua
         → maps.lua / space.lua load cache only
```

- `island1_content.lua` is curated fallback for CI / no-ROM only.
- Events are annotated with `scriptKey = g3:%08x` at extract time.
- Stdscripts (nurse/PC/`std:N`) overlay the bundle like Gen2 `gen2StdScripts`.
- Cache contract: ready bundle has events+scripts+text; incomplete cache does
  not silently replace a prior ROM extract during normal boots.

## Collision → shared std scripts

Mirror Gen2 `TILE_COLLISION_STD_SCRIPTS`: metatile behavior from ROM extract
(e.g. `MB_PC` → Gen2 `COLL_PC` `0x93`) maps to a **shared** script key
(`EventScript_PC`), not a per-map `(x,y)` bgEvent. Nurse is object-event
script that `call`s shared `EventScript_PkmnCenterNurse`.

## Map scripts

`onTransition`, `onResume` (stub OK), `onFrame[]`. Resume before frame.

## Graphics

Object may have `graphics` constant or `graphicsVar` (0x4010+); resolve at spawn.

Host movement (from FRLG movement_type):

| Content `movement` | Host |
|--------------------|------|
| `STAY` + `range` | standing face |
| `WALK` + `ANY_DIR` + `radius` | wander (Gen2 radius; default 1×1) |
| `LOOK` / `SPIN` | Gen2 `SPINRANDOM_SLOW`; Gen1 stays facing |

Talk: `World.talkNpc` + `freezeNpc` + `facePlayer`; `faceplayer` op refreshes facing.
`World.busy` treats game3 VM as busy so `frozeNpcs` lasts the whole dialog.

## Tier A / extract-driven opcodes

Control: nop, end, return, call, goto, goto_if, call_if, gotostd, callstd,
loadword, setvar, copyvar, setorcopyvar, compare_*, setflag, clearflag,
checkflag, faceplayer, waitmessage, message, messageautoscroll, closemessage,
lock, lockall, release, releaseall, waitbuttonpress, yesnobox, textcolor,
signmsg, normalmsg, setworldmapflag, callnative/special (allowlist or skip),
buffer* (stringVars), delay, random.

Movement / objects: applymovement, waitmovement, removeobject, addobject,
turnobject, hideobjectat, showobjectat, setobjectxy(perm), setobjectmovementtype.

Cutscene / field: opendoor, closedoor, waitdooranim, fadescreen,
warp/warpsilent/warpdoor/warpspinenter, setwarp*, waitstate, setmetatile,
dofieldeffect, waitfieldeffect (host optional).

Audio stubs: playse, playfanfare, waitfanfare.

Economy stubs: additem, removeitem.
Multichoice: interactive via adapters + `multichoice.lua` string tables (not default 0).

ISA grows when Island extract emits new ops — not as a coverage vanity target.

STD: MSGBOX_NPC=2, SIGN=3, DEFAULT=4, YESNO=5.

## Primary engine on `SEVII_*` (game3)

When the player crosses the ferry, **game3** (`sevii/game3/`) is the primary
field engine. Host Gen1/Gen2 run only outside Sevii. Handoff is
`bridge.enterFromHost` / `returnToHost` — not PackMenu/Pokegear/World grafts.

### Hard contracts H1–H9

| Id | Contract |
|----|----------|
| **H1** | RTC / playtime pump while host *field* is paused |
| **H2** | Item quarantine + qty: game3 ≤999; host merge fill to 99; remainder in sidecar overflow (never silent truncate/byte wrap) |
| **H3** | Wild + `setwildbattle`/`dowildbattle` via **game3 owned battle** (`BattleBridge` → `sevii/game3/battle`); same path for trainers; async `nativePoll` until result |
| **H4** | Transitional: foe/player Gen3 move ids kept in-engine; overlay PP writeback (H4∩H6). Host downgrade remaps unused while Sevii battle is owned |
| **H4∩H6** | PP writeback maps to quarantined Gen3 move ids — never overwrite move id with Gen2 fallback |
| **H5** | `setweather` / `doweather` / `resetweather` |
| **H6** | Opaque host-shaped party — **no** DV↔IV / Stat Exp↔EV math |
| **H7** | White-out: cancel host Sevii warp; FRLG money loss (not Gen2 half); respawn via game3 map loader |
| **H8** | `map_connections` depth=1 only; overscan-clipped neighbor draw (no recursive flood) |
| **H9** | National Dex species 252+ in `sevii_game3.national_dex` sidecar only |

Sidecar root: `save.modData.sevii_game3` (flags/vars + quarantine, overflow,
national_dex, move_overlay, heal point, options, pc).

## Field UI (game3 / pret FRLG)

Primary modules: `sevii/game3/ui/{stack,window,hud,message,choice,start_menu,
bag_menu,party_menu,pokedex,region_map,option_menu,save_menu,trainer_card,pc_menu}.lua`
plus `frlg_font.lua` / `chrome.lua`. Drawing via `gfx.lua` on the 240×160 canvas.

### Contracts

| Surface | Contract |
|---------|----------|
| Typography | All menus use `FrlgFont` (`latin_normal`); Gen2 `Font` is not used on Sevii UI |
| Start menu | Pret geometry `(tilemapLeft=22, top=1, width=7, height=2×n)`; entries POKéDEX / POKéMON / BAG / player / SAVE / OPTION / EXIT |
| Town Map | Not a Start row — `ShowTownMap` / Town Map key item → `region_map.lua` |
| Message frames | `dialogue` (menu_message) default; `signmsg` → signpost; `normalmsg` restores dialogue; prompt uses `down_arrows` |
| Yes/No | `Choice.yesNo` → `VAR_RESULT` 1/0; B = NO |
| Multichoice | Labels from `sevii/gba/multichoice.lua` + `extract/v1/scripts/multichoice.lua`; B-cancel = `0x7F` |
| Menu cursor | pret `gText_SelectorArrow2` = charmap `▶` = glyph **0xEF** from `sFontNormalLatinGlyphs` (ROM `0x1FF300`); baked `chrome/fonts/menu_cursor_right.png` via `extract_menu_cursor.py`. Not ASCII `>` / not `CHAR_RIGHT_ARROW` `0x7C`. |
| Options | `session.options` (textSpeed 0/1/2 → Message typewriter); persisted in sidecar |
| Bag | Pockets ITEMS / KEY_ITEMS / POKE_BALLS / TM_CASE / BERRY_POUCH; USE/TOSS/GIVE; field `item_use.lua` |
| Party | Opaque mons (H6); pret `PARTY_LAYOUT_SINGLE` coords; icons/names from Pokémon pack; summary pages; Gen3 move overlay marked; SWITCH is two-cursor |
| Pokédex | Regional ≤251 / National ≤386; names via `Pokemon.name`; 252+ H9 sidecar only |
| PC | `PcMenu` while game3 active — not Gen2 `World:openPc` |
| Save | Confirm YES/NO then host `saveGame` + sidecar persist |
| Pokémon pack | `sevii/gba/pokemon_extract.lua` → `extract/v1/pokemon/{names,types,national,icons}`; runtime `game3/pokemon.lua` (string host ids + internal SPECIES); `cli_extract.lua --pokemon` |
| Party chrome | ROM-baked `extract/v1/pokemon/party/{bg,slot_main,slot_wide,slot_wide_empty,status_balls}.rgba`; `FONT_SMALL` from FireRed hwlat (`extract_latin_small.py` → `latin_small_*.png`); loader `ui/party_chrome.lua` |
| Party layout | pret window templates + `sPartyBoxInfoRects` + `sPartyMenuSpriteCoords` (**center** coords); slot text uses `FrlgFont` `opts.small` |
| OAM / sprites | `game3/oam.lua` — pret `CreateSprite` pool (64), `centerToCornerVec`, priority→y→subpriority flush after UI BG/text in `Display.present`; party mon/ball/status via OAM (not top-left Love draws) |
| Field interact | `Field.interact` owns A-button on Sevii (NPC / bgEvent / collision-std + counter double); host `World.interact` / `OC.interact` no-op while Runtime active |
| Map / mirrors | `Map.load` owns Sevii enter (no host `setMap` soft-sync); `Player.syncSavePosition` on step/load; `Player.syncToHost` only for nurse heal anim / white-out; `Objects.syncToHost` is a no-op |
| Battle | Owned `sevii/game3/battle/` (rules, damage, residuals, effects, ROM `gBattleMoves` merge); placeholder HP/command UI; pret 1:1 chrome/anims later — see `battle/PARITY.md` |

Vendor pret menu BGs with `sevii/gba/chrome/vendor_ui.sh /path/to/pokefirered` (local-dev).

