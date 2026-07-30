-- A wild mon that escapes with TELEPORT ends the turn where it lands
-- (#441).  MainInBattleLoop reads wEscapedFromBattle right after
-- ExecuteEnemyMove and rets (engine/battle/core.asm:417-421, 456-460), so
-- the second mover never announces, HandlePoisonBurnLeechSeed never runs
-- the residual sweep, and CheckNumAttacksLeft never releases a trapping
-- counter.  resolveTurn queues both movers plus endOfTurn up front, so the
-- escape has to be observed by the rows themselves.
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

Data.moves.TELEPORT = {
  id = "TELEPORT", index = 100, name = "TELEPORT",
  type = "PSYCHIC", power = 0, accuracy = 100, pp = 20,
  effect = "SWITCH_AND_TELEPORT_EFFECT",
}

local function newGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  return { data = Data, save = save,
           stack = { top = function() return nil end, push = function() end } }
end

-- enemy first: the escaping mon outspeeds, and it holds TELEPORT alone so
-- the wild success path (level 40 >= level 30) cannot roll a failure
local function setup(enemyMove)
  local battle = BattleState.newWild(newGame(), "FIXMON_C", 40)
  battle.player.mon.stats.speed = 1
  battle.enemy.mon.stats.speed = 200
  battle.enemy.mon.moves = { { id = enemyMove, pp = 20 } }
  battle.enemy.curMoves = battle.enemy.mon.moves
  battle.enemyAction = function() return battle.enemy.curMoves[1] end
  battle.rng = function(lo) return lo end -- accuracy roll hits, damage roll floors
  return battle
end

-- drain the queue the way updateQueue does (fn rows run with nextInsert
-- reset so sayNext/actNext land right behind the current row), collecting
-- every message the turn would have printed
local function pump(battle)
  local said = {}
  local guard = 0
  while battle.queue[1] and guard < 400 do
    guard = guard + 1
    local item = table.remove(battle.queue, 1)
    if item.fn then
      battle.nextInsert = 0
      item.fn()
    elseif item.text then
      said[#said + 1] = item.text
    end
  end
  T.check(guard < 400, "the turn queue drained")
  return said
end

local function saidWith(said, needle)
  for _, line in ipairs(said) do
    if line:find(needle, 1, true) then return line end
  end
  return nil
end

-- --- the escape turn -------------------------------------------------
local battle = setup("TELEPORT")
battle.player.mon.status = "PSN"
local tackle = battle.player.curMoves[1]
local startEnemyHP, startPlayerHP = battle.enemy.mon.hp, battle.player.mon.hp
local startPP = tackle.pp

battle:resolveTurn(tackle)
local said = pump(battle)

T.check(saidWith(said, "ran from battle!"), "the wild mon announces the escape")
T.eq(battle.result, "run", "the escape settles the battle as a run")
T.eq(battle.afterQueue, "finish", "the queue finishes instead of reopening the menu")
T.check(not saidWith(said, "FIX TACKLE"),
  "the second mover never announces its move after the escape")
T.eq(battle.enemy.mon.hp, startEnemyHP, "the escaped mon takes no damage")
T.eq(tackle.pp, startPP, "the lost turn costs the second mover no PP")
T.check(not saidWith(said, "hurt by"), "the residual sweep is skipped")
T.eq(battle.player.mon.hp, startPlayerHP, "no poison tick on the escape turn")

-- --- the trapping counter, on its own -------------------------------
-- a counter sitting at 0 holds its victim until CheckNumAttacksLeft clears
-- it, so it rides a separate turn: the held player must not be what keeps
-- the second mover from moving above.
local trap = setup("TELEPORT")
trap.enemy.trappingTurns = 0
trap:resolveTurn(trap.player.curMoves[1])
pump(trap)
T.eq(trap.result, "run", "the escape still settles the trapped turn")
T.eq(trap.enemy.trappingTurns, 0,
  "CheckNumAttacksLeft does not release the counter on the escape turn")

local trapOk = setup("FIX_TACKLE")
trapOk.enemy.trappingTurns = 0
trapOk:resolveTurn(trapOk.player.curMoves[1])
pump(trapOk)
T.eq(trapOk.enemy.trappingTurns, nil,
  "an ordinary turn releases the spent counter")

-- --- a plain turn still does all of it ------------------------------
local ok = setup("FIX_TACKLE")
ok.player.mon.status = "PSN"
local scratch = ok.player.curMoves[1]
local okEnemyHP, okPlayerHP = ok.enemy.mon.hp, ok.player.mon.hp
local okPP = scratch.pp

ok:resolveTurn(scratch)
local okSaid = pump(ok)

T.eq(ok.result, nil, "an ordinary turn settles nothing")
T.check(saidWith(okSaid, "FIX TACKLE"), "both movers announce")
T.check(ok.enemy.mon.hp < okEnemyHP, "the second mover's move lands")
T.eq(scratch.pp, okPP - 1, "the second mover spends PP")
T.check(ok.player.mon.hp < okPlayerHP, "the poison tick runs")
T.check(saidWith(okSaid, "hurt by"), "the residual sweep prints")

Data.moves.TELEPORT = nil
T.finish("teleport escape ends turn")
