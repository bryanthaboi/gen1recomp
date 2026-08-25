# RFC 0018: `catch.party_full` — custody of a catch the party cannot hold

## Status

Proposed.

## Motivation

When a capture lands and the party already holds six Pokémon, the cart does
not ask the player anything: `AddPartyMon` fails and the mon goes to
`SendNewMonToBox` without a stop. The engine mirrors that —
`BattleState:storeCaughtMon` falls through to `Boxes.deposit` — and a game
mode has no way to stand in front of it.

That silence is wrong for any mode where the box is not a thing. A battle
royale locks the Pokémon Center PC for the whole match (the box is a second
health bar: deposit the healthy ones, fight with one, withdraw fresh ones),
so a seventh catch is deposited into storage the player cannot reach — the
mon is gone and everyone saw the fanfare. A Nuzlocke that counts a boxed mon
as lost, a randomizer that wants to hand out a replacement instead, a
challenge run that makes the player release someone for the catch — all want
the decision, and today there is no seam to catch it at.

The immediate consumer is a battle-royale mode, where the fix is the game's
own rule: at 6/6 you choose who makes room, and whoever leaves hits the
ground as a ball. Neither the decision nor the spill is specific to it.

## The decision it extends

This extends the **additive, guarded seam convention** Route B in
`CONTRIBUTING-mods.md` documents, and is gated by the parity guarantee
`tests/engine/gate_meta_coverage.lua` enforces. It sits next to
`catch.nickname` (RFC 0015) on the same capture path: that hook answers
*what the mon is called* once its home is decided; this one decides the home
when the party cannot hold it.

There is no in-repo D-number registry to amend.

## Exact API delta

### New hook: `catch.party_full`

```lua
mod.hooks:wrap("catch.party_full", function(next, ctx)
  -- ctx = { battle = <BattleState>, mon = <Pokemon>, name = <display name>,
  --         game = <Game> }
  if myMode.active then
    takeCustody(ctx.mon)      -- the mon is the mod's problem now
    return true               -- nothing is deposited
  end
  return next(ctx)            -- false: deposit, as today
end)
```

Call site: `BattleState:partyFullDestination(mon)`, called from the capture
path at the moment `AddPartyMon` has failed and `SendNewMonToBox` would run.
The vanilla link returns `false`. A truthy return skips the box entirely —
the mon is neither in the party nor in any box, and `pokemon.caught` reports
`destination = "mod"` so the mode can find its own custody again. Anything
falsy deposits as always, "But every BOX is full!" included.

The method returns `"box"` or `"mod"`, and is a *method* on purpose: the
compatibility seam for engines that predate this RFC needs a name to ask for
(see below), and `battleStyle`/`offerNickname` set the precedent.

### One event value, already emitted

`pokemon.caught`'s `destination` gains a third value, `"mod"`, next to
`"party"` and `"box"`. Nothing that reads the event today matches on it.

### No other surface changes

The call site is guarded by `Runtime.wantsHook`, and the vanilla link is a
file-local, so a build with nothing wrapped runs the branch exactly as
before and allocates nothing it did not allocate before.

## Migration

Nothing changes for existing mods. A mode that was fighting the box after
the fact — withdrawing the deposit it could not prevent, or eating the loss —
should wrap `catch.party_full` and take the mon at the moment of the catch.

## Verification

- `tests/modkit/cases/catch_party_full.lua` — through the public mod API:
  with no mod a 6/6 catch lands in the box with the transfer text; a wrapped
  mod that claims custody leaves the mon out of both party and boxes; a
  fall-through deposits; the hook's ctx carries the battle, the mon, the
  display name and the game.
- `tests/engine/gate_hooks.lua` — the name is in the live catalog and passes
  the no-mod parity gate (vanilla called exactly once, result unchanged,
  nothing allocated).
- `tests/engine/gate_meta_coverage.lua` — the name is covered by the unit
  corpus.

## Backward compatibility

Additive. No existing hook, event, registry or manifest field changes shape.
`storeCaughtMon`'s box branch keeps its text, its nickname offer and its
`pokemon.caught` emit; the only reader-visible difference with no subscriber
is one extra method on `BattleState`.

## Compatibility seam for older engines

The call site is mid-function, so a mod on a stock engine cannot see it —
the same problem `world.talk` has. The battle-royale mod's shim covers the
gap by wrapping `Boxes.deposit` (the one call the old branch makes that a
patch can reach): during a match it raises `catch.party_full` first, and a
claim refuses the deposit, so nothing reaches a box even there. The mod then
takes custody from the `pokemon.caught` emit, which carries the mon. What
the shim cannot repair is the text: the old branch answers a refused deposit
with "But every BOX is full!" before the mode's own prompt opens — the wrong
reason for the right decision, and the argument for the seam.
