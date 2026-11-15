package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install = function() end
Pokemon._moveNames = { [1] = "ROM POUND" }

check(Pokemon.moveName(1) == "ROM POUND", "a move name comes from the cache table")
check(Pokemon.moveName(0) == "-------", "MOVE_NONE prints the dashes")
local ok, err = pcall(Pokemon.moveName, 2)
check(not ok and tostring(err):find("move 2 has no name in the cache", 1, true) ~= nil,
  "a move the cache has no name for raises instead of a typed table name (" .. tostring(err) .. ")")

local src = assert(io.open("src/ui/game3/summary_menu.lua", "rb")):read("*a")
check(not src:find('"MOVE %s"', 1, true), "the summary has no MOVE %s placeholder name")
local mc = assert(io.open("src/core/game3/scripting/multichoice.lua", "rb")):read("*a")
check(not mc:find('"OPTION %s"', 1, true), "multichoice has no OPTION %s placeholder label")

T.finish("game3_move_name_rom_only")
