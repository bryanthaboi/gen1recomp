# RFC 0016: Engine-owned field residual descriptors

## Status

Proposed.

## Motivation

Battle-rule mods can keep deterministic data-only state in the public battle
field and observe `battle.turn_ended`, but that event fires after the engine's
residual and faint pipeline. A listener cannot safely deal end-of-round field
damage: directly changing live HP bypasses bar drains, faint messages,
experience, replacements, double-faint resolution, and checkpoint continuation.
Putting callbacks into `battle.field` is also rejected by the checkpoint
serializer, correctly, because executable state is not save-safe.

## Decision and plan extended

This implements **D-AT-004: public engine-owned field residual execution**, the
consuming decision required by Adaptive Trainers capability `ENGINE-FIELD-
RESIDUALS`. The plan is
[`docs/superpowers/plans/2026-08-14-adaptive-trainers.md`](https://github.com/MaxTomahawk/gen1recomp-adaptive-trainers/blob/main/docs/superpowers/plans/2026-08-14-adaptive-trainers.md),
Task 8. The engine delta defines only a generic end-of-round extension point;
it contains no weather names, immunities, damage formula, trainer identity, or
Adaptive Trainers policy.

## Exact API delta

Add the guarded Gen 1 hook:

```lua
mod.hooks:wrap("battle.field_residual", function(next, context)
  local rows = next(context)
  rows[#rows + 1] = {
    side = "enemy",
    amount = 7,
    message = context.battlers.enemy.name .. " is buffeted!",
  }
  return rows
end)
```

The hook runs once during an undecided battle's end-of-round processing, after
vanilla status residuals and before field/side token expiry and
`battle.turn_ended`. With no subscriber, the guarded site builds no context and
changes nothing. Vanilla contributes an empty list.

`context` is `{ field, battlers, turn }`. `field` is a strictly data-only view
with the same `{ weather, tokens }` shape captured by battle checkpoints. Its
recursive projection retains raw tables and finite numbers, strings, and
booleans under scalar keys. It strips metatables and omits functions, userdata,
threads, unsupported keys, and cyclic edges. Thus it exposes neither
`field.sides` nor a graph or executable callback back into live engine state.
`battlers.player` and `battlers.enemy` are detached snapshots with `{ side,
name, hp, maxHp, types, vanished }`. Changing either detached view cannot
change the live battle. `turn` is the current Gen 1 turn counter.

A result row is `{ side = "player"|"enemy", amount =
positive_finite_integer_number, message = optional_string }`. Numeric strings,
zero, negatives, fractions, NaN, infinities, malformed sides, and non-string
messages fail closed. Damage is clamped to current HP. The engine owns
mutation, HP-bar drain rows, and its existing faint pipeline. It applies every
accepted row before scheduling newly fainted battlers. If this hook batch
terminally faints the player with no healthy reserve, it queues only the player
faint authority, so descriptor order cannot race a blackout against an enemy
EXP/replacement path. Otherwise it schedules newly fainted battlers in fixed
player/enemy order. This precedence is scoped to this hook response; native
faint paths, including `enemyMonFainted`, keep their existing no-hook behavior.
Wrappers compose by calling `next(context)` and appending their own rows.
Callbacks are not part of the descriptor contract and hook functions are never
stored in the battle.

Gold already owns native weather and a generation-specific between-turn order;
this first additive call site is Gen 1-only. A future Gold site must keep the
same context and descriptor contract and choose its native ordering explicitly.

## Migration and compatibility

Existing mods change nothing. No hook name or payload changes. With no wrapper,
Gen 1 performs the same residual, token, event, and faint work as before,
including native simultaneous-faint resolution, and allocates no context. Gen
2 is unchanged. Existing and new checkpoints keep
serializing only the data stored in `battle.field`; hook callbacks remain
process-local loader state and are never serialized.

The v1 surface remains unchanged: `content.X:register/override/get`,
`events:on`, `hooks:wrap`, `mod.log`, `mod:read`, manifest v1 fields, and
`pokemon.before_give` keep their existing behavior.

## Verification

- The catalog hook parity gate proves null and live-empty buses return the
  vanilla list unchanged.
- A sandboxed fixture mod exercises the seam through `mod.hooks`, verifies the
  detached checkpoint-shaped context, applies damage, and reaches the engine
  faint pipeline.
- Engine validation tests cover strict number validation (including numeric
  strings, NaN, infinities, zero, and negatives), nested mutation isolation,
  omission of functions/userdata/threads/cycles and metatables from the public
  field projection, optional messages, non-table results, clamping, and
  settled-battle suppression.
- Both descriptor orders are driven through queue completion for a simultaneous
  terminal residual. Each proves player blackout loss with no EXP event,
  enemy replacement, or replacement UI.
- A disabled-bus sentinel proves the guard performs no `Runtime.call` or field
  context construction. An ordering probe proves the enabled hook runs after
  vanilla status residuals and before token expiry and `battle.turn_ended`.
- A no-hook native regression proves a simultaneous zero-HP state still enters
  the pre-existing enemy-faint EXP and win authority outside this hook batch.
- Capture/restore/capture evidence proves checkpointed field state round-trips
  while the enabled process-local hook remains installed and callable.

## Docs with the change

`docs/modding.md` documents the Gen 1 timing, detached payload, descriptor
validation, simultaneous-terminal result, and checkpoint boundary.
`docs/mod-api-gen2-compat.md` records that Gold does not yet expose the hook.
No registry or schema changes are involved, so generated registry docs do not
change.

## Deprecation etiquette

Nothing is deprecated. The hook is additive.
