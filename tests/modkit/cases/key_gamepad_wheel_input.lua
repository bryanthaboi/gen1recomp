-- RFC 0020: input.key, input.gamepad, and input.wheel, through the public
-- mod API. Driven the way main.lua drives them -- through Game's own
-- keypressed/keyreleased/gamepadpressed/gamepadreleased/gamepadaxis/
-- wheelmoved, against the real Input singleton -- so a green run means the
-- wiring, not just the buses. Structured after tests/modkit/cases/
-- pointer_input.lua, the direct precedent for a raw-input hook family.
--
-- The one property that matters beyond "the hook fires": input.key and
-- input.gamepad give a mod REAL suppression, unlike input.pointer's own
-- (inert) consume contract -- a wrapper that returns without calling
-- `next` must stop the vanilla body (Input:keypressed/gamepadpressed/
-- gamepadaxis, the engine's own hotkey ladder) from running at all. That
-- is asserted directly below, not just that the payload looks right.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Runtime = require("src.mods.Runtime")

-- Minimal stand-in stack: Game:keypressed's vanilla body reaches
-- self.stack:top() unconditionally near its end (feeding Pipelines.hotkey),
-- even for a key no hotkey claims, so this needs to resolve, not just be
-- absent the way pointer_input.lua's fakeGame leaves it.
local function fakeGame(loader, data)
  return setmetatable(
    { input = Input, mods = loader, data = data,
      stack = { top = function() return nil end } },
    { __index = Game })
end

-- ------- fixture mod: journals every event, and swallows the specific
-- keys/buttons/axes an "edit mode" would grab, proving real suppression

local FIXTURES = {
  ["mods/fix_key_gamepad_wheel/manifest.json"] = [[{
    "id": "fix_key_gamepad_wheel",
    "name": "Fixture Key Gamepad Wheel Watcher",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_key_gamepad_wheel/main.lua"] = [[
    local mod = ...
    local seenKey, seenPad, seenWheel = {}, {}, {}
    mod.exports.seenKey, mod.exports.seenPad, mod.exports.seenWheel =
      seenKey, seenPad, seenWheel
    local swallow = false
    mod.exports.setSwallow = function(v) swallow = v end

    mod.hooks:wrap("input.key", function(nextFn, game, ev)
      seenKey[#seenKey + 1] = { phase = ev.phase, key = ev.key }
      if swallow and ev.key == "left" then return "SWALLOWED" end
      return nextFn(game, ev)
    end)

    mod.hooks:wrap("input.gamepad", function(nextFn, game, ev)
      seenPad[#seenPad + 1] = { phase = ev.phase, button = ev.button,
        axis = ev.axis, value = ev.value }
      if swallow and ev.phase == "pressed" and ev.button == "a" then
        return "SWALLOWED"
      end
      if swallow and ev.phase == "axis" and ev.axis == "leftx" then
        return "SWALLOWED"
      end
      return nextFn(game, ev)
    end)

    mod.hooks:wrap("input.wheel", function(nextFn, game, dy)
      seenWheel[#seenWheel + 1] = dy
      if swallow then return "SWALLOWED" end
      return nextFn(game, dy)
    end)
  ]],
}

-- ------- no-mod parity: all three cost nothing unsubscribed, and vanilla
-- really runs (checked via the real Input singleton, not just "no crash")

do
  local run = T.sdk.loadNone({})
  Input:init()
  local game = fakeGame(run.loader, run.data)
  T.eq(Runtime.wantsHook("input.key"), false,
    "no subscriber: wantsHook(\"input.key\") is false")
  T.eq(Runtime.wantsHook("input.gamepad"), false,
    "no subscriber: wantsHook(\"input.gamepad\") is false")
  T.eq(Runtime.wantsHook("input.wheel"), false,
    "no subscriber: wantsHook(\"input.wheel\") is false")

  -- "up" is a DEFAULT_BINDINGS identity mapping (raw key "up" -> GB
  -- button "up"), unlike most letter keys, which remap to a differently
  -- named GB button (e.g. raw "z" -> GB "a") -- using an identity-mapped
  -- key here means Input:isDown can check the exact name just pressed.
  Game.keypressed(game, "up")
  T.eq(Input:isDown("up"), true,
    "no subscriber: keypressed still reaches Input (vanilla ran)")
  Game.keyreleased(game, "up")
  T.eq(Input:isDown("up"), false,
    "no subscriber: keyreleased still reaches Input")

  Game.gamepadpressed(game, nil, "b")
  T.eq(Input:isDown("b"), true,
    "no subscriber: gamepadpressed still reaches Input")
  Game.gamepadreleased(game, nil, "b")
  T.eq(Input:isDown("b"), false,
    "no subscriber: gamepadreleased still reaches Input")
  Game.gamepadaxis(game, nil, "leftx", 0.9)  -- must not error with no chain

  local zoomedBefore = game.save
  Game.wheelmoved(game, 0, 1)  -- must not error; Game.wheelmoved needs no save
  run.release()
end

-- ------- the subscribed path, through the loader-created mod API

local run = T.sdk.loadMods(
  { "mods/fix_key_gamepad_wheel" }, { fs = T.sdk.memfs(FIXTURES) })
T.eq(#run.errors, 0,
  "the fixture mod loads clean (" .. tostring(run.errors[1]) .. ")")

local fx = run.loader.exports.fix_key_gamepad_wheel
local game = fakeGame(run.loader, run.data)
Input:init()

local function wipe()
  for _, t in ipairs({ fx.seenKey, fx.seenPad, fx.seenWheel }) do
    for i = #t, 1, -1 do t[i] = nil end
  end
end

-- input.key: payload shape, and observing (calling next) changes nothing
do
  wipe()
  fx.setSwallow(false)
  Game.keypressed(game, "up")
  Game.keyreleased(game, "up")
  T.eq(#fx.seenKey, 2, "keypressed+keyreleased each reach the hook once")
  T.eq(fx.seenKey[1].phase, "pressed", "...pressed first")
  T.eq(fx.seenKey[1].key, "up", "...carrying the key")
  T.eq(fx.seenKey[2].phase, "released", "...released second")
  T.eq(Input:isDown("up"), false, "calling next() lets the release reach Input")
end

-- input.key: NOT calling next is real suppression -- the game never sees it
do
  wipe()
  fx.setSwallow(true)
  Game.keypressed(game, "left")
  T.eq(#fx.seenKey, 1, "the swallowed key still reaches the hook once")
  T.eq(Input:isDown("left"), false,
    "a wrapper that returns without calling next prevents Input:keypressed "
    .. "from ever running -- real suppression, not observation")
  fx.setSwallow(false)
  Game.keyreleased(game, "left")  -- clean up any stray state
end

-- input.key: a key the mod doesn't care about still falls all the way
-- through to Input, even while swallow is armed for a different key
do
  wipe()
  fx.setSwallow(true)
  Game.keypressed(game, "right")
  T.eq(#fx.seenKey, 1, "an unrelated key still reaches the hook")
  T.eq(Input:isDown("right"), true,
    "...and still reaches Input, since this wrapper only swallows \"left\"")
  Game.keyreleased(game, "right")
  fx.setSwallow(false)
end

-- input.gamepad: press/release/axis all reach the hook with the right shape
do
  wipe()
  fx.setSwallow(false)
  Game.gamepadpressed(game, nil, "b")
  Game.gamepadreleased(game, nil, "b")
  Game.gamepadaxis(game, nil, "lefty", 0.4)
  T.eq(#fx.seenPad, 3, "press, release, and axis each reach the hook once")
  T.eq(fx.seenPad[1].phase, "pressed", "...pressed first")
  T.eq(fx.seenPad[1].button, "b", "...carrying the button")
  T.eq(fx.seenPad[2].phase, "released", "...released second")
  T.eq(fx.seenPad[3].phase, "axis", "...axis third")
  T.eq(fx.seenPad[3].button, nil, "axis carries no button")
  T.eq(fx.seenPad[3].axis, "lefty", "...carrying the axis name")
  T.eq(fx.seenPad[3].value, 0.4, "...and its value")
  T.eq(Input:isDown("b"), false, "observed release still reaches Input")
end

-- input.gamepad: real suppression on a pressed button
do
  wipe()
  fx.setSwallow(true)
  Game.gamepadpressed(game, nil, "a")
  T.eq(#fx.seenPad, 1, "the swallowed press still reaches the hook once")
  T.eq(Input:isDown("a"), false,
    "a wrapper that returns without calling next prevents "
    .. "Input:gamepadpressed from ever running")
  fx.setSwallow(false)
end

-- input.wheel: reaches the hook, and consuming it stops the zoom call from
-- happening (checked as "no error and only one event seen", since Game's
-- own zoomStep needs a real self.save this fixture does not provide --
-- the point under test is whether `next` runs, not what zoomStep does)
do
  wipe()
  fx.setSwallow(false)
  Game.wheelmoved(game, 0, 1)
  T.eq(#fx.seenWheel, 1, "a wheel event reaches the hook")
  T.eq(fx.seenWheel[1], 1, "...carrying the raw delta")
end

run.release()

T.finish("key_gamepad_wheel_input")
