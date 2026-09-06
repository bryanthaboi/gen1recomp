# RFC 0020: Keyboard, gamepad, and wheel input hooks (`input.key`, `input.gamepad`, `input.wheel`)

## Status

Proposed.

## Motivation

`input.pointer` gives a mod one consume-capable seam for mouse and touch.
Keyboard, gamepad, and the scroll wheel have no equivalent. A mod can
already *read* them (`love.keyboard`/`love.joystick` stay open under the
sandbox), but polling can only read: it can never stop the base game from
also acting on the same key or button.

The immediate consumer is Kanto Companion's overlay Edit Mode, which drags
and resizes panels with the D-pad, the left stick, and A, the same inputs
that move the player and drive the battle menu. Before the sandbox
changes (83682f01), a mod ran in the real global environment and could
just reassign `love.gamepadpressed` and friends directly, giving its own
dispatch first refusal before calling the saved original: real
suppression, not just observation. The sandbox changes closed off
writable `love.*` globals, rightly, but nothing replaced that one
capability. The only way left to keep a mod's nav input from also
reaching the game is to pause it outright, which is what Edit Mode does
today, gated to the overworld only since pausing a live battle would
freeze it. That gate isn't a design choice: Edit Mode can't run during
battle because there's no other way to stop a D-pad press from also being
read as a battle-menu press.

## The decision it extends

This finishes the `input.pointer` family for mouse and touch, giving
keyboard, gamepad, and wheel the same kind of seam. It doesn't change
`input.pointer`'s contract, `input.step`'s contract, or `Input.lua`'s
existing key/button remapping.

There is no in-repo D-number registry to amend.

## Exact API delta

### Where these differ from `input.pointer`, and why that's deliberate

`input.pointer`'s "return true to consume" is, today, provably inert: none
of its 14 real call sites read what `Game:pointerEvent` returns, because
its vanilla callback is a no-op stub, so there's no gameplay behavior to
gate.

Keyboard and gamepad are the opposite: they drive real, load-bearing
behavior (movement, menus, battle input, save/load, zoom, speed, tilt,
display hotkeys). Mirroring `input.pointer` mechanically (firing the hook
as a side observation and then running `Input:keypressed`/
`Input:gamepadpressed` regardless) would make "consume" just as inert
here, and wouldn't restore what Edit Mode actually needs: stopping a D-pad
press from also walking the player. So `input.key` and `input.gamepad` use
a stronger contract instead. `vanilla` is a closure over the entire
existing method body: top-of-stack capture, the hotkey ladder, the final
`Input:*` call, all of it. The hook fires as the first thing the method
does, and a wrapper that returns without calling `next(...)` stops all of
that from running for this event, same precedence a mod's own global
reassignment always had before the sandbox changes. Nothing new is being
granted, just the old precedence, reachable through a hook instead of a
global clobber.

`input.wheel` has no such tension: it only ever drives camera zoom, and
nothing depends on suppressing it, so it stays a plain observer,
contract-identical to `input.pointer`.

### New hook: `input.key`

```lua
mod.hooks:wrap("input.key", function(next, game, ev)
  -- ev = { phase, key } -- phase: "pressed" | "released"
  if editingPanel and ev.phase == "pressed" and NAV_KEYS[ev.key] then
    handlePanelNav(ev.key)
    return  -- swallowed: the player's own keypressed handling never runs
  end
  return next(game, ev)
end)
```

`ev` carries exactly what `Game:keypressed`/`Game:keyreleased` already
receive: `main.lua` already drops LÖVE's `scancode`/`isrepeat` before
either method sees them, so this doesn't add them. A later RFC can widen
the payload if something needs those two fields.

Raised from the very first line of `Game:keypressed`/`Game:keyreleased` and
their `Game2` equivalents, before the top-of-stack capture
(`stack:top().onKeyPressed`), before the engine's own hotkey ladder (F1/F2/
F5/F10, `-`/`=` zoom, 1-4 display hotkeys), and before `Input:keypressed`/
`Input:keyreleased`. `vanilla` is a closure over that entire existing method
body. `game` is the live `Game`/`Game2` instance, same object `input.pointer`
already hands a mod.

### New hook: `input.gamepad`

```lua
mod.hooks:wrap("input.gamepad", function(next, game, ev)
  -- ev = { phase, joystick, button, axis, value }
  -- phase: "pressed" | "released" | "axis"
  -- button is nil on "axis"; axis/value are nil on "pressed"/"released"
  if editingPanel then
    if ev.phase == "axis" and (ev.axis == "leftx" or ev.axis == "lefty") then
      updateStickCursor(ev.axis, ev.value)
      return
    end
    if ev.phase == "pressed" and ev.button == "a" then
      grabOrDropPanel()
      return
    end
  end
  return next(game, ev)
end)
```

Unlike `input.pointer`, this covers three raw LÖVE callbacks, not one:
`gamepadpressed`, `gamepadreleased`, and `gamepadaxis`, because the
motivating use case (a stick-driven cursor for touch-free panel dragging)
needs raw analog axis values, which `stack:top().onGamepadPressed`-style
button capture cannot deliver at all. Each of the three raw callbacks in
`Game.lua`/`Game2.lua` raises `input.gamepad` as its first line, `vanilla`
wrapping that callback's entire existing body (the Select-chord intercept,
the shoulder-button speed cycling, the top-of-stack capture, `Input:*`),
the same "mod runs before everything, including the engine's own
top-of-stack capture" precedence as `input.key`, for the same reason.

### New hook: `input.wheel`

```lua
mod.hooks:wrap("input.wheel", function(next, game, dy)
  if scrollingOwnList then
    scrollList(dy)
    return
  end
  return next(game, dy)
end)
```

Raised from `Game:wheelmoved`/`Game2:wheelmoved`, `vanilla` wrapping the
existing zoom-step body. Contract-identical to `input.pointer`: return
`true` without calling `next` to consume, which only arbitrates between
mods in the chain; no engine behavior reads the outer return value.
`dy` is the raw LÖVE wheel delta, matching `love.wheelmoved`'s own second
argument (the engine's callback already drops the first, horizontal,
argument, and this RFC doesn't change that).

### Call-site summary

| Hook | Files | Existing callbacks wrapped |
|---|---|---|
| `input.key` | `Game.lua`, `Game2.lua` | `keypressed`, `keyreleased` |
| `input.gamepad` | `Game.lua`, `Game2.lua` | `gamepadpressed`, `gamepadreleased`, `gamepadaxis` |
| `input.wheel` | `Game.lua`, `Game2.lua` | `wheelmoved` |

All three are guarded by `ModRuntime.wantsHook(name)` before any payload
table is built, same as `input.pointer`, so a mod-free boot allocates
nothing new here.

### On overriding the engine's own top-of-stack capture

Because `input.key`/`input.gamepad` fire before `stack:top().onKeyPressed`/
`onGamepadPressed`, a mod can swallow input an engine screen like
`BindingsMenu` would otherwise have captured: the same precedence every
mod already had before the sandbox changes. Nothing uses either hook yet,
so nothing regresses; reviewing a specific mod's use of it just means
checking it isn't swallowing input it shouldn't.

## Migration and compatibility

Nothing changes for existing mods, manifests, or any currently-shipping
hook. `input.key`, `input.gamepad`, and `input.wheel` are additive only:
new hook names with no prior meaning. `mod.hooks:wrap("input.key", fn)` is
already mechanically callable today (`Hooks:wrap` validates only that `name`
is a non-empty string); it simply never fires until this RFC's engine-side
call sites land.

## Verification

- `tests/modkit/cases/key_gamepad_wheel_input.lua` (new), through the public
  mod API via `T.sdk.loadMods(...)` against a `fakeGame` the way
  `tests/modkit/cases/pointer_input.lua` already does for `input.pointer`:
  - `input.key`: pressed/released sequences with the `phase`/`key` payload
    shape confirmed, a mod returning without calling `next` prevents a
    synthetic `Input:keypressed` spy from being called; a mod calling
    `next` lets it through; no-mod-installed still calls it
    (vanilla-through).
  - `input.gamepad`: press/release/axis all reach the hook; a swallowed
    press never reaches `Input:gamepadpressed`; an axis event carries
    `axis`/`value` and no `button`.
  - `input.wheel`: delta reaches the hook; consuming it stops the zoom-step
    spy from firing; no-mod-installed still zooms.
  - A no-mod-installed pass for all three confirming `wantsHook(...) ==
    false` and nothing new gets allocated (mirrors `pointer_input.lua`'s own
    first case).
- `tests/engine/gate_hooks.lua`: no edits needed, it auto-covers any hook
  name the source-scanning catalog discovers, provided the vanilla callback
  follows the same call-once/return-through/error-propagate contract every
  existing hook already gets from `Hooks:call`, which these do.
- `tests/engine/gate_gen2_mod_api.lua`: `input.key`, `input.gamepad`, and
  `input.wheel` each have call sites in both a `gen2`-pathed file
  (`Game2.lua`) and a non-`gen2` file (`Game.lua`), so all three need an
  explicit entry in that gate's `GEN2_HOOKS` list (next to `"input.step",
  "input.pointer"`), or the gate fails naming them.
- `docs/mod-api-gen2-compat.md`: a line in "Hooks and events that fire on
  Gold" → "The frame" bullet, next to the existing `input.step`/
  `input.pointer` entry.
- `docs/modding.md`: new paragraphs in the existing "Tool input and
  title-menu hooks" section (it already mixes `input.step`, `input.pointer`,
  `mod.input`, and `ui.title_menu.items`; these three are the same family
  of raw-input seam), each citing "(RFC 0020)" per the convention
  `pokemon.level_visible (RFC 0019)` established.

## Deprecation etiquette

Nothing is removed, renamed, or superseded.
