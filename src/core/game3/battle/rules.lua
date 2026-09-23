-- Game3 battle rules (owned). Crit / weather mods / residual phase labels.

local Capabilities = require("src.core.game3.battle.capabilities")
local Oak = require("src.core.game3.battle.oak_advice")

local Rules = {}

-- pokefirered/src/battle_util.c:453
Rules.FIELD_PHASES_ORDER = {
  "reflect",
  "light_screen",
  "mist",
  "safeguard",
  "wish",
  "weather_continue",
}

-- pokefirered/src/battle_util.c:722
Rules.BATTLER_PHASES_ORDER = {
  "ingrain",
  "abilities_eot",
  "held_items",
  "leech_seed",
  "status_chip",
  "nightmare",
  "curse",
  "partial_trap_chip",
  "uproar",
  "thrash",
  "disable",
  "encore",
  "lock_on",
  "charge",
  "taunt",
  "yawn",
  "volatiles",
}

-- pokefirered/src/battle_util.c:1064
Rules.POST_PHASES_ORDER = {
  "fainted_actions",
  "future_sight",
  "perish_song",
}

Rules.FAINT_HALT_PHASES = {
  ingrain = true,
  leech_seed = true,
  status_chip = true,
  nightmare = true,
  curse = true,
  partial_trap_chip = true,
}

function Rules.shouldHaltBattlerOnFaint(phase)
  return Rules.FAINT_HALT_PHASES[phase] == true
end

local function fallback_rng(lo, hi)
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end

-- Partial trap (Gen3)
Rules.partialTrap = {}

-- pokefirered/src/battle_util.c:886
function Rules.partialTrap.chipAmount(maxHp)
  return math.max(1, math.floor((maxHp or 16) / Capabilities.partialTrapChipDenom))
end

-- pokefirered/src/battle_script_commands.c:2490
function Rules.partialTrap.rollTurns(rng)
  rng = rng or fallback_rng
  local ok, n = pcall(rng, 0, 3)
  if not (ok and type(n) == "number") then n = fallback_rng(0, 3) end
  return (math.floor(n) % 4) + 3
end

function Rules.partialTrap.active()
  return Capabilities.gen3PartialTrap
end

-- pokefirered/src/battle_message.c:1263
Rules.partialTrap.MOVES = { 20, 35, 83, 128, 250, 328 }

Rules.safari = {}

-- pokefirered/src/safari_zone.c:31
Rules.safari.BALLS = 30
Rules.safari.STEPS = 600

-- pokefirered/src/battle_main.c:2284
function Rules.safari.catchFactor(catchRate)
  return math.floor((tonumber(catchRate) or 0) * 100 / 1275)
end

-- pokefirered/src/battle_main.c:2285
function Rules.safari.escapeFactor(fleeRate)
  local f = math.floor((tonumber(fleeRate) or 0) * 100 / 1275)
  if f <= 1 then f = 2 end
  return f
end

-- pokefirered/src/battle_main.c:2282
function Rules.safari.newState(catchRate, fleeRate)
  return {
    balls = Rules.safari.BALLS,
    catchFactor = Rules.safari.catchFactor(catchRate),
    escapeFactor = Rules.safari.escapeFactor(fleeRate),
    baseCatchRate = tonumber(catchRate) or 0,
    rockCounter = 0,
    baitCounter = 0,
  }
end

local function throw_counter(rng)
  local ok, n = pcall(rng or fallback_rng, 0, 4)
  if not (ok and type(n) == "number") then n = fallback_rng(0, 4) end
  return (math.floor(n) % 5) + 2
end

-- pokefirered/src/battle_main.c:4382
function Rules.safari.throwBait(sf, rng)
  if not sf then return end
  sf.baitCounter = math.min(6, (sf.baitCounter or 0) + throw_counter(rng))
  sf.rockCounter = 0
  sf.catchFactor = math.floor((sf.catchFactor or 0) / 2)
  if sf.catchFactor <= 2 then sf.catchFactor = 3 end
end

-- pokefirered/src/battle_main.c:4398
function Rules.safari.throwRock(sf, rng)
  if not sf then return end
  sf.rockCounter = math.min(6, (sf.rockCounter or 0) + throw_counter(rng))
  sf.baitCounter = 0
  sf.catchFactor = (sf.catchFactor or 0) * 2
  if sf.catchFactor > 20 then sf.catchFactor = 20 end
end

-- pokefirered/src/battle_main.c:4334
function Rules.safari.watchStep(sf)
  if not sf then return "watching" end
  if (sf.rockCounter or 0) ~= 0 then
    sf.rockCounter = sf.rockCounter - 1
    if sf.rockCounter == 0 then
      sf.catchFactor = Rules.safari.catchFactor(sf.baseCatchRate)
      return "watching"
    end
    return "angry"
  end
  if (sf.baitCounter or 0) ~= 0 then
    sf.baitCounter = sf.baitCounter - 1
    if sf.baitCounter == 0 then return "watching" end
    return "eating"
  end
  return "watching"
end

-- pokefirered/src/battle_ai_script_commands.c:1713
function Rules.safari.fleeRate(sf)
  if not sf then return 0 end
  local rate
  if (sf.rockCounter or 0) ~= 0 then
    rate = math.min(20, (sf.escapeFactor or 0) * 2)
  elseif (sf.baitCounter or 0) ~= 0 then
    rate = math.max(1, math.floor((sf.escapeFactor or 0) / 4))
  else
    rate = sf.escapeFactor or 0
  end
  return rate * 5
end

-- pokefirered/src/battle_script_commands.c:9497
function Rules.safari.ballCatchRate(sf)
  return math.floor(((sf and sf.catchFactor) or 0) * 1275 / 100)
end

Rules.weather = {}

function Rules.weather.kind(weather)
  if not weather then return nil end
  local w = tostring(weather):upper()
  if w == "SUN" or w == "SUNNY" or w == "HARSH_SUN" then return "SUN" end
  if w == "RAIN" or w == "RAINY" or w == "DOWNPOUR" then return "RAIN" end
  if w == "SAND" or w == "SANDSTORM" then return "SAND" end
  if w == "HAIL" or w == "SNOWY" then return "HAIL" end
  return nil
end

-- pokefirered/include/battle_util.h:49
function Rules.weather.effective(st, adapter)
  local kind = Rules.weather.kind(st and st.weather)
  if not kind then return nil end
  if adapter and adapter.activeBattlers then
    for _, b in ipairs(adapter:activeBattlers()) do
      local ab = adapter:abilityOf(b)
      if ab == "CLOUD_NINE" or ab == "AIR_LOCK" then return nil end
    end
  end
  return kind
end

function Rules.weather.typeModifier(weather, moveTypeName)
  local kind = Rules.weather.kind(weather)
  local mods = {
    SUN = { FIRE = 1.5, WATER = 0.5 },
    RAIN = { WATER = 1.5, FIRE = 0.5 },
  }
  local row = kind and mods[kind]
  if row and moveTypeName and row[moveTypeName] then return row[moveTypeName] end
  return 1
end

function Rules.weather.chipAmount(maxHp)
  return math.max(1, math.floor((maxHp or 16) / Capabilities.weatherChipDenom))
end

-- Critical hit (Gen3)
Rules.crit = {}

Rules.crit.CHANCE = { [0] = 16, [1] = 8, [2] = 4, [3] = 3, [4] = 2 }

local HIGH_CRIT_EFFECTS = {
  [43] = true,
  [75] = true,
  [200] = true,
  [209] = true,
}

-- pokefirered/src/battle_script_commands.c:1170
function Rules.crit.stage(attacker, moveOrId, highCrit)
  if not Capabilities.gen3Crit then return 0 end
  local stage = 0
  if attacker and (attacker.focusEnergy or attacker.expFocusEnergy) then
    stage = stage + 2
  end
  if highCrit == nil and type(moveOrId) == "table" then
    highCrit = HIGH_CRIT_EFFECTS[tonumber(moveOrId.effect) or -1] or false
  end
  if highCrit then stage = stage + 1 end
  local item = attacker and (attacker.item or (attacker.mon and (attacker.mon.item or attacker.mon.heldItem)))
  item = tonumber(item) or 0
  if item == 198 then stage = stage + 1 end
  local species = attacker and tonumber(attacker.species or (attacker.mon and attacker.mon.species))
  if item == 222 and species == 113 then stage = stage + 2 end
  if item == 225 and species == 83 then stage = stage + 2 end
  if stage > 4 then stage = 4 end
  return stage
end

function Rules.crit.isHighCritEffect(effect)
  return HIGH_CRIT_EFFECTS[tonumber(effect) or -1] == true
end

local function rollZeroTo(rng, den)
  if den <= 1 then return 0 end
  if type(rng) ~= "function" then
    return fallback_rng(0, den - 1)
  end
  local ok, a = pcall(rng, 0, den - 1)
  if ok and type(a) == "number" then return a % den end
  return fallback_rng(0, den - 1)
end

-- pokefirered/src/battle_script_commands.c:1199
function Rules.crit.roll(attacker, moveOrId, highCrit, rng, st)
  -- pokefirered/src/battle_script_commands.c:1200
  if Oak.active(st) and not Oak.testFlag(st, Oak.FLAG_INFLICT_DMG) then return false end
  local stage = Rules.crit.stage(attacker, moveOrId, highCrit)
  local den = Rules.crit.CHANCE[stage] or 2
  local hit = rollZeroTo(rng, den) == 0
  -- pokefirered/src/battle_script_commands.c:1201
  if st and st.pokedude then return false end
  return hit
end

function Rules.crit.multiplier()
  return Capabilities.critMultiplier or 2
end

Rules.weather.SAND_IMMUNE = { ROCK = true, GROUND = true, STEEL = true }
Rules.weather.HAIL_IMMUNE = { ICE = true }

function Rules.weather.hits(types, kind)
  kind = Rules.weather.kind(kind) or "SAND"
  local immune = (kind == "HAIL") and Rules.weather.HAIL_IMMUNE or Rules.weather.SAND_IMMUNE
  for _, t in ipairs(types or {}) do
    if immune[t] then return false end
  end
  return true
end

-- pokefirered/src/battle_script_commands.c:570
Rules.ACCURACY_STAGE = {
  [-6] = { 33, 100 }, [-5] = { 36, 100 }, [-4] = { 43, 100 }, [-3] = { 50, 100 },
  [-2] = { 60, 100 }, [-1] = { 75, 100 }, [0] = { 1, 1 }, [1] = { 133, 100 },
  [2] = { 166, 100 }, [3] = { 2, 1 }, [4] = { 233, 100 }, [5] = { 133, 50 }, [6] = { 3, 1 },
}

-- Substitute guard
Rules.substitute = {}

function Rules.substitute.hasSubstitute(battler, adapter)
  if not battler then return false end
  if adapter and type(adapter.hasSubstitute) == "function" then
    return adapter:hasSubstitute(battler)
  end
  return (battler.substituteHP or 0) > 0
end

function Rules.substitute.blocks(effectKind, target, adapter)
  if not Rules.substitute.hasSubstitute(target, adapter) then return false end
  local blocked = {
    status = true, stat_drop = true, taunt = true, yawn = true,
    burn = true, attract = true, pain_split = true,
  }
  return blocked[effectKind] == true
end

return Rules
