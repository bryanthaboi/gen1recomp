package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq
local Game2 = require("src.core.Game2")
local AtlasPrefetch = require("src.render.AtlasPrefetch")

local calls = 0
local update = AtlasPrefetch.update
AtlasPrefetch.update = function() calls = calls + 1 end

local game = setmetatable({ phase = "field", logicSpeed = function() return 1 end }, Game2)
Game2.update(game, 0)
eq(calls, 1, "a Gen 2 frame drains the background decode store")

AtlasPrefetch.update = update
T.finish("Gen 2 atlas prefetch drain")
