-- Game3 battle rules (owned). Crit / weather mods / residual phase labels.

local Capabilities = require("src.core.game3.battle.capabilities")
local Strings = require("src.core.Strings")

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

Rules.PHASE_ORDER = {}
for _, p in ipairs(Rules.FIELD_PHASES_ORDER) do Rules.PHASE_ORDER[#Rules.PHASE_ORDER + 1] = p end
for _, p in ipairs(Rules.BATTLER_PHASES_ORDER) do Rules.PHASE_ORDER[#Rules.PHASE_ORDER + 1] = p end
for _, p in ipairs(Rules.POST_PHASES_ORDER) do Rules.PHASE_ORDER[#Rules.PHASE_ORDER + 1] = p end

Rules.FAINT_HALT_PHASES = {
  ingrain = true,
  leech_seed = true,
  status_chip = true,
  nightmare = true,
  curse = true,
  partial_trap_chip = true,
}

Rules.FIELD_PHASES = {}
for _, p in ipairs(Rules.FIELD_PHASES_ORDER) do Rules.FIELD_PHASES[p] = true end

Rules.POST_PHASES = {}
for _, p in ipairs(Rules.POST_PHASES_ORDER) do Rules.POST_PHASES[p] = true end

function Rules.isFieldPhase(phase)
  return Rules.FIELD_PHASES[phase] == true
end

function Rules.isPostPhase(phase)
  return Rules.POST_PHASES[phase] == true
end

function Rules.phaseOrder()
  return Rules.PHASE_ORDER
end

function Rules.shouldHaltBattlerOnFaint(phase)
  return Rules.FAINT_HALT_PHASES[phase] == true
end

-- Partial trap (Gen3)
Rules.partialTrap = {}

function Rules.partialTrap.chipAmount(maxHp)
  return math.max(1, math.floor((maxHp or 16) / Capabilities.partialTrapChipDenom))
end

-- pokefirered/src/battle_script_commands.c:2490
function Rules.partialTrap.rollTurns(rng)
  rng = rng or math.random
  local ok, n = pcall(rng, 0, 3)
  if not (ok and type(n) == "number") then n = math.random(0, 3) end
  return (math.floor(n) % 4) + 3
end

function Rules.partialTrap.active()
  return Capabilities.gen3PartialTrap
end

-- pokefirered/src/battle_message.c:1263
Rules.partialTrap.MOVES = { 20, 35, 83, 128, 250, 328 }

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

local function fallback_rng(lo, hi)
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end

-- Partial trap (Gen3)
Rules.partialTrap = {}

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

local function partial_trap_name(moveId)
  local ok, Moves = pcall(require, "src.core.game3.battle.moves")
  if ok and Moves and Moves.displayName then
    return Moves.displayName(moveId)
  end
  return tostring(moveId or Strings("the attack"))
end

-- pokefirered/src/battle_message.c:1263
function Rules.partialTrap.message(moveId)
  local name = partial_trap_name(moveId)
  return Strings("{DEFENDER} was trapped by %s!", name)
end

-- pokefirered/src/battle_message.c:1268
function Rules.partialTrap.squeezeMessage(moveId)
  local name = partial_trap_name(moveId)
  return Strings("{DEFENDER} is hurt by %s!", name)
end

-- pokefirered/src/battle_message.c:1274
function Rules.partialTrap.freedMessage(moveId)
  local name = partial_trap_name(moveId)
  return Strings("{DEFENDER} was freed from %s!", name)
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
function Rules.crit.roll(attacker, moveOrId, highCrit, rng)
  local stage = Rules.crit.stage(attacker, moveOrId, highCrit)
  local den = Rules.crit.CHANCE[stage] or 2
  return rollZeroTo(rng, den) == 0
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
