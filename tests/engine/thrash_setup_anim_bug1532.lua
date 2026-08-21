-- THRASH/PETAL DANCE is a SpecialEffectsCont entry
-- (data/battle/special_effects.asm:22), so on the SETUP turn only,
-- engine/battle/core.asm:3129-3133 runs ThrashPetalDanceEffect before
-- damage; it ends in PlayBattleAnimation2 with SHRINKING_SQUARE_ANIM
-- (ANIM_B1 on the enemy's turn) plus the slow horizontal screen shake
-- (engine/battle/effects.asm:791-808, :1461-1471).  The port queued only
-- the move's own animation (#1532).
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
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = function(a) if a then return a end return 0 end
  return battle
end

local function animRows(battle)
  local rows = {}
  for _, item in ipairs(battle.queue) do
    if item.anim then
      rows[#rows + 1] = { anim = item.anim, hit = item.hit,
                          attackerIsPlayer = item.attackerIsPlayer }
    end
  end
  return rows
end

local function indexOf(rows, name)
  for i, row in ipairs(rows) do
    if row.anim == name then return i end
  end
  return nil
end

local function hasText(battle, needle)
  for _, item in ipairs(battle.queue) do
    if item.text and item.text:find(needle, 1, true) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------
-- the player's setup turn: the effect animation precedes the move's own
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  local slot = { id = "FIX_THRASH", pp = 20 }
  battle:performMove(battle.player, battle.enemy, slot)
  local rows = animRows(battle)
  local setup = indexOf(rows, "SHRINKING_SQUARE_ANIM")
  local move = indexOf(rows, "FIX_THRASH")
  T.check(setup ~= nil, "the setup turn queues SHRINKING_SQUARE_ANIM")
  T.check(move ~= nil and setup < move,
    "it plays BEFORE PlayPlayerMoveAnimation, as SpecialEffectsCont runs first")
  T.eq(rows[setup].attackerIsPlayer, true, "on the player's side")
  T.eq(rows[setup].hit and rows[setup].hit.animType, 6,
    "wAnimationType 6 -> ShakeScreenHorizontallySlow2 on the player's turn")

  -- the continuation turn never reaches the effect (.ThrashingAboutCheck,
  -- core.asm:3532-3550 jumps straight to PlayerCalcMoveDamage)
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.player, battle.enemy, slot)
  T.check(indexOf(animRows(battle), "SHRINKING_SQUARE_ANIM") == nil,
    "a locked-in Thrash queues no setup animation")
  -- .ThrashingAboutCheck (core.asm:3534-3535, enemy mirror :5909-5910) (#1577)
  T.check(indexOf(animRows(battle), "THRASH") ~= nil,
    "a continuation turn animates THRASH, not the locked move's own id")
  T.check(indexOf(animRows(battle), "FIX_THRASH") == nil,
    "so the locked move's own animation does not play")
  T.check(hasText(battle, "thrashing about"),
    "ThrashingAboutText prints in place of the used-move line")
  T.check(not hasText(battle, "used FIX THRASH"),
    "and the used-move line does not")
  T.eq(battle.player.thrashTurns, 1,
    "the continuation turn runs wPlayerNumAttacksLeft down")
end

-- ---------------------------------------------------------------------
-- the enemy's turn takes ANIM_B1 and wAnimationType 3
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:performMove(battle.enemy, battle.player, { id = "FIX_THRASH", pp = 20 })
  local rows = animRows(battle)
  local setup = indexOf(rows, "ANIM_B1")
  T.check(setup ~= nil, "the enemy's setup turn queues ANIM_B1")
  T.eq(rows[setup].attackerIsPlayer, false, "on the enemy's side")
  T.eq(rows[setup].hit and rows[setup].hit.animType, 3,
    "wAnimationType 3 -> ShakeScreenHorizontallySlow on the enemy's turn")
  T.check(indexOf(rows, "SHRINKING_SQUARE_ANIM") == nil,
    "and never the player-side id")
end

-- ---------------------------------------------------------------------
-- a missed setup turn still runs the effect (it precedes MoveHitTest)
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.accuracyRoll = function() return false end
  battle:performMove(battle.player, battle.enemy, { id = "FIX_THRASH", pp = 20 })
  local rows = animRows(battle)
  T.check(indexOf(rows, "SHRINKING_SQUARE_ANIM") ~= nil,
    "the setup animation survives a miss")
  T.check(indexOf(rows, "FIX_THRASH") == nil, "while the move's own anim is cancelled")
  -- ThrashPetalDanceEffect commits before MoveHitTest
  -- (core.asm:3129-3133, effects.asm:791-808) (#1565)
  T.eq(battle.player.thrashTurns, 2, "the miss still rolls wPlayerNumAttacksLeft")
  T.check(battle:menuLockedAction(battle.player) ~= nil,
    "and the user is locked into Thrash next turn")
end

-- ---------------------------------------------------------------------
-- JumpMoveEffect (core.asm:3129-3133) before MoveHitTest INVULNERABLE (:3150) (#1565)
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.enemy.invulnerable = true
  battle:performMove(battle.player, battle.enemy, { id = "FIX_THRASH", pp = 20 })
  T.check(indexOf(animRows(battle), "SHRINKING_SQUARE_ANIM") ~= nil,
    "the setup animation plays against a mid-Fly/Dig target")
  T.eq(battle.player.thrashTurns, 2,
    "the 2-3 roll commits against a mid-Fly/Dig target")
  T.check(battle:menuLockedAction(battle.player) ~= nil,
    "and the user is locked into Thrash next turn")
  T.check(hasText(battle, "attack missed"), "while the attack itself misses")
end

T.finish("thrash setup animation (#1532)")
