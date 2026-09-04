-- AdjustDamageForMoveType (engine/battle/core.asm:5169-5176)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
table.insert(Data.type_chart.matchups,
  { attacker = "FIRE", defender = "FIX_DEF_A", multiplier = 5 })
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local BattleState = require("src.battle.BattleState")
local Damage = require("src.battle.Damage")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local faithful = require("src.battle.rulesets.gen1_faithful")
local modern = require("src.battle.rulesets.modern_clean")

Data.moves.FIX_WEAK_FIRE = {
  id = "FIX_WEAK_FIRE", index = 95, name = "FIX WEAK",
  type = "FIRE", power = 1, accuracy = 100, pp = 35,
  effect = "NO_ADDITIONAL_EFFECT",
}
local move = Data.moves.FIX_WEAK_FIRE

local save = SaveData.newGame()
save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
local battle = BattleState.newWild(game, "FIXMON_C", 5)
local atk, dfn = battle.player, battle.enemy
dfn.curTypes = { "WATER", "FIX_DEF_A" }
local opts = { forceCrit = false, rng = function(_, hi) return hi end }

T.eq(TypeChart.effectiveness("FIRE", dfn.curTypes), 2,
  "the matchup is 0.25x (x10 scale)")

local d, info = Damage.compute(faithful, atk, dfn, move, opts)
T.eq(d, 0, "gen1_faithful floors the hit to zero")
T.eq(info.missed, true, "and flags it as a miss (core.asm:5171)")

local dm, im = Damage.compute(modern, atk, dfn, move, opts)
T.eq(dm, 1, "modern_clean deals the minimum 1 instead")
T.eq(im.missed, nil, "and never reports a miss")

local unset = { name = "fix_unset", randMin = 217, randMax = 255,
                critUsesBaseSpeed = true, critIgnoresStages = true }
T.eq(select(2, Damage.compute(unset, atk, dfn, move, opts)).missed, true,
  "an unset flag defaults to the Gen 1 quirk")

T.eq(Damage.accuracyThreshold(modern, { accuracy = 100 }, atk, dfn), 256,
  "modern_clean still removes the 1/256 miss")
T.eq(Damage.accuracyThreshold(faithful, { accuracy = 100 }, atk, dfn), 255,
  "gen1_faithful keeps it")

Data.moves.FIX_WEAK_FIRE = nil
T.finish("zero-damage miss is ruleset-gated (#2153)")
