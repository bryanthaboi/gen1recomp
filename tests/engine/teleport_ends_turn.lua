-- A successful Teleport/Roar/Whirlwind ends the turn where it lands: the
-- second mover never moves and the residual sweep never runs (#438).
-- MainInBattleLoop reads wEscapedFromBattle after every Execute*Move and
-- `ret nz` (engine/battle/core.asm:419-457), leaving the loop before the
-- other side's move and before HandlePoisonBurnLeechSeed; the port queues
-- both moves plus endOfTurn up front, so each has to re-read battle.result.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

-- keyed TELEPORT because SwitchAndTeleportEffect picks its escape and
-- failure text off the move id (Roar and Whirlwind read differently)
Data.moves.TELEPORT = {
  id = "TELEPORT", index = 97, name = "FIX TELEPORT",
  type = "PSYCHIC", power = 0, accuracy = 100, pp = 20,
  effect = "SWITCH_AND_TELEPORT_EFFECT",
}
Data.moves.FIX_SING = {
  id = "FIX_SING", index = 98, name = "FIX SING",
  type = "NORMAL", power = 0, accuracy = 55, pp = 15,
  effect = "SLEEP_EFFECT",
}

local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }

-- foeLevel decides SwitchAndTeleportEffect's auto-success (effects.asm:
-- 810-909): at or above the player's level it always escapes, below it
-- the rng(0, sum) roll of 0 below foeLevel/4 always fails
local function setup(foeLevel)
  local battle = BattleState.newWild(game, "FIXMON_C", foeLevel)
  battle.rng = function() return 0 end
  battle.enemyAction = function() return { id = "TELEPORT", pp = 20 } end
  battle.enemy.curStats.speed = 200 -- the foe moves first
  battle.player.curStats.speed = 1
  battle.player.mon.status = "PSN" -- something for the residual sweep to do
  battle.player.mon.hp = battle.player.curStats.hp
  return battle, { id = "FIX_SING", pp = 15 }
end

-- consume the queue the way updateQueue does, minus the presentation
local function drain(battle)
  local texts = {}
  for _ = 1, 400 do
    local item = table.remove(battle.queue, 1)
    if not item then return texts end
    if item.text then texts[#texts + 1] = item.text end
    if item.fn then
      battle.nextInsert = 0
      item.fn()
    end
  end
  error("the turn queue never drained")
end

local function saidWith(texts, needle)
  for _, text in ipairs(texts) do
    if text:find(needle, 1, true) then return true end
  end
  return false
end

local escaped, sing = setup(40)
local hpBefore = escaped.player.mon.hp
escaped:resolveTurn(sing)
local texts = drain(escaped)

T.eq(escaped.result, "run", "the escape decides the battle")
T.eq(escaped.afterQueue, "finish", "the queue closes the battle")
T.check(saidWith(texts, "ran from battle"), "the foe announces the escape")
T.check(not saidWith(texts, "FIX SING"), "the player's move never announces")
T.eq(texts[#texts]:find("ran from battle", 1, true) ~= nil, true,
  "the escape line is the last thing printed")
T.eq(escaped.enemy.mon.status, nil, "the foe is gone, not asleep")
T.eq(sing.pp, 15, "the unspent move keeps its PP")
T.eq(escaped.player.mon.hp, hpBefore, "no residual poison tick after the escape")

-- the guard must not swallow the ordinary turn: a failed Teleport leaves
-- result nil, so the player still moves and the residual sweep still runs
local stayed, sing2 = setup(8)
local hpBefore2 = stayed.player.mon.hp
stayed:resolveTurn(sing2)
local texts2 = drain(stayed)

T.eq(stayed.result, nil, "a failed escape decides nothing")
T.eq(stayed.afterQueue, "menu", "the turn hands back to the menu")
T.check(saidWith(texts2, "But, it failed!"), "the failed Teleport says so")
T.check(saidWith(texts2, "FIX SING"), "the player still moves")
T.eq(stayed.enemy.mon.status, "SLP", "the foe still falls asleep")
T.eq(sing2.pp, 14, "the move that ran spent its PP")
T.check(stayed.player.mon.hp < hpBefore2, "the residual sweep still ticks poison")

Data.moves.TELEPORT = nil
Data.moves.FIX_SING = nil
T.finish("teleport ends turn")
