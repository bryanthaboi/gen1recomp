# RFC 0014: Mod-driven world actors and adopted link sessions

## Status

Proposed.

## Motivation

A mod can already spawn a runtime object with `mod.world:spawnNpc` and can
already start a link battle. It cannot make either of them behave like
something the mod itself owns.

Three walls, each of which stops a mode rather than inconveniencing it:

**An actor cannot move on its own schedule.** The only public way to animate a
spawned object is `Handle:scriptMove`, which queues onto
`OverworldState.scriptMoves`. A non-empty `scriptMoves` is how the overworld
knows a cutscene is running -- `handleInput` gates on it -- so anything
animated that way freezes the player's controls for as long as it walks. That
is correct for Oak marching into his lab and wrong for an ambient walker or a
networked player's ghost, which move continuously and must not lock anyone out.

**A spawned object cannot answer the A press.** Talking is resolved from the
map's text tables by `TEXT_*` id. A runtime object has no id, so the vanilla
path has nothing to say for it, and the mod that created it has no way to say
anything either.

**A link battle cannot ride a connection the mod already has.** `LinkState`
owns pairing, so a mode that already has a socket to its peer must either open
a second connection for the battle or reimplement lockstep. And when the
battle ends, cable rules leave the real party untouched, so the damage exists
only in the battle's own copies -- which are gone by the time the state
unwinds. A mode built on link battles cannot learn what the fight cost.

The immediate consumer is an overworld multiplayer mode, but nothing here is
specific to it: the first two are wanted by any mod with an actor that moves
itself, and the third by any mode that runs battles over its own transport --
a tournament ladder, a draft, a gauntlet.

## The decision it extends

This adds nothing to the compatibility surface's shape; it extends the
**additive, guarded seam convention** that Route B in `CONTRIBUTING-mods.md`
documents, and is gated by the parity guarantee `tests/engine/gate_meta_coverage.lua`
enforces ("21-testing-and-ci: a parity gate for every extension point"; M14).

There is no in-repo D-number registry to amend; the consuming design lives
outside this repository, as it did for RFC 0011.

## Exact API delta

### New hook: `world.talk`

```lua
mod.hooks:wrap("world.talk", function(next, ow, target)
  -- ow     = the OverworldState raising it
  -- target = the object on the faced cell
  if mine(target) then
    say(target)
    return                    -- the mod answered; the text path is skipped
  end
  return next(ow, target)     -- anything else falls through unchanged
end)
```

Call site: `OverworldState:interact`, on the branch that has already resolved
an object on the faced cell (including across a counter) and confirmed it is
not mid-step and not the Pikachu follower. It runs before the map's text
tables are consulted. With no subscriber, `Runtime.call` invokes the vanilla
fallthrough, which is a file-local function rather than a per-press closure,
so an unhooked A press allocates nothing it did not allocate before.

### New event: `link.battle_ended`

```lua
mod.events:on("link.battle_ended", function(ev)
  -- ev = {
  --   result     = "win" | "lose" | "draw" | "ended",
  --   myParty    = lockstep copy of our party,
  --   theirParty = lockstep copy of theirs,
  --   peerName   = string,
  --   role       = "host" | "guest",
  -- }
end)
```

Call site: `LinkState:update`, in the `battleRunning` stage, once the battle
state has been popped and before `exitWith` unwinds the link stack. Guarded by
`Runtime.wants("link.battle_ended")`, so with no subscriber no payload table
is allocated and the branch runs exactly as before.

The party copies are the point of the event. They are the lockstep records the
battle actually fought with, which is where the damage lives under cable rules.

### New `WorldAPI` handle methods

```lua
handle:stepNow(dir)        --> true when the step started
handle:canStep(dir)        --> would stepNow land somewhere legal?
handle:placeAt(x, y, dir)  --> snap, no animation, clears a step in flight
handle:isMoving()          --> true while a step is animating
handle:setPassable(flag)   --> may the player walk through this object?
```

`stepNow` sets the same per-tile state `scriptMove` does, without the queue and
therefore without the input lockout. It does **not** consult collision: the
intended caller is replaying a move already decided elsewhere (validated on a
peer, or authored), and re-judging it locally would let two copies of the same
actor disagree about where it is. `canStep` is the separate opinion for callers
that want it. `setPassable` sets the flag `Collision.occupied` already honours
for Yellow's companion Pikachu; a passable object still draws and still talks.

### Two supporting changes

`Game:startNewGame(opts)` -- the title screen's NEW GAME closure, made callable,
with `opts.intro = false` to land directly in the world. A mode that issues its
own starting state has no use for the intro cutscene.

`CodeEntry.new(shape)` -- accepts an optional `{ length =, charset = }`, so the
slot-scrub widget that enters a link code can also carry a room code or a
host:port address. Called with no argument it is byte-for-byte the previous
widget.

## Migration and compatibility

**Existing mods change nothing.** Every item above is a new name or a new
optional argument; no existing name, payload, signature, or default changes.

The v1 surface is unaffected: `content.X:register/override/get`, `events:on`,
`hooks:wrap`, `mod.log`, `mod:read`, the manifest v1 fields and
`pokemon.before_give` all behave as before. `mods/example_mew_starter` -- api 1,
`category = "GAMEPLAY"`, whole-species copy -- loads unchanged, which
`tests/run_modkit.lua` proves on every run.

With no subscriber to either seam, Red, Blue, Yellow, Gold and Silver behave
exactly as they did: the A press reaches `talkTo`, the link battle unwinds
without building an event payload, and no handle method is reachable unless a
mod calls it.

## Verification

- `tests/modkit/cases/world_talk.lua` drives the real `OverworldState:interact`
  path. It asserts the unhooked build first (the A press reaches `talkTo`),
  then that a mod owning the object suppresses the text path by not calling
  `next`, that an object the mod ignores still falls through, and that an
  object mid-step raises no hook at all.
- `tests/modkit/cases/link_battle_ended.lua` drives the real `LinkState:update`
  path. It asserts that with nothing subscribed the event is not wanted (so no
  payload is built) and the battle still unwinds, then that a subscriber
  receives the result, the role, the peer name and both party copies including
  the damage the real party never took, from both sides of the cable.
- `tests/engine/gate_hooks.lua` and `tests/engine/gate_events.lua` walk the live
  catalog, so both seams are parity-gated structurally; `gate_meta_coverage`
  passes 208/208 with both names covered and no DEBT entry added.

## Deprecation etiquette

Nothing is removed, renamed, superseded or deprecated.
