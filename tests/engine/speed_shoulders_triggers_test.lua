-- The built-in GAME SPEED hotkeys on controller: the shoulder buttons
-- (L1/R1) and the analog triggers (L2/R2) all cycle the engine speed
-- ladder, R-side faster and L-side slower, exactly like keyboard hotkey
-- No pokered cite: port-only (gap C2).
--   luajit tests/engine/speed_shoulders_triggers_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
Input:init()

local dirs = {}
local game = {
  save = { options = { speed = 1 } },
  _cycleSpeed = function(self, dir)
    dirs[#dirs + 1] = dir
    self.save.options.speed = self.save.options.speed + dir
  end,
  stack = { top = function() return nil end },
}
function game:writeOptions() end

local function last()
  return dirs[#dirs]
end

-- ---- shoulders ----------------------------------------------------------
dirs = {}
Game.gamepadpressed(game, nil, "rightshoulder")
eq(last(), 1, "R1 speeds up")
Game.gamepadpressed(game, nil, "leftshoulder")
eq(last(), -1, "L1 slows down")

-- ---- analog triggers ----------------------------------------------------
dirs = {}
Input:reset()
Game.gamepadaxis(game, nil, "triggerright", 0.3)
Game.gamepadaxis(game, nil, "triggerright", 0.35)
eq(#dirs, 0, "resting-trigger drift under the ON threshold is not a press")
Game.gamepadaxis(game, nil, "triggerright", 1.0)
eq(last(), 1, "R2 past the threshold speeds up")
eq(#dirs, 1, "exactly once")
Game.gamepadaxis(game, nil, "triggerright", 1.0)
Game.gamepadaxis(game, nil, "triggerright", 0.45)
Game.gamepadaxis(game, nil, "triggerright", 0.3)
eq(#dirs, 1, "a held trigger is an edge, not a level, and jitter is neither")
Game.gamepadaxis(game, nil, "triggerright", 0.0)
eq(#dirs, 1, "the release cycles nothing by itself")
Game.gamepadaxis(game, nil, "triggerright", 1.0)
eq(#dirs, 2, "but the next crossing is a fresh press")
eq(last(), 1, "still faster")
Game.gamepadaxis(game, nil, "triggerleft", 1.0)
eq(last(), -1, "L2 slows down")
eq(Input.stickDir, nil, "and no trigger sample ever moved the walk direction")

Input:reset()
local routed = nil
game.stack.top = function()
  return { onGamepadPressed = function(_, b) routed = b end }
end
Game.gamepadpressed(game, nil, "a")
eq(routed, "a", "a normal button still reaches the top-state pad routing")
routed = nil
Game.gamepadpressed(game, nil, "rightshoulder")
eq(routed, "rightshoulder",
   "a screen owning pad input sees L1/R1 too, so CONTROLS can capture them")
Game.gamepadaxis(game, nil, "triggerleft", 1.0)
eq(routed, "triggerleft",
   "and a trigger arrives there under its axis name, so CONTROLS can bind L2")
check(#dirs == 3, "a captured shoulder never touches the speed ladder")

game.stack.top = function() return nil end
local forwarded = nil
local origPad = Input.gamepadpressed
function Input:gamepadpressed(joystick, button) forwarded = button end
Game.gamepadpressed(game, nil, "rightshoulder")
check(forwarded == nil, "the speed buttons never reach the GB button map")
eq(#dirs, 4, "and they still cycle the ladder")
Game.gamepadpressed(game, nil, "a")
eq(forwarded, "a", "everything else does reach it")
Input:reset()
Game.gamepadaxis(game, nil, "triggerleft", 1.0)
eq(#dirs, 5, "a trigger speed action does not reach it either")
Input.gamepadpressed = origPad

Input:init()
Input:applyBindings({ a = { pad = "triggerright" }, speedUp = false })
game.stack.top = function() return nil end
Game.gamepadaxis(game, nil, "triggerright", 1.0)
Input:step()
check(Input:isDown("a"), "a held L2/R2 holds the GB button it is bound to")
Game.gamepadaxis(game, nil, "triggerright", 0.3)
Input:step()
check(Input:isDown("a"), "jitter above OFF does not drop the hold")
Game.gamepadaxis(game, nil, "triggerright", 0.0)
Input:step()
check(not Input:isDown("a"), "and the release lets go")
Input:init()

dirs = {}
Input:applyBindings({ speedUp = { pad = "joy12" } })
eq(Input:joyAction(12), "speedUp", "the joyN decode reaches the action map")
Game.joystickpressed(game, nil, 12)
eq(last(), 1, "and the raw press cycles the ladder")
eq(#dirs, 1, "once")
Input:step()
local held = 0
for _ in pairs(Input.state) do held = held + 1 end
eq(held, 0, "without also pressing a Game Boy button")
Input:init()

T.finish("speed_shoulders_triggers")
