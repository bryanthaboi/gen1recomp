# Mods and Gen 3 (FireRed, LeafGreen, Ruby, Sapphire, Emerald)

The mod API is one API across all three generations. Hook names, event names
and registry names are shared: Gen 3 reuses the Gen 1 / Gen 2 names and
invents none. A name has no `gen3.` prefix, and a name is only listed here when
it has a native call site in the Gen 3 code (`src/core/game3`,
`src/core/Game3.lua`, `src/link/Game3Link.lua`, `src/ui/game3`) as well as in
the other generations.

`tests/engine/gate_gen3_mod_api.lua` reads these names back out of the source.
It fails if a listed name loses its Gen 3 site, if a Gen 3 site appears for a
name not listed there and here, and if a Gen 3 event emit is not guarded by
`Runtime.wants`.

## Declaring the games

A mod opts in with `games`: `"gen3"` (every Gen 3 game), `"rse"` (the Hoenn
games) or individual version ids (`"firered"`, `"leafgreen"`, `"ruby"`,
`"sapphire"`, `"emerald"`). A manifest that says nothing is not a Gen 3 mod,
and `gen2compat` is not a Gen 3 claim.

`api` 3 mods share one entry file across generations; see
[Portable API 3](modding.md#portable-api-3) for the shared services and the
capability query, which answers per version whether a hook or event has a
native Gen 3 call site.

## Events

- *Boot, save and scripts:* `game.ready`, `save.created`, `save.loaded`,
  `save.loading`, `save.writing`, `script.started`, `script.ended`.
- *The intro speech:* `intro.oak_speech.started`, `intro.oak_speech.step`,
  `intro.oak_speech.answered`, `intro.oak_speech.finished`.
- *Overworld:* `map.entered`, `map.exited`, `map.reloaded`, `player.warped`,
  `world.stepped`, `world.interacted`, `world.npc_spawned`,
  `world.blacked_out`, `world.block_replaced`, `world.boulder_moved`,
  `world.object_toggled`, `world.trainer_engaged`, `flag.changed`.
- *Battle:* `battle.started`, `battle.ended`, `battle.turn_started`,
  `battle.turn_ended`, `battle.move_used`, `battle.damage_dealt`,
  `battle.status_inflicted`, `battle.fainted`, `battle.battler_switched`,
  `battle.exp_gained`, `battle.ball_thrown`, `pokemon.caught`,
  `pokemon.level_up`, `pokemon.move_learned`, `pokemon.before_give`,
  `pokemon.evolved`.
- *Breeding and Pokemon state (`src/core/game3/breeding.lua`, `pokemon.lua`):*
  - `breeding.egg_created` carries `{ egg, stepsToEgg }`.
  - `egg.hatched` carries `{ mon, egg, slot, species, nickname }`.
  - `happiness.changed` carries `{ mon, event, reason, delta, from, to }`.
  - `pokerus.infected` carries `{ party, slot, mon, strain, days, source }`.
- *Roamers (`src/core/game3/roamer.lua`):* `roamer.encountered` carries
  `{ index, slot, species, level, mapId }` and `roamer.moved` carries
  `{ index, slot, species, from, to, reason }`.
- *Link and trade (`src/link/Game3Link.lua`, `src/core/game3/link/`):*
  - `link.connected` is raised once the handshake has the peer's hello, with
    `{ role, remote = { name, mode, mods, fingerprint } }`.
  - `link.ended` carries `{ reason }`.
  - `link.desync` carries `{ turn, component, localHash, remoteHash, fatal,
    seat }`.
  - `link.battle_ended` carries the result, both parties, the peer name and
    the role.
  - `pokemon.received` carries `{ mon, from, peerName }` and
    `trade.completed` carries `{ sent, received, evolveTo }`.

## Hooks

- *Overworld:* `warp.destination`, `movement.collision`, `movement.speed`,
  `encounter.roll`, `encounter.species`, `encounter.table`,
  `encounter.fishing`, `fieldmove.eligibility`, `world.talk`, `item.use`,
  `world.follower.spawn`. `encounter.fishing` is raised from
  `src/core/game3/encounters.lua` with the rod id, map id and pool;
  `movement.speed` wraps the frame count of a step, and the Hoenn bike path
  honours it too.
- *Pokemon rolls:* `gender.roll` and `shiny.roll`
  (`src/core/game3/pokemon.lua`), `breeding.compatibility`
  (`src/core/game3/breeding.lua`).
- *Battle:* `battle.damage`, `battle.crit`, `battle.accuracy`,
  `battle.charge_required`, `battle.turn_order`, `battle.enemy_action`,
  `battle.run`, `battle.enemy_switch_or_item`, `battle.exp_award`,
  `battle.catch_exp`,
  `battle.low_health_alarm`, `battle.field_residual`,
  `battle.menu_auxiliary`, `battle.caught_marker_visible`,
  `battle.bottom_ui_visible`, `battle.status_hud_visible`,
  `battle.move_grid_navigation`, `held_item.trigger`, `exp.gain`,
  `catch.rate`, `trainer.party`, `evolution.check`.
  `battle.field_residual` returns data-only damage rows from
  `src/core/game3/battle/residuals.lua`; the native faint and experience paths
  keep authority over HP, replacements and battle end.
  `battle.menu_auxiliary` is raised from the main battle menu
  (`src/core/game3/battle/init.lua`) and a truthy return claims the press.
- *Trainers:* `trainer.before_battle`
  (`src/core/game3/battle_bridge.lua`) receives the game, a context table and a
  `continueBattle` function; a truthy return defers the battle until a mod
  calls `continueBattle`, optionally with `{ cancel = true }`.
- *Menus (`src/ui/game3`):* `ui.start_menu.items`, `ui.options.rows`,
  `ui.party.submenu`, `ui.party.grid_navigation`, `ui.naming.grid`,
  `ui.list_menu`.
- *Sprites:* `pokemon.sprite`, `pokemon.icon`.
- *The frame (`src/core/Game3.lua`):* `core.logic_speed` (the resolved
  logic-clock multiplier, clamped by `GameSpeed.clamp`; a locked or overridden
  speed never reaches it), `input.step`, `input.pointer`, `input.key`,
  `input.gamepad`, `input.wheel`, `render.hud`, `render.zones`.
- *Save and scripts:* `script.command`, `save.write`, `save.new_game`.

## Registries

Of the 47 registries, 34 are available on Emerald (33 on FireRed and LeafGreen)
and 13 report that they have no Gen 3 target. Routing is
`Schemas.GEN3` in `src/mods/Schemas.lua`.

| Routing | Registries |
| --- | --- |
| Own Gen 3 table (`gen3*`) | `pokemon`, `moves`, `items`, `trainers`, `encounters`, `text`, `rom_text`, `map_scripts`, `move_effects`, `statuses`, `ai_classes`, `battle_anims`, `palettes`, `font`, `landmarks`, `decorations` (Ruby, Sapphire, Emerald only) |
| Shared Gen 1 target | `balls`, `commands`, `evolution_methods`, `growth_rates`, `icons`, `item_effects`, `maps`, `render_pipelines`, `screens`, `sprites`, `strings`, `tokens`, `type_chart`, `music`, `sfx`, `cries`, `map_songs` |
| Code registry, no data target | `migrations` |
| No Gen 3 target (reported, never merged) | `apricorns`, `audio`, `battle_sprite_scales`, `constants`, `field`, `held_items`, `link_fields`, `phone_contacts`, `radio_channels`, `rulesets`, `text_pointers`, `tilesets`, `transitions` |

`render_pipelines` run all three stages on Gen 3: `drawWorld` owns the field
plane (`src/core/game3/display.lua`), `worldPresent` folds over it before the
UI, `present` over the whole frame, and every pipeline gets its OPTION row.
The Gen 3 `ctx` and `ctx.drawField(opts)` are described in `docs/modding.md`
("Rendering pipelines") and [RFC 0022](rfcs/0022-gen3-world-pipeline.md).

On an `api` 3 mod, `pokemon`, `moves`, `items`, `trainers` and `encounters`
take the canonical Gen 1 record shape; `text`, `rom_text`, `landmarks` and
`decorations` pass native shapes through; registries with a Gen 3 shape and no
canonical adapter (`move_effects`, `statuses`, `ai_classes`, `battle_anims`,
`palettes`, `sprites`, `icons`, `balls`, `maps`, `map_scripts`) pass the native
shape through for `api` 2 and `api` 3 mods alike, and `mod:supports` is true
for them. Only the registries with no Gen 3 target report `unsupported`.

Gen 3 routes the content registries that have a native consumer. `music`,
`sfx`, `cries` and `map_songs` take `file` (and `chip`) rows played by the
Gen 3 audio engine (`src/core/game3/mod_audio.lua`); a row keyed by a native
name (`SE_PIN`, a species) replaces the cart sound. `trainers` rows may carry
`className`, `class`, `baseMoney` and a `pic` image path. `tokens` expand in
Gen 3 text, `icons` replace a species' party icon (a string borrows another
species' icon), `sprites` feed the field renderer, `screens` feed `mod.ui`, and
`balls` take `{ multiplier, autoCatch }`. The registries in the last table row above have no Gen 3 consumer and report
that they have no Gen 3 target.

### Graphics registries

`sprites` records draw through the field renderer for any NPC whose `sprite`
names one (`mod.world:spawnNpc`, `npc:setAppearance`). Gen 3 art is full
colour, so every mod sheet is drawn as true colour; `trueColor` is accepted and
changes nothing, and `paletteSource` (a Gen 1 OBJ palette assignment) has no
Gen 3 meaning. A species' battle pictures come from `pokemon` records
(`spriteFront`, `spriteBack`, 64x64, recentred when smaller).

`palettes` records keep the Gen 1 shape (four `{r, g, b}` rows, or
`{ colors = ... }`) and land in `data.gen3Palettes`. The cache stores Gen 3 art
as pre-baked RGBA, so a record is applied where the cache image becomes a
texture (`src/core/game3/palette_mods.lua`): the four rows are a ramp from the
lightest colour to the darkest, every opaque pixel is placed on it by its
luminance (normalised over the image), and the result is quantised to GBA
15-bit colour. Ids are `<SPECIES>MON` (normal pictures, front, back and party
icon), `<SPECIES>MON_SHINY` (shiny pictures) and `OBJ_EVENT_GFX_<NAME>`
(overworld sheets, including the reflection palette). A species or graphic
with no record is untouched, and with no records installed the bytes are
returned as read. Mod art from `sprites` or `pokemon` records is never
recoloured. Register the ids with `register`; there is no vanilla record to
`override`. A four-row ramp cannot reproduce a multi-hue native palette, which
is the same trade the Gen 1 DMG palette makes.

`font` records keep the Gen 1 shape and land in `data.gen3Font`
(`src/ui/game3/font_mods.lua`, hooked into `frlg_font`). A page's image alpha is
the glyph mask in 8x8 cells (colour is ignored and the text colour and shadow
apply), `base` is the first glyph code (below 0x400, which is where the
Japanese sheet starts), and `advance` is the pixel advance. A code that is
already a native glyph replaces it. A `charmap:` row maps one character to a
glyph code; a multi-character sequence has no Gen 3 meaning and is ignored with
a warning. The `ttf` entry draws Latin text (ASCII and Latin-1 and Latin
Extended-A) through the TTF with the window's shadow, using `file` (the bundled
Plain Pixel by default), `size`, `spacing`, `yOffset`, `bold` and `tiles`
(characters that keep their ROM glyph). The ROM's special glyphs, control
codes and the Japanese sheet are untouched.

`tilesets` stays gated. Gen 3 maps are 16px metatiles from a primary and a
secondary tileset whose tile art, palettes and behaviours are baked per pair
into layered atlases (`tileset_native`); there is no per-tile block table or
walkable-tile list for a Gen 1 record to replace, and a metatile behaviour
override would be a new Gen 3 shape rather than the Gen 1 record.

`item_effects` runs through the native item-use flow. A mod item sets
`effect = "ID"` and the record's `use(ctx)` returns `"consumed"`, `"kept"` or
`"failed"` plus a list of messages, as on Gen 1. Field use goes through
`ItemUse.useField` (the bag, and the party menu when `needsTarget` is set);
battle use through `BattleItems.use`, so `battle = false` hides the item from
the battle bag and `field = false` refuses it outside battle. `ctx.target` is
the native Gen 3 party record, and `ctx.battle` is the battle state in battle.
Native items keep their ROM effect bytes; the mod id is stored beside them.

`landmarks` are map sections (`regionMapSectionId`). `index` names the section:
an index the cart already uses renames and re-themes it, a free one adds a
section. Optional `x`, `y`, `width`, `height` claim zero-based region map
cells for the cursor (`region` selects the FireRed layout), and the new name
shows in the map-name popup, the region map name box and the save screen. The
tilemap art is not redrawn.

`decorations` exist on Ruby, Sapphire and Emerald only (FireRed and LeafGreen
have no secret bases and report the registry as unavailable). A record is a
`gDecorations` row: `index`, `name`, `permission` (0..3), `shape`, `category`,
`price`, `description` and the `tiles` painted row by row. Sprite decorations
are not moddable. The decoration PC, the bag counts and secret base placement
read the merged row.

### Battle registries

`move_effects`, `statuses`, `ai_classes` and `battle_anims` keep their Gen 1
records and verbs and land in `gen3MoveEffects`, `gen3Statuses`,
`gen3AiClasses` and `gen3BattleAnims`. The Gen 3 battle is the pret battle
script engine with native status bits, so nothing is seeded into them: the
cart's own effects, statuses and AI scripts are code, not records, and cannot
be patched. They hold mod content only.

- *Move effects.* An API 3 mod sets a registered id as a move's `effect`; the
  move keeps native effect byte 0 and the engine runs the callback where the
  cart runs the move's battle script. `primary` runs for a power-0 move
  (`accuracyChecked` rolls the cart's accuracy check and `missText` picks the
  refusal line), `secondary` and `full` run `run` after a hit that dealt damage,
  and a `primary` record on a damaging move never runs, as on Gen 1. `run(ctx)`
  returns the messages to print; set `failed = true` on the table when the
  effect did not land. `ctx` has the Gen 1 members (`user`, `target`, `move`,
  `rng`, `say`, `anim`, `damage`, `inflict`, `cure`, `changeStage`,
  `computeDamage`, `accuracyRoll`, `callMove`, `displayName`, `side`) over Gen 3
  battlers (`battler.mon.hp`, `battler.stages`, `battler.status`). `inflict`
  takes the native ids `SLP PSN BRN PAR FRZ TOX` (through the cart's status
  path, abilities and Safeguard included) or a mod status id; `changeStage`
  reads `special` as Special Attack. The Gen 1 damage-pipeline stage fields
  (`hitCount`, `chooseDamage`, `beforeAccuracy`, `onMiss`, `afterDamage`, `gate`,
  `perform`) have no Gen 3 hook and are not read.
- *Statuses.* A mod status lives in its own per-battler slot, never in the
  native status bits, so it lasts for the battle and a mon holds at most one
  status of either kind. `canInflict`, `onInflict`, `beforeMove` (priority above
  20 runs where the cart checks sleep and freeze, 20 or below where it checks
  paralysis), `residual` (runs with the cart's poison and burn chip),
  `cureOnSwitch` (otherwise the status waits on the bench and returns with the
  mon), `statPenalty` (attack, defense, speed, spAtk, spDef, or `special` for
  both) and `catchBonus` (added to the capture odds) are honoured; `label` or
  `hudLabel` shows in the healthbox status slot. `shakeBonus` is not read: the
  Gen 3 capture shake is four independent rolls with no status term.
- *AI classes.* A trainer row (an API 2 or API 3 mod, as on Gen 1) names one with
  `aiClass`, and lists layers in `aiMods`. A `layer` adjusts each usable move's score after the cart's AI
  scripts, on the Gen 3 scale where higher is better (Gen 1 is lowest-wins). A
  `brain` receives `view.moves` and returns the slot (1 to 4) to use, and
  replaces the scripts. A `class` is consulted before the cart's own item and
  switch logic with the Gen 1 fields (`uses` per party member, `chance`,
  `item`, `hpBelow`, `switch`, `switchChance`, `switchBelow`, `onStatus`); its
  `item` must be one the trainer already carries, and a switch picks the first
  healthy party member. Wild battles ignore classes.
- *Battle animations.* An id is a move id and `seq` is the battle animation
  script for it, in the `op` vocabulary of the cart's own animation pack
  (`createsprite`, `createvisualtask`, `delay`, `playsewithpan`,
  `waitforvisualfinish`, `end`). A native move id replaces the cart animation,
  and `ctx.anim` plays any registered id. Gen 1 `blocks` and tilesheet records
  have no Gen 3 form. These registries carry a Gen 3 shape, so like Gold's they
  take the native record as a pass-through write from an `api` 2 or `api` 3 mod.

## What Gen 3 does not get

A shared name is registrable everywhere, but a feature only does something
where the cart has it. Gen 3 has no phone, radio or apricorns, so none of
those registries or events are raised from Gen 3 code.

## Screens

`mod.ui.push` shows a screen registered in `content.screens` on the Gen 3
stack. This bridge is what an `api` 3 mod gets from `mod.ui`; `api` 1 and 2 mods
keep the Screens-based `push` and the Gen 1 `TextBox`. The screen draws into the 160x144 interior of the 240x160 frame,
translated to (40, 8); set `gbaCanvas = true` on the state to draw in the full
frame. `mod.ui.TextBox` opens the native message window and does not support
the `choice` or `stay` options. The bridge is `src/ui/game3/mod_ui.lua`.
