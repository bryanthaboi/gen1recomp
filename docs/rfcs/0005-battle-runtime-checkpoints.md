# RFC 0005 — Persistent battle safe-point checkpoints

## Status

Proposed. Extends RFC 0004. Engine: `BattleCheckpoint.lua`, `Checkpoint.lua`,
`Game.lua`, `BattleState.lua`, and `OverworldController.lua`. Tests:
`battle_checkpoint_*.lua`, `checkpoints.lua`, and the existing no-mod suites.

## Motivation

RFC 0004 lets a tool capture and reconstruct settled overworld progress without
private engine access. A battle is a different runtime: its queue can hold Lua
functions and UI factories, its controller contains renderer objects and live
references, completion is currently an `onFinish` closure, and scripted battles
resume a suspended `ScriptRunner` coroutine. Copying the controller would create
a record that is neither data-only nor process-independent.

The engine can instead expose a narrow semantic safe point. This gives all mods
the strongest persistent battle checkpoint the current architecture can prove,
without claiming mid-animation or suspended-script support.

## API delta

No new facade is added. The existing additive `mod.checkpoints` API gains a
second format-1 runtime kind.

### Capability

`mod.checkpoints:inspect(game)` returns this only when an ordinary single-player
wild or trainer battle is settled at the player command menu:

```lua
{ canCapture = true, canRestore = true, kind = "battle" }
```

The action/message queue, waits, UI, animations, HP/status presentation, and
faint processing must be settled. The player must actually control the menu.
The underlying overworld must have no running/queued script or scripted move,
and the battle must carry an engine-owned semantic continuation descriptor.

Additional refusal codes are `battle_phase_busy`, `battle_origin_unsupported`,
`battle_variant_unsupported`, and `link_battle_unsupported`. Link, Safari,
ghost, old-man/demo, fishing, static-object, script-suspended, and mod-created
closure continuations remain rejected.

### Capture

A battle checkpoint remains detached and data-only:

```lua
{
  format = 1,
  kind = "battle",
  identity = { engineVersion = "...", gameVersion = "red",
               playthroughId = "..." },
  save = { -- canonical dynamic progress, excluding global options },
  runtime = {
    overworld = { map = "ROUTE_1", x = 7, y = 8,
                  facing = "left", surfing = false },
    battle = { -- normalized semantic model and continuation },
  },
  rng = { love = "..." },
}
```

The model carries player/enemy roster indices, dynamic enemy Pokémon, turn and
escape state, HP/PP/status/stages/volatiles, participants, level-up tracking,
trainer AI state, battle ruleset identity, side/field extension data, and
normalized pointer relationships such as multi-turn move slots and Mimic
restoration entries. Definitions, sprites, canvases, queues, callbacks, and
controller objects are reconstructed or excluded.

Callback-bearing battle extension tokens fail with `battle_extension_unsafe`;
invalid live reference relationships fail with `battle_state_invalid`. Nothing
is silently stripped.

New overworld checkpoints also carry the LÖVE gameplay RNG state. Legacy
format-1 overworld checkpoints without `rng` remain loadable and leave the
current stream untouched.

### Restore

Battle restore validates the detached save, map, content references, ruleset,
roster indices, move references, continuation identity, and RNG before live
mutation. The engine then:

1. reconstructs the saved overworld return point without entry side effects;
2. creates a fresh `BattleState` from current content registries;
3. applies the normalized battle model and rebuilds object-reference relations;
4. binds an engine-owned wild/trainer completion continuation;
5. installs the battle directly at the settled menu without replaying its intro;
6. restores the RNG after reconstruction has finished; and
7. recaptures and compares the complete checkpoint; and
8. emits `checkpoint.restored` with `{ game = game, kind = "battle" }` after the
   comparison succeeds.

The pre-operation checkpoint is the transaction rollback. A failed post-install
RNG restore is covered: both battle runtime and RNG are reconstructed back to
their original values. Validation failure, failed reconstruction, and successful
rollback emit no checkpoint lifecycle event.

## Continuation decision

Ordinary random wild battles resume through `OverworldState:afterBattle`.
Ordinary trainer battles use a descriptor containing map id, stable NPC id,
trainer class/party, and optional header event; a win reapplies the same defeated
flag, event, reward, and `afterBattle` path. Reconstructed overworld input and
NPC freeze state are normalized instead of reviving the old closure.

`Commands.start_battle` is deliberately unsupported: its completion closure
mutates script context and resumes a coroutine whose program counter and Lua
stack cannot be serialized. Existing script rejection remains the correct safe
contract until a separate semantic ScriptRunner checkpoint RFC exists.

## Migration note

**Existing mods require no changes.** The facade and format number are unchanged;
the new kind, RNG field, and success-only lifecycle event are additive.
Overworld-only callers may continue to filter `capability.kind`. Mods with derived
runtime caches may rebuild them from restored public state when the event fires.
No-mod behavior is unchanged when checkpoints are unused.

## Verification

- settled/unsafe boundary and every variant refusal;
- data-only wild and trainer capture, including callback-bearing extension
  rejection;
- process-independent controller and continuation reconstruction;
- exact differential recapture for wild and trainer states;
- HP, PP, status/stages/volatiles, AI layer, participants, enemy roster,
  multi-turn move references, and Mimic restore pointers;
- exact damage, critical, accuracy, random AI, escape, next encounter, and next
  raw RNG result after reload;
- corrupt content/continuation rejection before mutation;
- injected post-install failure with full runtime and RNG rollback;
- mod-added Pokémon metadata and `mod.save` rewind while independent
  `mod.storage` and options remain current;
- exactly one post-verification `checkpoint.restored` event and none on failure;
- legacy overworld checkpoint compatibility;
- complete ROM-free engine and public mod-API suites.
