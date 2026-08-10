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

Regenerate the reference straight into a wiki checkout:

```sh
luajit tools/gen_registry_docs.lua ../gen1recomp.wiki
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
read-only snapshots; mods choose which layers to render.

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

`context` returns `{ engineVersion, gameVersion, playthroughId }`. The engine
version is compatibility metadata; physical launcher-slot and path identity stays
private.

Values must be tables containing serializable data only. Keys are conservative
slash-separated segments (letters, digits, `_`, `-`); paths and filesystem
handles are never exposed. Writes are staged and decode-verified, reads recover
from a valid staged/backup generation, and methods return structured errors for
normal data or I/O failures. The playthrough identity is allocated lazily on the
first storage/checkpoint call, so an unused API changes no save bytes.

`mod.checkpoints` captures and reconstructs engine-owned semantic runtime state:

```lua
local capability = mod.checkpoints:inspect(game)
if capability.canCapture then
  local checkpoint, code, message = mod.checkpoints:capture(game)
  -- Store the detached data-only checkpoint through mod.storage.
end

local ok, code, message = mod.checkpoints:restore(game, checkpoint)
```

Checkpoint format 1 supports settled overworld control and proven battle
player-decision safe points. Battle checkpoints are limited to ordinary
single-player wild/trainer origins with no suspended script; link, Safari,
ghost, demo, scripted, animation, message, queue, and forced-action phases fail
closed. New checkpoints preserve gameplay RNG, while legacy overworld records
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

See RFC 0003, RFC 0004, and RFC 0005 for exact contracts and error codes.

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
is `{ phase, source, id, x, y, dx, dy, pressure, button }`: `phase` is
`"pressed"`, `"moved"`, `"released"` or `"cancelled"`; `source` is `"touch"`
or `"mouse"`; `id` is the LÖVE touch id or `"mouse"`; and the coordinates
are LOVE window units, the same space `render.hud`'s viewport and the touch
overlay lay out in. The on-screen touch controls keep first refusal: a
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

`render.compose` wraps the whole-window composite in `Renderer:endFrame`. It
receives `(next, renderer, ctx)`; returning `true` without calling `next` hands
the mod full control of the window, while calling `next` runs the engine's
normal single-window composite so the mod can decorate around it. `ctx` carries
the finished `worldCanvas` and `uiCanvas` with their SGB `zones` / `worldZones`,
`worldActive`, the frame metrics (`ww`, `wh`, `pw`, `ph`, `ox`, `oy`, `vpw`,
`vph`, `scale`, `Sx`, `Sy`, `dpiX`, `dpiY`), `renderer:blitCanvas(...)` for a
palette-correct blit of either canvas into an arbitrary screen rect, and the
`secondScreen` bridge (`available()` / `push(imageData, w, h)` / `pollTouch()` /
`setEnabled`) for driving a second physical display. `pollTouch()` returns the
oldest queued event as `"action,x,y"` in submitted-frame coordinates, or `nil`.
This is what lets a mod lay the two passes out as two stacked Game Boy screens,
or push one onto a second screen, without the engine knowing the layout.

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
Pushed text boxes also pass through `battle.bottom_ui_visible`; a wrapper that
only owns battle presentation should return `false` only for its active battle
or text-box state.

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
