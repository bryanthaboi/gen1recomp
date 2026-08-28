# Mods and Gen 2 (Gold)

The mod API is one API across both generations. Hook names, event names,
registry names and the `mod.*` facade are shared on purpose: a mod that runs on
Red should be able to run on Gold without learning a second vocabulary.

What differs is how much of it Gold can actually serve, and that is why Gen 2
support is something a mod **declares** rather than something it inherits.

## What you can rely on today

The short version, for an author deciding what to write:

- **Every registry name, hook name and event name means the same thing in both
  games.** Nothing is prefixed, renamed or repurposed per generation. Where Gen
  2 genuinely carries more, the record or the payload gains a *field*.
- **40 of the 46 registries are available on Gold.** 17 keep their Gen 1 target
  outright (`commands`, `tokens`, `growth_rates`, `battle_sprite_scales` and
  `render_pipelines` among them), 16 route to a Gen 2 table under the same
  name, 6 are Gen 2-only systems Red has no counterpart for, and `migrations`
  is a code registry with no data target in either game. The other 6 are gated,
  and are listed below with the consumer change each one still needs.
- **A registry with no home in a generation is reported, never silently
  merged.** The write is taken, dropped, and named once per mod in the same
  error feed the mod manager shows -- in both directions, so a Red boot writing
  to `decorations` is told exactly as a Gold boot writing to `map_scripts` is.
- **40 event names and 44 hook names have a call site in both generations**, so
  one subscription serves both games. `tests/engine/gate_gen2_mod_api.lua`
  reads those names back out of the source and fails if a site is renamed or
  deleted on either side, and fails again if a new shared site appears without
  being listed here.
- **24 further names are Gen 2-only** (friendship, breeding, the Pokegear, the
  radio, Pokerus, the roamers, Kurt, the Bug Contest, the Unown puzzle, mail,
  held items, shininess, gender, and the five cards of the GS boot cinema).
  They are plain names, not a `gen2.` namespace, so if Red ever grows the
  system the name is already right.
- **Every Gen 2 seam is guarded** by `Runtime.wants` / `Runtime.wantsHook`, so
  a boot with no mod subscribed allocates nothing at any of them.
- **A mod is loaded on Gold only if it says so.** See `gen2compat` below.

`src/mods/Schemas.lua` is authoritative for routing;
`tests/engine/gate_gen2_mod_api.lua` holds this document to it.

## Declaring which games a mod is for

```json
{
  "id": "my_mod",
  "name": "My Mod",
  "version": "1.0.0",
  "entry": "main.lua",
  "api": 2,
  "games": ["gen1", "gen2"]
}
```

`games` is an optional array of version ids (`"red"`, `"blue"`, `"yellow"`,
`"gold"`, `"silver"`, `"crystal"`), generations (`"gen1"`, `"gen2"`,
case-insensitive) or `"all"`. `src/mods/ModTargets.lua` resolves the tokens off
`GameVersion.ORDER` and `GameVersion.generation`, so nothing anywhere restates
the game list. `"gen2"` now expands to Gold, Silver and Crystal.
`Manifest.validate` stores the resolved, ORDER-sorted ids on `manifest.games`
and **derives** `manifest.gen2compat` from them, which is the one field the
loader's gate reads.

Nothing moves on disk for any of this. A mod is installed once, into
`mods/<id>/`, and that directory serves every game: there is no `mods/gen1/`
and no per-generation copy. Targeting is declared, not filed.

`"gen2compat": true` is the legacy spelling and is still accepted. It is purely
additive -- it *adds* the Gen 2 games to whatever `games` says -- so no shipped
manifest can lose a game it already ran on. A manifest with neither key is Gen
1 only, which is exactly what it always meant. An unknown token warns and is
dropped under `api` 1 and refuses the manifest under `api` 2; a `games` array
that names no game this engine knows falls back to the default rather than
orphaning the mod; a non-array `games` is a hard error.

Every token is enforced, per game. `Loader:_gateGeneration` gates on
`ModTargets.supports(manifest, version, generation)`, the same call both mod
surfaces make, so `"games": ["blue"]` really does not load on Red and the
loader's skip line is the launcher's line, `For Blue, not Red`. A manifest with
no `games` and no `gen2compat` still covers every Gen 1 game, so nothing
written before the key existed changes behavior.

On a Gold boot, a mod claiming no Gen 2 game is **not loaded at all**: no
registrations, no subscriptions, no entry chunk. The manager still lists it,
showing `ENABLED (NOT THIS GAME)` and the reason, and the player's enable flag
is left alone so it comes straight back on Red.

Both mod surfaces derive what they show from `ModTargets` rather than from
their own copy of the rule. The launcher's mod panel carries a `Show for:` game
chip row and a per-mod tag (`GEN 1`, `GEN 1+2`, `RED/GOLD`), greyed with `Not
for this game` and the detail `For Gen 1, not Gold` when the mod does not run
on the selected game; the in-game manager shows the same verdict as
`ENABLED (NOT THIS GAME)` plus an inert `FOR GEN 1+2` row on the detail screen.
The launcher asks the same question of a mod's dependencies: one whose hard
dependency does not run on the selected game reads `Needs <id> (not for Gold)`,
matching the loader's contagious skip.

A separate overlay, `options.modsByVersion[version][id]`, holds each game's
enable flag. The launcher shows a coloured Red / Blue / Yellow / Gold checkbox
for every installed mod, and the loader and in-game manager read the same
game-specific answer on the next boot. On the first launch after this feature,
the existing shared state is copied to every game, so a mod that was enabled
remains enabled everywhere; after that, changing one checkbox affects only
that game. New mods still default to enabled on every game (experimental mods
retain their explicit opt-in default).

That is deliberate. Gold reimplements the battle engine, the overworld, the
script VM and the save format, so a Gen 1 mod dropped into a Gold boot would
find a small fraction of its call sites live. A mod that half-applies reads to
a player as a broken mod. Not running is the honest state, and naming a Gen 2
game is the author saying "I have tested this there".

Adding a Gen 2 game does not opt out of anything on Gen 1, because `games` is a
union: `["gen1", "gen2"]` covers everything it covered before. What does change
is that the gate now runs on a Gen 1 boot too, so a manifest that names *only*
Gen 2 games no longer loads on Red, Blue or Yellow. Say `["all"]` or list both
generations if you want both.

Two riders. **A hard dependency that does not run here takes the dependent down
with it** (unless scoped to specific games, e.g.
`dependencies: [{ id = "x", games = ["gen2"] }]`), as a skip rather than a
failure and carrying the dependency's own wording (`depends on X, which does not
run here (For Blue, not Red)`), so the whole chain has to cover the same games.
And **the claim is yours, not the last word**: it is the manager's `TRY HERE ANYWAY` row that lets a player run a mod
whose author never opted in, which is the only route for a mod written before
the field existed. The override is per game -- `options.modsGen2[id]` is a
`{ [version] = true }` table, so forcing a mod onto Red does not force it onto
Gold, and a legacy `options.modsGen2[id] = true` reads as "the Gen 2 games",
the only set it could ever have affected. It applies on the next boot; a forced
mod loads normally and keeps a note saying it was never verified here. Where
the choice cannot be persisted the manager says `COULD NOT SAVE` instead of
promising a restart.

If you are writing new code, still prefer the API: take the live game from
`mod.game` (or the `game.ready` payload, or a `ui.*` hook's first argument) and
the world from `mod.world`. Those are the names that mean the same thing in
both games. What follows is for the mods that were written before Gold existed
and reach past it.

## Gen 1 module facades

A mod with `engine_internals` reaches engine modules by name, and under Gold
those names used to resolve to Gen 1 modules nothing instantiates -- so the
patch landed on dead code and the mod was inert with no symptom but silence.

On a Gen 2 boot, **a require made from a mod's own chunk is answered by an
adapter**: the Gen 1 API, backed by Gen 2 internals. `src/mods/Gen2Compat.lua`
is the table, `src/mods/Loader.lua`'s require shim is where the swap happens,
and `tests/engine/gate_gen2_mod_facade.lua` holds both to it. Engine code is
not affected -- the shim only substitutes when the calling chunk is outside the
engine tree, so `src/render/PaletteFX.lua` still gets the real Gen 1 module on
both generations.

Fifteen names are served. **alias** means the adapter *is* the Gen 2 module, so
a monkey-patch, a `rawset` sentinel and a `getmetatable(x) == M` check all land
on the table Gold runs; **facade** means a translating wrapper over it.

| the Gen 1 name a mod requires | kind | what it gets on Gold |
| --- | --- | --- |
| `src.core.Game` | facade | a live proxy onto the Game2 instance |
| `src.world.OverworldController` | facade | over `src/world/gen2/World.lua`; `World:step` / `:interact` / `:interactBody` dispatch through it |
| `src.world.Map` | alias | `src/world/gen2/Map.lua`, grown Gen 1's statics and instance methods |
| `src.world.NPC` | alias | `src/world/gen2/Npc.lua`; `NPC.new` sniffs the Gen 1 argument order |
| `src.pokemon.Boxes` | facade | over `src/core/gen2/Boxes.lua`, plus Gen 1's `COUNT` / `CAPACITY` / `ensure` / `active` / `deposit` |
| `src.battle.BattleState` | facade | over `src/ui/gen2/BattleState.lua`, write-through |
| `src.ui.PartyMenu` | facade | over `src/ui/gen2/PartyMenu.lua`, write-through |
| `src.world.WorldAPI` | alias | `src/world/gen2/WorldAPI.lua` |
| `src.world.PikachuFollower` | alias | `src/world/gen2/Follower.lua` |
| `src.script.ScriptRunner` | facade | over `src/script/gen2/Vm.lua` |
| `src.ui.OptionsMenu` | facade | over `src/ui/gen2/OptionsMenu.lua`, write-through |
| `src.world.FieldDefaults` | facade | the `playerSprites` answer, and a named refusal for the rest |
| `src.world.Collision` | facade | `DELTA` / `target` / `occupied` / `canMove` |
| `src.ui.StartMenu` | facade | over `src/ui/gen2/StartMenu.lua`, write-through |
| `src.ui.BoxMenu` | alias | `src/ui/gen2/PcMenu.lua` |

Two entries in that table are not the pairing they look like.
`src.ui.BoxMenu` resolves to `PcMenu`, not to `src/ui/gen2/BoxMenu.lua`: Gen 1's
`BoxMenu` is Bill's PC *top menu*, whose Gold counterpart is `PcMenu`, while
Gold's `BoxMenu` is the withdraw/deposit *list* Gen 1 builds inline. And
`src.script.ScriptRunner` is served narrowly rather than fully: `scanLabels`
and `validate` forward verbatim, with the default verb lookup swapped to
`game.data.commands` so a script of Gen 1 built-ins cannot validate clean and
then run as nothing, while the lifecycle half is a thin handle onto the one
`world.vm` with `resume` and `update` refused rather than double-driving it.
The `script.started` / `script.ended` / `script.command` seams are the
supported route and already work on Gold.

`src.script.Commands` and `src.ui.OptionRows` have **no** adapter and are the
two names a require of which still lands in the boot error feed the manager
shows, with the module named. Both load fine under Gold and both are traps: the
first hands back 61 Gen 1 verbs none of which Gold can run, the second paints
Red's four-box options chrome over Gold's single 18x16 one.

`docs/preparing-your-mod-for-gen2.md` is the migration guide for an author
working through this, and `python3 tools/modkit.py gen2check <id>` reports a
mod's own findings against the coverage table below.

Three rules the adapters keep, because a plausible wrong answer is worse than
the module being missing:

- **Live, never a snapshot.** A mod captures `require("src.core.Game")` at file
  scope, before a save or a world exists. The facade is a proxy that reads the
  live instance on every touch, so `Game.save` is nil during the entry chunk
  and correct forever after. It aliases the two names Gold spells differently
  (`Game.overworld` is `Game2.world`, `Game.writeOptions` is
  `Game2:persistOptions`) and the one data table that was renamed
  (`game.data.sprites` is `data.gen2Sprites`).
- **A member with no backing says so.** `game.data.field` does not exist on
  Gold, so it reads nil *and* logs once, naming the mods holding the facade.
  `BattleState.newWild` is absent rather than invented, because a `newWild`
  that took a species and a level would be a lie about what Gold's battle
  screen is.
- **One stable table for the run.** Where the Gen 2 arm can serve the name
  outright the adapter *is* that module, so a mod's monkey-patch, its
  `rawset` sentinel and its `==` idempotency check all land on the table Gold
  actually runs.

### What the adapter says it covers

The adapter publishes its own coverage, versioned by
`Gen2Compat.COVERAGE_VERSION` (1), and `modkit gen2check` consumes that table
rather than a second copy of the same knowledge:

```lua
Gen2Compat.modules()                            -- the 15 names, sorted
Gen2Compat.serves(name)                         -- boolean
Gen2Compat.memberStatus(name, member)           -- "backed" | "warned" | "absent" | nil
Gen2Compat.coverage(name)                       -- a fresh table per call:
--   { module, kind = "facade"|"alias", target, members = { [name] = status },
--     notes = { [name-or-topic] = "one line" } }
```

The status vocabulary is frozen at three values, and a member listed as both
resolves to the weaker claim:

| status | means |
| --- | --- |
| `backed` | present, and it does the Gen 1 job on Gold |
| `warned` | present, answers nil or degrades, and names itself once with the mod attributed |
| `absent` | deliberately not served; a nil read is the honest failure |

Today that is 291 backed, 32 warned and 161 absent across the fifteen modules.
`notes` keys are documentation topics rather than a member list -- dotted paths
(`save.money`), field names (`warpAt`), hook names (`hook ui.pc.items`) and
bare topics (`identity`, `iteration`, `rawset`) all appear there. `members` is
the authoritative set, and a member it does not record is not a promise either
way: on an alias it resolves to whatever the Gen 2 module has, on a
write-through facade it falls to the Gen 2 class, on the `src.core.Game` facade
it reads nil and says so, and on the `src.world.OverworldController` facade it
reads nil silently.

**The follower.** Gold's cart has no trailing companion at all, so
`src/world/gen2/Follower.lua` is new Gen 2 code rather than a facade: the
entity, the trail loop, and a `shouldSpawn` a mod replaces. `World:step` calls
`Follower.update(game, world)` once per logic frame after the body, and
`World:setMap` calls `Follower.onMapEntered` before it emits `map.entered` --
the same two call sites `src/world/OverworldController.lua` gives the Gen 1
arm, which is what makes a Gen 1 follower mod's wrappers tick.

Vanilla never spawns one: `shouldSpawn` answers false until something replaces
it. `Follower.setShouldSpawn(fn)` is the supported way, and it writes the same
file-local the Gen 1 mods reach through `debug.setupvalue` on the upvalue named
`shouldSpawn`, so the two cannot disagree.

Two Gen 2 engine changes came with it, both general rather than follower-only:
an entity with `passable` set never blocks a step (the Gen 1 name and meaning,
`src/world/Collision.lua`), and `World:rebuildPeople` now preserves **guests** --
anything in the people list it did not put there. A rebuild runs on every zoom
and every time-of-day roll, so without that a follower vanished at the top of
the hour.

**What the facades cannot fix.** A mod that allow-lists version strings
(`GameVersion.get() == "red" or ...`) excludes itself from Gold by construction,
and no adapter should special-case it. Neither is a Gen 1 screen id: Gold's
builtins carry a `Gen2` prefix, so a mod matching `id == "BoxMenu"` matches
nothing. A write to a field on a live Gen 2 menu instance is inert where Gen 1
read it back (`menu.onSwitch`, `menu.swapFrom`, `StartMenu`'s box geometry),
and `map.warpAt` is a name collision rather than a rename -- Gen 1's is a table
keyed by cell, Gold's is a method, so indexing or iterating it raises. All of
these are mod-side edits, each with a route that works on both generations;
`docs/preparing-your-mod-for-gen2.md` walks through them.

## What works on Gold today

**Screens.** The `screens` registry serves both generations. Gold's screens
are registered under `Gen2`-prefixed ids so a mod that replaces Gold's party
menu does not also replace Red's; `Screens.GEN2_IDS` in `src/ui/Screens.lua`
is the full list. Every screen Gold opens goes through an id, including the
boot cinema and the START menu.

**Asset overrides.** `overrides/` shadowing and asset transforms work
unchanged: Gold's screens load art through `src/render/Assets.lua`, the same
choke point Gen 1 uses.

**Content registries at the shared path.** `pokemon`, `moves`, `items`,
`type_chart`, `strings`, `font`, `screens`, `commands`, `tokens`,
`growth_rates`, `battle_sprite_scales`, `render_pipelines`, and the audio
family (`audio`, `music`, `sfx`, `cries`, `map_songs`). These keep their Gen 1
target path, so one mod source targets both generations.

The last two are the newest and each carries one caveat worth stating before
you write against it:

- **`battle_sprite_scales`.** `src/ui/gen2/BattleState.lua:imageScale` walks
  the merged table for a record whose `path` matches the pic being drawn,
  skipping the registry's own `_owners` row, and `picScale` falls through to
  the species record's `battleScaleFront` / `battleScaleBack` after it -- the
  same image-then-species-then-default order Gen 1 resolves in. Because the key
  is the asset path it also reaches the pics that are nobody's species: the
  player's trainer back, the DUDE's, an opponent's frontpic. The **default**
  differs and is not a registry record either side: Red's 32x32 back pics draw
  at 2x, Gold's 48x48 ones fill their 6x6 box at 1x, so a scale that looks
  right on Red is twice as large on Gold. At any scale the pic stays centred in
  its box and standing on the same ground line.
- **`render_pipelines`.** `src/core/Game2.lua:load` installs
  `src/render/Pipelines.lua` on Gold's dataset *after* `mods:load`, so the
  merged table is the one it walks, and `Game2:draw` composites the
  whole-frame half through `Pipelines.wantsPresent` / `Pipelines.present` with
  the Gen 1 ctx keys (`width`, `height`, `scale`, `dpi`, `dpiX`, `dpiY`). The
  **`drawWorld` half is inert on Gold**: its overworld draws straight to the
  window rather than into a canvas the way `src/world/OverworldController.lua`
  hands one to `Pipelines.drawWorld`. A drawWorld-only pipeline is not left
  switched on and drawing nothing -- `Game2:load` retires a restored level for
  one, leaving `options.pipelines` untouched so the mode comes back the day
  Gold grows a world canvas. Gold also has no OPTION row for a pipeline
  (`Pipelines.rows` is read only from `src/ui/OptionsMenu.lua`), so a Gold
  player reaches one by its `hotkey`.

  The additive **`drawBillboards` stage is live on Gold, Silver, and Crystal**
  when the built-in TILT mode is active. It receives the same semantic
  collision-map view as Gen 1 plus `drawMapCutout`, `maskMapCutout`, and
  `billboard` helpers. Source silhouettes are masked from the tilted ground
  before queued cards join the normal upright-object Y-sort, preventing the
  flat and upright copies from being drawn together.

**Content registries at a Gen 2 path.** `maps`, `tilesets`, `sprites`, `text`,
`encounters`, `trainers`, `palettes`, `icons`, `battle_anims`, `constants`,
`statuses`, `move_effects`, `item_effects`, `balls`, `ai_classes` and
`evolution_methods`. Same registry name, same verbs, a Gen 2 table underneath
(`data.gen2Maps`, `data.gen2Encounters`, `data.gen2Statuses`, ...).
`src/core/Game2.lua` loads the extracted ones into `game.data` before it
calls `mods:load`, and every consumer takes them by reference and never
copies, so what a mod merges is what the game walks: a registered map is a map
Gold can warp into, a patched tileset is the one `Map.new` reads, a patched
encounter table is the one the grass rolls.

The battle-rule six are the newer half and work slightly differently: there is
no table on disk for them at all. They come into existence *as* the merge, and
each consumer reads a record through a lookup that falls back to its own module
records when no loader ran, so a mod-free Gold boot behaves identically:

| registry | who reads it |
| --- | --- |
| `statuses` | `Battle.statusRecordFor` / `statusPenaltyFor`, `Catching.statusBonus`, `ItemEffects.healClassOf` |
| `move_effects` | `Battle.moveEffectRecordFor` (`useMove`'s dispatch) |
| `balls` | `Catching.recordFor` |
| `ai_classes` | `Ai.layersFor` (the ten `scoring.asm` passes, plus mod layers) |
| `evolution_methods` | `Evolution.methodFor` |
| `item_effects` | `ItemEffects.recordFor` / `partyAction` |

`src/mods/Builtins.lua` seeds those six with **Gold's** records under Gen 2
rather than Red's. It has to: both games call it `GREAT_BALL`, and Red's record
carries no `multiplier`, so seeding Red's would leave Gold's x1.5 reading nil.

**Content registries that exist because Gold does.** Six systems Red has no
counterpart for, so there is no Gen 1 table to share and none of these carries
a Gen 1 target at all. The routed Gen 2 path is their only home, and
`Schemas.GEN1` gates them on a Red boot the way `Schemas.GEN2` gates
`map_scripts` on a Gold one -- reported, not silently merged.

| registry | id space | who reads it |
| --- | --- | --- |
| `held_items` | item ids | `ItemEffects.heldItemFor`; the merged rows are written back onto `data.items` for `Battle:itemDef` |
| `phone_contacts` | `PHONE_*` (`data.gen2Constants.phoneContactOrder`) | `Phone.useRegistry`, folded onto the contact table |
| `decorations` | `"deco:<n>"` | `Decorations.attributes`, the single read point for an attribute row |
| `apricorns` | apricorn item ids | `Apricorns.useRegistry`, which rebuilds all three lookups and Kurt's menu order |
| `landmarks` | `LANDMARK_*` | `Nests.landmarkId` / `Nests.landmark`, which resolve a map header's landmark byte |
| `radio_channels` | station ids | `MapRadio.channelRecord`, which puts a registered station on the dial |

`Game2:load` calls `Phone.useRegistry`, `Decorations.useRegistry`,
`Apricorns.useRegistry` and `ItemEffects.applyHeldItems` immediately after
`mods:load`, so the merge is live before the first frame. `landmarks` and
`radio_channels` need no such call: their consumers take `data` at call time.

`landmarks` merges onto the cache's own `gen2Landmarks.landmarks` and
`held_items` onto the view `Game2` builds from `data.items`, so both fold
against the vanilla row -- a `register` for an existing id collides, a
`patch` stacks. The other four come into existence as the merge, seeded from
their module's literals by `src/mods/Builtins.lua`.

Four honest limits on that surface:

- `held_items` reaches the battle by being written back onto `data.items`, so a
  held row for an id with no `data.items` record lands nowhere. To invent a
  held item, register the `items` record too. The write-back is a diff against
  a pre-merge snapshot, which is what lets `items` and `held_items` compose
  instead of one reverting the other.
- `decorations` ids are `"deco:<n>"`, not `DECO_*` names: the cart's decoration
  constants are a bare `const_def` block with no name table behind them, so
  there is nothing in the ROM to spell them by. `battle_anims` addresses its
  unnamed rows the same way. `n` is the attribute row's index, which is
  `wMenuSelection`.
- `phone_contacts` does not register the four `PHONE_UNUSED` `const_skip` holes
  (contact bytes 8, 9, 10 and 25). The manifest gives all four the same id, and
  one id cannot key four rows. They stay copies of the wrong-number filler,
  which is what the cart does with them.
- `radio_channels` and `phone_contacts` register *content*, not new UI: a
  registered station gets a dial position and a name, and a registered contact
  gets a row the Pokegear indexes, but neither invents a screen.

**Record shapes.** A registry whose Gen 2 records genuinely differ carries a
Gen 2 schema beside its Gen 1 one (`gen2Fields` / `gen2Keys` / `gen2Write` in
`src/mods/Schemas.lua`, resolved by `Schemas.shapeFor`). The registry name, the
verbs and wherever possible the ids stay shared; only the record changes. The
differences an author meets:

- **`pokemon`.** Gen 2 splits `special` into `specialAttack` /
  `specialDefense`, names the level-up table `levelMoves` and the pic size
  `picSize`, has no separate `level1Moves`, and points an evolution at `into`
  rather than `species`. It also carries the breeding block (`eggGroups`,
  `eggMoves`, `eggSteps`, `genderRatio`) and the wild held-item pair.
- **`encounters`.** The id is the encounter *kind*, not the map:
  `mod.content.encounters:patch("grass", { ROUTE_29 = { rates = { NITE = 40 } } })`.
  A map's row carries a `rates` set per time of day and one slot list.
  `fishGroups`, `trees` / `treeSets`, `rocks`, `bugContest` and `roamMaps` are
  ids of their own.
- **`trainers`.** The id is the trainer *class*, and the record is
  `{ name, index, attributes, baseMoney, encounterMusic, trainers, items }`,
  with one entry per named trainer of the class. The registry writes one level
  in, into `data.gen2Trainers.classes`, so the call shape is unchanged.
- **`icons`.** Two id forms in one registry, routed by the `ICON_` prefix a
  sheet name carries: a species id names an assignment (a string, the sheet's
  name), an `ICON_*` id names a sheet.
- **`palettes`, `battle_anims`, `constants`.** The id is a subtable of the
  target: `pokemon` / `trainers` / `bg` / `objects` / `roofs` for palettes,
  `scripts` / `moves` / `objects` / `framesets` / `oamsets` / `gfx` for
  battle_anims, and one of Gold's 42 ordered ROM name lists (plus `mapGroups`,
  `trainerClassMembers`, `types`) for constants. Those lists are ordered and
  position *is* the id a script byte resolves through, so they replace rather
  than append.

Four more id-space notes, because the records at those paths came out of a
Gen 2 ROM:

- Gold's `text` ids are ROM pointer strings such as `"55:4067"`, not the
  `TEXT_*` names Red uses. `override` them by pointer; there is no name table.
- A Gen 2 tileset carries its walkability as `collision` where Gen 1 says
  `walkable`. Both fields validate; only `collision` is read on Gold.
- A Gen 2 warp row carries `destGroup` / `destMapNum` beside the `destMap` /
  `destWarp` pair Gen 1 also has. Both are optional in the shared schema, so a
  Gen 1 warp row and a Gen 2 one both validate, and patching one of Gold's own
  maps does not mean restating the ROM's map-group numbers.
- Gold writes `"burn"` / `"sleep"` into `mon.status` where Red writes `BRN` /
  `SLP`. The `statuses` registry is the same registry; only the ids differ, and
  they have to.

**`mod.commands`.** Works on Gold. `src/script/gen2/Vm.lua` runs the cart's own
bytecode, so there is no opcode byte to hand a mod -- the seam is a row the
cart cannot write. `Opcodes.MOD_COMMAND` (`"modcommand"`) is an op *name* with
no byte behind it, and the VM dispatches it through the same merged
`data.commands` table Gen 1's runner resolves by name. Two row shapes reach it:

```lua
{ op = "modcommand", verb = "mymod:shake", args = { 4, 2 } }   -- native
{ "mymod:shake", 4, 2 }                                        -- Gen 1 row
```

The second is the Gen 1 row shape verbatim, so one row list can serve both
games as long as every row in it is the mod's own verb. The handler is called
`fn(ctx, unpack(args))` with `ctx.vm` where Gen 1 has `ctx.runner`; it may
block on `ctx.vm:showText` / `:waitFrames`, and its return value speaks Gen 1's
control vocabulary (`"end"`, a row number, or nil). A missing or raising verb
is warned once per name and the rest of the list still runs. The engine's own
Gen 1 verbs are **not** seeded on Gold: a row-list verb handed Gold's ctx would
find no runner on it, so `data.commands` under Gen 2 is the mod verbs alone.

**`mod.save`, `mod.options`, `mod.log`, `mod.assets`, `mod.find`,
`mod.developer`, exports.** Generation-agnostic; nothing to adapt.
`mod.developer` is the same fixed boot-time boolean on both generations and is
available while the entry chunk runs. Gold does not gain Gen 1's developer
console or F5 hot-reload hotkey; the field reports the loader's mode only.

**`mod.world`.** Same method set, resolved against Gold's world
(`src/world/gen2/WorldAPI.lua`). Two differences show through and are
documented on the module: Gold's world is not a stack state, and Gen 2 event
flags are numeric ids into `wEventFlags` rather than string keys.
`mapOverview` returns the same read-only terrain, tile-shading, and marker
shape, using Gold's live object masks and event flags to omit collected items.
`spawnNpc` / `removeNpc` append onto the map def's own object list, the way the
Gen 1 arm does, so a spawned actor is pooled, drawn, walked and talked to like
an extracted one and survives a map reload; it is not serialized, so a mod
respawns on `map.entered`. `queueScript` takes a small allowlist of verbs Gold
has its own entry points for (`start_battle "wild" species level`, `warp`,
`text`, `setflag`, `clearflag`) and refuses a list containing anything else
**by name, before the first row runs**, so a mod never gets a half-run queue.
`marchInPlace` still has no Gen 2 equivalent (the Gen 2 movement stream has no
byte for it) and returns `nil, reason` rather than approximating one.
`availableFieldActions` and `useFieldAction` expose the same contextual field
item and move records in both games. Gold extends the shared ids with its own
`headbutt`, `whirlpool`, `waterfall`, `sweet_scent`, and `squirtbottle`
actions. Each engine keeps ownership of its inventory, badges, terrain,
surfing, bike, fishing, and field-move rules.

**Hooks and events that fire on Gold.** Every name below is the Gen 1 name
carrying the Gen 1 payload keys, because Gold's call sites reuse them rather
than defining a parallel vocabulary; where Gen 2 carries more, the payload
gains a field instead of the name gaining a prefix.

- *Engine-wide, from the shared modules:* `game.ready`, `screen.pushed`,
  `screen.popped`, `screen.render_visible`, `music.started`, `music.stopped`,
  `music.select`, `music.volume`, `sound.played`, `zoom.range`,
  `assets.transformed`, `mods.loaded`, `mod.options_changed`.
- *Overworld (`src/world/gen2/`):* `map.entered`, `map.exited`,
  `map.reloaded`, `player.warped`, `world.stepped`, `world.interacted`,
  `world.npc_spawned`, `world.trainer_engaged`, `world.blacked_out`,
  `world.block_replaced`, `world.boulder_moved`, `world.tod_changed`,
  `world.object_toggled`, `flag.changed`; hooks `warp.destination`,
  `movement.collision`, `movement.speed`, `encounter.roll`,
  `encounter.species`, `encounter.fishing`, `world.tod`, `map.palette`,
  `fieldmove.eligibility`. `flag.changed` carries the numeric `wEventFlags`
  id under Gen 1's `name` key, which is the one payload difference the
  numeric flag space forces.
- *Menus (`src/ui/gen2/`):* `ui.start_menu.items`, `ui.title_menu.items`,
  `ui.options.rows`, `ui.party.submenu`, `ui.party.grid_navigation`,
  `ui.naming.grid`, `ui.pc.items`, `ui.list_menu`, `transition.style`.
  `ui.list_menu` covers Gold's script
  menus (`ScriptMenu.lua`); the `Chrome.List` widget the START and title
  menus draw with does not raise it yet, so those two are composed through
  their own hooks only.
- *The Oak speech (`src/ui/gen2/OakSpeech.lua`):* `intro.oak_speech.started`,
  `intro.oak_speech.step`, `intro.oak_speech.answered`,
  `intro.oak_speech.finished`, and the `intro.oak_speech.build` hook. Gold has
  a real Oak speech, so it is the same extension point rather than a second
  one: same names, same payload keys, same moments in the sequence. The beats
  are a data table with the same step vocabulary (`say` / `pic` / `name` /
  `choice` / `yesno` / `shrink` / `fn`, plus Gold's own `initclock` and
  `demo`), and the step *ids* match Gen 1's wherever the moment is the same --
  `oak_welcome`, `demo_mon`, `world_spiel`, `ask_player_name`, `name_player`,
  `legend`, `shrink` -- so `ModUI.insertStepBefore(steps, "name_player", ...)`
  lands in the right place in both games. The two ids with no Gen 1
  counterpart are Gold's own beats, `init_clock` (the `farcall InitClock` the
  speech opens with) and `oak_study` (the return to Oak for `_OakText5`). Gold
  has no rival-naming or name-confirmation beats, so it raises no anchors for
  them: the rival is named by `CopScript` in `maps/ElmsLab.asm`, hours later.
- *Battle (`src/battle/gen2/`):* `battle.started`, `battle.ended`,
  `battle.turn_started`, `battle.turn_ended`, `battle.move_used`,
  `battle.damage_dealt`, `battle.fainted`, `battle.status_inflicted`,
  `battle.battler_switched`, `battle.ball_thrown`, `battle.exp_gained`,
  `pokemon.level_up`, `pokemon.move_learned`; hooks `battle.damage`,
  `battle.crit`, `battle.accuracy`, `battle.charge_required`,
  `battle.turn_order`,
  `battle.enemy_action`, `battle.run`, `battle.exp_award`, `exp.gain`,
  `catch.rate`, `trainer.party`, `battle.overlay`, `battle.low_health_alarm`,
  `battle.catch_exp`, `battle.bottom_ui_visible`,
  `battle.status_hud_visible` and `battle.move_grid_navigation`. One payload
  difference: Gen 1's vanilla
  `battle.low_health_alarm` link reads `ctx.battle.data`, and Gold's battle
  screen has no `.data` field, so the Gen 2 site **adds** `ctx.data` beside the
  Gen 1 keys. A mod that calls `nextFn` is unaffected; one that reaches through
  `ctx.battle.data` instead gets nil on Gold.
  `battle.exp_award`'s `ctx.applyShare(mon, split, announce)` reads its third
  argument on both generations: truthy prints the mon's GainedText, falsy pays
  it silently, so one mod source can print a single summary line for a
  party-wide award instead of a box per recipient. Gold honours it **only when
  it is passed**, by argument count -- `applyShare(mon, split)` was written
  against a seam that always announced on Gold and keeps announcing there,
  while `applyShare(mon, split, nil)` is silent on both. Pass the argument
  explicitly and the two generations agree; omit it and Gen 1 stays silent
  where Gold speaks. Only the line is affected: the exp, the stat exp,
  `battle.exp_gained`, the level-up line, learned moves and the forget prompt
  happen either way.
- *The catch and the evolution:* `pokemon.caught`, `pokemon.evolved`; hook
  `evolution.check`. `src/ui/gen2/BattleState.lua:pushCaught` emits
  `pokemon.caught` once the mon is in the party or the box, and
  `src/core/gen2/Evolution.lua` emits `pokemon.evolved` from `apply` and wraps
  each row's decision in `evolution.check`. The hook passes `data` where Gen 1
  passes `game`; positions 2-4 (mon, row, trigger) match.
- *The frame (`src/core/Game2.lua`):* hooks `input.step`, `input.pointer`,
  `render.zones`, `render.compose`, `render.output_enabled`, `render.output`,
  `render.letterbox`, `render.hud`, `render.viewport`, `render.window`. Each sits
  at the same moment `src/core/Game.lua` and `src/render/Renderer.lua` raise it
  -- the logic tick before the pad is read, a pointer the touch overlay gets
  first refusal on, the palette zone list handed to the present pass, the
  composed frame before ShaderFX, the letterbox, and the finished playfield rect
  -- and carries the same payload.
  `render.hud`'s `gameX` / `gameY` really is where Gold's dialogue boxes and
  menus land, because `Chrome.fitScale` / `fitOrigin` and `World:fitScale`
  compute the same number. `render.zones` is handed `nil` in GBC mode (Gold
  computes no zone of its own there) and the engine's own one-rect list in
  CLASSIC mode; a rect that clamps to nothing is skipped rather than throwing,
  which is what `src/render/Renderer.lua:scissorClamped` does on the Gen 1 side.
- *Sprites (`src/pokemon/Sprites.lua`, shared):* `pokemon.sprite`,
  `pokemon.icon` and `player.sprite`. `pokemon.icon` is reached from
  `src/ui/gen2/PartyMenu.lua` through the shared module, so it is one call site
  serving both games. `player.sprite` is raised by `Sprites.playerPic`, which
  Gold's battle back pic (`src/ui/gen2/BattleState.lua`), Hall of Fame and
  intro call with an already-resolved path: Gold's trainer art is not in
  `field.playerPics`, so the path is found first and the hook raised over it,
  with the Gen 1 `ctx` keys (`side`, `kind`, `demo`, `battle`, `data`)
  unchanged. The Gen 2 trainer card is the one player-art read still outside
  it: its portrait is a tile sheet that also carries the frame tiles, not a
  swappable pic.
  `pokemon.sprite` has a second site of its own in
  `src/ui/gen2/BattleState.lua`, which adds `letter` (Unown) and `shiny` to the
  Gen 1 ctx keys -- both concepts Red does not have.
- *Save and the script VM:* `save.created`, `save.loaded`, `save.loading`,
  `save.writing`; hooks `save.write`, `save.new_game`, `script.command`, and
  the `script.started` / `script.ended` pair off `src/script/gen2/Vm.lua`.
  `script.command` reports a mod's own row under the name `"modcommand"` with
  the row's real operands, and may rewrite them, on the same path it wraps a
  cart row.

## New in Gen 2

These have no Gen 1 analogue -- Red has no friendship byte, no day care egg,
no Pokegear, no radio, no held items -- so they are the only places a new name
is justified. They are **live**, guarded by `Runtime.wants` /
`Runtime.wantsHook`, and each is driven through a real bus by
`tests/engine/gen2_new_seams.lua`.

### Events

| event | raised from | payload |
| --- | --- | --- |
| `happiness.changed` | `Happiness` (`ChangeHappiness`, `StepHappiness`) | `mon`, `event`, `reason` (`"event"` / `"step"`), `delta`, `from`, `to` |
| `breeding.egg_created` | `Breeding` (`DayCare_InitBreeding`) | `egg`, `mother`, `father`, `compatibility`, `stepsToEgg` |
| `egg.hatched` | `Breeding` | `mon`, `egg`, `slot`, `species`, `nickname` |
| `phone.call_received` | `PhoneRing.script` | `call`, `contact`, `name`, `className`, `special`, `scriptKey` |
| `clock.day_changed` | `Clock` | `day`, `previous`, `reason` |
| `pokerus.infected` | `Pokerus` | `party`, `slot`, `mon`, `strain`, `days`, `source` |
| `roamer.moved` | `Roamers` | `index`, `slot`, `species`, `from`, `to`, `reason` |
| `roamer.encountered` | `Roamers` | `index`, `slot`, `species`, `level`, `mapId` |
| `apricorn.converted` | `Apricorns` (Kurt) | `apricorn`, `ball`, `event` |
| `bug_contest.scored` | `BugContest` | `mon`, `score`, `place`, `results` |
| `unown.unlocked` | `Unown` (`UpdateUnownDex`) | `letter`, `name`, `word`, `count` |
| `radio.channel` | `MapRadio` | `station`, `channel`, `name`, `source` |
| `mail.written` | `Mail` | `entry`, `slot`, `mon`, `message`, `author`, `source` |
| `mail.read` | `Mail` | `entry`, `message`, `author`, `top`, `bottom` |
| `intro.boot.copyright` | `CopyrightSplash:enter` | `screen`, `game` |
| `intro.boot.gamefreak` | `GameFreakPresents:enter` | `screen`, `game` |
| `intro.boot.movie` | `GoldSilverIntro:enter` | `screen`, `game` |
| `intro.boot.movie_ended` | `GoldSilverIntro:finish` | `screen`, `game`, `skipped`, `frames` |
| `intro.boot.title` | `TitleState:enter` | `screen`, `game` |

The four `intro.boot.*` cards are the GS boot cinema, and they are the one part
of Gold's intro with no Gen 1 moment to share a name with: Red boots into
`IntroMovie` with no copyright card, no GAME FREAK splash and no attract movie.
The Oak speech immediately after them is the opposite case and reuses
`intro.oak_speech.*` verbatim (see the shared table above).

Each card raises its name the frame it comes up, because that is the moment a
mod can act on. Only the movie has an `_ended` name, and only because it
carries a fact nothing downstream does -- `skipped` is the difference between a
player who watched all 2335 frames and one who pressed START. The other three
cards chain straight into the next card, whose own event is their end.

`delta` on `happiness.changed` is `to - from`, not the table's column, because
the 0 and $ff carry clamps are part of what the cart applied: a mon at 254
gaining "5" gained 1.

`clock.day_changed` compares against a process-local latch, so the first read
after a boot has nothing to compare against and raises nothing. That is by
design; it is a day *change*, not a day report.

`unown.unlocked` is raised from `UpdateUnownDex` -- a form first entering the
`#DEX` list -- not from the four `ENGINE_UNLOCKED_UNOWNS_*` puzzle flags. Those
flags are written by the cart's own `setflag`, so there is no Lua transition at
the puzzle solve to hang a second event on yet.

`mail.read` rides `Mail.lines` with a per-struct latch, because the read page
redraws every frame. The latch is re-armed by `Mail.get` / `Mail.mailbox`,
which is how both readers pick the letter they are about to open, so reopening
the same letter raises a second event.

### Hooks

| hook | wraps | ctx | vanilla answer |
| --- | --- | --- | --- |
| `held_item.trigger` | `Battle:heldEffect` | `battle`, `mon`, `item`, `def`, `effect`, `parameter`, `trigger` | `ctx.effect, ctx.parameter` |
| `breeding.compatibility` | `Breeding.compatibility` | `data`, `mon1`, `mon2`, `dayCare` | the vanilla byte |
| `phone.contact_list` | `Phone`'s `wPhoneList` read | called `(save, list)`, the shape the other list hooks use | the same list |
| `shiny.roll` | `Mon` | `dvs`, `species`, `def`, `level` | the DV-derived boolean |
| `gender.roll` | `Mon` | `def`, `dvs`, `ratio`, `species`, `level` | the DV-derived gender |

`held_item.trigger` is one hook over eight call sites, because on the cart
those eight *are* one routine (`GetUserItem` / `GetOpponentItem` loading b and
c, and the caller comparing b against the `HELD_*` it cares about). `trigger`
says which comparison is about to happen: `"priority"` (Quick Claw),
`"damage"` (Scope Lens and the type-boost family), `"endure"` (Focus Band),
`"flinch"` (King's Rock), `"accuracy"` (BrightPowder), `"confuse"`,
`"residual"` (the end-of-turn Leftovers / Berry / cure arm), and `"check"` for
any other read. Return nil to make the item do nothing at that trigger, or
another `HELD_*` name to substitute one -- every call site compares against a
name, so substitution is the whole mechanism.

`held_item.trigger` wraps the *read*, so a mod can suppress or substitute an
effect from any item. Defining a **new** held item is the `held_items`
registry's job, and the two compose: register the row, then steer it from the
hook.

`phone.contact_list` refuses an answer of the wrong length or with an unknown
contact id (unknown ids blank to 0 on purpose, so the Pokegear never indexes a
nil). It reorders and blanks the ten save slots; registering a contact id the
game does not know is `phone_contacts`' job.

`shiny.roll` does not override a forced-shiny battle (`opts.shiny`), which is
how the cart's own scripted shiny Gyarados stays shiny.

## Registries with no Gen 2 home

Writing to one of these while Gold is running takes the write, drops it, and
reports it once per mod into the same error feed the manager shows. It is not
fatal: a mod that supports both generations registers its Gen 1 content
unconditionally and still loads the half that applies. The report is worded
from the boot's own generation, because the gating runs both ways.

`rulesets`, `transitions`, `field`, `text_pointers`, `link_fields`,
`map_scripts`.

`Schemas.GEN2` in `src/mods/Schemas.lua` is the authoritative table, and
`tests/engine/gate_gen2_mod_api.lua` holds it to the catalog.

The list used to have three causes behind it and now has one. "No Data path
exists" closed when the overworld tables stopped loading off disk into World
fields. "The shape differs" closed when a registry gained the option of
carrying a Gen 2 record schema beside its Gen 1 one. What is left is one cause:

**Gold reimplements the system without reading a registry.** The Gen 1 target
is still built and merged into, but nothing in a Gold boot ever looks at it, so
routing the registry would be a merge into a table with no reader -- exactly
the silent no-op the gate exists to prevent. Closing one of these is a consumer
change in the Gen 2 module first and a routing row second:

- `rulesets`: no Gen 2 ruleset dispatch exists.
- `transitions`: Gold draws its own battle intro
  (`src/ui/gen2/BattleTransition.lua`), and its `STYLES` is a boolean *set* of
  the four cart wipes (`spin`, `speckle`, `zoom`, `sine`) rather than the
  `{ frames, draw, sound, flash }` record this registry carries. There is no
  styleDef lookup for a registered id to reach, so a mod style would fail the
  `STYLES` membership test and fall back to vanilla -- routing it would be the
  silent no-op, not the fix.
- `field`: the Gen 1 overworld's data grab bag. Gold's equivalents live in
  `data.gen2Maps` and the VM's own tables.
- `text_pointers`: Gen 1's `TEXT_*` indirection. Gold's text *is* pointers.
- `link_fields`: link play is Gen 1 only.
- `map_scripts`: `data.gen2Scripts` is the cart's bytecode pool keyed by ROM
  pointer, and a Lua row list merged into it is not something
  `src/script/gen2/Vm.lua` can run. Routing it needs a Gen 2 side dispatcher in
  `World`, not just the verb table `mod.commands` already has. The
  `script.started` / `script.ended` / `script.command` seams do fire, so a mod
  observes and can veto a script it cannot yet author whole.

Four of this list closed after it was written, and how they closed is the
pattern for the rest:

- **`growth_rates`** now routes to the SHARED Gen 1 target. Gold's curves are
  coefficient rows in the extracted `pokemon.lua`, so `src/mods/Builtins.lua`'s
  Gen 2 registrant wraps each as the `{ expForLevel }` record Gen 1's registry
  uses, and `src/battle/gen2/Mon.lua:growthFor` is the one accessor all six
  readers go through (`Mon` twice, `BattleState`, `SummaryMenu`, `Breeding`,
  `ItemEffects`). One record shape, one id space, one mod source for both
  games. Because it is routed, the `pokemon` schema's `growthRate` reference is
  now checked rather than skipped, and it resolves: both sides say
  `GROWTH_MEDIUM_SLOW`.
- **`tokens`** was on the list by mistake rather than by cause. `TextBox.new`
  runs `TextBox.substitute` on every box in both generations and `substitute`
  reads `game.data.tokens`, so the shared target was live on Gold the whole
  time. A `{NAME}` a mod registers expands in the world, the menus and the VM's
  pages alike.
- **`battle_sprite_scales`** closed consumer-first, the `growth_rates` way:
  `src/ui/gen2/BattleState.lua` grew `imageScale` / `picScale`, a faithful
  mirror of Gen 1's `BattleState.imageBattleScale` / `resolveBattleScale` down
  to skipping `_owners` and the image-then-species-then-default order, so the
  registry now routes to the SHARED Gen 1 path and one record serves both
  games. Only the default is generation-specific, and neither side reads that
  from the registry.
- **`render_pipelines`** closed because the reader moved, not the registry:
  `src/core/Game2.lua:load` installs `src/render/Pipelines.lua` on Gold's
  merged dataset after `mods:load` and `Game2:draw` composites `present`. The
  `drawWorld` half is still inert, which is why this one is worth reading the
  caveat above for -- it is routed on the strength of the half that works, and
  Gold retires a drawWorld-only level rather than pretending.

## Hooks and events Gold does not raise yet

Gold has its own draw path, intro, evolution and sprite lookups, so the call
sites in those Gen 1 modules are not on Gold's path. The names are not taken
and not reserved for Gen 1: when a Gen 2 call site lands it uses the existing
name and the existing payload, plus fields where Gen 2 genuinely carries more
(the split special stats, held items on a trainer roster).

The list is much shorter than it was. What is outstanding, in descending value:

- `battle.field_residual`: the first guarded call site is in Gen 1 end-of-round
  processing. Gold already has a native weather/between-turn pipeline but does
  not yet expose the shared data-only descriptor hook.
- `trainer.before_battle`: Gold constructs and pushes its trainer battle in
  `src/world/gen2/World.lua:startBattle`, which does not yet expose a deferred
  preparation boundary or a battle-local player-party view. Gen 1 mods can use
  the hook documented in `docs/modding.md`; do not claim Gold compatibility
  when that selection is required.
- `pokemon.before_give` / `pokemon.received`: Gold has no give-mon seam of its
  own yet.
- `link.*` and `trade.completed`: a Gold boot offers no link menu at all. The
  Gen 2 fingerprint and handshake exist (`src/link/Fingerprint.lua` hashes a
  Gen 2 surface and a cross-generation pairing is refused by name), but nothing
  in `src/ui/gen2/` opens onto the protocol, so these raise nowhere.

Four groups that used to sit here have since landed and moved to the shared
table above: the frame seams (`render.compose` / `render.hud` /
`render.letterbox` / `render.zones`, `input.step` / `input.pointer`), the three
battle seams (`battle.overlay`, `battle.low_health_alarm`,
`battle.catch_exp`), the two sprite lookups (`pokemon.sprite`,
`pokemon.icon`), and the catch/evolution trio (`pokemon.caught`,
`pokemon.evolved`, `evolution.check` -- `src/ui/gen2/BattleState.lua` emits
`pokemon.caught` from `pushCaught` once the mon is in the party or the box, and
`src/core/gen2/Evolution.lua` emits `pokemon.evolved` from `apply` and wraps
each row's decision in `evolution.check`).

Three partial coverages worth knowing about, because "the hook exists" is not
the same as "the hook sees everything":

- `encounter.roll` / `encounter.species` are wired into the grass/water step,
  `randomwildmon`, the Bug Contest and SWEET SCENT, but **not** into
  `World:tryHeadbutt`, `World:rockMonEncounter` or `Roamers.checkEncounter`.
  Those three read row shapes that are not `{ species, level }` slot lists, so
  a mod that reskins encounters misses headbutt trees, rock smash and the
  roamers.
- `src/ui/gen2/BattleState.lua` builds a flat `opts` for `Catching.attempt`
  with no `data` in it, so a mod-registered ball is readable through
  `Catching.recordFor` but is not yet resolved at the real throw site.
- Three Gold UI files carry their own copy of the status HUD labels the merged
  `statuses` records now hold as `hudLabel`, so a mod status shows no label in
  the battle HUD, the party menu or the summary page until they read
  `Battle.statusRecordFor(data, status).hudLabel`. The values are identical
  today, so nothing vanilla is affected.

## Gen 2 tables with no registry

`Game2:load` assigns 24 `data.gen2*` tables and 12 of them are registry-backed,
so twelve sit in `game.data` on a Gold boot with no registry pointing at them:
`gen2Marts`, `gen2Roofs`, `gen2StdScripts`, `gen2EventTables` (the phone book,
in-game trades, elevator labels, decoration descriptions), `gen2InitialEvents`,
`gen2Pokedex`, `gen2MenuGfx`, `gen2Intro`, `gen2Credits`, `gen2Diploma`,
`gen2Trade`, and `gen2Scripts` (which the `map_scripts` registry does reach, so
it is the one of the twelve that is not out of reach). Naming registries for the
rest is new API surface rather than a routing change, so it is deliberately not
done yet.

## Testing a Gen 2 mod

Static first. `gen2check` reads the manifest, scans every `.lua` the package
carries and cross-references what it finds against the coverage table above:

```sh
python3 tools/modkit.py gen2check my_mod            # or a path
python3 tools/modkit.py gen2check my_mod --notes    # + the caveat on each backed member
```

It reports one of `will load`, `will load but degrade` or `will not work`, with
a `MK4xx` finding per site and an `unresolved:` note, carrying a file and a
line, for every reach a static scan could not follow. Exit 0 clean, 1 on a
fatal finding (or any finding under `--strict`), 2 on usage; `--json` emits the
whole batch as one document, and `--quiet` prints the findings alone, so a
clean mod prints nothing and the exit code is the answer. The rule ladder is
`MK400`-`MK410` and is listed in `tools/modkit.py`'s section header.

Then the headless harness, which takes the generation without booting Gold:

```lua
local run = T.sdk.loadMod("mods/my_mod", { generation = 2 })
T.eq(run.mod and run.mod.state, "loaded",
  "runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))
T.eq(#run.errors, 0, "and loads with no boot errors")
```

Everything else is the production path: same loader, same validate, same
topological sort, same merge. Assert the state as well as the error count: a
gate skip is deliberately not an error, so `#run.errors == 0` passes for a mod
that never ran a line.

Neither substitutes for a real Gold boot, and the two output channels there are
not the same. The adapter's own warnings (`Gen2Compat.warnOnce`) go to the log
only, each attributed to the mod holding the facade. The boot error feed the
manager shows is `loader.errors`: a failed mod, a duplicate id, a registry with
no Gen 2 target, a cross-validation problem, and a require for a Gen 1 module
the adapter does not serve. A skipped mod and a degraded member are on neither
list, by design.
