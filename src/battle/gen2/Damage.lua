-- Gen 2 damage.
--
-- Ported from engine/battle/effect_commands.asm, in the order the cart's move
-- sequence runs them: damagestats -> damagecalc -> stab -> damagevariation.
--
-- What differs from Gen 1 (src/battle/Damage.lua), and why this is its own
-- module rather than a flag on that one:
--   * Special is split into Special Attack and Special Defense, so a special
--     move reads the attacker's SpA against the defender's SpD instead of both
--     sides' single `special`.
--   * Critical hits are a *chance ladder* (data/battle/critical_hit_chances.asm
--     1/15, 1/8, 1/4, 1/3, 1/2) indexed by a "critical level" that Focus
--     Energy, a high-crit move, Scope Lens, and the Lucky Punch / Stick raise.
--     Gen 1 instead derived the chance from base Speed.
--   * A critical hit is a flat x2 and, unlike Gen 1, ignores the attacker's
--     *negative* stat stages rather than all stages.
--   * Type-boost held items (Charcoal, Mystic Water, ...) multiply before the
--     crit, and Steel and Dark exist in the matchup table.
--
-- Whether a move is physical or special is still decided by its *type*, not
-- per-move as in Gen 4: type ids below FIRE are physical.  type_chart.lua's
-- records carry that as `category`.

local GameVersion = require("src.core.GameVersion")

local Damage = {}

-- ../pokecrystal/constants/battle_constants.asm:78
Damage.MAX_STAT_VALUE = 999

-- data/battle/critical_hit_chances.asm, as "1 in N".
Damage.CRITICAL_CHANCES = { [0] = 15, 8, 4, 3, 2, 2, 2 }

-- Gen 2's damage spread: 85% to 100% inclusive.
Damage.MIN_VARIATION = 85
Damage.MAX_VARIATION = 100

-- The cart caps a single hit at 999 (DAMAGE_CAP + MIN_DAMAGE in
-- BattleCommand_DamageCalc).
Damage.MAX_DAMAGE = 999

-- BattleCommand_DamageCalc's tail (engine/battle/effect_commands.asm) caps the
-- computed damage at DAMAGE_CAP (997) and then adds MIN_DAMAGE (2) back, so
-- every damaging hit leaves DamageCalc worth at least 2 -- which is what keeps
-- a resisted hit from flooring to zero once the type matchup halves it.
Damage.MIN_DAMAGE = 2

-- Stat stage multipliers (numerator, denominator), -6..+6.  Same table as
-- Gen 1; a critical hit skips only the negative half for the attacker.
local STAGE = {
  [-6] = { 25, 100 }, [-5] = { 28, 100 }, [-4] = { 33, 100 },
  [-3] = { 40, 100 }, [-2] = { 50, 100 }, [-1] = { 66, 100 },
  [0] = { 1, 1 },
  [1] = { 15, 10 }, [2] = { 2, 1 }, [3] = { 25, 10 },
  [4] = { 3, 1 }, [5] = { 35, 10 }, [6] = { 4, 1 },
}

function Damage.stageMultiplier(stage)
  local entry = STAGE[math.max(-6, math.min(6, stage or 0))]
  return entry[1], entry[2]
end

-- Apply a stat stage, flooring like the cart's Multiply/Divide pair, and never
-- letting a stat reach 0 (a 0 defence would divide by zero).
function Damage.applyStage(value, stage)
  local numerator, denominator = Damage.stageMultiplier(stage)
  local out = math.floor(value * numerator / denominator)
  -- ../pokecrystal/engine/battle/core.asm:6739
  return math.max(1, math.min(Damage.MAX_STAT_VALUE, out))
end

-- TruncateHL_BC: ../pokegold/engine/battle/effect_commands.asm:2625 runs one
-- pass, ../pokecrystal/engine/battle/effect_commands.asm:2644 loops it.
function Damage.truncateStats(attack, defense, fixed)
  local a = math.max(0, math.floor(attack or 0))
  local d = math.max(0, math.floor(defense or 0))
  while a > 255 or d > 255 do
    d = math.floor(d / 4)
    if d == 0 then d = 1 end
    a = math.floor(a / 4)
    if a == 0 then a = 1 end
    if not fixed then break end
  end
  return a % 256, d % 256
end

-- Is this move physical?  `types` is type_chart.lua's `types` table.
function Damage.isPhysical(moveType, types)
  local record = types and types[moveType]
  if record and record.category then return record.category == "physical" end
  -- Without the table, fall back to the Gen 1/2 boundary: the physical block
  -- runs NORMAL..GROUND, and the special block starts at FIRE.
  local PHYSICAL = {
    NORMAL = true, FIGHTING = true, FLYING = true, POISON = true,
    GROUND = true, ROCK = true, BUG = true, GHOST = true, STEEL = true,
  }
  return PHYSICAL[moveType] == true
end

-- The 1-in-N chance for a critical level.
function Damage.criticalChance(level)
  local capped = math.max(0, math.min(6, level or 0))
  return Damage.CRITICAL_CHANCES[capped]
end

-- BattleCommand_Critical, as a level rather than a roll:
--   +1 Focus Energy, +2 a high-crit move, +1 Scope Lens,
--   +2 Lucky Punch on Chansey / Stick on Farfetch'd.
function Damage.criticalLevel(opts)
  local level = 0
  if opts.focusEnergy then level = level + 1 end
  if opts.highCritMove then level = level + 2 end
  if opts.scopeLens then level = level + 1 end
  if opts.speciesItemBonus then level = level + 2 end
  return math.min(6, level)
end

-- Roll a critical hit.  `random(n)` must return 0..n-1 (the cart compares a
-- BattleRandom byte against the chance), and defaults to love/math random.
function Damage.rollCritical(criticalLevel, random)
  local chance = Damage.criticalChance(criticalLevel)
  local roll
  if random then
    roll = random(chance)
  elseif love and love.math then
    roll = love.math.random(chance) - 1
  else
    roll = math.random(chance) - 1
  end
  return roll == 0
end

-- The x10 type multiplier of a move against a defender, applying each matchup
-- row separately and flooring in between -- the same rule Gen 1 follows, which
-- is why a dual type can land on 4x or 0.25x.
function Damage.typeMultiplier(moveType, defenderTypes, matchups)
  local multiplier = 10
  for _, row in ipairs(matchups or {}) do
    if row.attacker == moveType then
      for _, defenderType in ipairs(defenderTypes or {}) do
        if row.defender == defenderType then
          multiplier = math.floor(multiplier * row.multiplier / 10)
          break
        end
      end
    end
  end
  return multiplier
end

-- The core formula (BattleCommand_DamageCalc):
--
--   (((2 * Level / 5 + 2) * Power * Attack / Defense) / 50)
--
-- every step floored, defence clamped to at least 1.
function Damage.base(level, power, attack, defense)
  if (power or 0) <= 0 then return 0 end
  defense = math.max(1, defense or 1)
  local value = math.floor(level * 2 / 5) + 2
  value = value * power
  value = value * attack
  value = math.floor(value / defense)
  value = math.floor(value / 50)
  return value
end

-- Every `info` table Damage.calc returns carries BOTH generations' names for
-- the same two facts: Gen 2 calls them `critical` and `effectiveness`, Gen 1
-- (src/battle/Damage.lua) calls them `crit` and `typeMult`.  The battle.damage
-- hook hands this table to whatever wrapped it, and a mod written against Red
-- must be able to read what it wrapped.
local function withGen1Names(info)
  info.crit = info.critical
  info.typeMult = info.effectiveness
  return info
end

-- opts:
--   level, power, moveType
--   attacker { attack, specialAttack, types, stages = { attack =, ... } }
--   defender { defense, specialDefense, types, stages }
--   types, matchups        -- type_chart.lua's `types` / `matchups`
--   critical               -- boolean (roll it with rollCritical first)
--   itemBoostPercent       -- type-boost held item, e.g. 10 for Charcoal
--   weatherPercent         -- DoWeatherModifiers in tenths (15 / 5 / nil),
--                             applied ahead of the badge boost and STAB
--   badgeTypeBoost         -- DoBadgeTypeBoosts: the player owns the badge
--                             matching the move's type, +1/8 before STAB
--   variation              -- 85..100; omit to roll
--   random(n)              -- 0..n-1, for the variation roll
--   screen                 -- Reflect/Light Screen active on the defender
--   defenseHalved          -- EFFECT_SELFDESTRUCT's srl c
--   reflectOverflowFixed   -- override GameVersion.fixes()'s TruncateHL_BC
--     answer; ../pokecrystal/engine/battle/effect_commands.asm:2644
--
-- Returns damage, info where info carries the pieces a battle message needs:
-- effectiveness (x10), critical, physical, variation.
function Damage.calc(opts)
  local physical = Damage.isPhysical(opts.moveType, opts.types)
  local attacker = opts.attacker or {}
  local defender = opts.defender or {}
  local stagesA = attacker.stages or {}
  local stagesD = defender.stages or {}

  local rawAttack = physical and (attacker.attack or 1)
    or (attacker.specialAttack or attacker.special or 1)
  local rawDefense = physical and (defender.defense or 1)
    or (defender.specialDefense or defender.special or 1)
  local stageA = physical and (stagesA.attack or 0)
    or (stagesA.specialAttack or 0)
  local stageD = physical and (stagesD.defense or 0)
    or (stagesD.specialDefense or 0)

  -- A critical hit ignores stat changes that would *lower* the damage: the
  -- attacker's negative stages and the defender's positive ones.
  if opts.critical then
    if stageA < 0 then stageA = 0 end
    if stageD > 0 then stageD = 0 end
  end

  local attack = Damage.applyStage(rawAttack, stageA)
  local defense = Damage.applyStage(rawDefense, stageD)

  -- Reflect and Light Screen double the matching defence, and are the one
  -- multiplier a critical hit also ignores.
  if opts.screen and not opts.critical then
    defense = defense * 2
  end

  -- PlayerAttackDamage hands DamageCalc one-byte stats
  -- (../pokecrystal/engine/battle/effect_commands.asm:2604).
  local fixed = opts.reflectOverflowFixed
  if fixed == nil then fixed = GameVersion.fixes().reflectOverflow == true end
  attack, defense = Damage.truncateStats(attack, defense, fixed)

  -- BattleCommand_DamageCalc (effect_commands.asm:2905-2913): Selfdestruct and
  -- Explosion halve the defence, never below 1.
  if opts.defenseHalved then defense = math.max(1, math.floor(defense / 2)) end

  if (opts.power or 0) <= 0 then
    return 0, withGen1Names({ effectiveness = 10, critical = false,
      physical = physical })
  end
  local damage = Damage.base(opts.level or 1, opts.power or 0, attack, defense)

  -- Type-boost held items multiply before the crit (.NextItem / .DoneItem).
  if opts.itemBoostPercent and opts.itemBoostPercent > 0 then
    damage = math.floor(damage * (100 + opts.itemBoostPercent) / 100)
  end

  if opts.critical then damage = damage * 2 end

  -- BattleCommand_DamageCalc's tail: cap at DAMAGE_CAP, then add MIN_DAMAGE
  -- back, so even a hit whose stat math floored to nothing leaves with 2.
  damage = math.min(damage, Damage.MAX_DAMAGE - Damage.MIN_DAMAGE)
    + Damage.MIN_DAMAGE

  -- DoWeatherModifiers (engine/battle/misc.asm:102-140), farcalled by
  -- BattleCommand_Stab as its very FIRST act (effect_commands.asm:1254): it
  -- sits ahead of the badge boost, the STAB x1.5, the type rows and
  -- DamageVariation, so every later step floors on top of it.  The table's
  -- values are tenths (weather_modifiers.asm: MORE_EFFECTIVE 15,
  -- NOT_VERY_EFFECTIVE 05), and .ApplyModifier's zero-quotient arm forces the
  -- result back to 1, so a weather-halved hit never falls to nothing.
  if opts.weatherPercent and opts.weatherPercent ~= 10 then
    damage = math.max(1, math.floor(damage * opts.weatherPercent / 10))
  end

  -- DoBadgeTypeBoosts (engine/battle/misc.asm:146), farcalled from
  -- BattleCommand_Stab ahead of the STAB multiply: a matching owned badge
  -- adds an eighth of the running damage, at least 1, on the player's turn.
  if opts.badgeTypeBoost then
    damage = damage + math.max(1, math.floor(damage / 8))
  end

  -- STAB, then each type row.  BattleCommand_Stab does STAB first, so a
  -- resisted same-type move floors after the x1.5.
  local stab = false
  for _, attackerType in ipairs(attacker.types or {}) do
    if attackerType == opts.moveType then stab = true break end
  end
  if stab then damage = math.floor(damage * 15 / 10) end

  -- Each matchup row multiplies the running damage separately, the way
  -- BattleCommand_Stab's .TypesLoop does -- and its zero-quotient check forces
  -- the damage back to 1 whenever a non-immune row floors it to nothing, so a
  -- resisted hit that lands always deals at least 1 HP.
  local effectiveness = Damage.typeMultiplier(
    opts.moveType, defender.types, opts.matchups)
  for _, row in ipairs(opts.matchups or {}) do
    if row.attacker == opts.moveType then
      for _, defenderType in ipairs(defender.types or {}) do
        if row.defender == defenderType then
          damage = math.floor(damage * row.multiplier / 10)
          if damage == 0 and row.multiplier > 0 then damage = 1 end
          break
        end
      end
    end
  end

  if effectiveness <= 0 or damage <= 0 then
    return 0, withGen1Names({
      effectiveness = effectiveness, critical = opts.critical or false,
      physical = physical, stab = stab,
    })
  end

  -- Damage variation last, and only when the running damage is 2 or more
  -- (BattleCommand_DamageVariation returns early below that).
  local variation = opts.variation
  if not variation then
    if opts.random then
      variation = Damage.MIN_VARIATION
        + opts.random(Damage.MAX_VARIATION - Damage.MIN_VARIATION + 1)
    elseif love and love.math then
      variation = love.math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    else
      variation = math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    end
  end
  if damage >= 2 then
    damage = math.floor(damage * variation / 100)
  end

  damage = math.max(1, math.min(Damage.MAX_DAMAGE, damage))
  return damage, withGen1Names({
    effectiveness = effectiveness,
    critical = opts.critical or false,
    physical = physical,
    stab = stab,
    variation = variation,
  })
end

-- Accuracy check.  Gen 2 rolls one byte against accuracy scaled by the
-- attacker's accuracy stage and the defender's evasion stage; accuracy of 0 in
-- the data means "never misses" (Swift and friends).
function Damage.rollHit(accuracy, accuracyStage, evasionStage, random)
  if not accuracy or accuracy <= 0 then return true end
  local numerator, denominator = Damage.stageMultiplier(accuracyStage or 0)
  local value = math.floor(accuracy * numerator / denominator)
  numerator, denominator = Damage.stageMultiplier(-(evasionStage or 0))
  value = math.floor(value * numerator / denominator)
  value = math.max(1, math.min(100, value))
  local roll
  if random then
    roll = random(100)
  elseif love and love.math then
    roll = love.math.random(100) - 1
  else
    roll = math.random(100) - 1
  end
  return roll < value
end

return Damage
