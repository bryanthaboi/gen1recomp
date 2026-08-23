# Native modding

The modding book lives on the
[project wiki](https://github.com/bryanthaboi/gen1recomp/wiki).

- [Getting started](https://github.com/bryanthaboi/gen1recomp/wiki/Getting-Started)
  — install a mod, write a first one, enable and disable it.
- [Tutorials](https://github.com/bryanthaboi/gen1recomp/wiki/Tutorials)
  — twelve dependency-ordered rungs, each a runnable mod.
- [Cookbook](https://github.com/bryanthaboi/gen1recomp/wiki/Cookbook)
  — task-sized recipes.
- [Registry reference](https://github.com/bryanthaboi/gen1recomp/wiki/Reference-Registries)
  — every registry, generated from `src/mods/Schemas.lua`.

Regenerate the reference. With no argument it writes in-repo, to
`docs/modding/reference/registries.md`; name a wiki checkout to write the
wiki's own page name into it instead:

```sh
luajit tools/gen_registry_docs.lua
luajit tools/gen_registry_docs.lua ../gen1recomp.wiki
```

## Manifest specification (`manifest.json`)

Every mod contains a root `manifest.json` defining its metadata, supported games, and dependencies for the engine loader.

```json
{
  "id": "my_mod",
  "name": "My Cool Mod",
  "version": "1.0.0",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "category": "GAMEPLAY",
  "games": ["gen1", "gen2"],
  "game_version": ">=0.0.0-dev <2.0.0",
  "priority": 100,
  "dependencies": [
    "helper_lib@^1.0.0",
    { "id": "pokegear_cards", "games": ["gen2"], "range": "^1.0.0", "github": "1jamie/pokegear_cards" }
  ],
  "optional_dependencies": [
    "gen1_modern_ui"
  ],
  "required_imports": [
    {
      "id": "stadium2",
      "name": "Pokemon Stadium 2 ROM",
      "description": "Pokemon Stadium 2 (USA), any supported N64 byte order",
      "file": "stadium2.z64",
      "format": "n64",
      "size": 67108864,
      "md5": ["00000000000000000000000000000000"]
    }
  ],
  "optional_imports": [
    {
      "id": "bonus_source",
      "name": "Optional bonus source",
      "file": "bonus.bin",
      "md5": "00000000000000000000000000000000"
    }
  ],
  "conflicts": [],
  "permissions": ["engine_internals"],
  "description": "A brief description of the mod.",
  "github": "author/my_mod"
}
```

### Manifest Fields

| Field | Type | Description |
| --- | --- | --- |
| `id` | `string` | Unique identifier (lowercase alphanumeric, underscores, hyphens). |
| `name` | `string` | Human-readable title shown in launcher and manager. |
| `version` | `string` | Semantic version string (e.g. `"1.0.0"`). |
| `api` | `integer` | Mod API level (`2` for current standard, `1` for legacy). |
| `entry` | `string` | Entry Lua file path relative to mod root (usually `"main.lua"`). |
| `profile` | `string` | Mod profile: `"content"`, `"overhaul"`, or `"total_conversion"`. |
| `category` | `string` | Categorization chip (e.g. `"GAMEPLAY"`, `"CONTENT"`, `"UI"`, `"AUDIO"`). |
| `games` | `array` | Supported game versions: `["gen1"]`, `["gen2"]`, `["red"]`, `["blue"]`, `["yellow"]`, `["gold"]`, `["silver"]`, or `["all"]`. |
| `game_version`| `string` | Semver range of required engine version (e.g. `">=0.0.0-dev <2.0.0"`). |
| `priority` | `integer` | Load priority order (lower numbers load earlier; dependencies always precede dependents regardless of priority). |
| `dependencies` | `array` | Hard required dependencies. A mod will not load if a required dependency is missing or disabled for the active game. |
| `optional_dependencies` | `array` | Soft dependencies. Guarantees that if the target mod is present and active, it loads *before* this mod without blocking load if absent. |
| `required_imports` | `array` | User-supplied files required by this mod. The launcher validates and copies each file into this mod's `baseroms/` directory; the mod does not load while one is missing. |
| `optional_imports` | `array` | User-supplied files that unlock optional mod functionality. They use the same validation and private-copy flow but never block the mod from loading. |
| `conflicts` / `incompatible` | `array` | List of mod IDs that cannot run concurrently with this mod. |
| `permissions` | `array` | Requested privileges (e.g. `["engine_internals"]`, `["network"]`, `["filesystem"]`). |
| `log_url` | `string` | Optional https URL for `mod.postLog` log reporting (api 2; requires the `network` permission). |
| `github` | `string` | GitHub repository (`"owner/repo"`) used for update checks and dependency download links. |

### Declaring Dependencies & Scoping

Dependencies in `dependencies` and `optional_dependencies` can be declared in several formats:

1. **Simple string**: `"mod_id"`
2. **Version-pinned string**: `"mod_id@^1.2.0"`
3. **Repository-hinted string**: `"mod_id#owner/repo"` or `"mod_id@^1.2.0#owner/repo"`
4. **Structured object**:
   ```json
   {
     "id": "mod_id",
     "range": "^1.2.0",
     "games": ["gen2"],
     "github": "owner/repo"
   }
   ```

#### Version-Scoped Dependencies
When a mod supports multiple games (`"games": ["gen1", "gen2"]`), a dependency can specify `"games": ["gen2"]` to indicate it is only required when booting Gen 2. When booting Gen 1, the engine will ignore the dependency, preventing unnecessary boot blocks on games that do not need it.

### Required user-supplied files

`required_imports` and `optional_imports` keep copyrighted or otherwise user-owned source material
out of mod archives while giving every platform the same installation flow.
Each object requires a stable `id`, a display `name`, a destination `file`
(a filename, never a path), and one MD5 digest or an array of accepted MD5
digests. `format` is either `"raw"` (the default) or `"n64"`. An optional
`description` gives players dump or region guidance in the import panel.
`size` declares the exact canonical byte length; `max_size` declares a smaller
per-import ceiling when an exact size is not appropriate. The engine hard limit
is 2 GiB. Imports above 128 MiB receive an explicit free-space confirmation and
use the launcher's streaming large-file path rather than being materialized as
one Lua string.

For `"n64"`, the launcher recognizes `.z64`, `.v64`, and `.n64` byte orders,
strips a recognized 512-byte copier header, converts the bytes to canonical
big-endian `.z64` order, and then checks MD5. The canonical bytes are written
to `mods/<mod-id>/baseroms/<file>`. Each selection is a private grant to that
mod: the launcher never scans or copies another mod's imported files merely
because its manifest names the same digest. Small sources can still be read
with the existing scoped `mod:read` API, for example
`mod:read("baseroms/stadium2.z64")`. For large sources, prefer the bounded
`mod.imports` facade described below; no host path or new general filesystem
permission is exposed. Missing `required_imports` block the mod before its
entry chunk runs; missing `optional_imports` remain visible in the same
launcher panel but do not block loading.

#### Bounded access to validated imports

A loaded mod can address only ids declared by its own `required_imports` or
`optional_imports` arrays:

```lua
local info, err = mod.imports:info("stadium2")
local header, err = mod.imports:read("stadium2", 0, 4096)
```

`read` uses zero-based offsets and is capped at 8 MiB per call. The engine
rechecks the stored import before exposing it, seeks into the engine-owned
copy, and never gives the mod a host path or file handle. This is intended for
large source formats whose table/index can be parsed with small reads before
selectively reading the payloads a transform actually needs.

MD5 here identifies a known dump because ROM databases commonly publish it;
it is not a security or authenticity guarantee. Do not paste the SHA-1 used by
Gen1Recomp's own game-ROM importer into an import's `md5` field. Mod archives
must not include anything beneath `baseroms/`. The engine records a validation
receipt keyed by file size and modification time so launcher refreshes and
later boots do not repeatedly hash an unchanged imported ROM.

New mobile code should call `love.system.pickFile("required_import")`. The
older iOS-only `"stadium"` picker kind remains temporarily for compatibility.
Android now returns `false` for unknown picker kinds instead of treating them
as game-ROM picks.

### Platform import flow

The same per-mod validation and private `mods/<mod-id>/baseroms/` destination
applies on every supported platform. Windows, macOS, and Linux use the
launcher file chooser. Android uses the Storage Access Framework, and iOS uses
the Files document picker; both stage the choice as `picked_required_import.bin`
before validation. Xbox/UWP uses its native picker and hands the launcher a
temporary path. Switch/NX has no host picker, so the player copies a file to
`imports/baseroms/` over MTP and chooses the import again. No platform grants
the mod a host filesystem path or bypasses the manifest's size, format, and MD5
checks.

## Mods and Gold (Gen 2)

The mod API is one API across both generations, but Gold runs its own battle
engine, overworld, script VM and save format, so a mod says which games it is
for and Gold serves a declared subset of the surface.

- [`docs/preparing-your-mod-for-gen2.md`](preparing-your-mod-for-gen2.md)
  the migration guide: what breaks, the `games` manifest key, the module
  adapter, the patterns no adapter can fix, and a worked before/after.
- [`docs/mod-api-gen2-compat.md`](mod-api-gen2-compat.md)
  the reference: every registry, hook and event, whether Gold serves it, and
  the record-shape differences where it does.

Start with the checker, which reads your manifest and scans your Lua against
the adapter's own coverage table:

```sh
python3 tools/modkit.py gen2check mods/my_mod
```

## Editing maps in Tiled

Maps are data, not assets, so they can be authored in a real map editor and
exported as a mod. `tools/tiled_export.py` builds a
[Tiled](https://www.mapeditor.org) workspace out of the imported ROM cache:

```sh
python3 tools/tiled_export.py          # -> build/tiled/ (gitignored)
```

Open `build/tiled/gen1.tiled-project`, edit any of the 222 maps (or
`kanto.world` for the stitched overworld), and export with the
`gen1-mod-export` extension — one map file, or a whole loadable mod folder.
An edited vanilla map becomes a `mod.content.maps:patch` carrying only the
fields that moved; a new map becomes a `:register`. See
`docs/new-features.md` and the extension's own README.

## Read-only map overviews

`mod.world:mapOverview()` returns collision `rows` at map-cell resolution,
optional visual `tileRows` at 2x resolution, and optional `tileDetailRows` at
4x resolution. Visual rows contain Game Boy shades from `"0"` (lightest) to
`"3"` (darkest); their matching width and height fields describe the grid.
`markers` contains active `{ kind, x, y }` points in map-cell coordinates for
`warp`, visible `item`, and untaken `hidden` locations. All fields are
read-only snapshots; mods choose which layers to render. Red and Gold expose
the same contract while applying their own object and event visibility rules.

## Party ordering

Companion UIs and alternate party screens can call
`mod.world:canReorderParty()` before offering a reorder action, then
`mod.world:reorderParty(fromSlot, toSlot)` with one-based party slots. The
operation is accepted only during idle overworld play; menus, movement,
scripts, battles, and transitions leave the party untouched.

## Contextual field actions

`mod.world:availableFieldActions()` returns the field items and moves that can
start at the player's current position. Both games expose `bicycle`, `fish`,
`cut`, `surf`, `strength`, `flash`, `dig`, and `teleport`; Gold additionally
exposes `headbutt`, `whirlpool`, `waterfall`, `sweet_scent`, and the
contextual `squirtbottle` key item. Red additionally exposes `softboiled` with
eligible `sources`; each source contains its eligible `targets`. Fishing rows
include the owned rods that are valid choices. The list is empty while the
world is busy, and omits an action whenever its item, move, badge, terrain, or
engine state forbids it.
The optional second return is `"world is busy"` during transient input locks
or `"no overworld"` before a playable world exists.

Call `mod.world:useFieldAction(id, opts)` to perform a listed action through
the active game's own field-item path. Fishing accepts `{ rod = "OLD_ROD" }`
and chooses automatically when only one rod is available. Red's `softboiled`
accepts one-based `{ sourceSlot, targetSlot }` values copied from its action
record. Invalid, stale, and busy requests return `nil` plus a reason without
changing game state. Mods do not need generation-specific badge, terrain,
bike, fishing, or field-move
logic. Action lists are extensible; callers should render the records they
understand and ignore unknown ids rather than assuming a fixed list length.

Red exposes FLY separately because it requires a destination picker:
`mod.world:canFly()` reports whether FLY is eligible at the current location,
and `mod.world:flyTo(mapId)` accepts only a visited destination from the native
Fly town list. Gold does not expose these two methods yet.

## Read-only battle snapshots

`mod.battle:snapshot()` returns `nil` outside a battle and a copied battle
record while one is active. Gen 1 (Red, Blue, and Yellow) and Gold expose the
same core fields:
`revision`, `kind`, `catchable`, `prompt`, `message`, `turn`, `player`,
`enemy`, `party`, `moves`, and `items`. Pokémon, moves, messages, and items in
the result are detached records; changing them cannot change the battle.
`revision` stays stable while the visible battle context is unchanged and
advances when it changes, so a UI can skip rebuilding an identical view.

Pokémon records contain `species`, `name`, `level`, `hp`, `maxHp`, `status`,
and `active` (plus `slot` in `party`). Move records contain `slot`, `id`,
`name`, `pp`, `maxPp`, `type`, `power`, `accuracy`, and `disabled`. Gen 1 also
reports the actual ruleset-aware `displayPower`, `hitChance` percentage, and
`effectiveness` multiplier (`10` neutral, `20` super-effective, `5`
resisted). Item rows contain `id`, `name`, `count`, `ball`, `needsTarget`, and
an optional stock `catchChance` percentage.

`prompt` describes the currently visible choice (`menu`, `moves`, `party`,
`advance`, `safari`, or `mimic`) and is `locked` when another screen or battle
phase owns input. Generation-specific features remain optional: Gen 1 includes
battle medicine, balls, catch previews, Safari balls, and Mimic choices. Gold
exposes balls and their exact stock catch previews; targeted medicine remains
screen-owned and is omitted rather than guessing at its pocketed PACK flow.
Callers should ignore unknown fields and tolerate absent optional ones.

## Caught Pokémon storage result

The `pokemon.caught` event includes the boolean `stored`. It is `true` only
when the exact caught Pokémon has been inserted into the player's party or a
PC box before the listener runs. It is `false` when the ball catch completed
but both party and PC storage rejected the Pokémon. Pokédex ownership alone
does not make `stored` true.

The existing `destination` field remains `"party"` or `"box"` and describes
the selected storage route. It is not proof that insertion succeeded. Mods
that require confirmed storage should test `ev.stored == true`; this also
fails closed on older engines where the field is absent. All other event
fields and catch behavior are unchanged.

## Battle menu intents

`mod.battle:submit(intent)` applies a validated choice to the snapshot the mod
just read. Every intent needs a mod-owned, strictly increasing positive
integer `id` and the latest snapshot `revision`. Stale, replayed, covered, or
invalid choices return `nil` plus a reason without changing the battle.

The shared Red, Blue, Yellow, and Gold intents are:

- `{ kind = "menu", choice = "fight" }` (`party`, `item`, and `run` are the
  other accepted choices)
- `{ kind = "move", slot = 1..4 }`
- `{ kind = "back" }` while the move menu is active

Red, Blue, and Yellow also expose their generation-specific choices:

- `{ kind = "safari", action = "ball" }` (`bait`, `rock`, and `run` are the
  other accepted actions)
- `{ kind = "mimic", index = 1 }` using an entry's snapshot `index`

Menu choices and moves use the same engine methods as the native controls;
`party` and `item` open the native screens rather than exposing or duplicating
their mutable logic. Tutorial, link, forced, stale, and covered battle states
refuse core intents. Use `mod.input` for ordinary text advance.

## Rendering pipelines

Most registries hand the engine *content*. `render_pipelines` hands it
*drawing*: a pipeline is a display mode a mod owns, which may replace the
overworld's world pass with geometry of its own and/or post-process the
finished image. `mods/voxel_world` is the worked example — a 3D diorama
overworld plus a tilt-shift miniature pass, in about 120 lines of glue over
its renderer.

A record declares what the mode *is*; the engine
(`src/render/Pipelines.lua`) supplies everything about *being a display
mode*: the OFF/1/2/3 ladder, an options row next to TILT, a hotkey,
persistence in `save.options.pipelines`, and the rule that a world pipeline
and the engine's own TILT are mutually exclusive.

```lua
mod.content.render_pipelines:register("diorama", {
  label = "DIORAMA",                    -- options row label
  levels = { "OFF", "15", "35", "50" }, -- ladder; defaults to OFF/ON
  hotkey = "6",                         -- checked after the engine's keys
  priority = 20,                        -- highest eligible wins the world
  available = function() return Renderer3D.ok() end,
  update = function(dt, level) Camera.ease(dt, level) end,
  drawWorld = function(ctx) return renderScene(ctx) end,
})
```

Three draw stages, each optional; a record needs at least one:

| stage | signature | runs |
| --- | --- | --- |
| `drawWorld` | `(ctx) -> canvas \| nil` | instead of the flat/tilt world pass |
| `worldPresent` | `(canvas, ctx) -> canvas` | over the world, **before** the UI composites |
| `present` | `(canvas, ctx) -> canvas` | over the whole frame, world and UI alike |

`worldPresent` is the one to reach for when an effect must leave dialog
boxes and menus crisp — a depth-of-field or colour grade on the world only.
`present` is for effects that genuinely own the screen, like a CRT curve.

`ctx` carries the frame: `state`, `cam`, `vw`/`vh` (world-pixel view),
`width`/`height` (window pixels), `scale`, `level`, `paletteFor(map)` and
`spriteColors(map)`. It also carries `ctx.drawFx(project, scale)` — call it
with your own projection and the engine draws every active field effect
(the "!" bubble, the Poké Center heal machine, the Fly bird, the fishing
rod, Rock Tunnel darkness) at its correct anchor under your camera. There
is exactly one copy of each effect, so a new engine effect works in your
pipeline without you touching anything.

Three rules worth knowing:

- **`gate` governs input, never the draw.** It decides whether the player
  may *change* the mode (default: free-roam overworld only). A mode that
  stopped rendering during a warp would flash the flat 2D world every time
  the player walked through a door.
- **`available` is re-read every frame** and is the only thing that decides
  whether the mode can render at all. Answer `false` on a headless run or a
  driver with no depth canvas and the engine silently keeps the vanilla 2D
  path — which is why shipping a pipeline enabled is safe.
- **A callback that throws retires its pipeline**, attributed to your mod in
  the manager's error feed, and the frame falls back to 2D. A broken
  renderer costs the player a display mode, never the game.

Returning `nil` from `drawWorld` is a normal answer meaning "not this
frame"; the engine draws the vanilla world instead.

## Variable-size overworld sprites

The `sprites` registry keeps the vanilla 16x16 grounded walker as its default,
but a mod can describe any frame rectangle and anchor for player characters,
NPCs, followers, mounts, vehicles, bosses, or other field actors:

```lua
mod.content.sprites:register("SPRITE_COMPANION", {
  image = "mods/example/companion.png", -- one frame per row
  frames = 6,
  walker = true,
  frameWidth = 32,
  frameHeight = 32,
  anchorX = 16, -- frame-relative bottom-center anchor
  anchorY = 32,
})
```

`frameWidth` and `frameHeight` are sheet pixels. `anchorX` and `anchorY` are
measured from each frame's top-left; when omitted they default to the frame's
horizontal center and bottom edge, so a larger sprite grows upward while its
feet stay on the same world cell. Omitting all four fields is exactly the
vanilla 16x16 placement. The normal player/NPC/follower draw paths consume
these values automatically, including horizontal flips and the fishing pose.

Custom render pipelines can use the same geometry without reproducing the
pose rules:

```lua
local geometry = sprite:getPoseGeometry(facing, walkPhase, stepFlip)
-- geometry.quad, .x/.y/.width/.height, .anchorX/.anchorY, .mirror
local originX, originY = sprite:getScreenOrigin(px, py, camX, camY)
```

`getFrameGeometry(frame)` is the corresponding accessor for a specific
zero-based sheet frame. Both accessors return fresh tables and share the
renderer’s frame selection and mirror conventions.

## Battle sprite scaling

The enemy's front pic draws at 1x and the player's back pic at 2x, the way
the Game Boy did. A mod can override either, per species or per image.

Per species, on the `pokemon` record:

```lua
-- MEW's back pic renders 1.5x; its front pic is untouched
mod.content.pokemon:patch("MEW", { battleScaleBack = 1.5 })
```

`battleScaleFront` scales the enemy pic, `battleScaleBack` the player pic;
both take a number in `0.25 .. 4.0`.

Per image, on the `battle_sprite_scales` registry, keyed by the asset path
exactly as the data references it:

```lua
mod.content.battle_sprite_scales:register("abra_back", {
  path = "assets/generated/battle/back/abrab.png",
  scale = 1.5,
})
```

An image-level entry beats the species scale for that one pic, and it is
the only way to scale a pic that is not species-keyed — the player's
trainer back sprite, held on screen until "Go!", is a bare image path.

The resolution order at draw time is **image-level → species-level →
default** (1x front, 2x back).

- **The pic stays grounded at every scale.** The player pic keeps its feet
  flush on the text-box top (`y = 96`); the enemy pic keeps its bottom edge
  and horizontal centre pinned in its 7×7 slot. A larger pic grows upward
  and outward from that anchor, never off the shelf.
- **Scaling composes with the send-out grow.** The `AnimateSendingOutMon`
  ball-to-pic grow multiplies your scale through each stage, so a rescaled
  mon still grows into place from the ball, grounded the whole way.

## Installation-scoped generated cache

Generated data derived from a validated user source often belongs to the mod
installation rather than to one Pokémon save. `mod.cache` is that namespace:

```lua
local ok, err = mod.cache:write("extract/v1/arena.bin", encodedArena)
local bytes, err = mod.cache:read("extract/v1/arena.bin")
local info = mod.cache:info("extract/v1/arena.bin")
mod.cache:delete("extract/v1/arena.bin")
```

The physical root is engine-owned (`mod_cache/<mod-id>/`) and never exposed to
the mod. Keys are safe relative paths and a single write is capped at 64 MiB.
The cache does not rewind with checkpoints and is not scoped to game version,
slot, or playthrough. The mod owns its generated format, fingerprints, rebuild
policy, and completion marker; the engine treats the bytes as opaque data.

Use `mod.storage` instead when the data belongs to one playthrough. Use
`mod.cache` when it is a reproducible installation artifact that can be rebuilt
from a declared user source.

## Durable tool storage and runtime checkpoints

`mod.save` remains the right place for state that should travel with the next
normal Pokémon SAVE. Tools that need independently written, larger data-only
records can use `mod.storage`; the engine scopes every logical key by game
version, opaque playthrough identity, and mod id, and routes it through the same
standard or portable persistence backend as saves:

```lua
local context, code, message = mod.storage:context(game)
local ok, code, message = mod.storage:write(game, "history/quick/q0001", {
  format = 1, createdAt = os.time(), payload = { money = 3000 },
})
local value, code, message = mod.storage:read(game, "history/quick/q0001")
local keys, code, message = mod.storage:list(game, "history/quick")
local deleted, code, message = mod.storage:delete(game, "history/quick/q0001")
```

For independently generated binary data, use the opaque byte methods. They
accept and return the exact Lua string of bytes, including NUL bytes and bytes
that are not valid text:

```lua
local ok, code, message = mod.storage:writeBytes(
  game, "cache/maps/pallet/terrain", encodedMesh)
local encodedMesh, code, message = mod.storage:readBytes(
  game, "cache/maps/pallet/terrain")
```

Opaque values are limited to 512 MiB per key. The engine stores them without
decoding, compression, or an engine-defined file format, and never executes
them. A consuming mod owns validation of its format, fingerprint, checksum,
and compression metadata. Byte writes are staged and compared byte-for-byte
before replacement, and reads can recover a valid backup after an interrupted
write. Existing table values and opaque byte values use one shared logical key
space; delete a key before changing its value from one type to the other.

`context` returns `{ engineVersion, gameVersion, playthroughId }`. The engine
version is compatibility metadata; physical launcher-slot and path identity stays
private. A title-selected context may additionally contain `normalSavedAt`, the
validated matching ordinary-save chronology only; it never exposes normal-save
progress or a slot/path handle.

At the title screen only, `mod.storage:selected(game)` returns a bound storage
facade for the launcher-selected existing playthrough, or `nil, code, message`.
Resolving this facade is non-allocating: it never allocates an identity, adopts a
fresh New Game, or exposes a slot id/path. Its `context()`, `read(key)`,
`write(key, value)`, `readBytes(key)`, `writeBytes(key, bytes)`,
`list(prefix)`, and `delete(key)` methods have the same scoped and
transactional contract as `mod.storage`, but remain restricted to the calling
mod's selected existing namespace. It is intended for title tools that need to
browse or manage durable history before the first normal SAVE.

Table values must contain serializable data only. Opaque values must be Lua
strings. Keys are conservative slash-separated segments (letters, digits, `_`,
`-`); paths and filesystem handles are never exposed. Table writes are staged
and decode-verified; opaque writes are staged and byte-verified; reads recover
from a valid staged/backup generation. Methods return structured errors for
normal data, byte validation, and I/O failures. The playthrough identity is
allocated lazily on the first storage/checkpoint call, so an unused API changes
no save bytes.

`mod.checkpoints` captures and reconstructs engine-owned semantic runtime state:

```lua
local capability = mod.checkpoints:inspect(game)
if capability.canCapture then
  local checkpoint, code, message = mod.checkpoints:capture(game)
  -- Store the detached data-only checkpoint through mod.storage.
end

local ok, code, message = mod.checkpoints:restore(game, checkpoint)

-- After the tool has durably committed its first checkpoint, make a
-- never-saved playthrough reachable through ordinary title boot exactly once.
local anchored, anchorCode, anchorMessage =
  mod.checkpoints:ensureNormalSave(game, checkpoint)
```

Checkpoint format 1 supports settled overworld control and proven battle
player-decision safe points. Ordinary single-player wild/trainer encounters are
supported. Scripted story battles are also supported when the engine can detach
their current built-in battle command and data-only row continuation, rebind any
NPC by stable id, and resume the story through a fresh runner. The suspended Lua
coroutine is never serialized. Link, Safari, ghost, demo, opaque callback,
non-data-only script, animation, message, queue, concurrent-script, and
forced-action phases fail closed. New checkpoints preserve gameplay RNG, while legacy overworld records
without RNG remain loadable. Capture excludes global options and runtime
objects. Restore validates format, game/playthrough identity, content,
coordinates, battle relationships, continuation, and RNG before mutation;
preserves current options; suppresses normal map-entry/save-load/intro side
effects; verifies a recapture; and rolls back runtime plus RNG in memory if
reconstruction fails. Callers that need crash recovery should durably capture
their own recovery checkpoint before restore.

Checkpoint ownership follows the persistence model rather than mod identity:

- canonical `game.save` progress, including every mod's `save.modData` /
  `mod.save` bucket and data-only fields added to saved Pokémon, rewinds;
- global and per-mod options remain at their current values;
- independently written `mod.storage` records do not rewind; and
- mod-owned runtime objects, references, and caches are never serialized.

Successful restore emits `checkpoint.restored` only after reconstruction and
differential recapture have committed. Mods that cache rewound progress or hold
references to reconstructed runtime objects can re-read their own public state
and rebuild at that point:

```lua
mod.events:on("checkpoint.restored", function(ev)
  -- ev.kind is "overworld" or "battle"; ev.game is fully reconstructed.
  cachedQuestStage = mod.save:get("quest_stage", 0)
  rebuildRuntimeFor(ev.game, ev.kind)
end)
```

The event is not emitted for validation failure, failed reconstruction, or a
successful rollback. Its payload contains no checkpoint data or other mod's
private state. A mod that deliberately stores progress-coupled truth in
`mod.storage` must version and reconcile that relationship itself; the engine
cannot distinguish it safely from independent history, configuration, or cache
data.

`mod.checkpoints:resume(game, checkpoint)` is the title-session counterpart to
live `restore`. It validates the same data-only checkpoint against the
engine-selected existing playthrough, reconstructs only after all validation
passes, preserves current options, and verifies by recapture. A title session
has no live gameplay rollback state: if reconstruction or verification fails,
the engine rebuilds a usable title session and returns `false, code, message`.
It never rewrites a normal Pokémon save. It is unavailable outside title and does
not broaden capture or arbitrary-frame support.

`mod.checkpoints:ensureNormalSave(game, checkpoint)` is a separate live-runtime
operation for durable checkpoint tools. It creates ordinary progress only when
none exists, only after validating that the supplied checkpoint is the exact
current safe runtime, and through the normal atomic save lifecycle. Once an
ordinary save exists it returns `true, "already_exists"` without writing, so
subsequent checkpoints and the player's later SAVE commands remain independent.
Call it only after the tool's own checkpoint/index commit; treat an anchoring
failure as a failed first checkpoint rather than claiming restart safety.
See RFC 0003, RFC 0004, RFC 0005, and RFC 0006 for exact contracts and error
codes.

At that same settled supported wild/trainer decision boundary, a tool may claim
START through `battle.menu_auxiliary`. It receives `(next, game, context)`, where
`context` is the data-only `{ kind = "wild" }` or `{ kind = "trainer" }`; it
never receives the live battle controller. Return `true` to consume START after
opening source-owned UI, or call `next(game, context)` to allow lower-priority
handlers. With no handler, START remains inert. Ordinary encounters and the
validated built-in scripted battle origins described by RFC 0005 are eligible;
opaque scripts, link/Safari/ghost/demo battles, action queues,
animation/messages, forced choices, and every phase that cannot safely be
checkpointed remain excluded. Exceptions are contained by normal hook isolation
and fall through without advancing a turn.

Gen 1 trainer encounters also expose `trainer.before_battle` after the
challenge text and immediately before battle construction. This lets a mod
defer the encounter while it collects a player choice through a registered
screen, then resume with a battle-local view of the save party:

```lua
mod.hooks:wrap("trainer.before_battle", function(next, game, context, continue)
  -- context = { trainerClass, partyIndex, mapId, npcId }
  mod.ui.push(game, "party_registration", {
    onConfirm = function(indices)
      continue({ playerPartyIndices = indices })
    end,
    onCancel = function()
      continue({ cancel = true })
    end,
  })
  return true
end)
```

Return `true` only when retaining `continue` for a later callback. Calling
`continue({ cancel = true })` ends the encounter without constructing a battle;
the normal encounter completion callback returns control to the overworld and
no trainer-defeated state is written. A cancelled sight encounter is suppressed
at the current player cell so it cannot immediately reopen; moving one cell or
talking to the trainer permits a new challenge. Calling `continue()` uses the
full save party; passing
`{ playerPartyIndices = { 2, 4, 5 } }` uses those ordered, one-based party
members for initial send, switching and forced replacement, exhaustion,
experience traversal, and battle party displays. The continuation is one-shot.
An empty, duplicate, out-of-range, or otherwise malformed list safely falls
back to the full party. The view references the original Pokemon records and
never reorders or replaces `game.save.party`; trainer battle checkpoints retain
the selected indices. Mods remain responsible for selection policy and should
use only public `mod.ui`, hook, and save APIs. See RFC 0010 for the exact
contract and compatibility guarantees.

Both battle engines expose the guarded `battle.charge_required` hook when a
charge-capable move is selected for its initial turn and the active ruleset
would otherwise charge it. The wrapper receives `(next, ctx)`, where `ctx` is
`{ battle, user, target, move, charge = true, isCalled }`. Return `false` to
skip only that initial charge and continue through the ordinary move pipeline;
call `next(ctx)` to keep it. The hook does not run for the release turn or when
the active ruleset already skips charging (for example, Gold Solarbeam in
sun). PP use, accuracy, damage, animation, and secondary effects remain owned
by the engine. With no subscriber, the vanilla decision runs without building
the hook context.

## Developer console

Boot with developer mode on to unlock the in-game console and hot-reload
hotkeys. Either set `POKEPORT_DEV=1` in the environment or pass
`--developer` on the command line:

```sh
love . --developer
```

While developer mode is active:

- `` ` `` (backtick) opens the console overlay — a Lua REPL with `game`,
  `data` and `mods` in scope. Press `` ` `` again to close it.
- `F5` hot-reloads mods and asset caches without restarting.

The console understands these verbs (anything else is evaluated as Lua):

- `warp MAP [x y]` — teleport to a map (default cell 5,5).
- `give ID [n|level]` — add an item (count) or a Pokémon (level).
- `flag NAME [on|off]` — read or set an event flag.
- `party` — dump the current party.
- `mods` — list loaded mods and their state.
- `reload` — hot-reload mods (same as `F5`).
- `trace PAT | trace off` — trace events/hooks matching a glob pattern.
- `help` — list the verbs.

## Tool input and title-menu hooks

Tool mods that need to act once per game logic tick can wrap `input.step`.
It runs immediately before queued button edges are promoted, so input added by
the wrapper is visible during that same fixed step. The callback receives
`(next, game, dt)` and must call `next(game, dt)`.

`input.pointer` delivers uncaptured gameplay pointer events -- touches and
real mouse input alike. The callback receives `(next, game, ev)` where `ev`
is `{ phase, source, id, x, y, gameX, gameY, insideGame, dx, dy, pressure,
button }`: `phase` is
`"pressed"`, `"moved"`, `"released"` or `"cancelled"`; `source` is `"touch"`
or `"mouse"`; `id` is the LÖVE touch id or `"mouse"`; and the coordinates
`x` / `y` are LOVE window units, while `gameX` / `gameY` are local to the
active game viewport and `insideGame` says whether the pointer is inside it.
Without a custom viewport both coordinate pairs are identical. The on-screen
touch controls keep first refusal: a
pointer that begins on a virtual control belongs to the pad for its whole
lifecycle and never reaches the hook, while one that begins outside stays
visible even if it later crosses a control. A real mouse reaches the hook
without `POKEPORT_TOUCH` (synthesized `istouch` mouse twins are dropped, so
a mobile touch fires once), and focus or visibility loss and input recovery
deliver a `"cancelled"` for every pointer the hook saw pressed but not yet
released. Return `true` without calling `next` to consume the event.

`mod.input` presses GB buttons source-safely. `mod.input:tap(game, btn)`
queues exactly one `wasPressed` edge for the next fixed step and holds
nothing; `local token = mod.input:press(game, btn)` holds the button until
`mod.input:release(token)`. Buttons are `up`, `down`, `left`, `right`, `a`,
`b`, `start` and `select`. Every press is its own input source inside the
engine's multi-source bookkeeping, so releasing a token never clears a hold
the keyboard, a controller, the touch overlay or another mod still owns;
`release` is idempotent and refuses tokens taken by another mod.
Outstanding tokens are released automatically on entry-chunk rollback, hot
reload and input recovery.

`ui.title_menu.items` receives `(next, game, items)` and follows the same
decorate-after-`next` convention as `ui.start_menu.items`. It is the safe place
for a tool to offer a fresh-session action before gameplay begins.

Ephemeral tools can wrap `save.write(next, game)` and return `false` to veto a
progress write before world state is captured or any bytes reach disk.

`render.hud` receives `(next, game, viewport)` after the finished game frame is
composited and before touch controls draw. The window-space viewport contains
`width`, `height`, `gameX`, `gameY`, `gameWidth`, `gameHeight`, `scale`, `dpiX`,
and `dpiY`, so a tool can use the letterbox margins without drawing over the
playfield or pushing an updating game state.

`render.viewport` lets a layout mod reserve the window-space rectangle in which
the game renders. It receives `(next, ctx)` with the full window's `width`,
`height`, `pixelWidth`, `pixelHeight`, `dpiX`, `dpiY`, and `generation`, and
returns `{ x, y, width, height }`. The engine clamps that rectangle to the
window and makes game layout, safe-area calculations, and rendering use it as
their display. Set `capture = true` to request a composition canvas even when
the rectangle fills the window. With no subscriber, no canvas is allocated and
the normal presentation path is unchanged.

When a viewport is active, `render.window` receives `(next, game, ctx)` after
the game frame has been captured. `ctx` contains its `canvas`, `x`, `y`,
`width`, `height`, the full `windowWidth` / `windowHeight`, `dpiX`, `dpiY`, and
`generation`. Calling `next(game, ctx)` draws the game at the requested origin;
a wrapper may instead compose that canvas with its own UI. Touch controls remain
full-size OS-window chrome and draw after this hook.

`render.compose` wraps the whole-window composite in `Renderer:endFrame`. It
receives `(next, renderer, ctx)`; returning `true` without calling `next` hands
the mod full control of the window, while calling `next` runs the engine's
normal single-window composite so the mod can decorate around it. `ctx` carries
the finished `worldCanvas` and `uiCanvas` with their SGB `zones` / `worldZones`,
`worldActive`, the frame metrics (`ww`, `wh`, `pw`, `ph`, `ox`, `oy`, `vpw`,
`vph`, `scale`, `Sx`, `Sy`, `dpiX`, `dpiY`), `renderer:blitCanvas(...)` for a
palette-correct blit of either canvas into an arbitrary screen rect, and the
`secondScreen` bridge (`available()` / `detected()` / `push(...)` /
`pollTouch()` / `setEnabled`) for driving a second physical display.
`detected()` reports a connected target even while its output is being created;
`available()` means it can accept a frame now. `push(imageData, w, h)` retains
the original contract. Its optional `background` (`0xRRGGBB`) and `preference`
arguments request an extended presentation; a preference ending in `:cover`
fills and crops the target, while other values preserve the whole frame.
Android also accepts `handheld` or `secondary` (with an optional `:cover`
suffix) as routing hints; unsupported or unavailable targets fall back to the
other connected display.
`pollTouch()` returns the oldest queued event as `"action,x,y"` in submitted-frame
coordinates, or `nil`.
This is what lets a mod lay the two passes out as two stacked Game Boy screens,
or push one onto a second screen, without the engine knowing the layout.
On process-capable Windows, Linux and macOS hosts without a native display
bridge, enabling this facade opens a second resizable app window instead. It
uses the same `available`, `detected`, `push`, `pollTouch` and `setEnabled`
contract, so a mod does not need a desktop-specific rendering path.

`render.output_enabled` and `render.output` are the later, whole-window seam
for mods that need the engine's normal composite rather than its separate
layers. It runs after registered present pipelines and before GBCFX,
`render.hud`, and touch controls. A mod wraps both hooks: the first returns
`true` only while output ownership is needed, and the second receives
`(next, ctx)` with `canvas`, `width`, `height`, `gameX`, `gameY`, `gameWidth`,
`gameHeight`, `scale`, `dpiX`,
`dpiY`, and `generation`. Returning `true` from `render.output` takes over the
window; calling `next(ctx)` keeps the normal presentation. Both hooks default
to `false`. Enabling the seam requires a full-window canvas for that frame.
With no `render.output` subscriber, or while `render.output_enabled` is false,
the existing presentation path is unchanged. `render.compose` takes precedence
when it owns the frame.

`screen.render_visible` receives `(next, state)` while the main screen is being
composed. Return `false` to omit that state from drawing, opacity selection and
palette-zone ownership. The state remains on the stack and keeps its normal
update and input ownership, so a mod can mirror a native menu on another
display without reimplementing it. The default is `true`. Treat the wrapper as
a pure predicate: the renderer may ask it more than once per frame.

Scrollable list states expose `state.kind` for use with this hook. Generic
lists fall back to their title; PC lists use stable, localization-independent
identifiers: `pc_box_withdraw`, `pc_box_deposit`, `pc_box_release`,
`pc_box_change`, `pc_item_withdraw`, `pc_item_deposit`, and `pc_item_toss`.

`battle.bottom_ui_visible` and `battle.status_hud_visible` independently
control the battle text/menu layer and the HP/status panels. Both receive
`(next, state)` and default to `true`, so vanilla rendering is unchanged.
Both hooks apply to Gen 1 and Gen 2 battles.
Text boxes and YES/NO prompts pushed above a battle inherit a `false` result
for that battle, so hiding the bottom layer cannot leave their white backing
behind under another overlay. Text boxes also pass through the hook as their
own state, preserving selective control outside a battle; a wrapper that only
owns battle presentation should return `false` only for its active battle or
text-box state.

`core.logic_speed` receives `(next, game)` once per `Game:logicSpeed()` call
(once per frame). Vanilla behavior resolves the per-category GAME SPEED
option (`GameSpeed.CATEGORIES`: overworld/battle/menu) for whichever
category `Game.speedCategoryInStack` says is active right now. A mod may
call `next(game)` and return its result to pass that resolution through, or
return a different number outright to override it for that frame (a bot mod
forcing 1X for one route segment, say, regardless of the category or saved
option). The result is clamped to the nearest valid `GameSpeed.LEVELS` entry
regardless of what a subscriber returns, so a bad value (0, negative, `nil`)
cannot destabilize the fixed-step accumulator. This hook runs *after* link
play's 1X lock and the `--speed`/equivalent run-argument override, both of
which stay unconditional and are never visible to a subscriber.

Developer mode also arms the mod loader's dev tripwire, which flags mods
that reach outside their permission set.

## Process-lifecycle hooks

These exist so a platform-specific launcher integration (a native shell
that embeds this engine and wraps its window in platform UI) can live
entirely in a mod instead of hand-patching `main.lua`, which every other
engine change also touches.

`core.update` receives `(next, game, dt)` once per frame from
`love.update`. Vanilla behavior is `game:update(dt)`, unconditionally. A
mod may skip calling `next(game, dt)` to pause the simulation for that
frame (e.g. while a native settings sheet is on top), and may run
additional per-frame polling before or after that call regardless of
whether it calls `next` -- useful for one-shot flags that must be observed
every frame even while paused.

`core.quit_to_launcher` receives `(next)` once from `love.quit()`. `next()`
returns the engine's own decision for whether closing the window should
return to the Lua launcher instead of exiting; a mod may return `false`
outright, without ever calling `next`, to veto that and let the process
really quit -- for a platform host that owns its own "return to launcher"
UI and would otherwise get looped straight back into the game it just
quit.

A manifest may also declare `force_enable_env`, an environment variable
name that re-enables the mod regardless of a saved disable in
`options.mods` when that variable is set to `"1"`. This is for a mod that
cannot function disabled on the one build where its env var is set (a
platform-bridge mod bundled only with that build's launcher, for example).

Neither hook needs a `Runtime.wantsHook` guard before calling it: `Hooks:call`
already falls straight through to the vanilla function when no mod has
wrapped the name, at negligible cost.

## Detached Pokémon icon presentation

`mod.ui.PokemonIcon.draw(game, summary, x, y, opts)` draws the same party icon
the native Party menu would resolve without exposing a live Pokémon record or
the private Party menu. `summary` is the detached data-only shape
`{ species = string, hp = integer, maxHp = integer }`; `opts.selected` and
`opts.counter` optionally request the native selected-icon animation phase.

The engine retains icon ownership. Content registered through
`mod.content.icons`, species `icon` definitions, asset overrides, and the
public `pokemon.icon` hook therefore continue to compose. Invalid summaries
return `false, code, message` and draw nothing. The helper is presentation
only: it does not expose moves, status, checkpoint payloads, or mutable party
state.

## Shared date and time presentation

The global Options menu owns `DATE FORMAT` (`DEVICE`, `DD-MM-YYYY`,
`MM-DD-YYYY`, `YYYY-MM-DD`) and `TIME FORMAT` (`DEVICE`, `24 HOUR`, `12 HOUR`).
These preferences live in `options.lua`, so checkpoint restore never rewinds
them. `DEVICE` uses the process time locale when the platform provides one;
the portable fallback is `DD-MM-YYYY` plus 24-hour time.

Mods format captured timestamps through the read-only public facade:

```lua
local date = mod.datetime:date(game, createdAt)
local time = mod.datetime:time(game, createdAt)
local both = mod.datetime:dateTime(game, createdAt)
```

The live `game` supplies only the current option context. Formatting never
mutates the save, options, or timestamp, and invalid timestamps return
`"----"`.

## Device power information

Sandboxed mods can read the host's battery state without receiving the rest
of `love.system`:

```lua
local state, percent = mod.device:powerInfo()
```

`state` follows LÖVE's values: `"unknown"`, `"battery"`, `"nobattery"`,
`"charging"`, or `"charged"`. `percent` is `0` through `100`, or `nil` when
the platform cannot report it. The facade is read-only and does not expose
URL launching, clipboard access, or other system operations.

## Real-world steps

On iOS and Android the game counts the player's real-world steps natively
(HealthKit / the hardware step counter). A mod reaches that bridge through
the `steps` permission in `manifest.json`, which the player sees in the
mod manager like every other permission:

```lua
if mod.steps:available() then
  mod.steps:sync()                -- async; OS consent sheet on first use
end
-- later, at a quiet moment:
local walk = mod.steps:poll()     -- { steps = n, from = ?, to = ? } or nil
```

`available()` is `false` on builds without the bridge (desktop) and for
mods without the permission, so a probe is always safe. `sync()` asks the
platform to refresh its count and returns whether there was a bridge to
ask. `poll()` returns the next delivery for this mod — the engine consumes
the native side's pending file itself, each permissioned mod receives its
own copy of a delivery, and steps are anchored natively so the same walk
is never delivered twice. Without the permission, `sync` and `poll` raise
an error naming it.

## Background HTTP

`mod.fetch` is how a mod does work off the main thread. It is behind the
`network` permission in `manifest.json`, the same one that gates
`require("socket")`, and the player sees it in the mod manager.

```lua
-- somewhere once
local job = mod.fetch:get("https://example.com/data.json")

-- in a hook or update, every frame -- poll never blocks
if job then
  local r = mod.fetch:poll(job)
  if r.status ~= "pending" then
    if r.status == "ok" then use(r.body) else warn(r.err) end
    mod.fetch:release(job)
    job = nil
  end
end
```

`get(url, opts)` returns an opaque handle, or `nil` plus a reason. `opts`
takes `accept` (a request Accept header) and `maxSeconds` (clamped to 30).
`poll(handle)` returns `{ status, body, err, progress }` where `status` is
`"pending"`, `"ok"`, `"error"` or `"cancelled"`; it is a copy, and it never
blocks, so calling it every frame is the intended use. `release(handle)`
frees a finished job — do it, or you will hit the ceiling. `cancel(handle)`
drops a result you no longer want. `available()` is `false` when the build
has no transport and for mods without the permission, so a probe is safe.

The rules worth knowing before you design around it:

- **http and https only.** The underlying transport also speaks `file://`,
  `ftp://` and `scp://`; those are refused, on the initial URL and on any
  redirect. `mod.fetch` is not a way to read a local file.
- **Four requests in flight per mod.** The worker pool is shared with the
  launcher's own downloads, so one mod cannot fill it. Over the ceiling,
  `get` returns `nil` and a reason until you release something.
- **Handles are yours alone.** A handle from another mod, a fabricated
  table, or a guessed number all poll as `"error"`.
- **Your mod id is in the User-Agent**, so a server operator can see who is
  calling and a mod cannot pose as the launcher.
- Jobs are released when your mod unloads.

This is deliberately not `love.thread`. A LÖVE thread is a fresh Lua state
with a full standard library that the sandbox cannot reach, so handing one
to a mod would undo every other rule; `mod.fetch`'s workers run engine
code, so a mod gets asynchrony without gaining any new reach.

## Log reporting

`mod.postLog(body, opts)` is the one-way exception to the rule that a mod
decides where it talks. It reports a debug/crash log to the https URL the
manifest declares in `log_url`, and it is the only API that may not be
pointed at a caller-chosen address:

```json
{
  "permissions": ["network"],
  "log_url": "https://logs.example.com/receive"
}
```

The URL is validated at load: it must be `https://`, and declaring it
without the `network` permission is a load violation for api 2 mods. The
destination is reviewed when the mod ships, not chosen per call, so a mod
cannot aim this at arbitrary hosts or read back anything a server replies.

```lua
-- fire and forget; poll() never blocks, same shape as mod.fetch
local job = mod:postLog("session crashed at 0x1f3a\n" .. logText)
```

`postLog(body, opts)` returns the same opaque handle as `mod.fetch:get`,
polled and released through `mod.fetch:poll` / `mod.fetch:release`. `opts`
is a closed list with one switch: `format`, either `"text"` (the default)
or `"json"`. `json` wraps the body in an envelope of `{ ts, mod, format,
body }` so a server can attribute and sort reports; any other key or value
is refused before a job is submitted. The body is capped at 64 KB, the
transfer is bounded by the same worker ceilings as `mod.fetch`, and the
response body is never returned to the mod.

## Background jobs

`mod.fetch` covers work waiting on a server. `mod.job` covers work waiting on
the CPU — generating a map, crunching a table, anything that would otherwise
stall a frame. It is behind the `background` permission in `manifest.json`.

Ship the job as its own file inside your mod:

```lua
-- mods/your_mod/jobs/crunch.lua
local arg = ...
local total = 0
for i = 1, arg.n do total = total + i end
return { total = total }
```

```lua
-- in your entry file
local job = mod.job:run("jobs/crunch.lua", { n = 1e6 })

-- later, in a hook -- poll never blocks
local r = mod.job:poll(job)
if r.status == "ok" then
  use(r.result.total)
  mod.job:release(job)
end
```

`run(script, arg, opts)` returns an opaque handle, or `nil` plus a reason.
`opts.maxSeconds` sets the job's time budget (default 5, clamped to 30).
`poll(handle)` returns `{ status, result, err }` with `status` one of
`"pending"`, `"ok"`, `"error"` or `"cancelled"`. `release(handle)` frees it.
`available()` is `false` on a host without threads and for mods without the
permission, so a probe is always safe.

**A job is pure compute.** This is the part to design around, not a detail:

- **Plain data in, plain data out.** Numbers, strings, booleans and tables of
  them. A function, userdata, a cycle or a table key that is not a string or
  number is refused at your `run` call with a reason. Nothing is shared —
  your argument is snapshotted, and mutating the original afterwards does not
  reach the job.
- **No engine API, no game state, no storage.** `require` is refused inside a
  job, and there is no `mod` object. A job cannot read the party, write
  `mod.storage`, or touch a registry. Get what it needs into the argument and
  act on the result back on the main thread.
- **Your script is a file in your mod folder.** The path goes through the same
  rules as `mod:read`; `..`, absolute paths and drive letters are refused.
- **Two jobs per mod, four on the machine.** Over the limit, `run` returns
  `nil` and a reason until you release one.
- **The budget bounds how long YOU wait, not how long the work runs.** Past
  `maxSeconds`, `poll` reports an error and the result is dropped if it ever
  arrives — but the thread runs to its own end. There is no way to stop a
  LÖVE thread from outside, and every attempt to stop one from inside was
  worse than the disease (a debug hook does not reliably interrupt LuaJIT,
  and raising from one wedged the whole process). `cancel(handle)` is the
  same deal: it drops the result, it does not stop the work.

  So **write jobs that terminate.** A job with an infinite loop will keep one
  core busy until the game closes. It will not freeze the game — the main
  thread stays responsive and quitting still works — but nothing will reclaim
  that core in the meantime.

Your job script runs in the same sandbox your entry file does, so `io`, `os`,
`debug`, `ffi`, `package` and `love.filesystem` are absent there too. That is
the whole reason this exists rather than `love.thread`: a raw LÖVE thread is a
fresh Lua state with a full standard library that the sandbox cannot reach, so
handing one to a mod would undo every other rule. Here the worker builds your
sandbox first and loads your chunk into it.

## Pre-sandbox globals (compat)

A mod written before the sandbox landed does not have to be updated to
load. `io`, `package`, `dofile`, `loadfile`, `os.getenv`, `love.filesystem`,
`love.system` and `love.event` are all present again as compat stand-ins
(`src/mods/LegacyCompat.lua`), and assigning a LÖVE callback
(`love.mousemoved = fn`) installs on the real table the way it always did.
Every stand-in call logs one warning naming its replacement, and
`loader:legacyReport(modId)` returns the same list with call counts, which
is what a "needs updating" badge should read.

The stand-ins are not the old globals. Paths are classified rather than
passed through:

- A path inside your own mod directory reads the file you shipped.
- Anything else, including an absolute path, resolves into a private
  per-mod overlay at `mod_compat/<your id>/` under the save directory.
  Two mods naming the same path never see each other's bytes, and nothing
  is written outside the game tree.
- A read misses through the overlay to your shipped file, then to
  `mod.storage`, so a half-migrated mod sees both.
- A write over a path you shipped shadows it; the packaged file is never
  modified, and `mod:read` still returns the packaged bytes.
- `love.filesystem.getSaveDirectory()` and `os.getenv("HOME")` answer with
  a virtual root, so a legacy mod that joins its own paths lands back in
  the same overlay.

`love.thread` stays refused. A LÖVE thread runs in a separate Lua state
with the full standard library, which the sandbox in this state cannot
reach, so a stand-in would be a hole rather than a reroute. The same goes
for `ffi`, `debug`, `setfenv`, `os.execute`, `io.popen`, `love.run` and
`love.errorhandler`. A mod that needs real background work needs an
engine-owned facility, not a compat shim -- for HTTP that facility is
[`mod.fetch`](#modfetch), which runs on the engine's own worker pool.
