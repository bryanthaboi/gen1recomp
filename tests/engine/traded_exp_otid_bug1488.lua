-- GainExperience compares MON_OTID against wPlayerID at every award
-- (engine/battle/experience.asm:69-88) (#1488)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function boostedText(mutate)
  local save = SaveData.newGame()
  save.player.id = save.player.id or 1234
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  mutate(save.party[1], save)
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 10)
  battle.participants = { [save.party[1]] = true }
  battle:enemyMonFainted()
  for _, item in ipairs(battle.queue) do
    if item.text and item.text:find("boosted", 1, true) then return true end
  end
  return false
end

T.eq(boostedText(function(mon, save) mon.otId = save.player.id end), false,
  "a mon whose OTID is the player's own earns no boost")
T.eq(boostedText(function(mon, save) mon.otId = (save.player.id or 0) + 1 end), true,
  "a foreign OTID trips BoostExp")
T.eq(boostedText(function(mon, save)
  -- traded away and traded back: the stored OTID is the player's again
  mon.traded = true
  mon.otId = save.player.id
end), false, "and a mon traded back to its original trainer loses it (#1488)")
T.eq(boostedText(function(mon)
  -- repairTradedOtIds leaves traded mons with otId nil (#1265, #1461)
  mon.traded = true
  mon.otId = nil
end), true, "a traded mon with no stored OTID keeps the boost (#1488)")

T.finish("traded exp boost is an OTID comparison (#1488)")
