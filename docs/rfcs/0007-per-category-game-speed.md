# RFC 0007 — Per-category GAME SPEED and the `core.logic_speed` hook

## Status

Proposed. Engine: `GameSpeed.lua`, `Game.lua`, `BattleState.lua`,
`OptionsMenu.lua`, `SaveData.lua`, `LauncherSettings.lua`. Tests:
`tests/engine/game_speed_categories_test.lua`,
`tests/engine/gate_hooks.lua` (structural, automatic), `tests/run_tests.lua`
(OptionsMenu row walk), `tests/mod_ui_tests.lua` (row id/order).

## Motivation

`GameSpeed` (`src/core/GameSpeed.lua`) is a single fast-forward multiplier
applied uniformly to the whole logic clock in `Game:logicSpeed()` /
`Game:update()` -- overworld walking, menu navigation and battle turns all
scale together. A player who wants 4X battles (grinding, a long gym fight)
but 1X overworld (so a scripted cutscene or NPC dialogue doesn't blur past)
has no way to get both; the one GAME SPEED row is a single ladder that
applies everywhere at once.

This needs to be an engine change, not a mod: there is no per-frame seam a
mod can use to swap the multiplier mid-step, and no public event granular
enough to say "which category is active" (`screen.pushed`/`screen.popped`
and `battle.started`/`battle.ended` are the closest and are not enough --
see Decisions below). The engine's own speed resolution has to become
category-aware.

A category-aware speed resolution is also the general seam a
platform-launcher integration or automation tool needs to read or override
the effective multiplier for a given frame without caring which category
produced it -- this RFC's `core.logic_speed` hook is written for that case
alongside the player-facing Options rows.

## The decision it extends

No prior D-number. Extends `GameSpeed.lua`'s multiplier ladder (unchanged)
with per-category resolution.

## The exact API delta

Backward-compatible except for one save-data field rename, which ships with
an automatic migration (see below) -- nothing in the public mod API (hooks,
events, registries, `mod.*`) is renamed or removed.

### `save.options`: `speed` -> `speedOverworld` / `speedBattle` / `speedMenu`

`GameSpeed.CATEGORIES = { "overworld", "battle", "menu" }` is the new list
of categories, and `GameSpeed.optionKey(category)` maps a category to its
`save.options` field name (`"overworld"` -> `"speedOverworld"`, etc.).
`GameSpeed.LEVELS`, `.DEFAULT`, `.levelLabel`, `.clamp` and `.cycle` are
unchanged -- the ladder and its behavior are exactly what they were, just
applied three times instead of once.

`SaveData.defaultOptions()` drops `speed = 1` and adds `speedOverworld = 1`,
`speedBattle = 1`, `speedMenu = 1`. `SaveData.mergeOptions()` migrates: a
loaded options table that still has `speed` and none of the three new
fields seeds all three from it, so an existing player's fast-forward
preference carries over instead of two of the three categories silently
resetting to 1X. `speed` is dropped on the way out (not carried forward),
so a re-save never re-triggers the migration.

### `Game.speedCategoryInStack(stack)`

New static helper, `(stack) -> "battle" | "overworld" | "menu"`. Walks the
whole state stack top-down -- the same idiom `Game.wideBattleInStack` and
`Game.fillScaleInStack` already use -- looking for `state.isBattle` (new
marker, `BattleState.isBattle = true`, covering every battle: wild,
trainer, link, safari, the old-man demo) or `state.isOverworld` (existing
marker, `OverworldController`'s `OverworldState.isOverworld = true`). The
first match wins; a state with neither marker (a menu, a text box, a
naming screen, a cutscene) is transparent to the walk and falls through to
whatever is under it. Nothing in the stack matching either falls back to
`"menu"`.

### `Game:logicSpeed()` / `Game:_resolveLogicSpeed()`

`Game:_resolveLogicSpeed()` is new: it resolves `Game.speedCategoryInStack`
against the live stack, maps the category to its `save.options` key via
`GameSpeed.optionKey`, and returns `GameSpeed.clamp` of that option (or
`GameSpeed.DEFAULT`). This is the exact category-resolution logic the new
hook wraps.

`Game:logicSpeed()` keeps its existing early returns -- link play forces
`1`, a run-argument speed override wins over the saved option -- unchanged,
and in the same order, before ever calling the hook. Only once neither
applies does it call the `core.logic_speed` hook.

### `Game:_cycleSpeed(dir)`

The keyboard hotkey and the gamepad shoulders/triggers that used to cycle
the single `speed` option now cycle whichever category
`Game.speedCategoryInStack` says is active: pressing the hotkey during a
battle speeds up just the battle, on the overworld just the walk, in a menu
just the menu. This is the natural per-category answer for a control that
used to have one option to reach and now has three -- see Decisions below
for why this reading was chosen over, say, always cycling `overworld`.

### `core.logic_speed`

New hook, `(game) -> number` through the public wrapper signature
`(next, game)`, called once per `Game:logicSpeed()` (i.e. once per frame).
Vanilla behavior (used when no mod claims the hook) is
`Game:_resolveLogicSpeed()` -- exactly the category resolution above,
nothing else. A subscriber may call `next(game)` and return its result to
pass the vanilla multiplier through, or return a different number outright
to override it for that frame (e.g. a bot mod forcing `1` during one route
segment regardless of what category or option is active).

This intentionally sits *after* the link and speed-override checks in
`Game:logicSpeed()`, not around them: link play staying locked to 1X "no
matter what either player set this to" is exactly the invariant that would
break if a mod's hook could override it, and the run-argument override
exists so a bot/screenshot run's speed does not depend on a mod any more
than on the player's saved option. Both stay unconditional early returns a
mod never sees.

Not guarded by `Runtime.wantsHook`: `Hooks:call` already fast-paths to a
bare `vanilla(...)` call when no mod has wrapped the name, and this hook
fires every frame regardless.

## Decisions on the issue's open questions

**1. Overlays on top of another category's state (a party menu, a choice
box, a naming screen opened mid-battle or mid-overworld).** Resolved by
making the category a property of stack *position*, not of the overlay's
own type: an overlay with no `isBattle`/`isOverworld` marker is transparent
to `Game.speedCategoryInStack`'s walk and inherits whatever is under it. A
party swap opened mid-battle reads as `"battle"`; a bag opened while
walking reads as `"overworld"`. This was chosen over giving every UI state
its own fixed category (which would make a fast-forwarded battle visibly
stutter back to 1X every time its party menu opens) because it matches
what the player is actually doing moment to moment, and it reuses a
pattern the codebase already leans on for exactly this "menus opened over
X should behave like X" class of problem (`Game.fillScaleInStack`,
`Game.wideBattleInStack`).

**2. Cutscenes/scripts.** No fourth category. A scripted sequence runs
through the owning state's own machinery -- the overworld's script runner
or a battle's message queue -- rather than pushing a state of its own, so
it is already covered by decision 1: it inherits whatever category the
state driving it resolves to. A cutscene state that genuinely has nothing
under it (a pre-game intro) falls to `"menu"`, the default for anything
that is not battle or overworld gameplay -- consistent with those being
pre-game presentation, not something a player is likely to want scaled
differently from menu navigation.

**3. Category granularity (splitting "menu" further).** Deferred. Start
with the three named here; `GameSpeed.CATEGORIES` and `GameSpeed.optionKey`
are written so adding a fourth later (a Pokédex/Bag category, say) is one
entry plus one new `save.options` field, not a resolution-logic rewrite.
No current request motivates it.

**4. The GAME SPEED hotkey/shoulder buttons, once "the" speed is three
things.** `Game:_cycleSpeed` now cycles whichever category is currently
active (`Game.speedCategoryInStack`), rather than, say, always cycling
`overworld` or requiring a modifier key to pick a category. A single
physical control that means "speed up whatever I'm looking at right now"
is the reading that needs no new UI and matches what a player pressing it
mid-battle almost certainly wants.

## Migration note for existing mods

**Nothing**, for the mod API surface: `content.X:register/override/get`,
`events:on`, `hooks:wrap`, `mod.log`, `mod:read`, manifest v1 fields are
untouched, and `GameSpeed.LEVELS`/`.DEFAULT`/`.levelLabel`/`.clamp`/`.cycle`
keep their exact signatures and behavior.

**One save-data field**, for anything that read `save.options.speed`
directly (not a formal registry/hook surface, but worth naming): it is
superseded by `speedOverworld`/`speedBattle`/`speedMenu`, migrated
automatically on load (see above) so a save from before this RFC keeps its
player's chosen speed. A mod reading `save.options.speed` after this change
sees `nil` (the key is dropped on migration, not kept as a stale alias) and
should read the per-category fields, or hook `core.logic_speed` to observe
the resolved multiplier directly regardless of which category produced it.

## Parity tests

- **No-mod:** `core.logic_speed` needs no dedicated no-mod test file --
  `tests/engine/gate_hooks.lua` walks the live hook catalog (which scans
  `src` for `Runtime.call("...")` call sites), so the new
  `Runtime.call("core.logic_speed", ...)` site is picked up and gated
  automatically: vanilla runs exactly once with an empty hook chain, an
  unsubscribed-but-live bus passes values and multiple returns through
  unchanged, and `Runtime.wantsHook` reads `false`.
- **Mod-API:** `tests/engine/game_speed_categories_test.lua` exercises the
  hook through the public API (`Hooks.new()` + `bus:wrap("core.logic_speed",
  ...)` + `Runtime.call`, the same idiom other hooks' tests use) -- a
  subscriber can read the vanilla category resolution via `next(game)` and
  can override it outright -- plus direct coverage of
  `Game.speedCategoryInStack` (battle-on-top, overworld-on-top, an overlay
  inheriting each, an empty/unmatched stack falling to `"menu"`) and
  `Game:logicSpeed()`'s precedence (link forces 1X over all three
  categories and over a hook override; the run-argument override wins over
  the category resolution).
- `tests/run_tests.lua`'s OptionsMenu walk exercises the three new rows
  (OVERWORLD SPEED / BATTLE SPEED / MENU SPEED) cycling and wrapping
  independently, in place of the old single GAME SPEED row.
- `tests/mod_ui_tests.lua`'s row-id/order check and hardcoded row-index
  activations (MODS, CONTROLS) are updated for the two extra rows.
- A link-play driver should set all three per-category speeds high before
  asserting `game:logicSpeed()` reads `1` during a real link session,
  proving the lock wins over every category at once, not just whichever
  one happens to be active.

## Deprecation etiquette

Nothing deprecated in the mod-facing hook/event/registry catalog -- this
adds one hook, additive. The `save.options.speed` field is superseded with
an automatic migration rather than a deprecation notice, since it was never
a registered mod-API surface (no schema entry, no registry) -- the same
treatment any other `save.options` field would get if it needed reshaping.
