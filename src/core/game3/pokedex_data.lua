-- Core Pokédex Data Query Layer for FRLG Pokédex system.
-- Provides access to entries, habitat categories, sorting orders, area markers, and statistics.

local Extract = require("src.import.gba.extract_island1")
local Dex = require("src.core.game3.dex")
local Pokemon = require("src.core.game3.pokemon")

local PokedexData = {}

PokedexData._entries = nil
PokedexData._categories = nil
PokedexData._orders = nil
PokedexData._areaData = nil
PokedexData._speciesWildAreas = nil

local function cache_root()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function load_lua(rel)
  local src = read_bytes(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil
end

function PokedexData.init()
  if PokedexData._entries then return true end
  local root = cache_root() .. "/pokemon/pokedex"
  PokedexData._entries = load_lua(root .. "/entries.lua") or {}
  PokedexData._categories = load_lua(root .. "/categories.lua") or {}
  PokedexData._orders = load_lua(root .. "/orders.lua") or {}
  PokedexData._areaData = load_lua(root .. "/area_markers.lua") or { markers = {}, mapsecToArea = {} }
  PokedexData._buildSpeciesWildAreas()
  return true
end

--- Map wild encounter tables to species DEX_AREA locations
function PokedexData._buildSpeciesWildAreas()
  PokedexData._speciesWildAreas = {}
  local encounters = load_lua("data/generated/gba/encounters.lua") or load_lua("data/generated/encounters.lua")
  local mapGroups = load_lua("src/import/gba/map_groups_firered.lua")
  local mapsecToArea = PokedexData._areaData and PokedexData._areaData.mapsecToArea or {}

  if encounters and mapGroups and mapGroups.groups then
    for key, header in pairs(encounters) do
      local gIdx, mIdx = header.mapGroup, header.mapNum
      if not gIdx or not mIdx then
        gIdx, mIdx = key:match("^(%d+):(%d+)$")
        gIdx, mIdx = tonumber(gIdx), tonumber(mIdx)
      end
      if gIdx and mIdx then
        local gTable = mapGroups.groups[gIdx + 1] or mapGroups.groups[gIdx]
        local mapInfo = gTable and (gTable[mIdx + 1] or gTable[mIdx])
        local mapSec = mapInfo and (mapInfo.mapSec or mapInfo.region_map_section or mapInfo.id)
        local dexArea = mapSec and mapsecToArea[mapSec]
        if dexArea then
          local function addSpecies(sp)
            if not sp or sp == 0 then return end
            PokedexData._speciesWildAreas[sp] = PokedexData._speciesWildAreas[sp] or {}
            local exists = false
            for _, a in ipairs(PokedexData._speciesWildAreas[sp]) do
              if a == dexArea then exists = true; break end
            end
            if not exists then
              table.insert(PokedexData._speciesWildAreas[sp], dexArea)
            end
          end

          for _, tableKey in ipairs({ "land", "water", "rockSmash", "fishing" }) do
            local t = header[tableKey]
            if t and t.slots then
              for _, slot in ipairs(t.slots) do
                addSpecies(slot.species)
              end
            end
          end
        end
      end
    end
  end
end

function PokedexData.getEntry(speciesId)
  PokedexData.init()
  local sp = tonumber(speciesId) or 1
  local natId = Pokemon.nationalPokedexNumber and Pokemon.nationalPokedexNumber(sp) or sp

  local raw = (PokedexData._entries and PokedexData._entries[natId])
    or (PokedexData._entries and PokedexData._entries[sp])

  if not raw then
    local name = (Pokemon.name and Pokemon.name(sp)) or "POKéMON"
    return {
      category = "UNKNOWN",
      categoryName = "UNKNOWN POKéMON",
      heightDm = 0,
      weightHg = 0,
      heightFormatted = "--'--\"",
      weightFormatted = "---.- lbs.",
      description = "This is a newly discovered POKéMON. It is\ncurrently under investigation.",
      description2 = "This is a newly discovered POKéMON. It is\ncurrently under investigation.",
      pokemonScale = 256,
      pokemonOffset = 0,
      trainerScale = 256,
      trainerOffset = 0,
    }
  end

  local dm = raw.height or 0
  local inchesTenths = math.floor(10000 * dm / 254)
  if inchesTenths % 10 >= 5 then
    inchesTenths = inchesTenths + 10
  end
  local feet = math.floor(inchesTenths / 120)
  local inches = math.floor((inchesTenths - feet * 120) / 10)
  local heightFormatted = string.format("%2d'%02d\"", feet, inches)

  local hg = raw.weight or 0
  local lbsHund = math.floor((hg * 100000) / 4536)
  if lbsHund % 10 >= 5 then
    lbsHund = lbsHund + 10
  end
  local wholeLbs = math.floor(lbsHund / 100)
  local fracLbs = math.floor((lbsHund % 100) / 10)
  local weightFormatted = string.format("%4d.%d lbs.", wholeLbs, fracLbs)

  local cat = raw.category or "POKéMON"
  local categoryName = cat:find("POKéMON") and cat or (cat .. " POKéMON")

  return {
    category = cat,
    categoryName = categoryName,
    heightDm = dm,
    weightHg = hg,
    heightFormatted = heightFormatted,
    weightFormatted = weightFormatted,
    description = raw.description or "",
    description2 = (raw.description2 and #raw.description2 > 0) and raw.description2 or raw.description or "",
    pokemonScale = raw.pokemonScale or 256,
    pokemonOffset = raw.pokemonOffset or 0,
    trainerScale = raw.trainerScale or 256,
    trainerOffset = raw.trainerOffset or 0,
  }
end

function PokedexData.getCategoryPages(categoryKey)
  PokedexData.init()
  return (PokedexData._categories and PokedexData._categories[categoryKey]) or {}
end

function PokedexData.getUnlockedCategoryPages(categoryKey, dex)
  PokedexData.init()
  local allPages = PokedexData.getCategoryPages(categoryKey)
  local unlocked = {}
  for pageIdx, page in ipairs(allPages) do
    local seenMons = {}
    for _, sp in ipairs(page) do
      if Dex.isSeen(dex, sp) then
        table.insert(seenMons, sp)
      end
    end
    if #seenMons > 0 then
      table.insert(unlocked, {
        rawPage = pageIdx,
        mons = seenMons,
      })
    end
  end
  return unlocked
end

function PokedexData.getOrderList(orderKey, dex)
  PokedexData.init()
  local rawList = (PokedexData._orders and PokedexData._orders[orderKey]) or {}
  if not dex then
    return rawList
  end

  local isNat = PokedexData.isNationalUnlocked(nil, dex)
  local maxN = isNat and (Dex.NATIONAL_MAX or 386) or (Dex.KANTO_MAX or 151)

  if orderKey == "numerical_kanto" then
    local maxKanto = Dex.KANTO_MAX or 151
    local highestSeen = 0
    for i = 1, maxKanto do
      if Dex.isSeen(dex, i) then
        highestSeen = i
      end
    end
    local result = {}
    for i = 1, highestSeen do
      table.insert(result, i)
    end
    return result
  elseif orderKey == "numerical_national" then
    local maxNat = Dex.NATIONAL_MAX or 386
    local highestSeen = 0
    for i = 1, maxNat do
      if Dex.isSeen(dex, i) then
        highestSeen = i
      end
    end
    local result = {}
    for i = 1, highestSeen do
      table.insert(result, i)
    end
    return result
  elseif orderKey == "atoz" then
    local result = {}
    for _, sp in ipairs(rawList) do
      if sp <= maxN and Dex.isSeen(dex, sp) then
        table.insert(result, sp)
      end
    end
    return result
  elseif orderKey == "type" or orderKey == "lightest" or orderKey == "smallest" then
    local result = {}
    for _, sp in ipairs(rawList) do
      if sp <= maxN and Dex.isCaught(dex, sp) then
        table.insert(result, sp)
      end
    end
    return result
  end

  return rawList
end

function PokedexData.getWildAreasForSpecies(speciesId)
  PokedexData.init()
  local sp = tonumber(speciesId) or 1
  return (PokedexData._areaData and PokedexData._areaData.speciesAreas and PokedexData._areaData.speciesAreas[sp])
    or (PokedexData._speciesWildAreas and PokedexData._speciesWildAreas[sp])
    or {}
end

function PokedexData.getAreaMarker(dexAreaKey)
  PokedexData.init()
  return PokedexData._areaData and PokedexData._areaData.markers and PokedexData._areaData.markers[dexAreaKey]
end

function PokedexData.isNationalUnlocked(session, dex)
  if dex and (dex.nationalUnlocked or dex.isNationalUnlocked) then
    return true
  end
  if session and (session.national_dex_unlocked or (session.save and session.save.national_dex_unlocked)) then
    return true
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local curSession = session or (Runtime and Runtime.getSession and Runtime.getSession())
  if curSession and (curSession.national_dex_unlocked or (curSession.dex and curSession.dex.nationalUnlocked)) then
    return true
  end
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = (curSession and curSession.store) or (Space and Space.store)
  if store and Flags and Flags.getFlag then
    if Flags.getFlag(store, nil, 0x840) == true then -- FLAG_SYS_NATIONAL_DEX
      return true
    end
    if Flags.getVar and Flags.getVar(store, nil, 0x404E) == 0x6258 then -- VAR_NATIONAL_DEX
      return true
    end
  end
  return false
end

function PokedexData.isCategoryUnlocked(dex, categoryKey)
  PokedexData.init()
  local pages = PokedexData.getCategoryPages(categoryKey)
  if not pages or #pages == 0 then return false end
  for _, page in ipairs(pages) do
    for _, sp in ipairs(page) do
      if Dex.isSeen(dex, sp) then
        return true
      end
    end
  end
  return false
end

function PokedexData.countCategory(dex, categoryKey)
  local pages = PokedexData.getCategoryPages(categoryKey)
  local seen, caught, total = 0, 0, 0
  for _, p in ipairs(pages) do
    for _, sp in ipairs(p) do
      total = total + 1
      if Dex.isSeen(dex, sp) then seen = seen + 1 end
      if Dex.isCaught(dex, sp) then caught = caught + 1 end
    end
  end
  return seen, caught, total
end

function PokedexData.countOrder(dex, orderKey)
  local list = PokedexData.getOrderList(orderKey)
  local seen, caught, total = 0, 0, #list
  for _, sp in ipairs(list) do
    if Dex.isSeen(dex, sp) then seen = seen + 1 end
    if Dex.isCaught(dex, sp) then caught = caught + 1 end
  end
  return seen, caught, total
end

return PokedexData
