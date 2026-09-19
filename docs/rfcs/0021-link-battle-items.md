# RFC 0021: `opts.items` — items on the link cable, for a mode that asks

## Status

Proposed.

## Motivation

A Gen 1 link battle runs under cable rules: no experience, no money, no
items. `LinkBattle` keeps them faithfully — its `openItems` prints "Items
can't be used in a link battle!" and the wire knows four action kinds
(move, struggle, locked, switch) plus RUN. That is right for the Cable
Club and wrong for every mode that is not the Cable Club.

The motivating case is a battle royale played over `LinkState.newFromSession`.
Its fights are link battles between two players' real, damaged parties, and
the loot on the ground — potions, X items, revives — is the whole economy of
the match: it is what you pick up, what you fight over, and what a fallen
trainer's bag spills. Against a bot the bag opens and the potion works;
against a person the same bag says "Items can't be used", and the one item
that does work is the POKé DOLL, only because RUN rides the wire and the
mode spends the doll on it. Players report it as a bug, because from the
chair it is one.

The mode cannot fix it. `submit`, `resolveLockstep` and the wire decoder are
closures inside `LinkBattle.new`; the instance exposes no way to put an
action on the cable. A mode could apply an item locally and send its own
message, but then it has to spend the turn, and there is no action that
means "nothing": `locked` decodes to the battler's held move on the peer
and to whatever object the mode passed on the user's side, which is the
one thing a lockstep must never do. A "free" item (no turn spent) breaks
the rules the other way — a heal *and* a move every turn. The seam has to
be in the engine, and it is a small one.

## The decision it extends

`LinkBattle.newHost` / `newGuest` already take mode-level options that the
Cable Club never sets: `turnLimit` (the tournament shot clock) and
`forceLevel`. `items` is one more of the same kind — off by default, so a
stock link battle is byte-for-byte the battle it was, and a mode that opts
in does so on both machines the way it already does for the clock.

It reuses rather than duplicates: the bag is `BattleState.openItems` (the
vanilla `BagMenu` against this battle, whose target picker already offers
the clamped copies through `battle.playerParty`), and the effect is
`ItemEffects.use`, the one dispatcher every fight uses. The single new
definition is *what the other machine does with it*, and it lives in one
module, `src/link/LinkItems.lua`, called from the two places a turn is
resolved (the participants' `resolveLockstep`, the observer's
`resolveSpecTurn`).

## Exact API delta

### `opts.items` on `LinkBattle.newHost` / `newGuest`

```lua
local battle = LinkBattle.newHost(game, net, {
  myParty = ..., theirParty = ..., theirName = ..., seed = ...,
  items = true,            -- the bag opens; an item is the turn's action
})
```

Default `nil`/`false`: cable rules, unchanged. With `items`:

- `battle.openItems` is `BattleState.openItems` — the bag, on this battle.
- `battle.itemUsed(messages, ctx)` — what `BagMenu` calls once an item has
  taken effect — no longer runs the single-player turn (the AI's move). It
  puts `{ type = "action", kind = "item", item = ctx.item, index = <slot of
  ctx.target in the user's party, or nil>, move = ctx.moveIndex }` on the
  wire as the turn's action, exactly as a switch is submitted.

`BagMenu` now hands that context to every `itemUsed` call (`ctx.item`,
`ctx.target`, `ctx.moveIndex`, alongside the existing `barShown`). A local
battle's `itemUsed` ignores the extra fields.

### One new wire action kind: `item`

Resolved before switches and moves on both machines and on a spectator:

- the side that used it already applied the effect to its own lockstep
  copies (the bag did, before the turn went out) and makes no attack this
  turn — `decodeWireAction` answers `nil` for `item`, as it does for a
  switch;
- the other side applies the same effect to *its* copies of that side
  through `LinkItems.apply`, which calls `ItemEffects.use` behind two
  facades: a battle whose `player` is the user's battler and a save whose
  `party` is the user's copies. Nothing is consumed there — the bag that
  was spent is on the user's machine.

The per-turn state hash is unchanged in shape and still agrees: every
effect reachable in a battle is deterministic (no roll in `ItemEffects`),
and both simulations apply it before the turn's first move.

### ...and the wire schema has to name its fields

`Wire.sanitize` rebuilds every inbound message field by field from
`SCHEMAS[type]` and drops anything the schema does not name, so a new
field on an existing message type is invisible until the schema knows
about it. `SCHEMAS.action` named `kind`, `slot` and `index`; `item` and
`move` are added beside them.

Without that, the failure is the quiet one. A loopback `Net` pair hands
the table straight over and every in-process test passes; a real
transport goes through `Session` -> `Wire.sanitize`, and the peer
receives `{ kind = "item" }` with no item in it. `LinkItems.apply`
returns `{}`, the turn is still spent, nothing is printed, and the two
machines are one heal apart with nothing on either screen to say so --
until the next hash, several turns later, blames the wrong turn.

### `ItemEffects.use`: a ball on the cable is refused

`BALLS[itemId]` returned `"ball"` unconditionally; in a link battle it now
returns the "not the time" refusal, the way the doll already does in any
trainer battle. Without this, opting in would let a player throw a ball at
the other trainer's Pokémon.

### The lines the other side reads

The user's own screen printed what the bag prints. The peer and the
spectator have no bag, so `LinkItems.apply` leads with `"<name> used
<ITEM>!"` (the engine's own `itemUseLine`, with the user's name) unless the
effect already printed one (the X items and the flute do), then the
effect's lines, then anything the effect prints after (the X item's
"rose!"). The status HUD follows at once as it does for the user; the HP
bar drains toward the new HP on its own, so a heal fills on the peer's
screen the way it filled in the user's party menu.

## Migration

None. No caller sets `opts.items` today; no message of the new kind is ever
sent unless a caller does. A peer on an older engine that receives an
`item` action would have decoded it as no action and desynced on the next
hash — which is why a mode must set the option on both machines, as it
already must for `turnLimit` and `forceLevel`.

## Verification

- `tests/engine/link_items.lua` — on the real lockstep over a loopback
  pair: cable rules by default (the bag is refused, `itemUsed` is the
  inherited one); opted in, the host's POTION lands on its copy, rides the
  wire, heals the guest's copy of the host's lead before the moves, prints
  the used and restore lines on the guest, resolves in one turn on both
  sides with agreeing hashes; and a spectator fed the same two messages
  heals its own copy and prints the same lines.
- `tests/run_engine.lua` — the tier the file lives in.

## Backward compatibility

A stock link battle never reaches any of it: `openItems` and `itemUsed` are
only replaced under `opts.items`, `resolveLockstep` and `resolveSpecTurn`
only act on a message kind nothing sends, and the ball refusal only fires
for `battle.kind == "link"`, where the bag could not be opened before.

## Scope, and what is deliberately not in this change

**Gen 1 only.** `LinkBattle2` (Gold) keeps its cable rules; it has its own
bag and its own item dispatcher, and a mode built on it can ask for the
same option in its own RFC.

**No new rule for what an item may do.** What the bag allows in a trainer
battle is what it allows here — medicines, X items, the flute — and what
it refuses there (balls, the doll, stones, TMs, candy) it refuses here. The
option is a door, not a ruleset.

**The shot clock waits at the bag.** `opts.turnLimit` ticks only in the
menu phase; a bag open over the menu is not the menu. A mode that wants a
clock on the bag as well has `battle.phase` and the stack to build one on,
and the mode that asked for this already keeps its own watchdog.

## Compatibility seam for older engines

There is none. The battle refuses the bag before any mod code runs, and
the wire's decoder is a closure. A mode on a stock engine can only keep
the refusal, which is what the motivating mode does today.
