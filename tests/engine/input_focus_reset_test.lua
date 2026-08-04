-- Focus / visibility loss clears held directions (SWNX-18).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check

local Input = require("src.core.Input")
local Game = require("src.core.Game")

Input:init()
Input:keypressed("left")
Input:step()
check(Input:isDown("left"), "left held before focus loss")

Game:focus(false)
check(not Input:isDown("left"), "focus loss clears held direction")

Input:keypressed("up")
Input:step()
Game:visible(false)
check(not Input:isDown("up"), "visibility loss clears held direction")

T.finish()
