# RFC 0011: Charge-required battle hook

## Status

Proposed.

## Motivation

A battle-mechanics mod can change damage through `battle.damage` and register
move effects, but it cannot conditionally skip the first turn of an existing
charge move. In Gen 1, the engine decides and stores the charge continuation
before any public effect callback can run. Reaching into `user.charging`,
`user.chargeReady`, or generation-specific volatile state is private,
checkpoint-fragile, and would require a mod to duplicate move-pipeline policy.

Weather is the immediate example: a portable sun rule needs Solarbeam to
resolve on selection while leaving Fly, Dig, PP use, hit resolution, animation,
and secondary effects to the engine. The capability is generic and useful to
other ruleset and move-mechanics mods.

## Decision and plan extended

This implements **D-AT-002: charge-stage policy remains mod authority through a
generic guarded engine decision seam**. The consuming design is tracked in the
Adaptive Trainers implementation plan,
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md),
Task 8. The delta follows the additive, guarded hook convention documented by
Route B in `CONTRIBUTING-mods.md`; it contains no weather, move-id, trainer, or
Adaptive Trainers policy.

## Exact API delta

Both the Gen 1 and Gen 2 battle engines add this guarded hook:

```lua
mod.hooks:wrap("battle.charge_required", function(next, ctx)
  -- ctx = {
  --   battle = live battle controller,
  --   user = attacking battler,
  --   target = defending battler,
  --   move = merged move record,
  --   charge = true,
  --   isCalled = false,
  -- }
  if should_resolve_now(ctx) then return false end
  return next(ctx)
end)
```

The call site is the initial-use charge decision, after announcement and PP
handling but before charge state, invulnerability, charge animation, or charge
text is created. It runs only when the active engine rules would otherwise
require a charge. It does not run on the release turn. Returning exactly
`false` skips that initial charge and continues through the engine-owned move
pipeline. Any other downstream return preserves the charge. `isCalled` is true
when Metronome or Mirror Move selected the move.

Gold keeps its native sun decision first, so Solarbeam in native sun already
requires no charge and does not invoke the hook. Gen 1 link battles use the
shared Gen 1 move pipeline and therefore receive the same seam; normal link
mod-compatibility rules continue to govern deterministic peers.

The hot path first calls `Runtime.wantsHook("battle.charge_required")`. With no
subscriber, no hook payload table is allocated and the existing branch runs
unchanged.

## Migration and compatibility

Existing mods change nothing. The hook name and payload are additive. With no
wrapper installed, Red, Blue, Yellow, Gold, and Silver retain their previous
charge state, PP use, text, animation, accuracy, damage, and native weather
behavior. Existing charge-move data and effect records require no migration.

A mod adopting the seam should call `next(ctx)` unless it deliberately wants to
skip this charge. It should not mutate private charge fields or re-run the move.

## Verification

- `tests/engine/battle_charge_required.lua` exercises the real Gen 1 and Gen 2
  engines through a sandboxed public mod, including false-to-skip, next-to-keep,
  release-turn behavior, called-move PP semantics, shared payload shape, and
  native Gold sun behavior.
- The same test proves no-mod charge/release parity and replaces
  `Runtime.call` with a sentinel behind a false `Runtime.wantsHook` guard.
- `tests/engine/gate_hooks.lua` discovers the new catalog name and proves empty
  chains preserve vanilla values and allocation behavior.
- `tests/engine/gate_gen2_mod_api.lua` requires a guarded site in both
  generations and keeps the compatibility reference list complete.

## Deprecation etiquette

Nothing is removed, renamed, superseded, or deprecated.
