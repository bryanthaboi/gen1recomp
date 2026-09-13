-- engine/battle/core.asm:293
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

Data.moves.FIX_THRASH = {
  id = "FIX_THRASH", index = 91, name = "FIX THRASH", type = "NORMAL",
  power = 90, accuracy = 100, pp = 20, effect = "THRASH_PETAL_DANCE_EFFECT",
}

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 40) }
  local game = { data = Data, save = save,
                 input = { wasPressed = function() return false end,
                           isDown = function() return false end },
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = function(a) if a then return a end return 0 end
  battle.introSlide = nil
  return battle
end

local function drainToMenu(battle)
  battle.queue, battle.nextInsert = { { wait = 2 } }, 0
  battle.phase = "messages"
  battle.afterQueue = "menu"
end

local function stepNeverMenu(battle, label)
  local sawMenu, turns = nil, 0
  local startTurn = battle.turnCount or 0
  for i = 1, 10 do
    battle:update(1 / 60)
    if battle.phase == "menu" and not sawMenu then sawMenu = i end
  end
  turns = (battle.turnCount or 0) - startTurn
  T.check(sawMenu == nil, label .. ": no frame leaves phase == menu (first seen frame "
    .. tostring(sawMenu) .. ")")
  T.check(turns >= 1, label .. ": the locked turn still resolves")
end

do
  local battle = newBattle()
  battle.player.thrashTurns = 2
  battle.player.thrashMove = battle.player.curMoves[1]
  battle.player.thrashAnnounced = true
  drainToMenu(battle)
  stepNeverMenu(battle, "thrash")
end

do
  local battle = newBattle()
  battle.player.mustRecharge = true
  drainToMenu(battle)
  stepNeverMenu(battle, "recharge")
end

do
  local battle = newBattle()
  battle.player.charging = battle.player.curMoves[1]
  drainToMenu(battle)
  stepNeverMenu(battle, "charging")
end

do
  local battle = newBattle()
  battle.player.flinched = true
  battle.player.thrashTurns = 2
  battle.player.thrashMove = battle.player.curMoves[1]
  battle.player.thrashAnnounced = true
  battle.player.mon.hp = 40
  battle.player.shownHP = 10
  drainToMenu(battle)
  battle:update(1 / 60)
  battle:update(1 / 60)
  battle:update(1 / 60)
  battle:update(1 / 60)
  T.check(battle.player.flinched == false, "the locked drain clears the player's flinch")
end

do
  local battle = newBattle()
  drainToMenu(battle)
  local reached
  for i = 1, 10 do
    battle:update(1 / 60)
    if battle.phase == "menu" then reached = reached or i end
  end
  T.check(reached ~= nil, "an unlocked player reaches the command menu")
  T.eq(battle.phase, "menu", "and stays on it")
end

do
  local battle = newBattle()
  battle.kind = "link"
  battle.player.thrashTurns = 2
  battle.player.thrashMove = battle.player.curMoves[1]
  battle.player.thrashAnnounced = true
  local resolved = 0
  battle.resolveTurn = function() resolved = resolved + 1 end
  drainToMenu(battle)
  for _ = 1, 4 do
    if battle.phase ~= "messages" then break end
    battle:update(1 / 60)
  end
  T.eq(battle.phase, "menu", "a link battle's drain still lands on phase == menu")
  T.eq(resolved, 0, "and leaves the locked action to the menu branch")
end

T.finish("locked turn skips the command menu frame (#2252)")
