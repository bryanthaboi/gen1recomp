# RFC 0006 — Generic process-lifecycle hooks for platform launcher integrations

## Status

Proposed. Engine: `PlatformHooks.lua` (new), `main.lua`, `Manifest.lua`,
`Loader.lua`. Tests: `tests/modkit/cases/platform_lifecycle_hooks.lua`,
`tests/mod_loader_tests.lua`, `tests/mod_manifest_tests.lua`.

## Motivation

A platform-specific launcher wrapper -- a native shell that embeds this
engine and owns its own UI around the game window (a mobile app shell,
say, presenting its own settings/import/save screens and only handing
control to the LÖVE window once play starts) needs three things no
current hook covers:

1. Pause the simulation while its own UI is on top of the game window.
2. Live-reload options it wrote from outside any Lua UI.
3. Veto `main.lua`'s "closing the window returns to the Lua launcher"
   behavior when the platform shell owns that job itself -- without this,
   a shell that re-fronts its own launcher UI on quit gets looped straight
   back into `HostShell.restart()`'s in-process reboot instead.

Implementing this by hand-patching `main.lua`'s `love.update`/`love.quit`
directly ties every such integration to editing the one file every other
engine change also touches, guaranteeing merge conflicts for any second
platform integration (or any unrelated engine PR landing around the same
time). No existing hook covers "should the per-frame simulation step run"
or "should closing the window return to the Lua launcher."

## The decision it extends

No prior D-number. Extends the hook-contract section of `docs/modding.md`
alongside `input.step`, `render.hud`, `screen.render_visible`, etc.

## The exact API delta

Backward-compatible, additive-only.

### `core.update`

New hook, `(game, dt) -> nil` through the public wrapper signature
`(next, game, dt)`, called once per frame from `love.update` via
`src/core/PlatformHooks.lua`'s `PlatformHooks.update(game, dt)`. Vanilla
behavior (used when no mod claims the hook) is `game:update(dt)`,
unconditionally -- identical to `love.update`'s behavior before this hook
existed. A subscriber may skip calling `next(game, dt)` to pause the
simulation for that frame, or do additional per-frame work before/after
calling it regardless of whether it calls `next`.

### `core.quit_to_launcher`

New hook, `() -> boolean` through the public wrapper signature `(next)`,
called once from `love.quit()` via
`PlatformHooks.quitToLauncher(vanilla)`. `vanilla` is the pre-existing
non-platform-specific decision (`Game and not Importer and not
quitToLauncher and not scripted and not launchedIntoGame`). A subscriber
may return `false` outright to veto returning to the Lua launcher (without
ever calling `next`, so the vanilla condition is never evaluated), or call
`next()` and return its result to pass the vanilla decision through
unchanged.

Neither hook is guarded by `Runtime.wantsHook` -- both fire unconditionally
every call, matching the existing `input.step` precedent
(`src/core/Game.lua`), since `Hooks:call` already fast-paths to a bare
`vanilla(...)` call when no mod has wrapped the name.

### `Manifest.force_enable_env`

New optional manifest field, a bare env-var name. `Loader:load` re-enables
a mod carrying this field whenever that variable is set to `"1"`,
regardless of a saved disable in `options.mods`. This exists for exactly
the mod class this RFC is for: a platform-bridge mod that ships only with
one build and cannot function disabled there, but must still behave like
every other mod (a manifest opt-in, not an engine special case) on every
build that doesn't set its variable.

## Migration note for existing mods

**Nothing.** With no subscriber, `love.update` still calls `Game:update(dt)`
unconditionally every frame and `love.quit()`'s restart-to-launcher
decision is exactly the pre-existing condition -- bit-identical to today's
behavior on every platform where no mod wraps either hook. A manifest with
no `force_enable_env` field behaves exactly as before.

## Parity tests

- **No-mod:** `core.update`'s vanilla runs exactly once per call with the
  hook chain empty; `core.quit_to_launcher`'s vanilla return value passes
  through unchanged. Both hooks are picked up automatically by the
  catalog-driven no-mod gate (`tests/engine/gate_hooks.lua`, which scans
  for `Runtime.call("...")` call sites), so neither needs a dedicated
  no-mod test file.
- **Mod-API:** `tests/modkit/cases/platform_lifecycle_hooks.lua` proves,
  through a fixture mod loaded via the public loader (not the engine's
  internals), that a subscriber can skip the vanilla update call (pause),
  run extra per-frame polling regardless of pause state, and veto the
  quit-to-launcher decision without the vanilla condition ever running.
- `tests/mod_loader_tests.lua` and `tests/mod_manifest_tests.lua` cover
  `force_enable_env`: a matching env var re-enables a mod saved as
  disabled, and an unset one leaves the saved disable alone.

## Deprecation etiquette

Nothing deprecated. These are two additive hooks and one additive manifest
field; `main.lua`'s only footprint is one `require` and two call sites
into `src/core/PlatformHooks.lua`.
