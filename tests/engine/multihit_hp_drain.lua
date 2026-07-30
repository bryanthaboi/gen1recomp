-- A multi-hit move must step the target's HP bar down once per strike
-- (#394).  ApplyDamageToEnemyPokemon (engine/battle/core.asm:4684-4727)
-- subtracts wDamage and runs UpdateHPBar2 inside the wNumAttacksLeft loop,
-- so the bar animates one hit's worth per pass; the port takes every
-- strike off the model while the turn is still being queued, so each drain
-- row has to carry its own stop.
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

local HITS = 3
Data.moves.FIX_MULTI = {
  id = "FIX_MULTI", index = 99, name = "FIX MULTI",
  type = "NORMAL", power = 15, accuracy = 100, pp = 10,
  effect = "TWO_TO_FIVE_ATTACKS_EFFECT", multiHit = HITS,
}

local function mkseq(vals) -- scripted rng: pops vals, then max rolls
  local i = 0
  return function(_, hi)
    i = i + 1
    return vals[i] ~= nil and vals[i] or hi
  end
end

local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
local battle = BattleState.newWild(game, "FIXMON_C", 40)
battle.rng = mkseq({ 0, 255, 255 }) -- hit, no crit, max damage roll

local startHP = battle.enemy.mon.hp
battle:performMove(battle.player, battle.enemy, { id = "FIX_MULTI", pp = 10 })

local drains = {}
for _, row in ipairs(battle.queue) do
  if row.drain then drains[#drains + 1] = row end
end
T.eq(#drains, HITS, "a drain row per strike")

local perHit = (startHP - battle.enemy.mon.hp) / HITS
T.check(perHit > 1, "the strikes take more than a pixel of bar each")
for h, row in ipairs(drains) do
  T.eq(row.battler, battle.enemy, "drain row " .. h .. " names the target")
  T.eq(row.stopAt, startHP - perHit * h,
    "drain row " .. h .. " stops at the HP left after strike " .. h)
end

-- replay the rows the way updateQueue consumes them: the row's stopAt
-- becomes the battler's drainFloor, the drain runs to a stop, the floor is
-- cleared.  Before the fix every row read the live post-last-hit HP, so
-- row 1 emptied the whole total and rows 2..n moved nothing.
local settled = {}
for _, row in ipairs(drains) do
  local before = battle.enemy.shownHP
  battle.enemy.drainFloor = row.stopAt
  local frames = 0
  while battle:stepHPDrain() and frames < 4000 do frames = frames + 1 end
  battle.enemy.drainFloor = nil
  T.check(battle.enemy.shownHP < before, "the bar moved on this strike")
  settled[#settled + 1] = battle.enemy.shownHP
end
for h, hp in ipairs(settled) do
  T.eq(hp, startHP - perHit * h, "the bar rests on strike " .. h .. "'s HP")
end
T.eq(settled[#settled], battle.enemy.mon.hp,
  "the last strike leaves the bar on the true HP")

-- a single-hit drain still runs to the live HP with no stop pinned
local single = BattleState.newWild(game, "FIXMON_C", 40)
single.rng = mkseq({ 0, 255, 255 })
single:performMove(single.player, single.enemy, { id = "FIX_TACKLE", pp = 35 })
local rows = 0
for _, row in ipairs(single.queue) do
  if row.drain then
    rows = rows + 1
    T.eq(row.stopAt, single.enemy.mon.hp, "the single drain stops at the new HP")
  end
end
T.eq(rows, 1, "one strike queues one drain")
local frames = 0
single.enemy.drainFloor = single.enemy.mon.hp
while single:stepHPDrain() and frames < 4000 do frames = frames + 1 end
T.eq(single.enemy.shownHP, single.enemy.mon.hp, "the single drain settles")

Data.moves.FIX_MULTI = nil
T.finish("multihit hp drain")
