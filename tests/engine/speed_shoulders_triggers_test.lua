-- The built-in GAME SPEED hotkeys on controller: the shoulder buttons
-- (L1/R1) and the analog triggers (L2/R2) all cycle the engine speed
-- ladder, R-side faster and L-side slower, exactly like keyboard hotkey
-- 1.  Anything else must still fall through to the top-state pad
-- routing and never touch the speed ladder.  LÖVE reports an analog
-- trigger as gamepadpressed once it crosses the press threshold, so
-- "lefttrigger"/"righttrigger" land here like any other pad button.
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
Game.gamepadpressed(game, nil, "righttrigger")
eq(last(), 1, "R2 speeds up")
Game.gamepadpressed(game, nil, "lefttrigger")
eq(last(), -1, "L2 slows down")

-- ---- everything else falls through to the top-state pad routing ---------
local routed = nil
game.stack.top = function()
  return { onGamepadPressed = function(_, b) routed = b end }
end
Game.gamepadpressed(game, nil, "a")
eq(routed, "a", "a normal button still reaches the top-state pad routing")
routed = nil
Game.gamepadpressed(game, nil, "rightshoulder")
check(routed == nil, "the speed buttons are consumed, never routed to a menu")
Game.gamepadpressed(game, nil, "lefttrigger")
check(routed == nil, "a trigger pull is consumed the same way")
check(#dirs == 4, "only the speed buttons touched the speed ladder")

T.finish("speed_shoulders_triggers")
