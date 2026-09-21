-- pret heal_locations.json whiteout destinations (SetWhiteoutRespawnWarpAndHealerNpc).
-- Indices match HEAL_LOCATION_* (1-based). setrespawn stores lastHealLocation;
-- whiteout warps to respawnMap at these coords (special-cased in heal_location.c).

local HealLocations = {}

-- MAP_* → FR_* for extracted Kanto maps; only One Island uses the SEVII_ prefix.
local function fr_center(city)
  return "FR_" .. city .. "_POKEMON_CENTER_1F"
end

-- Whiteout standing tile in front of healer (pret heal_location.c).
-- Pallet Mom house: (8,5). Indigo/One Island specials. Else poke-center (7,4).
HealLocations.BY_ID = {
  [1] = { -- HEAL_LOCATION_PALLET_TOWN
    map = "FR_PLAYERS_HOUSE_1F",
    x = 8,
    y = 5,
    healerLocalId = 1, -- LOCALID_MOM
  },
  [2] = { map = fr_center("VIRIDIAN_CITY"), x = 7, y = 4, healerLocalId = 1 },
  -- pokefirered/include/constants/map_event_ids.h:170
  [3] = { map = fr_center("PEWTER_CITY"), x = 7, y = 4, healerLocalId = 3 },
  [4] = { map = fr_center("CERULEAN_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [5] = { map = fr_center("LAVENDER_TOWN"), x = 7, y = 4, healerLocalId = 1 },
  [6] = { map = fr_center("VERMILION_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [7] = { map = fr_center("CELADON_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [8] = { map = fr_center("FUCHSIA_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [9] = { map = fr_center("CINNABAR_ISLAND"), x = 7, y = 4, healerLocalId = 1 },
  [10] = { -- HEAL_LOCATION_INDIGO_PLATEAU
    map = "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F",
    x = 13,
    y = 12,
    healerLocalId = 2, -- pokefirered/include/constants/map_event_ids.h:109
  },
  [11] = { map = fr_center("SAFFRON_CITY"), x = 7, y = 4, healerLocalId = 1 },
  [12] = { map = "FR_ROUTE_4_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [13] = { map = "FR_ROUTE_10_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [14] = { -- HEAL_LOCATION_ONE_ISLAND
    map = "SEVII_ONE_ISLAND_POKECENTER",
    x = 5,
    y = 4,
    healerLocalId = 1,
  },
  [15] = { map = "FR_TWO_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [16] = { map = "FR_THREE_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [17] = { map = "FR_FOUR_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [18] = { map = "FR_FIVE_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [19] = { map = "FR_SEVEN_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
  [20] = { map = "FR_SIX_ISLAND_POKEMON_CENTER_1F", x = 7, y = 4, healerLocalId = 1 },
}

-- pokefirered/src/heal_location.c:52 GetHealLocation
HealLocations.BAKED_REL = "region_map/heal_locations.lua"

HealLocations._baked = nil
HealLocations._bakedRoot = nil

local function default_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function love_cache()
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  if ok and Dataset and Dataset.cache then
    return Dataset.cache()
  end
  return nil
end

local function normalize(row)
  if type(row) ~= "table" then return nil end
  local map = row.map
  if type(map) ~= "string" or map == "" then return nil end
  return {
    map = map,
    x = tonumber(row.x) or 0,
    y = tonumber(row.y) or 0,
    healerLocalId = tonumber(row.healerLocalId) or 1,
  }
end

-- pokefirered/src/data/heal_locations.h:129 sWhiteoutRespawnHealCenterMapIdxs
function HealLocations.install(pack)
  HealLocations._baked = {}
  if type(pack) ~= "table" then return 0 end
  local rows = pack.whiteout
  if type(rows) ~= "table" then return 0 end
  local n = 0
  for key, row in pairs(rows) do
    local id = (type(row) == "table" and tonumber(row.id)) or tonumber(key)
    local loc = normalize(row)
    if id and loc then
      HealLocations._baked[id] = loc
      n = n + 1
    end
  end
  return n
end

function HealLocations.load(cache, root)
  cache = cache or love_cache()
  root = root or default_root()
  HealLocations._baked = {}
  HealLocations._bakedRoot = root
  if not (cache and cache.read) then return 0 end
  local rel = root .. "/" .. HealLocations.BAKED_REL
  local src = cache:read(rel)
  if type(src) ~= "string" or src == "" then return 0 end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return 0 end
  local ok, pack = pcall(chunk)
  if not ok then return 0 end
  return HealLocations.install(pack)
end

function HealLocations.invalidate()
  HealLocations._baked = nil
  HealLocations._bakedRoot = nil
end

function HealLocations.get(id)
  id = tonumber(id) or 0
  if HealLocations._baked == nil then
    HealLocations.load()
  end
  local baked = HealLocations._baked and HealLocations._baked[id]
  if baked then return baked end
  return HealLocations.BY_ID[id]
end

--- Apply setrespawn / default heal onto a session (whiteout destination).
function HealLocations.applyToSession(session, id)
  local loc = HealLocations.get(id)
  if not (session and loc) then return false end
  session.healMap = loc.map
  session.healX = loc.x
  session.healY = loc.y
  session.healHealerLocalId = loc.healerLocalId
  return true
end

--- Migrate bad early defaults (bedroom 2F has no Mom).
function HealLocations.normalizeSession(session)
  if not session then return end
  if session.healMap == "FR_PLAYERS_HOUSE_2F" then
    HealLocations.applyToSession(session, 1)
  end
end

return HealLocations
