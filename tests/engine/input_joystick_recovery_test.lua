-- Joystick remove / resume clears stuck input sources (SWNX-19).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check

local Input = require("src.core.Input")
local Game = require("src.core.Game")

Input:init()
Input:gamepadaxis(nil, "leftx", -0.9)
Input:step()
check(Input:isDown("left"), "stick holds left before disconnect")

Game:joystickremoved({})
check(not Input:isDown("left"), "joystickremoved clears stick hold")

Input:gamepadpressed(nil, "a")
Input:step()
check(Input:isDown("a"), "button held before reconnect reset")
Game:joystickadded({ getName = function() return "Joy-Con" end })
check(not Input:isDown("a"), "joystickadded clears stale button hold")

Input:gamepadaxis(nil, "lefty", 0.9)
Input:step()
Game:onResume()
check(not Input:isDown("down"), "resume clears stuck axis state")

T.finish()
