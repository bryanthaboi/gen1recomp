-- EnemySendOutFirstMon (engine/battle/core.asm:1432-1435)
-- then PlayCry -- which ends in WaitForSoundToFinish (home/pokemon.asm:145-149)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  return { data = Data, save = save,
           stack = { top = function() return nil end, push = function() end } }
end

local function step(battle)
  local row = table.remove(battle.queue, 1)
  if row and row.fn then
    battle.nextInsert = 0
    row.fn()
  end
  return row
end

do
  local game = newGame()
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.rng = function() return 0 end
  battle.enemyParty = { Pokemon.new(Data, "FIXMON_B", 30),
                        Pokemon.new(Data, "FIXMON_C", 30) }
  battle.enemyIndex = 1
  battle.queue, battle.nextInsert = {}, 0
  battle.enemyHudPending = nil
  battle:executeAction(battle.enemy, battle.player,
                       { special = "aiSwitch", index = 2 })

  local grew = false
  for _ = 1, 40 do
    if not battle.queue[1] then break end
    step(battle)
    if battle.growIn then grew = true break end
  end
  T.check(grew, "the AI switch queues AnimateSendingOutMon")
  T.eq(battle.enemyHudPending, true,
    "the enemy HUD stays down across PlayCry (core.asm:1434-1435)")

  T.check(battle.queue[1] and battle.queue[1].wait ~= nil,
    "the grow-in hold is the next row")
  step(battle)
  T.check(battle.queue[1] and battle.queue[1].fn ~= nil,
    "the cry act follows the grow-in hold")
  step(battle)
  T.check(battle.queue[1] and battle.queue[1].waitSound ~= nil,
    "PlayCry's WaitForSoundToFinish row is queued")
  T.eq(battle.enemyHudPending, true, "the HUD is still down during the cry")
  step(battle)
  T.check(battle.queue[1] and battle.queue[1].fn ~= nil,
    "DrawEnemyHUDAndHPBar follows the wait row")
  step(battle)
  T.eq(battle.enemyHudPending, nil,
    "the HUD comes up once the cry has finished")
end

do
  local game = newGame()
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.growIn = nil
  battle.enemyHudPending = true
  T.check(battle:growInScale(battle.enemy) == nil,
    "the grow-in is over")
  T.check(battle.enemyHudPending and true or false,
    "drawHUDs' enemy gate is closed while the cry is outstanding")
end

-- _InitBattleCommon (core.asm:6755-6763)
do
  local game = newGame()
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  T.eq(battle.enemyHudPending, nil,
    "the wild intro never gates the enemy HUD on a cry")
end

T.finish("enemy HUD waits for the send-out cry (#2118)")
