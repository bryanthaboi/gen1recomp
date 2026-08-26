# RFC 0012: `applyShare`'s announce argument on Gen 2

## Status

Proposed.

## Motivation

`battle.exp_award` hands a mod `ctx.applyShare(mon, split, announce)` on both
generations. On Gen 1 the third argument decides whether the mon's GainedText
box is printed (`src/battle/BattleState.lua`, `if announce then`), which is how
a mod that pays the whole party prints **one** summary line instead of a box
per recipient.

Gold accepts the argument and ignores it, as its own comment above the hook
call says. So the same mod source, running the same code, prints one line on
Red and six on Gold — one for the participant plus one for every bench mon it
paid.

This is not hypothetical. The [Exp Share](https://github.com/ShaneMcGovernIE/exp_share)
mod declares `"games": ["gen1", "gen2"]` and its description promises "a single
shared-exp line instead of one message per Pokemon". It passes `true` for the
fighters and `nil` for the bench, exactly as the Gen 1 seam asks. On Gold every
one of those `nil` calls announces anyway, so a five-mon party turns every KO
into six boxes to click through.

There is no mod-side fix. The announcement is emitted inside
`Battle:giveExperiencePass`, behind no hook, and a mod cannot ask for silence
because the argument that means "quietly" is discarded. The only workaround is
to intercept the battle's event queue afterwards and delete the boxes, which is
what a mod written for this had to do — a mod reaching into engine internals to
undo something the public seam should never have done.

## Decision and plan extended

This does not add a seam. It finishes one: `battle.exp_award` is documented as
"the same hook `BattleState:awardExp` calls on Gen 1 and with the same ctx",
and `docs/mod-api-gen2-compat.md` lists it among the hooks shared with Gen 1.
The third `applyShare` argument is the one part of that ctx whose meaning did
not survive the crossing, so the promise the catalog already makes is what this
change delivers.

The delta follows Route B's additive, guarded convention in
`CONTRIBUTING-mods.md`: nothing is renamed, nothing is removed, and no mod that
exists today changes behaviour.

## Exact API delta

`ctx.applyShare(mon, split, announce)` on Gen 2 now reads `announce`:

| Call | Gen 1 | Gen 2 before | Gen 2 after |
|---|---|---|---|
| `applyShare(mon, split)` | silent | announces | **announces** (unchanged) |
| `applyShare(mon, split, nil)` | silent | announces | **silent** |
| `applyShare(mon, split, false)` | silent | announces | **silent** |
| `applyShare(mon, split, true)` | announces | announces | announces |
| `applyShare(mon, split, "expAll")` | announces | announces | announces |

The argument is honoured **only when it is actually passed**, decided by
argument count rather than by value:

```lua
local function applyShare(mon, split, ...)
  local announce = ...
  local silent = select("#", ...) > 0 and not announce
  ...
end
```

`select("#", ...)` counts an explicit `nil`, so `applyShare(mon, split)` and
`applyShare(mon, split, nil)` are distinguishable — and they have to be, because
the first is a Gen 2-era call written against a seam that always announced, and
the second is a deliberate "pay this one quietly".

Only the `{ kind = "experience" }` event is affected. A silent award is still a
whole award: the exp, the stat exp, the `battle.exp_gained` event, the
`grew to level` line, learned moves and the interactive forget-a-move prompt all
happen exactly as before, in the same order.

Internally `Battle:giveExperiencePass` takes a sixth parameter, `silent`. It
defaults to announcing, so both of the cart's own passes are untouched.

## Migration and compatibility

**Existing mods change nothing.** A Gen 2 mod calling `applyShare(mon, split)`
gets the behaviour it was written against. A Gen 1 mod is untouched: no Gen 1
file is modified. The v1 surface — `content.X:register/override/get`,
`events:on`, `hooks:wrap`, `mod.log`, `mod:read`, the manifest v1 fields and
`pokemon.before_give` — is not involved; `mods/example_mew_starter` neither
calls this seam nor loads differently.

A mod that wants parity passes the argument explicitly, which is what the Gen 1
seam has always documented. Exp Share already does, and needs no edit to get
its own README's behaviour on Gold.

One residual difference is deliberate and now documented rather than silent: an
**omitted** third argument still means "silent" on Gen 1 and "announce" on
Gold. Closing that would change what an existing Gen 2 mod prints, which Route
B rejects. Passing the argument makes the two generations agree, so the rule an
author needs is one sentence: *say what you mean and both games do the same
thing.*

## Verification

- `tests/gen2_exp_share_test.lua` grows two sections and 14 checks, and the 23
  checks it already had are unchanged — which is itself the vanilla-parity
  evidence for this file.
  - **The no-mod test.** With nothing subscribed to `battle.exp_award`, a solo
    participant still prints one line and the EXP.SHARE double pass still
    prints both. The hot path is unchanged: `Runtime.wantsHook` still guards
    the ctx allocation, and `vanillaAward` never passes `silent`.
  - **The mod-API test.** The seam is driven through `hooks:wrap` on a real
    `Runtime.install`ed bus, not by calling internals: the omitted argument
    announces, an explicit `nil` and an explicit `false` are silent, a truthy
    value (including Gen 1's `"expAll"`) announces, the exp and stat exp paid
    are identical either way, and no `experience` event leaks into the queue on
    a silent pass.
- `tests/engine/gate_gen2_mod_api.lua` (943 checks),
  `tests/engine/gate_hooks.lua` (493) and `tests/engine/gate_events.lua` (529)
  pass unchanged; `battle.exp_award` was already in the shared catalog, so no
  gate list moves.
- `tests/gen2_battle_test.lua` (690), `gen2_battle_end_test.lua` (32),
  `gen2_battle_items_test.lua` (99), `gen2_badge_boosts_test.lua` (34) and
  `gen2_battle_loss_test.lua` (15) pass unchanged.

## Docs with the change

`docs/mod-api-gen2-compat.md` gains the `applyShare` reading beside the
existing `battle.low_health_alarm` payload note, in the same section that lists
`battle.exp_award` as shared — including the argument-count rule and the
residual difference above.

No registry or schema field changes, so `src/mods/Schemas.lua` is untouched and
`tools/gen_registry_docs.lua` has nothing new to emit.

## Deprecation etiquette

Nothing is removed, renamed, superseded or deprecated. The two-argument call is
not deprecated either — it keeps its current Gen 2 meaning permanently, and the
docs name the explicit form as the one that behaves the same on both games.
