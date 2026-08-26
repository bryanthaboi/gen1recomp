# RFC 0017: Public mod developer-mode signal

## Status

Proposed.

## Motivation

The loader already derives a boot-time developer-mode flag for its permission
diagnostics and headless test seam. Gen 1's `Game` independently derives a
similarly sourced flag for its console and hot reload. A sandboxed mod cannot
read either one. `mod.commands` can register a diagnostic command but cannot
say whether the current boot is a developer boot. `mod.exports` only publishes
values to other mods. `game.ready` fires after entry registration and carries
only the game. `mod.options` is player configuration, not engine mode, and
`mod.log` logs unconditionally. The pre-sandbox compatibility
`os.getenv("POKEPORT_DEV")` deliberately returns `nil`, because the process
environment is hidden from mods.

The concrete consumer is **Adaptive Trainers**. Its approved Chapter 30 and
Phase H require trainer, boss, Rival, and League diagnostic views plus
seed-label tracing to exist only when `POKEPORT_DEV` is active. Without a
public signal, the mod must either ship those registrations in production,
misuse a player option, or import loader/Logger internals. All three violate
the approved observability boundary or the sandbox/public-API policy.

## Decision and plan extended

This implements **D-AT-005: diagnostics and seed tracing are admitted only by
the engine's developer-mode decision**. The consuming design is tracked in the
Adaptive Trainers implementation plan,
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md),
Task 9. The engine delta is generic and contains no trainer, balancing,
diagnostic-layout, seed-label, or Adaptive Trainers policy.

## Exact API delta

Every sandboxed mod object adds one field:

```lua
mod.developer -- boolean
```

The loader copies its existing `dev` decision into this field before invoking
the mod's entry chunk. It is therefore available for load-time registration:

```lua
if mod.developer then
  mod.commands:register("my_mod:diagnostics", diagnostics_command)
end
```

The value is a plain boolean snapshot, not a loader reference or environment
facade. `false` is the normal player-build answer. `POKEPORT_DEV=1` and the
`--developer` command-line path make the loader flag true; on Gen 1 those inputs
separately make `Game`'s own developer flag true for its console and hot
reload. The loader's existing injected `opts.dev` test seam changes only the
loader flag and diagnostics, not `Game` or its hotkeys. It grants no permission
and does not expose environment variables. The answer is fixed for the life of
that loader; changing a field on a mod's own table cannot change engine mode.

The field is generation-independent and has identical semantics on Red, Blue,
Yellow, Gold, and Silver. Gold and Silver do not gain Gen 1's developer console
or hot-reload hotkeys from this field.

## Migration and compatibility

Existing mods change nothing. `mod.developer` is additive, requires no
permission, and does not bump the integer mod API. Existing API-v1 and API-v2
entry chunks receive one extra scalar field and retain all prior fields and
methods unchanged. No name is removed or shadowed.

With no mods installed, `Loader:_api` is never called, so the delta allocates no
mod object and changes no data, save, options, event, hook, command, or file.
With mods installed in a normal boot, the new field is `false` unless an author
explicitly reads it. Existing registration and logging behavior is unchanged.

An adopting mod should gate developer-only registrations and verbose logging
directly on `mod.developer`. Player-facing behavior belongs behind
`mod.options`, not this signal.

## Verification

- `tests/engine/mod_developer_mode_test.lua` loads a real sandboxed mod through
  the public SDK with developer mode both on and off. It proves the boolean is
  available during entry execution and that the same source registers its
  diagnostic command only for the developer load. It also covers the
  command-line global path and a Gen 2 load.
- `tests/engine/mod_developer_mode_parity_test.lua` is the separate no-mod
  parity suite. It proves both developer answers discover no mods, create no
  files, and leave injected vanilla data unchanged. It also loads an unchanged
  API-v1 probe and verifies identity, `mod:read`, exports, and options behavior.
- The full ROM-free engine and modkit tiers remain the compatibility proof for
  `content.X:register/override/get`, `events:on`, `hooks:wrap`, `mod.log`,
  `mod:read`, manifest v1 fields, and `pokemon.before_give`.

No registry or schema changes are involved, so generated registry documentation
is unaffected.

## Deprecation etiquette

Nothing is removed, renamed, superseded, or deprecated.
