-- Wild encounter tables + step rolls. Feeds battle_bridge.
-- Tables come from ROM extract (cache encounters.lua via gWildMonHeaders).
-- RNG: pret wild_encounter.c — Random() for gate/slot/level, WildEncounterRandom for rate.

local Rng = require("src.core.game3.rng")
local ModRuntime = require("src.mods.Runtime")

local Encounters = {}

Encounters._tables = {} -- mapId or "group:num" → { land = { rate, slots }, ... }
Encounters._pendingWild = nil
Encounters._prevGrass = false -- pret first-step-into-grass gate
Encounters._stepsSinceLastEncounter = 0 -- pret sWildEncounterData.stepsSinceLastEncounter
Encounters._encounterRateBuff = 0 -- pret sWildEncounterData.encounterRateBuff
Encounters._logged = false
Encounters._loaded = false

-- pret ENCOUNTER_CHANCE_LAND_MONS_* cumulative weights (total 100).
local LAND_WEIGHTS = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_WEIGHTS = { 60, 30, 5, 4, 1 }
local MAX_ENCOUNTER_RATE = 1600 -- pret wild_encounter.c (FireRed)

-- Ids the encounter-rate modifiers below key off (pret constants/abilities.h,
-- constants/items.h, constants/flags.h).
local ABILITY_STENCH = 1
local ABILITY_ILLUMINATE = 35
local ITEM_CLEANSE_TAG = 190
local FLAG_SYS_WHITE_FLUTE_ACTIVE = 0x803
local FLAG_SYS_BLACK_FLUTE_ACTIVE = 0x804

-- pret GetMapBaseEncounterCooldown returns 0xFF when the map has no encounter
-- data for that tile type, which aborts the check instead of granting a grace
-- period (the roll would fail anyway).
local COOLDOWN_NONE = 0xFF
local COOLDOWN_BASE_LEAK = 5 -- pret: encRate = 5 * 256
local COOLDOWN_SCALE = 256 -- pret keeps minSteps/encRate scaled so the modifiers stay fractional

-- pret AddToWildEncounterRateBuff banks into a u16 field, so it wraps there.
local RATE_BUFF_MOD = 65536
-- pret VAR_REPEL_STEP_COUNT (this tree stores it at the 0x4021 slot).
local VAR_REPEL_STEP_COUNT = 0x4021

local function log(msg)
  print("[game3/encounters] " .. tostring(msg))
end

local function merge_tables(dst, src)
  if type(src) ~= "table" then return end
  for k, v in pairs(src) do
    dst[k] = v
  end
end

local function load_lua_blob(src, label)
  if not src or src == "" then return nil end
  local chunk = load(src, label or "@encounters", "t", {})
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  if ok and type(data) == "table" then return data end
  return nil
end

--- Same cache path Dataset / NativeTileset use (firered/ + CacheFs.readActive).
local function load_from_cache()
  local Extract = package.loaded["src.import.gba.extract_island1"]
    or require("src.import.gba.extract_island1")
  local root = Extract.CACHE_ROOT or "data/generated/gba"
  local path = root .. "/encounters.lua"

  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local src = Dataset.cache():read(path)
    local data = load_lua_blob(src, "@" .. path)
    if data then return data end
  end

  -- Fallback: CacheFs directly (version prefix).
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local src = CacheFs.readActive(path)
    local data = load_lua_blob(src, "@" .. path)
    if data then return data end
  end

  if love and love.filesystem and love.filesystem.read then
    local src = love.filesystem.read(path)
    return load_lua_blob(src, "@" .. path)
  end
  return nil
end

function Encounters.loadFromMod(_mod)
  Encounters._tables = {}
  Encounters._loaded = false

  local data = load_from_cache()
  if data then
    merge_tables(Encounters._tables, data)
    Encounters._loaded = true
  end

  local okStub, stub = pcall(require, "src.core.game3.encounters_data_stub")
  if okStub and type(stub) == "table" then
    if stub.TABLES then merge_tables(Encounters._tables, stub.TABLES)
    else merge_tables(Encounters._tables, stub) end
  end

  local n = 0
  for _ in pairs(Encounters._tables) do n = n + 1 end
  if not Encounters._logged or n > 0 then
    log(string.format("loaded %d map tables%s",
      n, data and " (ROM extract)" or " (no extract — re-run gba extract)"))
    Encounters._logged = true
  end
end

--- Lazy reload if install ran before the firered cache was mounted.
function Encounters.ensureLoaded()
  if Encounters._loaded then
    local n = 0
    for _ in pairs(Encounters._tables) do n = n + 1 end
    if n > 0 then return true end
  end
  Encounters.loadFromMod(nil)
  return Encounters._loaded
end

function Encounters.setWildBattle(species, level, item)
  Encounters._pendingWild = {
    species = species,
    level = level,
    item = item,
  }
end

function Encounters.takePendingWild()
  local p = Encounters._pendingWild
  Encounters._pendingWild = nil
  return p
end

--- pret ChooseWildMonIndex_Land / WaterRock: Random() % total, cumulative slots.
local function pick_slot_index(weights)
  local total = 0
  for i = 1, #weights do
    total = total + (weights[i] or 0)
  end
  if total < 1 then return 1 end
  local rand = Rng.Random() % total
  local acc = 0
  for i = 1, #weights do
    acc = acc + (weights[i] or 0)
    if rand < acc then return i end
  end
  return #weights
end

local function pick_slot(slots, weights)
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local n = #slots
  local w = {}
  for i = 1, n do
    w[i] = weights[i] or 1
  end
  local idx = pick_slot_index(w)
  if idx < 1 then idx = 1 end
  if idx > n then idx = n end
  return slots[idx]
end

--- pret ChooseWildMonLevel: lo + Random() % (hi - lo + 1).
local function level_of(entry)
  if not entry then return 5 end
  local lo = tonumber(entry.minLevel or entry.level or entry[2]) or 5
  local hi = tonumber(entry.maxLevel or entry.level or entry[2]) or lo
  if hi < lo then hi = lo end
  if hi == lo then return lo end
  local mod = hi - lo + 1
  return lo + (Rng.Random() % mod)
end

--- pret DoWildEncounterRateDiceRoll: WildEncounterRandom() % 1600 < rate.
local function rate_dice_roll(rate)
  return (Rng.WildEncounterRandom() % MAX_ENCOUNTER_RATE) < rate
end

local function normalize_area(area, fallbackRate)
  if type(area) ~= "table" then return nil end
  if area.slots or area.mons then
    return {
      rate = area.rate or fallbackRate or 21,
      slots = area.slots or area.mons,
    }
  end
  if #area > 0 then
    return { rate = fallbackRate or 21, slots = area }
  end
  return nil
end

local function table_for(mapId)
  if not mapId then return nil end
  local t = Encounters._tables[mapId]
  if t then return t end
  local s = tostring(mapId)
  t = Encounters._tables[s]
  if t then return t end

  -- MapCatalog resolution (e.g. pret name or group:num)
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog then
    local res = MapCatalog.resolve(s)
    if res and Encounters._tables[res] then
      return Encounters._tables[res]
    end
    local slot = MapCatalog.slotKeyFor(s)
    if slot then
      local colonSlot = slot:gsub("_", ":")
      if Encounters._tables[colonSlot] then return Encounters._tables[colonSlot] end
      if Encounters._tables[slot] then return Encounters._tables[slot] end
    end
  end

  -- Prefix stripping / addition
  if s:sub(1, 3) == "FR_" then
    t = Encounters._tables[s:sub(4)]
    if t then return t end
  else
    t = Encounters._tables["FR_" .. s]
    if t then return t end
  end

  -- Route underscore normalization (ROUTE_22 <-> ROUTE22)
  local routeNum = s:match("ROUTE_?(%d+)")
  if routeNum then
    t = Encounters._tables["FR_ROUTE_" .. routeNum]
      or Encounters._tables["FR_ROUTE" .. routeNum]
      or Encounters._tables["ROUTE_" .. routeNum]
      or Encounters._tables["ROUTE" .. routeNum]
    if t then return t end
  end

  return nil
end

function Encounters.tableFor(mapId)
  Encounters.ensureLoaded()
  return table_for(mapId)
end
Encounters.table_for = Encounters.tableFor

--- The area `terrain` rolls on, resolved the same way rollLand/rollWater do.
--- The cooldown needs the rate before the roll happens, and must not consume
--- RNG to get it.
local function area_for(mapId, terrain)
  local t = table_for(mapId)
  if terrain == "water" then
    return normalize_area(t and t.water, 15)
  end
  return normalize_area(t and t.land) or normalize_area(t and t.grass)
end

-- ---------------------------------------------------------------------------
-- Wild encounter grace period (pret wild_encounter.c).
--
-- FireRed is the only generation with a step cooldown between wild battles:
-- HandleWildEncounterCooldown refuses the roll for a map-dependent number of
-- steps after the last encounter, then lets a small percentage per step
-- through so the wait is soft rather than a hard floor.
-- ---------------------------------------------------------------------------

--- pret GetMapBaseEncounterCooldown: how many steps after a battle are immune,
--- derived from the area's own encounter rate. Rates at 80+ get no grace period
--- at all; below that the wait grows as the rate drops.
function Encounters.mapBaseCooldown(terrain, rate)
  if terrain ~= "land" and terrain ~= "water" then return COOLDOWN_NONE end
  if rate == nil then return COOLDOWN_NONE end
  rate = tonumber(rate) or 0
  if rate >= 80 then return 0 end
  if rate < 10 then return 8 end
  return 8 - math.floor(rate / 10)
end

--- pret GetLeadMonIndex: the lead party slot, eggs excluded.
local function lead_mon()
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  local session = ok and Runtime and Runtime.getSession and Runtime.getSession()
  local party = session and session.party
  if type(party) ~= "table" then return nil end
  for i = 1, #party do
    local mon = party[i]
    if type(mon) == "table" and not mon.isEgg and not mon.egg then return mon end
  end
  return nil
end

--- pret GetFluteEncounterRateModType: 1 = White Flute, 2 = Black Flute.
local function flute_mod_type()
  local okS, Space = pcall(require, "src.core.game3.scripting.space")
  if not okS or not Space or not Space.store then return 0 end
  local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
  if not okF or not Flags or not Flags.getFlag then return 0 end
  if Flags.getFlag(Space.store, nil, FLAG_SYS_WHITE_FLUTE_ACTIVE) then return 1 end
  if Flags.getFlag(Space.store, nil, FLAG_SYS_BLACK_FLUTE_ACTIVE) then return 2 end
  return 0
end

--- pret IsLeadMonHoldingCleanseTag.
local function lead_holds_cleanse_tag()
  local mon = lead_mon()
  if not mon then return false end
  return (tonumber(mon.item or mon.heldItem) or 0) == ITEM_CLEANSE_TAG
end

--- pret GetAbilityEncounterRateModType: Stench 1 (rarer), Illuminate 2 (commoner).
local function ability_mod_type()
  local mon = lead_mon()
  if not mon then return 0 end
  local ability = tonumber(mon.abilityId or mon.ability) or 0
  if ability == ABILITY_STENCH then return 1 end
  if ability == ABILITY_ILLUMINATE then return 2 end
  return 0
end

--- The fully modified (minSteps, leak) pair pret computes inside
--- HandleWildEncounterCooldown. nil means "no encounter data here".
function Encounters.cooldownMinSteps(terrain, rate)
  local minSteps = Encounters.mapBaseCooldown(terrain, rate)
  if minSteps == COOLDOWN_NONE then return nil end

  minSteps = minSteps * COOLDOWN_SCALE
  local leak = COOLDOWN_BASE_LEAK * COOLDOWN_SCALE
  local flute = flute_mod_type()
  if flute == 1 then
    minSteps = minSteps - math.floor(minSteps / 2)
    leak = leak + math.floor(leak / 2)
  elseif flute == 2 then
    minSteps = minSteps * 2
    leak = math.floor(leak / 2)
  end
  if lead_holds_cleanse_tag() then
    minSteps = minSteps + math.floor(minSteps / 3)
    leak = leak - math.floor(leak / 3)
  end
  local ability = ability_mod_type()
  if ability == 1 then
    minSteps = minSteps * 2
    leak = math.floor(leak / 2)
  elseif ability == 2 then
    minSteps = math.floor(minSteps / 2)
    leak = leak * 2
  end
  return math.floor(minSteps / COOLDOWN_SCALE), math.floor(leak / COOLDOWN_SCALE)
end

--- pret HandleWildEncounterCooldown. TRUE means this step may roll for an
--- encounter. Runs on every step onto an encounter tile -- including the steps
--- the dice roll would have denied, which is what advances the counter.
function Encounters.handleCooldown(terrain, rate)
  local minSteps, leak = Encounters.cooldownMinSteps(terrain, rate)
  if minSteps == nil then return false end

  if Encounters._stepsSinceLastEncounter >= minSteps then return true end
  Encounters._stepsSinceLastEncounter = Encounters._stepsSinceLastEncounter + 1
  return (Rng.Random() % 100) < leak
end

--- pret ResetEncounterRateModifiers, reached from RestartWildEncounterImmunitySteps
--- on map load (overworld.c) and on battle start (battle_setup.c). Resetting when
--- the battle starts is what re-arms the grace period, including for wild battles
--- nothing stepped into (scripts, fishing).
function Encounters.resetRateModifiers()
  Encounters._stepsSinceLastEncounter = 0
  Encounters._encounterRateBuff = 0
end

--- pret TestPlayerAvatarFlags(PLAYER_AVATAR_FLAG_MACH_BIKE | ..._ACRO_BIKE).
local function bike_active()
  local ok, Player = pcall(require, "src.core.game3.player")
  return (ok and Player and Player.biking) == true
end

--- pret VarGet(VAR_REPEL_STEP_COUNT) != 0.
local function repel_active()
  local ok, Runtime = pcall(require, "src.core.game3.runtime")
  local session = ok and Runtime and Runtime.getSession and Runtime.getSession()
  if type(session) ~= "table" then return false end
  local vars = session.vars
  local steps = tonumber(session.repelSteps)
    or (type(vars) == "table" and tonumber(vars[VAR_REPEL_STEP_COUNT]))
    or 0
  return steps > 0
end

--- pret AddToWildEncounterRateBuff: bank a failed roll's rate so the next
--- attempt is likelier. A Repel zeroes the bank instead of growing it.
local function add_to_rate_buff(rate)
  if repel_active() then
    Encounters._encounterRateBuff = 0
    return
  end
  Encounters._encounterRateBuff =
    (Encounters._encounterRateBuff + (tonumber(rate) or 0)) % RATE_BUFF_MOD
end

--- pret DoWildEncounterRateTest, without the roll: the threshold in 1/1600ths
--- that the dice roll compares against. Every encounter-rate modifier applies
--- here as well as in the cooldown -- bike, banked buff, flute, Cleanse Tag,
--- then ability, in pret's order.
function Encounters.encounterRate(rate)
  local r = (tonumber(rate) or 0) * 16
  if bike_active() then r = math.floor(r * 80 / 100) end
  r = r + math.floor(Encounters._encounterRateBuff * 16 / 200)
  local flute = flute_mod_type()
  if flute == 1 then
    r = r + math.floor(r / 2)
  elseif flute == 2 then
    r = math.floor(r / 2)
  end
  if lead_holds_cleanse_tag() then r = math.floor(r * 2 / 3) end
  local ability = ability_mod_type()
  if ability == 1 then
    r = math.floor(r / 2)
  elseif ability == 2 then
    r = r * 2
  end
  if r > MAX_ENCOUNTER_RATE then r = MAX_ENCOUNTER_RATE end
  return r
end

local function rate_test(rate)
  return rate_dice_roll(Encounters.encounterRate(rate))
end

local function roll_area(mapId, areaKey, weights, enterFromOther, fallbackRate)
  local t = table_for(mapId)
  local area = normalize_area(t and t[areaKey], fallbackRate)
  if not area or #area.slots == 0 then return nil end

  -- pret DoGlobalWildEncounterDiceRoll: (Random() % 100) >= 60 → deny.
  -- This returns before the rate test, so it does not bank into the buff.
  if enterFromOther and (Rng.Random() % 100) >= 60 then
    return nil
  end
  if not rate_test(area.rate) then
    add_to_rate_buff(area.rate)
    return nil
  end

  local entry = pick_slot(area.slots, weights)
  if type(entry) ~= "table" then
    -- pret banks here too: the rate test passed but TryGenerateWildMon found
    -- no allowed mon (repel level check, empty slot).
    add_to_rate_buff(area.rate)
    return nil
  end
  return {
    species = entry.species or entry[1],
    level = level_of(entry),
    item = entry.item,
  }
end

function Encounters.rollLand(mapId, rate, enterFromOther)
  Encounters.ensureLoaded()
  return roll_area(mapId, "land", LAND_WEIGHTS, enterFromOther, rate)
    or roll_area(mapId, "grass", LAND_WEIGHTS, enterFromOther, rate)
end

function Encounters.rollWater(mapId, enterFromOther)
  Encounters.ensureLoaded()
  return roll_area(mapId, "water", WATER_WEIGHTS, enterFromOther, 15)
end

local function vanilla_step(mapId, terrain, opts)
  Encounters.ensureLoaded()
  opts = opts or {}
  local enterFromOther = opts.enterFromOther
  if enterFromOther == nil then
    enterFromOther = not Encounters._prevGrass
  end
  -- pret TryStandardWildEncounter consults the cooldown before the rate test.
  local area = area_for(mapId, terrain)
  if not Encounters.handleCooldown(terrain, area and area.rate) then return nil end
  local enc
  if terrain == "water" then
    enc = Encounters.rollWater(mapId, enterFromOther)
  else
    enc = Encounters.rollLand(mapId, nil, enterFromOther)
  end
  -- pret sets stepsSinceLastEncounter = 0 once an encounter actually starts.
  if enc then Encounters.resetRateModifiers() end
  return enc
end

local function mod_encounter(enc)
  if type(enc) ~= "table" then return enc end
  local Pokemon = require("src.core.game3.pokemon")
  local id = tonumber(enc.species)
  return {
    species = (id and Pokemon.keyName(id)) or enc.species,
    speciesId = id or Pokemon.speciesFromName(enc.species),
    level = enc.level,
    item = enc.item,
  }
end

local function engine_encounter(enc)
  if type(enc) ~= "table" then return nil end
  local id = tonumber(enc.species)
  if not id and enc.species ~= nil then
    local Pokemon = require("src.core.game3.pokemon")
    id = Pokemon.speciesFromName(enc.species)
  end
  id = id or tonumber(enc.speciesId)
  if not id then return nil end
  return { species = id, level = tonumber(enc.level) or 5, item = enc.item }
end

local function same_encounter(enc) return enc end

function Encounters.onStep(mapId, terrain, opts)
  local wantsRoll = ModRuntime.wantsHook("encounter.roll")
  local wantsSpecies = ModRuntime.wantsHook("encounter.species")
  if not (wantsRoll or wantsSpecies) then
    return vanilla_step(mapId, terrain, opts)
  end
  Encounters.ensureLoaded()
  local ctx = { mapId = mapId, terrain = terrain, rng = Rng.Random, opts = opts }
  local enc
  if wantsRoll then
    enc = ModRuntime.call("encounter.roll", function()
      return mod_encounter(vanilla_step(mapId, terrain, opts))
    end, table_for(mapId), ctx)
  else
    enc = mod_encounter(vanilla_step(mapId, terrain, opts))
  end
  if enc and wantsSpecies then
    enc = ModRuntime.call("encounter.species", same_encounter, enc, ctx)
  end
  enc = engine_encounter(enc)
  if enc then Encounters.resetRateModifiers() end
  return enc
end

function Encounters.noteGrass(onGrass)
  Encounters._prevGrass = onGrass and true or false
end

return Encounters
