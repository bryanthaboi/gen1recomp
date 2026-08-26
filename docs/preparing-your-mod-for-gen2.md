# Preparing your mod for Gen 2 (Gold)

You have a mod that works on Red, Blue or Yellow, and you want it to work on
Gold. This is the migration guide: what breaks, what the engine papers over
for you, what it refuses to paper over, and the order to do the work in.

`docs/mod-api-gen2-compat.md` is the reference for *what Gold serves*. This
document is the procedure for *getting your mod there*. Read that one when you
need to know whether a registry or a hook exists; read this one first.

## What actually breaks, and why

Gold is not a skin over the Gen 1 engine. It is a second engine living beside
the first one: `src/core/Game2.lua` owns the boot, `src/world/gen2/World.lua`
is the overworld, `src/battle/gen2/Battle.lua` is the battle, and
`src/script/gen2/Vm.lua` runs the cart's own bytecode instead of a Lua row
list. A Gold boot never loads `src/core/Game.lua`,
`src/world/OverworldController.lua` or `src/battle/BattleState.lua` at all.
The mod API on top is deliberately one API -- the same registry names, the
same hook names, the same event names, the same `mod.*` facade -- so a mod
that stays on that surface mostly moves across unchanged. What does not move
is everything underneath it.

The failure that motivated all of this is quiet, which is what makes it worth
a whole document. A mod with `engine_internals` writes
`local Game = require("src.core.Game")` and patches a method on it. Under Gold
that require used to succeed: the file is on disk, `require` finds it, hands
back a perfectly good module table, and your patch lands on it. Nothing ever
instantiates that table, so the patch runs zero times and the only symptom is
that your mod does nothing. No error, no warning, no crash to bisect. Two
things fixed that. First, a mod is not loaded on a Gold boot unless it says it
is for Gold, so the default outcome is "not running" rather than "running
wrong". Second, when it does say so, a require made from your own file is
answered by an adapter (`src/mods/Gen2Compat.lua`) that presents the Gen 1 API
over Gold's internals, and a member the adapter cannot honestly back reads nil
instead of reading plausibly-wrong.

## Step 1: run the checker before you change anything

`modkit gen2check` reads your manifest, statically scans every `.lua` the
package carries, and cross-references what it finds against the adapter's own
coverage table. Run it first, because it tells you the size of the job in a
few seconds.

```sh
python3 tools/modkit.py gen2check <id-or-path> [<id-or-path>...]
```

Real output, against a follower mod written for Yellow:

```
-- PokePCFollowers_VoxelMerge: api 1, profile content, no games declared, permissions engine_internals, 0 dependencies, game_version unset
MK400 ERROR manifest.json: no Gen 2 game in "games" (and no gen2compat), so a Gen 2 boot skips this mod; the rest of this report is what it would hit once it claims one
MK404 ERROR main.lua:575: BattleState.newWild has no Gen 2 backing: Gold has no factory that returns an unpushed battle, and World:startBattle constructs and pushes in one call. A mod that wraps newWild to rewrite the species must be pointed at the encounter.species hook, which Gold raises with the same name and shape (World:rollEncounter); this reads nil
MK404 ERROR main.lua:576: BattleState.newWild has no Gen 2 backing: ... ; nothing on a Gen 2 boot reads this write
MK409 WARN  main.lua:13: allow-lists a Gen 1 version string, which excludes this mod from a Gen 2 game by construction; test for the capability the code needs instead of the version
MK409 WARN  main.lua:424: ... (same, a second allow-list)
MK409 WARN  main.lua:565: ... (and a third)
modkit: unresolved: 1 site: requires whose result is neither bound to a name nor indexed here, so where the module goes is not followed (main.lua:221)
modkit: unresolved: 5 debug upvalue calls whose target function this scan could not tie to an engine module, so the local they reach could not be resolved (main.lua:279, main.lua:285, main.lua:288, main.lua:321 and 1 more)
modkit: src.world.PikachuFollower.onMapEntered closes over 'shouldSpawn' on a Gen 2 boot, so the upvalue surgery at main.lua:325 lands as it does on Gen 1
FAIL PokePCFollowers_VoxelMerge on gen 2: will not work (3 errors, 3 warnings)
```

Three kinds of line, and the difference matters:

- **`MK4xx ERROR` / `MK4xx WARN`** are findings with a file and a line. Errors
  set the exit code; warnings do not unless you pass `--strict`.
- **`modkit:` notes** are things the tool derived rather than found, or could
  not decide at all. They never change the exit code. The `shouldSpawn` note
  above is the tool resolving that member through the adapter on a Gen 2 boot,
  enumerating the function's real upvalues, and confirming the surgery lands;
  the `unresolved:` notes are the tool naming, with file and line, every reach
  it saw and could not follow.
- **The verdict**: `will load`, `will load but degrade`, or `will not work`.

The rule ladder:

| rule | what it means |
| --- | --- |
| `MK400` | the manifest claims no Gen 2 game, so a Gen 2 boot skips the mod |
| `MK401` | a dependency claims no Gen 2 game, which takes you down with it |
| `MK402` | you require a Gen 1-only module the adapter does not serve |
| `MK403` | a Gen 2 boot runs a `gen2/` sibling of the module instead |
| `MK404` | a member you touch has no Gen 2 backing (the adapter's own reason is quoted) |
| `MK405` | a member you touch degrades and says so once |
| `MK406` | the signature moved under an alias |
| `MK407` | `debug` upvalue surgery the Gen 2 arm cannot take: the member is not a function there, or the function does not close over that local |
| `MK408` | upvalue surgery the scan could not resolve either way |
| `MK409` | a version allow-list, or a Gen 1 screen id |
| `MK410` | the entry chunk reads a member of a game that is not up yet |

Flags: `--strict` promotes warnings to failures, `--notes` prints the adapter's
note for every *backed* member you touch (worth reading once per mod, because
several backed members are backed with a caveat), `--json` emits one document
for the whole batch, `--quiet` drops everything except the findings -- no
header, no notes, no verdict line, so a clean mod prints nothing at all and the
exit code is the whole answer. Exit code is 0 clean, 1 on a fatal finding, 2 on
usage.

Name several mods in one invocation and they are read as one install set, so a
mod and its dependencies can answer each other's `MK401`.

**What the checker cannot see, and now says so.** It is a static scan, not a
run. It follows more than it used to -- a require made through your own
`tryRequire`-style wrapper, `local ok, M = pcall(require, "...")`, an inline
`require("src.world.Map").waterTiles(...)`, a bracket index `M["member"]`, a
local hop `local F = M` -- so reaches that used to be invisible now produce
real findings, and a mod that passed before can fail now.

Two places where it used to answer confidently and wrongly now do not.
`local A, B = require("src.world.Map")` is read as binding `A`, which is what
Lua does; it used to take the name nearest the `=` and pin the module on `B`,
so every reach off `A` went unchecked and every reach off `B` was checked
against a module that was never there. And a helper of your own is only read as
upvalue surgery when the scan can see it forward its own `(function, name)`
pair into the `debug` call; a helper that merely mentions `upvalue`, or that
finds the slot by walking `debug.getupvalue`, no longer has its call sites
read as naming an engine local, because they do not.

What it still cannot follow it names instead of ignoring. Every unfollowed
reach comes back as an `unresolved:` note carrying a file and a line. The scan
side raises one for:

- a require name built at runtime, whether handed in whole or concatenated
  (`require("src.world." .. name)` is as unfollowable as `require(name)`);
- an engine module name handed to a call the scan does not follow;
- an engine module name spelled in a literal with no require attached;
- a require whose result is neither bound to a name nor indexed on the spot;
- a require in a multiple assignment whose value it cannot pair to a name;
- a name bound to a *member* of a module rather than the module;
- an engine module indexed with a computed key;
- `rawget` or `rawset` on a bound module: that goes straight to the table the
  require shim hands back, so on a Gen 2 boot it reads or writes the
  Gen2Compat facade and not the module behind it;
- an engine module read as a value rather than indexed, so where it goes from
  there (a table field, a call argument, a metatable's `__index`) is not
  followed;
- a `debug` upvalue call whose target function could not be tied to a module;
- a call through one of your own upvalue helpers that the scan could not
  confirm carries an upvalue name through to the `debug` call.

Four more come from the coverage side rather than the scan: a dependency that
is not installed beside your mod, a required name that is neither an adapter
nor a module in this checkout, a module with no coverage row at all, and a Gen
1 member the coverage table does not classify.

The practical consequence is worth stating plainly: an empty finding list
*plus* no `unresolved:` notes now means the scan followed everything it saw,
and an empty finding list on its own does not.

It is still silent on any member the adapter's coverage table does not record:
the table lists 481 members across the 15 served modules, which is a large
majority of what real mods touch and is not the whole Gen 1 API. A clean
`gen2check` means "nothing known-broken was found", not "this works". Boot it.

## Step 2: declare which games the mod is for

Nothing moves on disk. A mod is installed once, into `mods/<id>/`, and that one
directory serves every game. There is no `mods/gen1/`, no `mods/gen2/`, and no
per-generation copy: targeting is something the manifest *declares*, not
something the filesystem encodes.

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

`games` is an optional array. Each entry is one of:

| token | means |
| --- | --- |
| `"red"`, `"blue"`, `"yellow"`, `"gold"`, `"silver"`, `"crystal"` | that one game (a version id from `GameVersion.ORDER`) |
| `"gen1"`, `"gen2"` | every game of that generation (case-insensitive; `"gen 2"` also parses) |
| `"all"` | every game this engine has |

`src/mods/ModTargets.lua` is the one place those tokens are resolved, and it
derives the list from `GameVersion.ORDER` rather than restating it, so a game
added later needs no edit there. The scaffold writes the key for you:

```sh
python3 tools/modkit.py scaffold my_mod --games gen1,gen2
```

**Omitting `games` keeps the old meaning exactly.** No `games` key means Gen 1
only, plus Gen 2 if the legacy `"gen2compat": true` flag is set. Every manifest
written before the key existed means precisely what it always meant.
`gen2compat` is still accepted and is purely additive: it *adds* the Gen 2
games to whatever `games` says, so no manifest can lose a game it already ran
on. `Manifest.validate` (`src/mods/Manifest.lua:210-224`) resolves the two
into one ORDER-sorted `manifest.games` array and derives `manifest.gen2compat`
from it, which is why `"games": ["gen2"]` is honoured by the loader's gate
today with no other change.

An unknown token warns and is dropped under `api` 1 and refuses the manifest
under `api` 2 (the normal `violation()` rule). A `games` array that names no
game this engine knows falls back to the default rather than orphaning the mod.
A non-array `games` is a hard error.

### What you are claiming

Adding a game to `games` is you saying *I have run this there*. It is not a
request for best-effort support and the loader does not treat it as one: a mod
that claims a game is loaded on that boot in full, with its registrations, its
subscriptions and its entry chunk, exactly like a mod written for it. If it is
half-working, the player sees a broken mod, not a partially-supported one. That
is the whole reason the key exists rather than being inferred.

**Every token is enforced, per game.** `Loader:_gateGeneration`
(`src/mods/Loader.lua:447`) gates on `ModTargets.supports(manifest, version,
generation)` -- the same call both mod surfaces make -- so `"games": ["blue"]`
really does not load on Red, and the skip line is the launcher's line, `For
Blue, not Red`. `"games": ["gold"]` alone no longer loads on Red either: it
names one game, and that game is Gold. A manifest with no `games` and no
`gen2compat` still covers every Gen 1 game, so nothing written before the key
existed changes behavior; what changed is that a version-id token is now a
statement the boot keeps rather than a label the UIs draw. If you want a mod
everywhere, say so: `["gen1", "gen2"]` or `["all"]`.

**Dependencies are contagious.** A mod whose hard dependency does not run here
is left out too, carrying the dependency's own wording (`depends on X, which
does not run here (For Blue, not Red)`). It is reported as a skip rather than a
failure and neither mod lands on the boot error list, but the mod does not run.
Every hard dependency in the chain has to cover the same games; `MK401` is the
checker's version of this question for the Gen 2 half of it.

**The player can overrule you, in one direction only.** The in-game mod
manager offers `TRY HERE ANYWAY` on the detail pane for any mod that does not
claim *this* game (`src/mods/ManagerState.lua:386`), which now includes a Gen 1
boot: a Blue-only mod is genuinely skipped on Red, so that row is the only way
to run it there. The choice is **per game**: `options.modsGen2[id]` is a
`{ [version] = true }` table, so forcing a mod onto Red does not force it onto
Gold. A stored legacy `options.modsGen2[id] = true` from before the key was
per-game reads as "the Gen 2 games", which is the only set it could ever have
affected, and it is expanded in place the next time the player answers. A
forced mod loads normally and keeps a note saying its author never verified it
here; the launcher shows it as `Forced onto Gold by you (untested)`. If the
override cannot be persisted the manager says `COULD NOT SAVE` rather than
promising a restart that would change nothing.

### What the player sees

All three surfaces read the same derivation -- the two UIs and the loader --
so they cannot disagree about your mod. The launcher's mod panel carries a
`Show for:` chip row (All games / Red / Gold / ...) and a per-mod tag from
`ModTargets.chip` -- `GEN 1`, `GEN 1+2`, `RED/GOLD`, `BLUE` -- greyed out when
the mod does not run on the selected game, with the line `Not for this game`
(`src/import/LauncherView.lua:320`) and the detail from `ModTargets.detail`,
`For Gen 1, not Gold`. The in-game manager shows the same thing as
`ENABLED (NOT THIS GAME)` with the skipped glyph, plus an inert `FOR GEN 1+2`
row on the detail screen. The launcher's dependency verdict asks the same
question of your dependencies: a mod whose hard dependency does not run on the
selected game reads `Needs <id> (not for Gold)` rather than `Ready`.

### Scoping dependencies per game / generation

For mods targeting multiple generations (`"games": ["gen1", "gen2"]`), a hard
dependency can be scoped to specific games so that it is only enforced when
booting those games:

```json
"dependencies": [
  { "id": "pokegear_cards", "games": ["gen2"], "range": "^1.0.0", "github": "1jamie/pokegear_cards" }
]
```

When booting a Gen 1 game (Red, Blue, Yellow), the engine loader sees that
`pokegear_cards` is scoped to `"gen2"` and will not skip or block the parent mod
on Gen 1. When booting Gen 2 (Gold), `pokegear_cards` is strictly required.

For conditional integrations where the dependency is optional across the board,
`optional_dependencies` remains the standard pattern.

### One limit worth knowing

**Enablement is per game.** The overlay
`options.modsByVersion[version][id]` is read and written through
`SaveData.modEnabled` / `SaveData.setModEnabled` by the launcher, in-game
manager, and loader. Existing shared settings are copied to every game the
first time this version sees the installed mods; from then on, each coloured
game checkbox changes only that game's next boot. Nothing about this affects a
mod author; it affects what a player can express.

Targeting is a different question from enablement and *is* enforced per game,
as above. The two do not share a switch.

## Step 3: prefer the API over the modules

Before doing any adapter work, check whether you need the modules at all. In
new code, take the live game from `mod.game` and the world from `mod.world`.
Both resolve per generation inside the loader (`src/mods/Loader.lua:1021`):
`mod.game` is `src/core/Game.lua`'s singleton under Gen 1 and the `Game2`
*instance* Gold injected under Gen 2, read on every touch rather than cached;
`mod.world` is `src/world/WorldAPI.lua` or `src/world/gen2/WorldAPI.lua` behind
one method set. Neither needs `engine_internals`. The `game.ready` payload and
every `ui.*` hook's first argument carry the same live game.

Anything you can express as a registry write, a hook or an event subscription
is generation-agnostic already and needs nothing from this document. The
adapter exists for the code that was written before Gold did, and for the small
number of things the API genuinely does not reach.

## Step 4: the adapter, module by module

On a Gen 2 boot with mods present, `require` is interposed
(`Loader:_installDevShim`, `src/mods/Loader.lua:184`) and a require *made from
a mod's own chunk* for one of fifteen Gen 1 names is answered by
`src/mods/Gen2Compat.lua`. Engine code is unaffected: the shim compares the
caller's chunk name against the engine tree, so `src/render/PaletteFX.lua`
requiring `src.core.Game` still gets the real Gen 1 module on both generations.
This is not a dev-mode feature; it installs on any Gold boot that has mods.

| the name you require | kind | what you get | backed / warned / absent |
| --- | --- | --- | --- |
| `src.core.Game` | facade | a live proxy onto the `Game2` instance | 70 / 9 / 12 |
| `src.world.OverworldController` | facade | over `src/world/gen2/World.lua` | 56 / 5 / 68 |
| `src.world.Map` | alias | `src/world/gen2/Map.lua` | 28 / 2 / 9 |
| `src.world.NPC` | alias | `src/world/gen2/Npc.lua` | 27 / 0 / 1 |
| `src.pokemon.Boxes` | facade | over `src/core/gen2/Boxes.lua` | 22 / 0 / 0 |
| `src.battle.BattleState` | facade | over `src/ui/gen2/BattleState.lua` | 16 / 2 / 39 |
| `src.ui.PartyMenu` | facade | over `src/ui/gen2/PartyMenu.lua` | 15 / 2 / 16 |
| `src.world.WorldAPI` | alias | `src/world/gen2/WorldAPI.lua` | 15 / 2 / 0 |
| `src.world.PikachuFollower` | alias | `src/world/gen2/Follower.lua` | 10 / 0 / 11 |
| `src.script.ScriptRunner` | facade | over `src/script/gen2/Vm.lua` | 10 / 7 / 1 |
| `src.ui.OptionsMenu` | facade | over `src/ui/gen2/OptionsMenu.lua` | 8 / 0 / 1 |
| `src.world.FieldDefaults` | facade | the `playerSprites` answer and named refusals | 5 / 2 / 3 |
| `src.world.Collision` | facade | `DELTA` / `target` / `occupied` / `canMove` | 4 / 1 / 0 |
| `src.ui.StartMenu` | facade | over `src/ui/gen2/StartMenu.lua` | 4 / 0 / 0 |
| `src.ui.BoxMenu` | alias | `src/ui/gen2/PcMenu.lua` | 1 / 0 / 0 |

**Alias means the adapter *is* the Gen 2 module.** Your monkey-patch, your
`rawset` sentinel and your `==` idempotency check all land on the table Gold
actually runs, and `getmetatable(npc) == NPC` is true. Five names are aliases
because nothing less would work: mods set their own trailer's metatable to
`src.world.NPC`, a mod is handed `world.map` rather than building one, the
loader builds every `mod.world` out of `src.world.WorldAPI` so a copy would
give two, `src.world.PikachuFollower` is reached with `debug.setupvalue` on a
file-local, and `Screens` caches `src.ui.BoxMenu` for `"Gen2PcMenu"` so a
`.new` patch has to land there.

Note that `src.ui.BoxMenu` points at `src/ui/gen2/PcMenu.lua`, not at
`src/ui/gen2/BoxMenu.lua`. Gen 1's `BoxMenu` is Bill's PC *top menu*, whose
Gold counterpart is `PcMenu`; Gold's `BoxMenu` is the withdraw/deposit *list*
that Gen 1 builds inline.

**Facade means a translating wrapper.** `.overworld` resolves `Game2.world`,
`writeOptions` resolves `Game2:persistOptions`, `game.data.sprites` resolves
`data.gen2Sprites`, `NPC.new(data, mapId, objDef)` is sniffed apart from
`NPC.new(mapId, objDef, spriteDef)` and the movement vocabulary is translated
with it. The four UI facades (`PartyMenu`, `StartMenu`, `OptionsMenu`,
`BattleState`) are write-through: reads fall to the Gen 2 class and **writes go
to the Gen 2 class**, so `PartyMenu.update = wrapper` still patches the live
class Gold pushes. Your write also *reads back as your own value* -- after
`PartyMenu.new = wrapper`, `PartyMenu.new` is `wrapper` and nothing else, so
`rawequal` holds and an idempotency check works. That is what makes the ordinary
capture-and-chain idiom safe: a wrapper that calls the value it captured reaches
Gold's real constructor rather than re-entering the facade's own override.
Writing `nil` clears the member instead of re-exposing the override underneath.

The `src.world.OverworldController` facade is a facade over the live `World`,
not over a class, so seven of its fields (`map`, `player`, `npcs`, `entities`,
`ghosts`, `npcPool`, `camera`) read **and write** through to the running world:
Gen 1's module *is* the singleton, so a write has to land somewhere real. A
write made before a world exists is dropped with a warning rather than
shadowing the world it would have applied to.

### backed, warned, absent

The adapter publishes what it covers, and the checker consumes that same table
rather than a copy of it. Exactly three statuses, and a member listed as both
resolves to the weaker one:

- **`backed`** -- present, and it does the Gen 1 job on Gold. Read the note
  anyway where there is one: several backed members are backed with a caveat
  (`Boxes.COUNT` is 14 on Gold and not 12; `BattleState.say` ignores
  `sayAuto`'s delay because Gold's messages always auto-advance;
  `Collision.DELTA` is Gold's live table, so adding a key mutates Gold's own
  movement).
- **`warned`** -- present, answers nil or degrades, and names itself once in
  the log with your mod attributed. `Game.renderer`, `Game.load`,
  `Game.step`, `game.data.field`, `game.data.constants`,
  `ScriptRunner.resume` / `.update` / `.parallel`, `PartyMenu.tmhm` and
  `OverworldController.neighbors` / `.npcByIndex` are here. `neighbors` is the
  shape of the whole category: Gold's rows are `{ id, ox, oy, image }` where
  Gen 1's are `{ map = mapDef, ox, oy }`, so the field warns and answers nil
  rather than handing back a list whose `nb.map` is nil on every row.
- **`absent`** -- deliberately not on the table. It reads nil, which is the
  honest failure. `BattleState.newWild`, `OverworldController.rollEncounter`,
  `Map.warpPadOrHoleAt`, `PikachuFollower.shouldSpawn` and 157 others are
  here. (`shouldSpawn` is absent as a *module member* on both generations: it
  is a file-local, reached through `setShouldSpawn` or the upvalue of that
  name, and the coverage table says so rather than implying a field exists.)

"Absent" means *not served*, not *wrong*. Every one of them was left off for a
stated reason, and the reason is in the coverage note. `BattleState.newWild` is
the clearest case: Gold has no factory that returns an unpushed battle, because
`World:startBattle` constructs and pushes in one call, so a `newWild` taking a
species and a level would be a lie about what Gold's battle screen is. The
route for the thing you were actually doing (rewriting the species of a wild
encounter) is the `encounter.species` hook, which Gold raises under the same
name with the same shape.

A member the table does not record is not a guarantee of anything. What it does
depends on the adapter: an alias hands you the Gen 2 module's own member,
whatever that is; a write-through facade falls to the Gen 2 class; the
`src.core.Game` facade names it in the log and reads nil; the
`src.world.OverworldController` facade reads nil silently. The checker is
silent about it too.

### Reading the coverage yourself

The table is queryable, and it is the same query the checker makes:

```lua
local Gen2Compat = require("src.mods.Gen2Compat")

Gen2Compat.modules()                 -- the 15 served names, sorted
Gen2Compat.serves("src.world.Map")   -- true
Gen2Compat.memberStatus("src.battle.BattleState", "newWild")  -- "absent"

local c = Gen2Compat.coverage("src.world.Map")
-- { module, kind = "facade"|"alias", target, members = { [name] = status },
--   notes = { [name-or-topic] = "one line" } }
```

`Gen2Compat.COVERAGE_VERSION` is 1 and `Gen2Compat.STATUS` carries the three
status strings. `notes` keys are documentation topics, not a member list:
dotted paths (`save.money`), field names (`warpAt`), hook names
(`hook ui.pc.items`) and bare topics (`identity`, `iteration`, `rawset`) all
appear there. `members` is the authoritative set.

To dump the lot for one module:

```sh
luajit -e 'package.path="./?.lua;"..package.path
local G=require("src.mods.Gen2Compat")
local c=G.coverage("src.world.OverworldController")
for m,s in pairs(c.members) do print(s,m) end
for k,v in pairs(c.notes) do print("note",k,v) end'
```

## The patterns no adapter can fix

Five shapes come up in nearly every real Gen 1 mod, and none of them can be
fixed on the engine side without lying to you. Each one has a route that works
on both generations.

### 1. A hardcoded version allow-list

```lua
local v = GameVersion.get()
if v ~= "red" and v ~= "blue" and v ~= "yellow" then return false end
```

This excludes you from Gold by construction, and it does so *after* everything
else in your mod has been made to work, which is why it produces the most
confusing possible outcome: the adapter resolves, your patches land, and the
feature still never appears. `MK409` catches it.

**Instead**, test for the thing the branch actually depends on. If it is there
because a member might be missing, test the member:

```lua
local Follower = require("src.world.PikachuFollower")
if Follower.setShouldSpawn then ... end   -- present on Gold, absent on Gen 1
```

If it is there because a piece of per-cart content might be missing, test the
content -- `mod.find` and the merged data tables answer that in both games.
Version tests stay legitimate for genuinely per-cart *content*, which is what
Yellow's starter rename is; they are never right as a gate on a whole feature.

### 2. String-matching a screen id

```lua
if id == "BoxMenu" then ... end
```

Gold's builtin screens are registered under `Gen2`-prefixed ids, so this
matches nothing there. `Screens.GEN2_IDS` in `src/ui/Screens.lua` is the full
list, 51 ids: `Gen2BoxMenu`, `Gen2PartyMenu`, `Gen2NamingScreen`,
`Gen2Credits` and 47 more. `MK409` catches this exact line: it keys off the
string literal itself, not off a screen-shaped word elsewhere on the line, so
`if id == "BoxMenu" then` is flagged where it used to slip through. The price
of that is deliberate breadth -- any literal equal to a Gen 1 screen id with a
`Gen2` twin is warned about, wherever it appears -- so the message states what
is true of the literal rather than guessing what the surrounding code meant.
It is a warn, and reading past a false one costs you nothing.

**Instead**, either match both ids, or stop matching ids and take the seam the
screen offers. Most screens a mod wants to decorate raise a hook whose name is
shared across both generations -- `ui.start_menu.items`, `ui.options.rows`,
`ui.party.submenu`, `ui.pc.items`, `ui.naming.grid`, `ui.list_menu` -- and a
hook subscription needs no id at all. Where you genuinely must key off the id:

```lua
local BOX_IDS = { BoxMenu = true, Gen2PcMenu = true }
if BOX_IDS[id] then ... end
```

Watch the pairing. `ui.pc.items` has the same name on both sides but a
different menu behind it: Gen 1 raises it over the WHICH-PC list, Gold over
Bill's PC's own rows. And Gen 1's `BoxMenu` pairs with `Gen2PcMenu`, not with
`Gen2BoxMenu`.

### 3. `debug.setupvalue` on an engine local

```lua
local idx = findUpvalue(PikachuFollower.update, "shouldSpawn")
debug.setupvalue(PikachuFollower.update, idx, myPredicate)
```

This only ever worked because the Gen 1 file happened to hold that predicate in
a file-local of that name. Nothing about the engine promises it, and on the Gen
2 side the local has to exist under the same name and hold the same thing for
the surgery to land. Today it does: `src/world/gen2/Follower.lua:23` declares
`local shouldSpawn` for exactly this reason, so follower mods reaching for it
work unchanged on Gold. That is a deliberate courtesy, not a contract.

`MK407` fires in the two cases where the surgery cannot land: when a Gen 2 boot
resolves the member to something that is not a function (so `debug.setupvalue`
raises), and when the function it does resolve to does not close over that
name, in which case the message quotes the upvalues it *does* close over. The
check resolves the member through the adapter exactly as the loader does and
enumerates the resolved function's real upvalues, so a local that merely
appears somewhere in the Gen 2 file is never mistaken for one -- that used to
be the check, and it blessed surgery that landed on nothing. `MK408` fires when
the scan could not resolve the member either way, which is what you get when
`luajit` is not on `PATH`: the check degrades to an honest warn, never to a
reassuring note.

**Instead**, use the named seam when there is one, and fall back only when
there is not:

```lua
if Follower.setShouldSpawn then
  Follower.setShouldSpawn(myPredicate)      -- Gen 2, and any future Gen 1 arm
else
  patchUpvalue(Follower.update, "shouldSpawn", myPredicate)   -- Gen 1 today
end
```

`Follower.setShouldSpawn` writes the same cell `debug.setupvalue` reaches, so
the two cannot disagree. Note the presence test is doing real work:
`src/world/PikachuFollower.lua` has no `setShouldSpawn`, so this is not a
rename you can apply blindly. Note also that the predicate is called
`(game, world)` on Gold where Gen 1 passes `(game, ow)` -- the same object under
a different name, so a predicate reading `ow.player` or `ow.map` is unchanged.

### 4. Capturing state off `src.core.Game` at file scope

```lua
local Game = require("src.core.Game")
local save = Game.save          -- nil forever
local party = Game.save.party   -- error at load
```

The module require itself is fine and is meant to be: the Gen 2 `src.core.Game`
is a proxy that reads the live `Game2` instance on *every* touch, precisely so
that a mod capturing it at file scope, before a save or a world exists, keeps
working once they do. What does not survive is capturing a *field* off it at
file scope, which snapshots nil. This is true on Gen 1 as well; Gold just makes
it bite more often because the entry chunk runs earlier relative to the world.
`MK410` catches the file-scope read of a member the Gen 1 module only ever
writes as `self.<name>`.

**Instead**, read through the facade at the moment you need the value, or take
the live game from the `game.ready` payload:

```lua
local Game = require("src.core.Game")
mod.events:on("game.ready", function(ev)
  local game = ev.game            -- the real Game2 instance
  local party = Game.save.party   -- read now, not at file scope
end)
```

Three further properties of the proxy that a Gen 1 mod can trip over, all
recorded in the coverage notes:

- **Identity.** The proxy can never compare equal to the `Game2` instance the
  `game.ready` payload carries. Lua 5.1 fires `__eq` only when both operands
  share a metatable, so `Game == ev.game` is false on Gold. Do not use it as
  an idempotency check.
- **Iteration.** `pairs`, `next` and `rawget` see an *empty* table, because the
  proxy holds nothing of its own. Enumerate the `game.ready` payload instead.
- **`rawset`.** `rawset(Game, k, v)` lands on the proxy, reads back correctly
  through the same facade, and is completely invisible to the engine. That
  read-back is what hides it. Use a plain assignment, which writes through to
  the live instance.

The save layout moved too, and those fields are absent rather than aliased so
that a wrong read is loud rather than silent: `save.money` is
`save.player.money`, `save.player.map` / `.x` / `.y` / `.facing` are
`save.position.*`, and `save.player.rival` is `save.rival.name`. `save` itself
is a straight pass-through on purpose.

### 5. Monkey-patching a class, and the two ways it goes wrong

Patching a shared class method is *supported*, and this is worth stating
plainly because it is the thing most authors expect to have to rewrite. The
four UI facades write through: `__newindex` forwards to the Gen 2 class, so

```lua
local PartyMenu = require("src.ui.PartyMenu")
local origUpdate = PartyMenu.update
function PartyMenu.update(self, dt) ... return origUpdate(self, dt) end
```

lands on the class Gold actually pushes. Aliases are the class, so the same
holds there.

Two variants do not work, and neither can be made to.

**Patching a member the Gen 2 class does not have.** The write succeeds, reads
back as your own function, and nothing ever calls it. `BattleState.newWild =
wrapper` is the canonical case: the assignment is taken, and no Gold code path
reads that name. This is the one place the read-back works against you, which
is why `MK404` reports the write site separately from the read site.

**Patching a field on a live instance.** `menu.onSwitch = fn` writes a field
Gen 2 never reads -- Gold takes it as `onChoose` at construction. Same for
`menu.swapFrom` (renamed `switchFrom`) and for `StartMenu`'s `tx` / `ty` / `tw`
/ `th` / `anchor` / `maxVisible`, which do not exist on Gold at all because the
box is fixed at `Chrome.box(10, 0, 10, h)`. A write to any of them is inert.
Pass what you need to `.new` instead: `PartyMenu.new(game, { onSwitch = f })`
with no `battle`, `pickOnly` or `forceSwitch` opens the plain list and calls
`onSwitch(mon, menu)` on A, which is the Gen 1 behavior the facade reproduces.

A close relative worth calling out because it errors rather than no-ops:
`map.warpAt` is a name collision, not a rename. Gen 1's is a *table* keyed by
cell; Gold's `Map:warpAt` is a *method* of the same name. `map.warpAt[cell]`
and `pairs(map.warpAt)` both raise, which is loud but points at your mod.
Enumerate `map.warps`, which Gold carries as an ordered array.

## A worked migration

Here is one real one, start to finish. The mod is a follower pack written for
Red/Blue/Yellow. `gen2check` reports `MK400` on the manifest, `MK404` twice on
`BattleState.newWild` and `MK409` on a version allow-list, plus a note
confirming its `shouldSpawn` surgery lands.

**Before.** Three separate problems in about twenty lines.

```lua
local BattleState      = require("src.battle.BattleState")
local PikachuFollower  = require("src.world.PikachuFollower")
local GameVersion      = require("src.core.GameVersion")

return function(mod)
  -- (1) rewrite the starter encounter's species
  local origNewWild = BattleState.newWild
  BattleState.newWild = function(game, species, level, ...)
    if species == "PIKACHU" and level == 5 then species = "CHARMANDER" end
    return origNewWild(game, species, level, ...)
  end

  -- (2) decide whether a follower spawns
  local newShouldSpawn = function(game, ow)
    local v = GameVersion.get()
    if v ~= "red" and v ~= "blue" and v ~= "yellow" then return false end
    return packSize(game) > 0
  end

  -- (3) install it
  patchUpvalue(PikachuFollower.update,       "shouldSpawn", newShouldSpawn)
  patchUpvalue(PikachuFollower.onMapEntered, "shouldSpawn", newShouldSpawn)
end
```

On Gold: (1) assigns onto a name nothing reads, so the species rewrite never
happens. (2) returns false for every Gold boot, so no follower ever spawns.
(3) actually works, and works on a predicate that has already decided to do
nothing. Two silent failures and one correct mechanism pointed at them.

**After.** The manifest gains `"games": ["gen1", "gen2"]`, and:

```lua
local PikachuFollower = require("src.world.PikachuFollower")

return function(mod)
  -- (1) the species of a wild encounter is a hook on both generations
  mod.hooks:wrap("encounter.species", function(next, enc, ctx)
    local rolled = next(enc, ctx)
    if rolled and rolled.species == "PIKACHU" and rolled.level == 5 then
      rolled.species = "CHARMANDER"
    end
    return rolled
  end)

  -- (2) no cart check: whether there is a pack to walk is the whole question
  local newShouldSpawn = function(game, ow)
    return packSize(game) > 0
  end

  -- (3) the named seam where there is one, the upvalue where there is not
  if PikachuFollower.setShouldSpawn then
    PikachuFollower.setShouldSpawn(newShouldSpawn)
  else
    patchUpvalue(PikachuFollower.update,       "shouldSpawn", newShouldSpawn)
    patchUpvalue(PikachuFollower.onMapEntered, "shouldSpawn", newShouldSpawn)
  end
end
```

`gen2check` now reports clean, and the mod is shorter than it was on Gen 1
alone. That is the usual shape of this work: two of the three fixes replace
engine surgery with an API that existed the whole time, and only the third
needs a generation branch.

The one change that is *not* a simplification is the hook's contract. A wrapper
takes `(next, ...)` and must call `next` with the arguments it was handed, where
the monkey-patch could do as it liked with them. `encounter.species` transforms
a rolled `{ species, level }` and gets a `ctx` beside it: Gen 1 fills in
`mapId`, `terrain` and `rng`, and Gold adds `daytime`, `environment`, `kind`
(`"wild"` / `"contest"` / `"script"` / `"sweet_scent"`), `tables` and `data`.
So the same
subscription serves both games, and a Gold-only refinement is a field test
rather than a second hook. That is the trade: a narrower seam that both engines
raise, in exchange for not owning a function neither engine promised you.

## Testing

**Headless, without a Gold cache.** The SDK harness takes the generation
directly, and everything after that is the production path -- same loader, same
validate, same topological sort, same merge:

```lua
local run = T.sdk.loadMod("mods/my_mod", { generation = 2 })
T.eq(run.mod and run.mod.state, "loaded",
  "runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))
T.eq(#run.errors, 0, "and loads with no boot errors")
run.release()
```

**Assert the state, not just the error count.** A gate skip is deliberately not
an error: `Loader:_skip` sets `mod.state` and `mod.skipReason` and stays off
`loader.errors`, because neither the mod nor its dependency has a bug. So
`T.eq(#run.errors, 0)` on its own passes for a mod that never ran a line, which
is the one result you were testing to rule out. `run.mod.state` is `"loaded"`
when the entry chunk ran and `"wrong_generation"` when the gate or the
dependency contagion took it, with `run.mod.skipReason` carrying the sentence
the manager would show. Keep the error assertion too: it is what catches a
registry with no Gen 2 home and a require the adapter does not serve, both of
which *do* land on `loader.errors`.

**On a real Gold boot.** Nothing above substitutes for running it. Import Gold
in the launcher, enable your mod, and play the part your mod touches. Be
precise about where the adapter talks to you, because the two channels are not
the same:

- **The log** carries the adapter's own warnings, each attributed to the mod
  holding the facade (`[my_mod] Game.renderer has no Gen 2 backing: ...`), so a
  member that degraded tells you which one and why. `Gen2Compat.warnOnce` goes
  to `Logger.warn` and nowhere else -- these do **not** appear in the manager.
- **The manager's error feed** (`loader.errors`) is a shorter list: a mod that
  failed validation, a duplicate mod id, a registry with no Gen 2 target, a
  cross-validation problem, and the one adapter-adjacent case, a require for a
  Gen 1 module the adapter does not serve. A skipped mod is not on it, and
  neither is a degraded member.

So: read the log for coverage problems, and the manager for load problems.

`POKEPORT_IDENTITY=<name>` sandboxes the save directory if you want a clean
profile to test in. `POKEPORT_DEV=1` makes `mod.developer` true for loader-gated
diagnostics; Gold does not add Gen 1's console or `F5` hot reload.

## What this guide does not promise

- **Coverage is partial and will stay partial.** 15 Gen 1 modules are served
  out of a much larger engine, and within those 15 the coverage table records
  291 backed members against 32 warned and 161 absent. The absent ones are not
  a backlog; most are absent because there is no honest Gen 2 answer, and each
  one carries its reason. The counts move as the adapter learns something: a
  member that turns out to answer nil is demoted from backed to warned or
  absent rather than left flattering the table.
- **Absent is not broken, it is not-served.** A nil read is the designed
  outcome. If you would rather have an error, test for the member before you
  use it.
- **The checker is a static scan.** It cannot follow a require built at
  runtime, cannot tie every `debug` call to a module, and says nothing at all
  about a member the coverage table does not record. What it *can* do is admit
  each of those individually, with a file and a line, as an `unresolved:` note.
  Read the notes as part of the report: a clean finding list with notes under
  it means "nothing known-broken was found in the part I could follow", and
  only a clean finding list with no notes means the scan followed everything.
- **A backed member can still surprise you.** `backed` means the adapter took
  responsibility for the Gen 1 call shape, not that Gold behaves identically.
  Run `gen2check --notes` once and read the caveats on the members you touch.
- **The adapter is not a compatibility layer for new code.** It exists so mods
  written before Gold existed keep working. If you are writing something now,
  `mod.game`, `mod.world`, the registries and the hooks mean the same thing in
  both games and need none of this.
