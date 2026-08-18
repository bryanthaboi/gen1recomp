-- engine/battle/effect_commands.asm:5788, :3671, :3646, :4019

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")

local MATCHUPS = {
  { attacker = "ELECTRIC", defender = "GROUND", multiplier = 0 },
  { attacker = "POISON", defender = "STEEL", multiplier = 0 },
  { attacker = "POISON", defender = "POISON", multiplier = 5 },
  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
  { attacker = "PSYCHIC_TYPE", defender = "GROUND", multiplier = 10 },
}

local POKEMON = {
  GEODUDE = { types = { "ROCK", "GROUND" } },
  MAGNEMITE = { types = { "STEEL", "ELECTRIC" } },
  ZUBAT = { types = { "POISON", "FLYING" } },
  GASTLY = { types = { "GHOST", "POISON" } },
  PIDGEY = { types = { "NORMAL", "FLYING" } },
}

local battle = setmetatable({
  data = { type_chart = { matchups = MATCHUPS }, pokemon = POKEMON },
}, { __index = Battle })

local function mon(species) return { species = species, hp = 20 } end
local function refused(species, moveType, status)
  return battle:statusRefusedByType(mon(species), moveType, status)
end

-- The two repros the reporter filed, neither of which the #1318 fix touched.
T.eq(refused("GEODUDE", "ELECTRIC", "paralyze"), true,
  "Thunder Wave does not affect a GROUND type")
T.eq(refused("MAGNEMITE", "POISON", "poison"), true,
  "Poison Gas does not affect a STEEL type")

-- Poison vs POISON is 0.5x, not an immunity, so only CheckIfTargetIsPoisonType
-- refuses it: this is the Poison Sting on Zubat case.
T.eq(refused("ZUBAT", "POISON", "poison"), true,
  "a POISON type cannot be poisoned even on a resisted, landed hit")
T.eq(refused("GASTLY", "POISON", "toxic"), true,
  "Toxic is refused by the same check")
T.eq(refused("GASTLY", "NORMAL", "paralyze"), true,
  "Glare does not affect a GHOST type")

-- Everything the cart deliberately leaves ungated stays ungated.
T.eq(refused("GEODUDE", "PSYCHIC_TYPE", "sleep"), false,
  "Hypnosis still lands on a GROUND type")
T.eq(refused("GEODUDE", "PSYCHIC_TYPE", "confuse"), false,
  "confusion is never type-gated")
T.eq(refused("PIDGEY", "ELECTRIC", "paralyze"), false,
  "Thunder Wave still paralyses a non-immune target")
T.eq(refused("PIDGEY", "POISON", "poison"), false,
  "a non-POISON target is still poisonable")
T.eq(refused("GEODUDE", nil, "paralyze"), false,
  "a status with no move type behind it is not refused")

T.finish("gen2 status type immunity bug 1444")
