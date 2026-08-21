-- Gold noop'd the raw joystick road, so a stick with no SDL game-controller-db
-- entry pressed nothing in Gold while working in Gen 1 (#1570).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Input = require("src.core.Input")

local CALLBACKS = {
  "keypressed", "keyreleased",
  "gamepadpressed", "gamepadreleased", "gamepadaxis",
  "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat",
  "joystickadded", "joystickremoved",
}

for _, name in ipairs(CALLBACKS) do
  eq(type(Game[name]), "function", "Gen 1 routes " .. name)
  eq(type(Game2[name]), "function", "Gold routes " .. name)
end

local rawJoy = { isGamepad = function() return false end }
local gamepadJoy = { isGamepad = function() return true end }

local function newGold(top)
  return setmetatable({
    options = {},
    stack = { top = function() return top end },
  }, Game2)
end

Input:init()
local gold = newGold(nil)

gold:joystickpressed(rawJoy, 1)
Input:step()
check(Input:wasPressed("a"), "raw stick button 1 presses GB A in Gold")
check(Input:isDown("a"), "raw stick hold survives the step in Gold")
gold:joystickreleased(rawJoy, 1)
Input:step()
check(not Input:isDown("a"), "raw stick release clears the hold in Gold")

gold:joystickhat(rawJoy, 1, "l")
Input:step()
check(Input:wasPressed("left"), "raw hat left presses GB LEFT in Gold")
gold:joystickhat(rawJoy, 1, "c")
Input:step()
check(not Input:isDown("left"), "raw hat centre clears GB LEFT in Gold")

gold:joystickaxis(rawJoy, 2, 1)
Input:step()
check(Input:wasPressed("down"), "raw axis 2 presses GB DOWN in Gold")
gold:joystickaxis(rawJoy, 2, 0)
Input:step()
check(not Input:isDown("down"), "raw axis 2 back to centre clears GB DOWN")

-- A recognized pad raises BOTH roads for one press; the raw half must not
-- re-assert the factory map underneath a rebind (#620, #632).
Input:init()
gold = newGold(nil)
gold:gamepadpressed(gamepadJoy, "a")
gold:joystickpressed(gamepadJoy, 1)
gold:joystickpressed(gamepadJoy, 2)
Input:step()
check(Input:wasPressed("a"), "recognized pad A reaches Input in Gold")
check(not Input:wasPressed("b"), "raw must not stack B onto a recognized pad")

-- src/ui/BindingsMenu.lua's capture slots: Gold now hands the top state first
-- refusal on both roads, the way src/core/Game.lua does.
Input:init()
local captured = {}
local capturingTop = {
  onJoystickPressed = function(_, button) captured.joy = button end,
  onGamepadPressed = function(_, button) captured.pad = button end,
}
gold = newGold(capturingTop)
gold:joystickpressed(rawJoy, 3)
gold:gamepadpressed(gamepadJoy, "y")
Input:step()
eq(captured.joy, 3, "an armed CONTROLS row captures the raw button")
eq(captured.pad, "y", "an armed CONTROLS row captures the pad button")
check(not Input:wasPressed("a"), "a captured press never reaches gameplay")

-- Hotplug: the reset+reconcile Gen 1 runs, so a pad that vanished mid-hold
-- cannot strand a direction down (#799).
Input:init()
gold = newGold(nil)
gold:joystickpressed(rawJoy, 1)
Input:step()
check(Input:isDown("a"), "held before the hotplug")
gold:joystickadded(rawJoy)
Input:step()
check(not Input:isDown("a"), "joystickadded drops stranded holds in Gold")

gold:joystickpressed(rawJoy, 1)
Input:step()
gold:joystickremoved(rawJoy)
Input:step()
check(not Input:isDown("a"), "joystickremoved drops stranded holds in Gold")

T.finish()
