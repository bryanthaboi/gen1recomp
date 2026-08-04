-- When isGamepad(), raw face presses must not stack on gamepad* (NamingScreen a+b).
-- On NX, SDL face labels are swapped so physical A confirms / B cancels.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")
local Input = require("src.core.Input")

local gamepadJoy = {
  isGamepad = function() return true end,
}
local rawJoy = {
  isGamepad = function() return false end,
}

check(GamepadMap.ignoreRawForJoystick(gamepadJoy), "ignore raw when isGamepad")
check(not GamepadMap.ignoreRawForJoystick(rawJoy), "allow raw when not gamepad")
check(not GamepadMap.ignoreRawForJoystick(nil), "nil joystick does not ignore raw")

-- Desktop: SDL a → GB A (unchanged).
eq(GamepadMap.mapGamepadButton("a"), "a", "desktop SDL a -> GB A")
eq(GamepadMap.mapGamepadButton("b"), "b", "desktop SDL b -> GB B")

GamepadMap._setForceNXForTests(true)
eq(GamepadMap.mapGamepadButton("a"), "b", "NX SDL south (a) -> GB B (Nintendo B)")
eq(GamepadMap.mapGamepadButton("b"), "a", "NX SDL east (b) -> GB A (Nintendo A)")
eq(GamepadMap.mapRawButton(1), "b", "NX raw #1 Nintendo B -> GB B")
eq(GamepadMap.mapRawButton(2), "a", "NX raw #2 Nintendo A -> GB A")
eq(GamepadMap.mapRawButton(3), nil, "NX raw Y (#3) not mapped as confirm")
eq(GamepadMap.mapRawButton(4), nil, "NX raw X (#4) not mapped as confirm")
GamepadMap._setForceNXForTests(false)

Input:init()
Input:gamepadpressed(gamepadJoy, "a")
Input:joystickpressed(gamepadJoy, 1) -- must no-op
Input:joystickpressed(gamepadJoy, 2) -- must no-op
Input:step()
check(Input:wasPressed("a"), "desktop gamepad A edge present")
check(not Input:wasPressed("b"), "raw must not add B alongside gamepad A")
check(Input:isDown("a"), "A held from pad source only")

-- NX: physical A arrives as SDL "b" → GB A.
GamepadMap._setForceNXForTests(true)
Input:init()
Input:gamepadpressed(gamepadJoy, "b")
Input:step()
check(Input:wasPressed("a"), "NX physical A (SDL b) confirms as GB A")
check(not Input:wasPressed("b"), "NX physical A must not also erase")
GamepadMap._setForceNXForTests(false)

Input:init()
Input:joystickpressed(rawJoy, 1)
Input:step()
check(Input:wasPressed("a"), "non-gamepad raw #1 still maps to A on desktop")

T.finish()
