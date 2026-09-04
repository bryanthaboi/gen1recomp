-- QuarterSpeedDueToParalysis (pokered engine/battle/core.asm:6283)
-- pokered engine/battle/effects.asm:414-415
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local MoveEffects = require("src.battle.MoveEffects")
local Status = require("src.battle.Status")
local StatusRegistry = require("src.battle.StatusRegistry")
local TurnOrder = require("src.battle.TurnOrder")
local TrainerAI = require("src.battle.TrainerAI")
local faithful = require("src.battle.rulesets.gen1_faithful")
local modern = require("src.battle.rulesets.modern_clean")

local function mon(status)
  return {
    name = "MON", stages = {},
    curStats = { speed = 100, attack = 100, defense = 50, special = 50, hp = 100 },
    curTypes = { "NORMAL" },
    mon = { status = status, level = 50, stats = { hp = 100 } },
  }
end

local function arena(ruleset, player, enemy)
  return { data = Data, ruleset = ruleset, player = player, enemy = enemy }
end

-- a fresh send-out carries exactly one application (core.asm:1658)
T.eq(TurnOrder.effectiveSpeed(mon("PAR")), 25, "paralysis quarters speed once")

do
  local p, e = mon("PAR"), mon(nil)
  MoveEffects.primary.SPEED_UP2_EFFECT(arena(faithful, p, e), p, e)
  T.eq(TurnOrder.effectiveSpeed(p), 200, "paralysis then AGILITY wipes the quarter")
end

do
  local p, e = mon(nil), mon(nil)
  local B = arena(faithful, p, e)
  MoveEffects.primary.SPEED_UP2_EFFECT(B, p, e)
  StatusRegistry.inflict(B, p, "PAR", {})
  T.eq(TurnOrder.effectiveSpeed(p), 50, "AGILITY then paralysis quarters the boost")
end

do
  local p, e = mon(nil), mon("PAR")
  MoveEffects.primary.ATTACK_DOWN1_EFFECT(arena(faithful, p, e), p, e)
  T.eq(TurnOrder.effectiveSpeed(e), 6, "paralysis + GROWL quarters twice (100 -> 6)")
  T.eq(Status.penaltyStacks(e, "speed"), 2, "two applications are baked in")
end

do
  local p, e = mon(nil), mon("PAR")
  MoveEffects.primary.ACCURACY_DOWN1_EFFECT(arena(faithful, p, e), p, e)
  T.eq(Status.penaltyStacks(e, "speed"), 2,
    "an accuracy drop still re-applies the quarter to the non-user")
end

do
  local p, e = mon("PAR"), mon(nil)
  local B = arena(faithful, p, e)
  MoveEffects.primary.SPEED_UP2_EFFECT(B, p, e)
  MoveEffects.primary.HAZE_EFFECT(B, p, e)
  T.eq(TurnOrder.effectiveSpeed(p), 100, "Haze lifts the quarter")
  MoveEffects.primary.ATTACK_UP1_EFFECT(B, p, e)
  T.eq(TurnOrder.effectiveSpeed(p), 100, "and a later stage change does not re-arm it")
end

do
  local p, e = mon("PAR"), mon(nil)
  MoveEffects.primary.SPEED_UP2_EFFECT(arena(modern, p, e), p, e)
  T.eq(p.statusPenaltyStacks, nil, "modern_clean stays stateless")
  T.eq(TurnOrder.effectiveSpeed(p), 50, "and quarters the boosted speed")
end

-- (pokered engine/battle/move_effects/paralyze.asm:35)
do
  local p, e = mon(nil), mon(nil)
  local B = arena(faithful, p, e)
  MoveEffects.primary.HAZE_EFFECT(B, p, e)
  T.eq(p.statusPenaltyStacks, nil, "HAZE leaves an untouched mon stateless")
  StatusRegistry.inflict(B, p, "PAR", {})
  T.eq(Status.penaltyStacks(p, "speed"), 1, "a post-HAZE status still bakes its penalty")
  T.eq(TurnOrder.effectiveSpeed(p), 25, "and quarters the speed (100 -> 25)")
end

-- an AI X ITEM goes through StatModifierUpEffect (trainer_ai.asm:719)
do
  local p, e = mon("PAR"), mon(nil)
  local B = arena(faithful, p, e)
  B.trainer = { name = "LASS" }
  Data.items.X_ATTACK = Data.items.X_ATTACK or { id = "X_ATTACK", name = "X ATTACK" }
  TrainerAI.useItem(B, "X_ATTACK")
  T.eq(Status.penaltyStacks(p, "speed"), 2, "the AI's stat change re-applies the quarter")
  T.eq(TurnOrder.effectiveSpeed(p), 6, "player speed 100 -> 6")
end

do
  local bare = { name = "fix_unset" }
  T.eq(Status.rulesetBakes(bare), true, "an unset statusPenaltyIsBaked bakes")
  T.eq(Status.rulesetBakes(modern), false, "an explicit false does not")
  T.eq(Status.rulesetBakes(nil), false, "and no ruleset at all stays stateless")
  local p, e = mon(nil), mon(nil)
  local B = arena(bare, p, e)
  MoveEffects.primary.SPEED_UP2_EFFECT(B, p, e)
  StatusRegistry.inflict(B, p, "PAR", {})
  T.eq(TurnOrder.effectiveSpeed(p), 50, "so a bare mod ruleset matches gen1_faithful")
end

-- the burn half of the same seam (core.asm:6326, effects.asm:697-698)
do
  local p, e = mon(nil), mon("BRN")
  MoveEffects.primary.DEFENSE_DOWN2_EFFECT(arena(faithful, p, e), p, e)
  T.eq(Status.penaltyStacks(e, "attack"), 2, "burn + SCREECH quarters the attack")
end

T.finish("the status stat penalty is baked, not recomputed (#2148)")
