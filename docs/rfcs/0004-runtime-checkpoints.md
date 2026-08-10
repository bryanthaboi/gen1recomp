# RFC 0004 — Stable runtime checkpoints for mods

## Status

Proposed. Engine: `Checkpoint.lua`, `Game.lua`, `OverworldController.lua`,
`Loader.lua`. Tests: `checkpoints.lua`, existing world and engine suites.

## Motivation

Mods can observe world events and request semantic actions, but no supported API
can capture canonical progress at a proven-safe runtime boundary or reconstruct
the overworld without replaying map-entry scripts. Reaching into the state stack,
controller, ScriptRunner, or save restore internals would bind distributable mods
to private objects and can duplicate story side effects.

The engine is the only component that can authoritatively decide whether the
runtime is settled and rebuild its controller objects. A generic checkpoint seam
lets tools store data-only records while keeping those responsibilities private.

## The decision it extends

Extends the public world/tool surfaces in `docs/modding.md`. It does not change
`mod.world`, normal CONTINUE, vanilla SAVE, or save lifecycle hooks/events.

## The exact API delta

Backward-compatible, additive-only. `Loader:_api` binds `mod.checkpoints`; mods
never receive `Game`, StateStack, controller, coroutine, renderer, or filesystem
internals inside a checkpoint.

### `mod.checkpoints:inspect(game)`

Returns a capability record. Stable overworld control returns:

```lua
{ canCapture = true, canRestore = true, kind = "overworld" }
```

A refusal returns the same booleans as `false` plus `kind`, `reason`, and a
player-readable `message`. Format-1 supports only an overworld whose controller
is topmost, player movement has settled on a tile, and no transition, foreground
or parallel ScriptRunner, queued script, scripted move, engagement, emote,
teleport, field animation, or similar partial controller mutation is active.

Refusal reasons are `not_in_playthrough`, `not_overworld`, `screen_busy`,
`transition_busy`, `script_busy`, `animation_busy`, and `movement_busy`.
Identity allocation is lazy and happens only after an active topmost overworld
has been established.

### `mod.checkpoints:capture(game)`

Returns a detached data-only format-1 checkpoint, or
`nil, code, message`:

```lua
{
  format = 1,
  kind = "overworld",
  identity = {
    engineVersion = "...", gameVersion = "red", playthroughId = "...",
  },
  save = { -- canonical dynamic progress, excluding global options },
  runtime = { overworld = {
    map = "PALLET_TOWN", x = 5, y = 6,
    facing = "down", surfing = false,
  } },
}
```

`engineVersion` is metadata for caller compatibility warnings; the engine does
not reject patch/minor mismatches on restore. Capture deep-copies through the restricted serializer before and after
`OverworldController:captureSave` synchronizes live map, tile, facing, and surf
state. It excludes `save.options`, functions, userdata, threads, metatables as
behavior, controller instances, and static content registries. Failure code
`capture_failed` covers non-data progress and synchronization errors.

### `mod.checkpoints:restore(game, checkpoint)`

Returns `true`, or `false, code, message`. Before mutation it requires the current
runtime to be capturable and validates a detached copy of the complete record:
format, kind, internal identity consistency, current game/playthrough identity,
map availability, integral in-bounds tile, facing, surfing, and synchronized save
position.

Validation codes are `invalid_checkpoint`, `invalid_content`, `unsupported_format`,
`unsupported_runtime_kind`, `wrong_game`, `wrong_playthrough`, `invalid_map`, and
`invalid_position`, in addition to the capability refusal reasons.

The canonical save validator runs against the detached record. Unlike ordinary
CONTINUE, a checkpoint never accepts a quarantine, remap, reclaim, clamp, or
repair: any such content change returns `invalid_content` before live mutation.

The engine captures an in-memory rollback checkpoint, preserves current global
options, then reconstructs semantic overworld state through
`Game:restoreCheckpointSave`. Checkpoint entry suppresses normal map exit/entry
events, `onEnter` scripts, forced-movement/current checks, and last-map rewrites;
it does not emit normal `save.loading`/`save.loaded` lifecycle events. After
reconstruction, the engine recaptures and byte-compares normalized data. A failed
apply rolls back and returns `restore_failed`; failure of that rollback returns
`rollback_failed`. Only after a successful comparison does the engine emit
`checkpoint.restored` with `{ game = game, kind = "overworld" }`. Validation
failure, failed apply, and successful rollback emit nothing.

Durable recovery remains a caller responsibility: in-memory rollback handles a
runtime exception, not process termination.

## Runtime boundary and future kinds

This RFC's original Level A contract intentionally rejects battles, menus,
transitions, animations, and suspended/queued scripts. RFC 0005 subsequently
adds a separately inventoried `battle` kind with deterministic RNG and
differential reconstruction tests; it does not broaden script or arbitrary-frame
support implied here.

## Migration note for existing mods

**Nothing required.** No existing hook, save, controller, or world action changes
when `mod.checkpoints` is unused. The reconstruction path is called only by a
successful public restore after validation. Mods whose runtime caches derive from
rewound `game.save` or `mod.save` state may optionally subscribe to
`checkpoint.restored` and rebuild from their own public state.

## Parity tests

- **No-mod:** the complete ROM-free engine suite and existing world behavior stay
  green; ordinary New Game/save/load allocates no checkpoint identity.
- **Public Mod API:** a real API-2 entry chunk proves stable inspection and every
  unsafe refusal, detached data-only capture, exact map/tile/facing/surf sync,
  `A -> mutate B -> restore A -> recapture A2` equality across representative
  progress, settings preservation, compatibility rejection without mutation,
  map-side-effect suppression, injected reconstruction rollback, mod-owned
  metadata and `mod.save` rewind, independent `mod.storage`/options preservation,
  and success-only runtime-cache reconciliation through `checkpoint.restored`.

## Deprecation etiquette

Nothing deprecated. This adds one public facade and a checkpoint-only semantic
reconstruction route.
