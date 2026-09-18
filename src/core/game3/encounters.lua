-- Wild encounter tables + step rolls. Feeds battle_bridge.
-- Tables come from ROM extract (cache encounters.lua via gWildMonHeaders).
-- RNG: pret wild_encounter.c — Random() for gate/slot/level, WildEncounterRandom for rate.

local Rng = require("src.core.game3.rng")
local ModRuntime = require("src.mods.Runtime")

local Encounters = {}

Encounters._tables = {} -- mapId or "group:num" → { land = { rate, slots }, ... }
Encounters._pendingWild = nil
Encounters._prevGrass = false -- pret first-step-into-grass gate
Encounters._logged = false
Encounters._loaded = false

-- pret ENCOUNTER_CHANCE_LAND_MONS_* cumulative weights (total 100).
local LAND_WEIGHTS = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_WEIGHTS = { 60, 30, 5, 4, 1 }
local MAX_ENCOUNTER_RATE = 1600 -- pret wild_encounter.c (FireRed)

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
local function rate_test(rate)
  rate = (tonumber(rate) or 0) * 16
  if rate > MAX_ENCOUNTER_RATE then rate = MAX_ENCOUNTER_RATE end
  if rate < 1 then return false end
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
  return Encounters._tables[tostring(mapId)]
end

local function roll_area(mapId, areaKey, weights, enterFromOther, fallbackRate)
  local t = table_for(mapId)
  local area = normalize_area(t and t[areaKey], fallbackRate)
  if not area or #area.slots == 0 then return nil end

  -- pret DoGlobalWildEncounterDiceRoll: (Random() % 100) >= 60 → deny.
  if enterFromOther and (Rng.Random() % 100) >= 60 then
    return nil
  end
  if not rate_test(area.rate) then
    return nil
  end

  local entry = pick_slot(area.slots, weights)
  if type(entry) ~= "table" then return nil end
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
  if terrain == "water" then
    return Encounters.rollWater(mapId, enterFromOther)
  end
  return Encounters.rollLand(mapId, nil, enterFromOther)
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
  return engine_encounter(enc)
end

function Encounters.noteGrass(onGrass)
  Encounters._prevGrass = onGrass and true or false
end

return Encounters
