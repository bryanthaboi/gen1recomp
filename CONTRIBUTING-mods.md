# Contributing to the mod platform

Two routes

| You are... | Lane | Review bar |
|---|---|---|
| adding a mod to the gallery, or listing one in the showcase | [Lane A](#route-a--contributing-a-mod) | template + polish checklist + green `modkit validate` |
| changing the loader, a registry schema, an event/hook name, or a manifest field | [Lane B](#route-b--contributing-an-engine--mod-api-change) | RFC + backward-compat statement + parity test + generated docs |

If you are not sure which lane you are in, ask this: **could my change make
somebody else's existing mod behave differently?** If yes, it is Lane B.

---

## Route A — contributing a mod

### 1. Scaffold

```sh
python3 tools/modkit.py scaffold my_mod --profile content
```

`--profile` is one of `content`, `overhaul`, `total_conversion`. The
scaffold refuses to overwrite an existing directory, and prints the next
commands.

Or copy the gallery entry closest to your intent — that is what the gallery
is for:

| You want to... | Copy |
|---|---|
| change numbers | `mods/examples/example_balance_tweaks` |
| change art | `mods/examples/example_shiny_palette` |
| add music or cries | `mods/examples/example_jukebox` |
| add a quest, NPC or dialogue | `mods/examples/example_lost_parcel` |
| change how battles work | `mods/examples/example_weather` |
| add a screen or a tool | `mods/examples/example_dexnav` |
| build a whole new game | `mods/examples/example_mini_conversion` |

### 2. What the PR must contain

1. **A green `modkit validate`.** CI runs it; so should you.

   ```sh
   python3 tools/modkit.py validate mods/examples/<id> --base imported
   python3 tools/modkit.py lint mods/examples/<id>
   ```

   `validate` drives the *real* loader headlessly, so a mod that passes
   here does not surface load errors in game. `--base imported` folds
   against the full vanilla id space; without it, rules that can only be
   decided against real Red content (`MK103`, the patch-target check) are
   reported as skipped rather than guessed at.

2. **A `tests/` directory** with at least one suite that loads the mod
   through the headless loader and asserts its *stated effect* — not just
   that it loaded.

   ```lua
   package.path = "./?.lua;./?/init.lua;" .. package.path
   local T = require("tests.modkit")
   local Data = require("src.core.Data"); Data:load()
   local run = T.sdk.loadMod("mods/examples/my_mod", { data = Data })
   T.eq(#run.errors, 0, "loads clean")
   T.eq(Data.pokemon.PIKACHU.baseStats.speed, 120, "the patch landed")
   run.release()
   T.finish("my_mod")
   ```

   Add a `.modkitignore` listing the suite so it stays out of the
   distributed package — a test requiring engine modules is a
   private-require finding against the shipped archive, and `pack` treats
   warnings as fatal.

3. **A `README.md`** that opens with one sentence saying what the mod does,
   names its persona, and gives the three commands to try it. No
   prerequisites the scaffold did not already create.

4. **A `mod.card`** meeting the [§3.2 schema](#modcard):

   ```lua
   return {
     summary   = "One sentence, <=100 chars.",
     author    = "Your handle",           -- never blank; no author is anonymous by omission
     tags      = { "balance", "beginner" },
     differences = { changed = {…}, added = {…}, known = {…} },
     credits   = { { who = "…", for_ = "original chiptune arrangement" } },
     compat    = { engine = ">=1.0.0 <2.0.0", modApi = 2 },
   }
   ```

5. **A `CHANGELOG.md`** in keep-a-changelog format, with a heading matching
   `manifest.version`. `validate` warns when the version advanced without
   one.

6. **Disabled by default.** Gallery entries live in `mods/examples/`, which
   the loader's one-level discovery does not walk, so a fresh install
   discovers none of them and the vanilla game is unchanged.

7. **No ROM-derived bytes.** Art and audio ship as originals or as a
   `transforms.lua` operating on the player's own cache. `modkit lint`
   is the hard floor; see
   [the legal posture](#legal-posture-non-negotiable).

CI checks 1, 2, 6 and 7 mechanically. A reviewer checks 3, 4, 5 and the
polish checklist.

### 3. Category

`manifest.category` is a closed vocabulary. An unknown value is a warning,
not a hard error, so the list can grow without breaking old mods.

| category | Meaning | Typical profile |
|---|---|---|
| `TWEAK` | Small data edits: stats, prices, learnsets, encounter tables | content |
| `BALANCE` | Systematic rebalance across many records or a ruleset | content / overhaul |
| `CONTENT` | New species / moves / items / maps / trainers | content |
| `QUEST` | New story, NPCs, dialogue, cutscenes | content |
| `MECHANIC` | New or changed battle/field mechanics via hooks/effects | overhaul |
| `GRAPHICS` | Sprite / tileset / palette / font changes | content |
| `LANGUAGE` | A translation: `text`, `strings` and the glyphs it needs | content |
| `AUDIO` | Music, sfx, cries | content |
| `UI` | New or modified screens, menus, overlays | content / overhaul |
| `TOOL` | Dev/QoL utilities, overlays, inter-mod libraries | content |
| `TOTAL_CONVERSION` | Full re-theme; owns its own tri-ledger | total_conversion |
| `OTHER` | Fallback | any |

`GAMEPLAY` is accepted as an alias for `TWEAK`, so `example_mew_starter`
keeps validating with the value it has shipped since before the taxonomy
existed.

A translation may also set `"language": true` in the manifest. That is the
one claim online play acts on: an install running nothing but verified
translations may take an ONLINE MATCH or a TOURNAMENT instead of being
asked to restart vanilla. The claim is checked, not taken -- the mod
qualifies only if every record it writes lands in `text`, `strings` or
`font`, it wraps no hook, subscribes to no event and requests no
permission. Anything else and it is an ordinary content mod that happens to
ship text.

### 4. `games` (and the legacy `gen2compat`)

Pokemon Gold, Silver and Crystal are Gen 2, and they run their own battle
engine, overworld, script VM and save format. The mod API is shared across both
generations (same hook names, same event names, same registry names) but Gen 2
cannot serve all of it yet, so it is opt-in. Say which games the mod is for:

```json
"games": ["gen1", "gen2"]
```

Each entry is a version id (`"red"`, `"blue"`, `"yellow"`, `"gold"`,
`"silver"`, `"crystal"`), a generation (`"gen1"`, `"gen2"`) or `"all"`;
`src/mods/ModTargets.lua` resolves them off `GameVersion.ORDER` so nothing
restates the game list, which is why `"gen2"` covers Crystal as well as Gold
and Silver. `python3 tools/modkit.py scaffold my_mod --games gen1,gen2` writes
the key for you. The mod still installs to one directory, `mods/<id>/`, shared
by every game -- targeting is declared, never filed.

Absent means Gen 1 only, which is what every mod written before the key existed
was tested as. `"gen2compat": true` is the legacy spelling, still accepted and
purely additive (it *adds* the Gen 2 games), so no manifest can lose a game it
already ran on. On a Gen 2 boot a mod claiming no Gen 2 game is not loaded at
all: the manager lists it as `ENABLED (NOT THIS GAME)` and says why, because a
mod that half-applies reads as a broken mod. Claim Gen 2 once you have actually
run your mod on Gold, Silver or Crystal.

Every token is enforced, per game: the loader gates on the same
`ModTargets.supports` answer both mod surfaces draw, so `"games": ["blue"]`
really does not load on Red and the skip line is the launcher's line, `For
Blue, not Red`, and `"games": ["gold"]` alone does not load on Red either. A
manifest with neither key still covers every Gen 1 game, so nothing written
before the key existed changes behavior; list both generations or say `"all"`
when you mean everywhere.

`docs/mod-api-gen2-compat.md` is the compatibility matrix: what works on Gold,
Silver and Crystal today (40 of the 46 registries, 40 event and 44 hook names
shared with Gen 1, and 24 Gen 2-only ones), which registries have no Gen 2 home
and drop their writes with a report, and which hooks and events are still to
come.
`docs/preparing-your-mod-for-gen2.md` is the step-by-step migration guide for a
Gen 1 mod, and it is the one to start from.

Two consequences worth knowing before you claim Gen 2.

**Dependencies are contagious.** A mod whose hard dependency does not run here
is left out too, with the dependency's own wording (`depends on X, which does
not run here (For Blue, not Red)`). It is reported as a skip, not as a failure,
and neither mod lands on the boot error list, but the mod does not run, so
every hard dependency has to cover the same games.

**The player can override you.** The claim is yours, and a mod written before
the key existed can never carry one, so the manager's detail pane offers
`TRY HERE ANYWAY` for any mod that does not claim the game being played. It
persists per game in `options.modsGen2[id][version]` and takes effect on the
next boot; forcing a mod onto Red does not force it onto Gold. A forced mod
loads normally and keeps a note saying its author never verified it here.

**Prefer the API on Gold, but the Gen 1 names still work.** Gen 2 is a
parallel module tree behind `src/core/Game2.lua`. In new code take the live
game from `mod.game` (or the `game.ready` payload, or any `ui.*` hook's first
argument) and the world from `mod.world`; both resolve per generation, and
neither needs `engine_internals`.

For the mods written before Gold existed, a require made from a mod's own file
is answered on a Gold boot by an adapter presenting the Gen 1 API over Gen 2
internals. Fifteen names are served -- `src.core.Game`,
`src.world.OverworldController`, `src.world.Map`, `src.world.NPC`,
`src.world.Collision`, `src.world.WorldAPI`, `src.world.PikachuFollower`,
`src.world.FieldDefaults`, `src.pokemon.Boxes`, `src.script.ScriptRunner`,
`src.ui.PartyMenu`, `src.ui.StartMenu`, `src.ui.OptionsMenu`, `src.ui.BoxMenu`
and `src.battle.BattleState`. `src/mods/Gen2Compat.lua` is the full table and
publishes what it covers through `Gen2Compat.coverage(name)`, whose members are
`backed`, `warned` or `absent`. A name with no adapter (`src.script.Commands`,
`src.ui.OptionRows`) is reported against the mod that required it, and a member
an adapter cannot back is absent or logs once rather than answering wrongly.

Things no adapter can fix, all mod-side: a hardcoded version allow-list
(`GameVersion.get() == "red" or ...`) excludes you from Gold by construction;
Gold's builtin screen ids carry a `Gen2` prefix, so a string match on
`"BoxMenu"` matches nothing there; a write to a field on a live Gen 2 menu
instance is inert; and `map.warpAt` is a table on Gen 1 and a method on Gold,
so indexing it raises. Each has a route that works on both generations, in
`docs/preparing-your-mod-for-gen2.md`.

Check it statically, then load it headless:

```sh
python3 tools/modkit.py gen2check mods/my_mod
```

```lua
local run = T.sdk.loadMod("mods/my_mod", { generation = 2 })
T.eq(run.mod and run.mod.state, "loaded",
  "runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))
T.eq(#run.errors, 0, "and loads with no boot errors")
```

Assert the state, not only the error count: a gate skip is deliberately not an
error, so `#run.errors == 0` passes for a mod that never ran a line.

`gen2check` answers `will load`, `will load but degrade` or `will not work`,
with a `MK4xx` finding per site and an `unresolved:` note, with a file and a
line, for every reach a static scan could not follow. Neither substitutes for a
real Gold boot.

### 5. What a mod's code can reach

Your code runs in a sandbox (`src/mods/Sandbox.lua`), not against the
engine's globals. Every chunk you author gets it: `main.lua`, your
`options_schema`, and anything you `load()` yourself.

The globals the sandbox took away are still *reachable*, as compat
stand-ins (`src/mods/LegacyCompat.lua`) that answer with the new API
underneath. A mod written before the sandbox keeps working; it logs one
warning per call it should migrate, and the mod manager lists them. What
each stand-in actually does:

| Pre-sandbox call | What it does now | Migrate to |
| --- | --- | --- |
| `io.open`, `io.lines`, `love.filesystem.read`/`lines`/`newFile` | reads your own shipped files, then your overlay, then `mod.storage` | `mod:read`, `mod.storage` |
| `love.filesystem.write`/`append`, `io.open(…, "w")`, `os.remove`, `os.rename` | writes to a private per-mod overlay under `mod_compat/<your id>/` | `mod.storage` |
| `love.filesystem.getDirectoryItems`/`getInfo` | your own directory plus your overlay | `mod:list`, `mod:info` |
| `love.filesystem.getSaveDirectory` and friends | a virtual root; anything joined to it lands in your overlay | `mod.storage` |
| `os.getenv` | `nil`, except home-like names, which answer with that same virtual root | nothing |
| `love.filesystem.load`, `dofile`, `loadfile` | compiles the chunk into your sandbox | `require`, `mod:read` plus `load` |
| `love.system` | `getOS`/`getPowerInfo`/`getProcessorCount` read through; clipboard and `openURL` do nothing | `mod.device:powerInfo()`, `mod.steps` |
| `love.event` | passes through, except `quit`, which does nothing | `mod.events`, `mod.hooks` |
| `love.mousemoved = fn` and the other callbacks | installs on the real `love` table, the way it always did | `mod.hooks`, `mod.events` |
| `package` | an inert stub, so `package.path = …` does not crash | `require` |

What has no stand-in, because there is nothing honest to reroute it to:

| Still refused | Why |
| --- | --- |
| `love.thread` | a LÖVE thread is a fresh Lua state with the full standard library, which no environment-based sandbox in this state can reach. Use `mod.fetch` for background HTTP (`network`) or `mod.job` for background compute (`background`) — both run your code inside the sandbox instead of outside it |
| `require("ffi")` | arbitrary C |
| `debug`, `getfenv`, `setfenv` | each one undoes the sandbox from inside |
| `io.popen`, `os.execute` | spawning a process |
| `love.run`, `love.errorhandler` | the engine's own loop and its crash path |
| replacing a `love` module table (`love.filesystem = {}`) | the engine reads those tables too |

The rest of `love` passes through unchanged, so graphics, audio, timers and
input work as they always have.

Three consequences worth knowing before you write against it:

- **Your globals are yours.** `_G` inside a mod is that mod's own table. Two
  mods no longer share a namespace, and neither can reach the engine's. To
  publish something to another mod, put it on `mod.exports` and let them
  `mod.find("your_id").exports` — the channel that was always the intended
  one. The same goes for the standard library: `string`, `table` and `math`
  are per-mod copies, so patching one is a local decision.
- **Paths cannot climb.** `mod:read`, `mod:list`, `mod:info`, `mod.assets:path`
  and `mod.assets:image` join to your own directory, and `..`, absolute paths
  and drive letters are refused. So are `entry` and `options_schema` in your
  manifest. `mod:list("assets")` is the sandboxed `getDirectoryItems` for a
  folder you shipped; `mod:info` tells file from directory so a walk can
  recurse.
- **Ship source, not bytecode.** A precompiled entry file is refused.

`permissions` in the manifest is still a disclosure the manager shows the
player. `network` gates `require("socket")` and friends plus `mod.fetch`
(non-blocking HTTP), and `background` gates `mod.job` (compute on a worker
thread). Those two are the sanctioned ways to work off the main thread now
that `love.thread` is refused. There is no
permission that grants raw filesystem access, because no mod needs one:
everything a mod legitimately writes is already scoped by
`mod.storage` or the asset-transform derived root.

If your mod used one of the rerouted globals, the fix is almost always
`mod.storage`. The overlay is a compatibility floor, not a second storage
system: it is not scoped per playthrough, it does not migrate, and it is
the first thing that will be dropped once the mods on the index have
moved off it. Open an issue if you have a case `mod.storage` does not
cover.

### 6. `mod.card`

The manifest is the *engine's* contract: identity, load order, dependencies,
permissions, profile (see [Manifest specification](docs/modding.md#manifest-specification-manifestjson)).
The card is the *human-facing* one: who made this,
what it changes, what it does not do yet. It is never read by the loader's
merge — only by tooling and the manager's detail pane — so an absent or
malformed card can never break a load.

Two fields deserve their own note:

- **`differences`** is a self-declared tri-ledger, mirroring the discipline
  the engine holds itself to. `changed` and `added` let a player see the
  blast radius before installing; `known` is where you are honest about
  what is rough. A card with an empty `known` on a complex mod reads as
  carelessness, not polish.
- **`screenshots[].transform`** describes a screenshot by the *driver
  script* that regenerates it from the player's build, rather than shipping
  the pixels. That is the legal posture extended to your marketing: a
  distributed mod never carries ROM-derived bytes, not even in its preview
  images.

### 7. Tags

Lowercase kebab strings, open vocabulary. The showcase generator
lowercases and de-dupes. A recommended starting set: `beginner`,
`data-only`, `quality-of-life`, `hardcore`, `cosmetic`, `story`, `ruleset`,
`audio`, `ui`, `total-conversion`.

---

## Route B — contributing an engine / mod-API change

Changing the loader, a registry schema, an event or hook name, or a manifest
field touches the **compatibility surface** the project promises to hold
stable. Those PRs carry five obligations.

### 1. An RFC

`docs/rfcs/NNNN-<slug>.md`, covering:

- **Motivation** — the mod that cannot be written today.
- **The decision it extends or amends** — name the D-number and the plan
  file, so the change is traceable to the design it modifies.
- **The exact API delta** — new registry names, new schema fields, new
  event/hook names and their payload shapes and call sites.
- **A migration note for existing mods** — what an author has to do, if
  anything. "Nothing" is a valid and preferred answer.

### 2. A backward-compatibility statement

Show that the v1 surface still works: `content.X:register/override/get`,
`events:on`, `hooks:wrap`, `mod.log`, `mod:read`, the manifest v1 fields,
and `pokemon.before_give`.

**A change that would break a v1 mod is rejected unless it is
additive-with-alias.** `mods/example_mew_starter` is the live proof: it is
api 1, uses `category = "GAMEPLAY"`, copies a whole species record because
`patch` did not exist yet, and it must keep loading unchanged.

### 3. A parity-guarantee test

Two tests, not one:

- **The no-mod test** — vanilla behavior is unchanged with nothing
  installed. A new hook with no subscriber must return the vanilla value;
  a new registry must be a provable no-op when empty; a new event must not
  allocate its payload when nothing wants it (`Runtime.wants(name)` /
  `Runtime.wantsHook(name)` guard the hot paths).
- **The mod-API test** — the new seam, exercised through the *public* mod
  API rather than by reaching into internals. If the test has to require a
  private module to drive your seam, the seam is not finished.

### 4. Docs with the change

The reference pages are generated from `src/mods/Schemas.lua`, so a new
registry or a new schema field lands with its catalog entry in the same PR
and the generator runs clean:

```sh
luajit tools/gen_registry_docs.lua                 # docs/modding/reference/registries.md
luajit tools/gen_registry_docs.lua ../project.wiki # Reference-Registries.md in a wiki checkout
```

With no argument it writes inside the repo, which is the copy `python3
tools/modkit.py docs` regenerates and `--out` copies from. Pass a directory
(or set `POKEPORT_DOCS_DIR`) to write the wiki's flat page name into a wiki
checkout instead. The prose reference lives in the GitHub wiki; both copies
come off `src/mods/Schemas.lua`, so neither can drift from the engine.

### 5. Deprecation etiquette

**Nothing is removed.** A superseded seam is marked deprecated in the
generated reference with its replacement named, keeps firing and working,
and is listed in the deprecations page.

`pokemon.before_give` is the worked precedent: the `pokemon.give` hook
supersedes it, and it is grandfathered forever anyway.

### Review

PRs touching `src/mods/`, `src/mods/Schemas.lua`, or the event/hook catalog
need the RFC label and a green parity gate before merge.

---

## The polish checklist

Every gallery example and every community mod the guide recommends meets
this bar. `[auto]` items are checked by `modkit validate`; `[review]` items
by a human.

### Error messages

- `[auto]` No bare `error()` or `assert()` in mod callbacks. Every failure
  path uses `mod.log:warn` / `mod.log:error` — the loader already prefixes
  `[modid]` — **and names a remediation**:

  ```lua
  -- no
  local mew = assert(mod.content.pokemon:get("MEW"), "Mew is missing")

  -- yes
  if not mod.content.pokemon:get("MEW") then
    mod.log:warn("MEW missing from the merged view -- is a species mod "
      .. "loaded before this one? speed patch skipped")
    return
  end
  ```

- `[review]` Every registration is validated against its schema, so a typo
  is a load-time message naming the field, not a nil-index crash three
  screens later.

### Empty states

- `[review]` Every screen a mod adds renders a sentence when its data set
  is empty — "No songs registered", "Nothing seen yet" — never a blank box.
  `ListMenu` gives you this for free.

### First-run experience

- `[review]` The README opens with one sentence of what the mod does, then
  the commands to try it.
- `[auto]` The mod loads clean on a fresh install — zero `Loader.errors` —
  with only its declared dependencies.
- `[review]` Options have sane defaults, so the mod does something useful
  before the player opens its options pane.

### Credits and honoring authors

- `[review]` `mod.card.credits` names every upstream contribution — art,
  music arrangement, borrowed code — and what it was for. A mod that ports
  another community work credits it and links it.
- `[auto]` `mod.card.author` (or `authors`) is present and non-empty. The
  showcase and the manager both surface it, so no author is anonymous by
  omission.
- `[review]` Asset provenance is honest: originals declared original,
  cache-derived output produced by a declared transform, third-party assets
  credited and license-compatible.

### Legal posture (non-negotiable)

- `[auto]` **No ROM-derived bytes in the packaged mod.** `modkit pack`
  refuses otherwise, and `pack` runs `validate --strict`, so even warnings
  block the archive.
- `[review]` A total conversion carries the TC legal callout: the Red
  import still runs and supplies fallback infrastructure, the conversion
  overrides on top, and it distributes recipes rather than extracted
  content.

---

## Versioning etiquette

Three version numbers coexist.

**Engine version** — `src/core/Version.lua`. Major = a breaking change to
the mod-facing schemas or API; minor = new backward-compatible seams;
patch = bugfix.

**Mod API version** — the integer `modApi`, currently `2`. Bumped only on a
breaking change to the `mod` object surface. A manifest's `api` field pins
the surface the mod was written against, so an api-2 mod keeps working when
the engine ships api 3.

**Your mod's version** — the manifest `version`, semver:

| bump | when |
|---|---|
| patch | data fixes; no save-shape change, no new content ids |
| minor | new content ids, new options with defaults, new optional deps |
| major | removed or renamed content ids, a changed `mod.save` shape (needs a `mod.migrations:add(sinceVersion, fn)` entry), or a raised `game_version` floor |

Declare the engine range you target in `game_version` (a semver range, e.g.
`">=1.0.0 <2.0.0"`). The loader checks it on load; a mismatch is a clear,
mod-attributed manager error, never a silent partial load.

Every version change gets a `CHANGELOG.md` heading. `modkit validate` warns
when `manifest.version` advanced without one.
