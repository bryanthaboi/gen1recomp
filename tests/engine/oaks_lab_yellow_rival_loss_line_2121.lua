-- pokeyellow scripts/OaksLab.asm:340-364, home/trainers.asm:312-374,
-- engine/battle/core.asm:947-958; pokered scripts/OaksLab.asm:404-409.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("oaks lab yellow rival loss line")
local check, eq = S.check, S.eq

local LOSS = "_OaksLabRivalIPickedTheWrongPokemonText"

local function fakeOw(rival)
  local captured
  local ow = {
    npcByIndex = function(_, i) return i == 1 and rival or nil end,
    map = {
      inBounds = function() return true end,
      isWalkableCell = function() return true end,
    },
    runner = { run = function(_, rows) captured = rows return true end },
  }
  return ow, function() return captured end
end

local function challengeRows(path, x, y)
  local M = assert(loadfile(path))()
  local ow, rows = fakeOw({ cellX = 7, cellY = 4 })
  local game = { save = { flags = {
    EVENT_GOT_STARTER = true,
    EVENT_CHOSE_PIKACHU = true,
    EVENT_BATTLED_RIVAL_IN_OAKS_LAB = false,
  } } }
  local ok = M.onStep(game, ow, x, y)
  check(ok == true, path .. ": onStep claims the rival-challenge step")
  check(rows() ~= nil, path .. ": the challenge rows reached the runner")
  return rows() or {}
end

local function find(rows, verb, arg, from)
  for i = from or 1, #rows do
    local row = rows[i]
    if row[1] == verb and (arg == nil or row[2] == arg) then return i, row end
  end
end

local ScriptRunner = require("src.script.ScriptRunner")

for _, x in ipairs({ 4, 5 }) do
  local rows = challengeRows("data/scripts/oaks_lab_yellow.lua", x, 6)
  local iBattle, battle = find(rows, "start_battle")
  check(iBattle ~= nil, ("x=%d the step starts the rival battle"):format(x))
  check(battle and battle[3] == "OPP_RIVAL1" and battle[4] == 1,
        ("x=%d it is OPP_RIVAL1 roster 1"):format(x))
  local iArm = find(rows, "save_end_battle_text", LOSS)
  check(iArm ~= nil, ("x=%d %s is armed for the battle"):format(x, LOSS))
  check(iBattle and iArm == iBattle - 1,
        ("x=%d SaveEndBattleTextPointers runs just before the battle"):format(x))
  eq(select("#", find(rows, "save_end_battle_text", nil, (iArm or 0) + 1)), 0,
     ("x=%d only one end-battle text is armed"):format(x))
  check(find(rows, "show_text", LOSS) == nil,
        ("x=%d the loss line is not also printed on the map"):format(x))
  local iHeal = find(rows, "heal_party")
  check(iHeal and iBattle and iHeal > iBattle,
        ("x=%d the heal follows the battle"):format(x))
  local problems = ScriptRunner.validate(rows)
  eq(#problems, 0, ("x=%d challenge rows validate: %s"):format(
     x, table.concat(problems, "; ")))
end

do
  local M = assert(loadfile("data/scripts/oaks_lab.lua"))()
  local ow, rows = fakeOw({ cellX = 7, cellY = 4 })
  local game = { save = { flags = {
    EVENT_GOT_STARTER = true,
    EVENT_CHOSE_BULBASAUR = true,
    EVENT_BATTLED_RIVAL_IN_OAKS_LAB = false,
  } } }
  M.onStep(game, ow, 4, 6)
  local red = rows() or {}
  local iBattle = find(red, "start_battle")
  local iArm = find(red, "save_end_battle_text", LOSS)
  check(iArm and iBattle and iArm == iBattle - 1,
        "Red's lab script arms the same loss line before its battle")
  local yellow = challengeRows("data/scripts/oaks_lab_yellow.lua", 4, 6)
  local _, yArm = find(yellow, "save_end_battle_text", LOSS)
  local _, rArm = find(red, "save_end_battle_text", LOSS)
  eq(yArm and yArm[2], rArm and rArm[2],
     "Yellow and Red hand the battle the same text id")
end

S.finish()
