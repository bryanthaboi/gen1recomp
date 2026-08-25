# RFC 0013: Conditional map occupancy and active-block reads

## Status

Proposed.

## Motivation

The Gen 1 Vermilion Dock script correctly ejects a player who enters after the
S.S. Anne has departed. A content mod can add a city-side route back to that
empty harbor, but it cannot preserve the dock visit: replacing the complete
dock handler would discard vanilla behavior and peer handlers, while an added
handler cannot cancel the base handler's ejection.

A mod that changes one active map block also needs to prove that it is looking
at the expected Red, Blue, or Yellow layout before it acts. `mapOverview()` is
intentionally presentation-oriented and does not expose block identity.
Requiring internal `Map` state or generated ROM data would cross the public mod
boundary and make a wrong-version edit difficult to fail closed.

## Decision and plan extended

This extends Route B in `CONTRIBUTING-mods.md`: new behavior is additive,
ordinary hook composition remains the authority, an empty hook chain is a
provable no-op, and mods receive copied or scalar data rather than mutable
engine state. It supports the approved Mew-under-the-truck implementation plan
without adding any Mew-specific rule, asset, flag, or content to the engine.

## Exact API delta

### `map.occupancy_allowed`

The post-departure `VERMILION_DOCK` script calls this hook after it replaces the
ship blocks with water and immediately before it would display the departure
message and warp the player to Vermilion City.

A wrapper has this shape:

```lua
function(next, game, context) -> boolean
```

The context is a new table with these fields:

| Field | Meaning |
|---|---|
| `mapId` | `"VERMILION_DOCK"` at this call site |
| `reason` | Stable reason key `"ss_anne_departed"` |
| `gameVersion` | Active save version (`red`, `blue`, or `yellow`) when present |
| `x`, `y` | Current player cell coordinates when present |

Vanilla returns `false`. The player remains only when the final chain result is
exactly `true`. Absent, throwing, or malformed wrappers therefore preserve
ejection. A wrapper composes by calling `next(game, context)` and returning
true when either downstream or its own narrow rule permits occupancy. The hook
does not replace `MapScripts` registration, merging, or dispatch, and does not
change the departure flag or reconstruct the ship.

As with every wrapper hook, a callback that does not call `next` intentionally
owns the final answer and does not run lower-priority callbacks. Permission
wrappers must call downstream to compose. A false, non-forwarding wrapper
safely denies occupancy and can suppress downstream permission by this normal
rule. A malformed final result also fails closed and cannot permit occupancy.

The call is guarded by `Runtime.wantsHook`, so an empty chain allocates no
context and follows the prior branch exactly.

### `WorldAPI:activeBlockAt`

Gen 1's public `mod.world` facade adds:

```lua
activeBlockAt(mapId, blockX, blockY) -> blockId
                                      | nil, reason
```

`mapId` must equal the active map ID. Coordinates are finite, integral,
zero-based block coordinates. A successful result is a numeric scalar copied
from the active runtime map. The method never returns the map's mutable block
array and never writes game or save state.

Failure reasons are stable:

| Condition | Reason |
|---|---|
| No active overworld map | `no overworld` |
| `mapId` differs from the active map | `map is not active` |
| Coordinate has the wrong type, is non-finite, or is fractional | `invalid block coordinates` |
| Coordinate is negative or outside the active map | `block coordinates out of bounds` |
| Active block data is absent or malformed | `block unavailable` |

The block slot and the active map accessor must both contain the same valid
nonnegative integer. Missing or sparse storage and inconsistent accessor data
return `block unavailable`.

Requiring the expected map ID and rejecting all ambiguous input lets a mod
compare every cell in its version-specific signature before it calls an
existing mutation API. Red, Blue, and Yellow each use their own loaded map
data. Gold does not gain this method in this RFC.

## Migration and compatibility

Existing mods change nothing. No hook, event, registry, manifest field, save
field, map handler, or WorldAPI method is removed or renamed. With no hook
subscriber the departed-dock behavior is unchanged. Existing callers cannot
invoke the new WorldAPI method accidentally.

The occupancy answer is not persisted by the engine. Disabling or uninstalling
a mod removes its wrapper through normal owner cleanup, so a later dock entry
uses vanilla ejection. The engine writes no new save state and neither API
returns or serializes ROM or save data.

## Verification requirements

The parity gate must prove:

- vanilla departed-dock message and warp remain with no subscriber;
- one permission wrapper can allow occupancy without removing the ship-erasure
  work or any map handler;
- multiple cooperative wrappers preserve downstream permission;
- absent, throwing, nil, false, malformed, and non-forwarding hook answers fail
  closed according to the normal wrapper-chain rule;
- Red, Blue, and Yellow contexts keep their version identity separate;
- disabling or removing the owner restores vanilla behavior without a save
  migration;
- `activeBlockAt` accepts only the active map and valid in-range integral
  coordinates, returns a scalar, and never mutates map or save state; and
- the test fixtures and resulting changes contain no ROM or save payload.

The hook must be driven through a real public `hooks:wrap` chain. The block API
must be exercised through a public `WorldAPI` instance. Tests must not replace
the production map handler with a test-only implementation.

## Docs with the change

`docs/modding.md` documents both contracts, their failure behavior, the
cooperative wrapper pattern, and the Gen 1-only block method. No registry or
schema changes occur, so generated registry documentation is unchanged.

## Deprecation etiquette

Nothing is removed, superseded, or deprecated.
