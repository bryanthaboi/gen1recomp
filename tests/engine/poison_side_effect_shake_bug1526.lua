-- A landed secondary POISON runs PoisonEffect's tail
-- (engine/battle/effects.asm:119-151): SHAKE_SCREEN_ANIM when the foe
-- poisoned you, ENEMY_HUD_SHAKE_ANIM when you poisoned the foe, through
-- PlayBattleAnimation2 (:1461-1471), which also stamps wAnimationType 6 /
-- 3 so the slow applying shake runs even with battle animations off.
-- FreezeBurnParalyzeEffect (:194-255) zeroes wAnimationType and only
-- shakes the enemy HUD on the player's turn.  The port queued neither
-- (#1526).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

Data.moves.FIX_POISON_STING = {
  id = "FIX_POISON_STING", index = 5, name = "FIX PSN STING", type = "POISON",
  power = 15, accuracy = 100, pp = 35, effect = "POISON_SIDE_EFFECT1",
}

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 40) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = function() return 0 end -- every roll lands
  return battle
end

local function animRows(battle)
  local rows = {}
  for _, item in ipairs(battle.queue) do
    if item.anim then rows[#rows + 1] = item end
  end
  return rows
end

local function find(rows, name)
  for i, row in ipairs(rows) do
    if row.anim == name then return i, row end
  end
  return nil
end

local function textIndex(battle, needle)
  for i, item in ipairs(battle.queue) do
    if item.text and item.text:find(needle, 1, true) then return i end
  end
  return nil
end

local function animIndex(battle, name)
  for i, item in ipairs(battle.queue) do
    if item.anim == name then return i end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- the foe poisons you: SE_SHAKE_SCREEN plus wAnimationType 3
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.enemy, battle.player, { id = "FIX_POISON_STING", pp = 35 })
  T.eq(battle.player.mon.status, "PSN", "the secondary poison landed")
  local rows = animRows(battle)
  local i, row = find(rows, "SHAKE_SCREEN_ANIM")
  T.check(i ~= nil, "the enemy's turn queues SHAKE_SCREEN_ANIM")
  T.eq(row.attackerIsPlayer, false, "attributed to the enemy side")
  T.eq(row.hit and row.hit.animType, 3, "wAnimationType 3 rides the row")
  T.eq(row.animDelayed, true, "PlayBattleAnimationGotID pays no Delay3")
  local moveIdx = animIndex(battle, "FIX_POISON_STING")
  local shakeIdx = animIndex(battle, "SHAKE_SCREEN_ANIM")
  local textIdx = textIndex(battle, "poisoned")
  T.check(moveIdx and shakeIdx and moveIdx < shakeIdx,
    "the move animation still runs first")
  T.check(textIdx and shakeIdx < textIdx,
    "PlayBattleAnimation2 precedes PrintText (effects.asm:149-151)")
end

-- ---------------------------------------------------------------------
-- you poison the foe: SE_SHAKE_ENEMY_HUD plus wAnimationType 6
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.player, battle.enemy, { id = "FIX_POISON_STING", pp = 35 })
  T.eq(battle.enemy.mon.status, "PSN", "the secondary poison landed")
  local _, row = find(animRows(battle), "ENEMY_HUD_SHAKE_ANIM")
  T.check(row ~= nil, "the player's turn queues ENEMY_HUD_SHAKE_ANIM")
  T.eq(row.attackerIsPlayer, true, "attributed to the player side")
  T.eq(row.hit and row.hit.animType, 6, "wAnimationType 6 rides the row")
  T.check(find(animRows(battle), "SHAKE_SCREEN_ANIM") == nil,
    "and never the enemy-side id")
end

-- ---------------------------------------------------------------------
-- burn takes the FreezeBurnParalyzeEffect arms: HUD shake on the player's
-- turn only, and no wAnimationType at all
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.player, battle.enemy, { id = "FIX_EMBERISH", pp = 25 })
  T.eq(battle.enemy.mon.status, "BRN", "the secondary burn landed")
  local _, row = find(animRows(battle), "ENEMY_HUD_SHAKE_ANIM")
  T.check(row ~= nil, "the player's burn shakes the enemy HUD")
  T.eq(row.hit, nil, "FreezeBurnParalyzeEffect zeroes wAnimationType")

  local other = newBattle()
  other.queue, other.nextInsert = {}, 0
  other:performMove(other.enemy, other.player, { id = "FIX_EMBERISH", pp = 25 })
  T.eq(other.player.mon.status, "BRN", "the enemy's burn landed too")
  T.check(find(animRows(other), "ENEMY_HUD_SHAKE_ANIM") == nil,
    "the enemy's-turn arm plays nothing")
end

-- ---------------------------------------------------------------------
-- a plain damaging move queues neither
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.player, battle.enemy, { id = "FIX_TACKLE", pp = 35 })
  local rows = animRows(battle)
  T.check(find(rows, "ENEMY_HUD_SHAKE_ANIM") == nil
          and find(rows, "SHAKE_SCREEN_ANIM") == nil,
    "no status, no PlayBattleAnimation2 row")
end

-- ---------------------------------------------------------------------
-- the residual tick plays BURN_PSN_ANIM with NO shake: core.asm:490-491
-- explicitly zeroes wAnimationType before it
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.player.mon.status = "PSN"
  battle:residualFor(battle.player, battle.enemy)
  local _, row = find(animRows(battle), "BURN_PSN_ANIM")
  T.check(row ~= nil, "the poison tick animates")
  T.eq(row.hit, nil, "with no applying-attack shake")
  T.eq(row.attackerIsPlayer, true, "on the hurt mon's side")
end

T.finish("secondary status animation (#1526)")
