package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local Pokemon = require("src.core.game3.pokemon")
local realInstall = Pokemon.install
local realRows = Pokemon._battleMoves
Pokemon.install = function() end

Pokemon._battleMoves = nil
local ok, err = pcall(Pokemon.battleMove, 2)
check(not ok and tostring(err):find("battle_moves.lua", 1, true) ~= nil,
  "a missing cache battle move table raises instead of reading a typed table (" .. tostring(err) .. ")")
ok = pcall(Pokemon.movePp, 2)
check(not ok, "move PP has no typed fallback either")

Pokemon._battleMoves = { [2] = { pp = 7, power = 1 } }
check(Pokemon.battleMove(2).pp == 7, "a battle move row comes from the cache table")
check(Pokemon.movePp(2) == 7, "move PP comes from the cache row")
check(Pokemon.battleMove(400) == nil, "an id past the cache table has no row")

local f = io.open("src/core/game3/battle/builtin_moves.lua", "rb")
if f then f:close() end
check(f == nil, "the hand-typed FireRed move table is gone")

local MonOps = require("tools.save-editor.MonOps")
Pokemon._battleMoves = nil
local okG1, pp1 = pcall(MonOps.getBasePp, { moves = {} }, { moves = { 2 } }, 1)
check(okG1 and pp1 == 10, "a Gen 1/2 mon never reads Gen 3 move data (" .. tostring(pp1) .. ")")
Pokemon._battleMoves = { [2] = { pp = 7 } }
check(MonOps.getBasePp({ moves = {} }, { personality = 1, moves = { 2 } }, 1) == 7,
  "a Gen 3 mon's base PP comes from the cache row")

Pokemon.install = realInstall
Pokemon._battleMoves = realRows
T.finish("game3_battle_move_rom_only")
