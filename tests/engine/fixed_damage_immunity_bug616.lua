-- Gen 1 fixed-damage moves and Super Fang ignore the type chart (#616).
-- SPECIAL_DAMAGE_EFFECT and SUPER_FANG_EFFECT are the SetDamageEffects
-- table (data/battle/set_damage_effects.asm); engine/battle/core.asm:3139
-- jumps straight to MoveHitTest for them, so CalculateDamage and
-- AdjustDamageForMoveType never run and ApplyAttackToEnemyPokemon
-- (core.asm:4612) stores wDamage unscaled.  Night Shade therefore hits
-- Normal-types and Super Fang hits Ghosts.  OHKO is the exception: it
-- returns through AdjustDamageForMoveType (core.asm:4329, 4467) and a 0x
-- matchup still zeroes its 65535 and sets wMoveMissed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
-- the shared fixture type chart is just the GRASS/FIRE/WATER triangle
-- (tests/fixture_data/type_chart.lua) with no 0x row, so this suite adds
-- its own immune matchups: one for the SetDamageEffects moves under test
-- and a separate one for OHKO, kept apart so neither probe leaks into
-- the other's assertion
table.insert(Data.type_chart.matchups,
  { attacker = "FIX_ATK_A", defender = "FIX_DEF_A", multiplier = 0 })
table.insert(Data.type_chart.matchups,
  { attacker = "FIX_ATK_B", defender = "FIX_DEF_B", multiplier = 0 })
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

-- Night Shade's shape: 0 BP, fixed damage equal to the user's level,
-- attacking type that the fixture chart marks as 0x against the target
Data.moves.FIX_NIGHT_SHADE = {
  id = "FIX_NIGHT_SHADE", index = 98, name = "FIX NSHADE",
  type = "FIX_ATK_A", power = 0, accuracy = 100, pp = 15,
  effect = "SPECIAL_DAMAGE_EFFECT", fixedDamage = "level",
}
Data.moves.FIX_SUPER_FANG = {
  id = "FIX_SUPER_FANG", index = 97, name = "FIX SFANG",
  type = "FIX_ATK_A", power = 1, accuracy = 90, pp = 10,
  effect = "SUPER_FANG_EFFECT",
}
Data.moves.FIX_FISSURE = {
  id = "FIX_FISSURE", index = 96, name = "FIX FISSURE",
  type = "FIX_ATK_B", power = 1, accuracy = 30, pp = 5,
  effect = "OHKO_EFFECT",
}

local function mkseq(vals) -- scripted rng: pops vals, then max rolls
  local i = 0
  return function(_, hi)
    i = i + 1
    return vals[i] ~= nil and vals[i] or hi
  end
end

-- a battle whose target's live types are forced to `types` (curTypes is
-- what TypeChart reads, BattleState.lua:443)
local function mkbattle(level, types)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", level) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local b = BattleState.newWild(game, "FIXMON_C", 5)
  b.enemy.curTypes = types
  b.rng = mkseq({ 0 }) -- accuracy hits; nothing else rolls
  return b
end

-- FIX_ATK_A is 0x against FIX_DEF_A, and Night Shade lands anyway
T.eq(TypeChart.effectiveness("FIX_ATK_A", { "FIX_DEF_A" }), 0,
  "FIX_ATK_A does nothing to FIX_DEF_A")
local ns = mkbattle(12, { "FIX_DEF_A" })
local before = ns.enemy.mon.hp
ns:performMove(ns.player, ns.enemy, { id = "FIX_NIGHT_SHADE", pp = 15 })
T.eq(before - ns.enemy.mon.hp, 12, "Night Shade takes level damage off an immune type")

-- same 0x matchup, and Super Fang still halves
local sf = mkbattle(12, { "FIX_DEF_A" })
local hp = sf.enemy.mon.hp
sf:performMove(sf.player, sf.enemy, { id = "FIX_SUPER_FANG", pp = 10 })
T.eq(hp - sf.enemy.mon.hp, math.max(1, math.floor(hp / 2)),
  "Super Fang halves an immune type's HP")

-- OHKO keeps its immunity gate: it does return through AdjustDamageForMoveType
T.eq(TypeChart.effectiveness("FIX_ATK_B", { "FIX_DEF_B" }), 0,
  "FIX_ATK_B does nothing to FIX_DEF_B")
local ko = mkbattle(50, { "FIX_DEF_B" })
local full = ko.enemy.mon.hp
ko:performMove(ko.player, ko.enemy, { id = "FIX_FISSURE", pp = 5 })
T.eq(ko.enemy.mon.hp, full, "OHKO still cannot touch an immune type")

Data.moves.FIX_NIGHT_SHADE = nil
Data.moves.FIX_SUPER_FANG = nil
Data.moves.FIX_FISSURE = nil
T.finish("fixed damage ignores type immunity")
