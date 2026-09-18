-- Bake Kanto Region Map background, cursor, and map section grid from ROM / pret assets.
-- Outputs to data/generated/gba/region_map/:
--   kanto_map.rgba (240x160)
--   cursor.rgba (16x16)
--   player_red.rgba (16x16), player_leaf.rgba (16x16)
--   map_sections.lua

local RegionMapExtract = {}

RegionMapExtract.CACHE_SUB = "region_map"
RegionMapExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

-- Kanto 22x15 layout from pokefirered/src/data/region_map/region_map_layout_kanto.h
RegionMapExtract.MAP_WIDTH = 22
RegionMapExtract.MAP_HEIGHT = 15

RegionMapExtract.SECTION_NAMES = {
  MAPSEC_PALLET_TOWN = "PALLET TOWN",
  MAPSEC_VIRIDIAN_CITY = "VIRIDIAN CITY",
  MAPSEC_PEWTER_CITY = "PEWTER CITY",
  MAPSEC_CERULEAN_CITY = "CERULEAN CITY",
  MAPSEC_LAVENDER_TOWN = "LAVENDER TOWN",
  MAPSEC_VERMILION_CITY = "VERMILION CITY",
  MAPSEC_CELADON_CITY = "CELADON CITY",
  MAPSEC_FUCHSIA_CITY = "FUCHSIA CITY",
  MAPSEC_CINNABAR_ISLAND = "CINNABAR ISLAND",
  MAPSEC_INDIGO_PLATEAU = "INDIGO PLATEAU",
  MAPSEC_SAFFRON_CITY = "SAFFRON CITY",
  MAPSEC_ROUTE_4_POKECENTER = "ROUTE 4",
  MAPSEC_ROUTE_10_POKECENTER = "ROUTE 10",
  MAPSEC_ROUTE_1 = "ROUTE 1",
  MAPSEC_ROUTE_2 = "ROUTE 2",
  MAPSEC_ROUTE_3 = "ROUTE 3",
  MAPSEC_ROUTE_4 = "ROUTE 4",
  MAPSEC_ROUTE_5 = "ROUTE 5",
  MAPSEC_ROUTE_6 = "ROUTE 6",
  MAPSEC_ROUTE_7 = "ROUTE 7",
  MAPSEC_ROUTE_8 = "ROUTE 8",
  MAPSEC_ROUTE_9 = "ROUTE 9",
  MAPSEC_ROUTE_10 = "ROUTE 10",
  MAPSEC_ROUTE_11 = "ROUTE 11",
  MAPSEC_ROUTE_12 = "ROUTE 12",
  MAPSEC_ROUTE_13 = "ROUTE 13",
  MAPSEC_ROUTE_14 = "ROUTE 14",
  MAPSEC_ROUTE_15 = "ROUTE 15",
  MAPSEC_ROUTE_16 = "ROUTE 16",
  MAPSEC_ROUTE_17 = "ROUTE 17",
  MAPSEC_ROUTE_18 = "ROUTE 18",
  MAPSEC_ROUTE_19 = "ROUTE 19",
  MAPSEC_ROUTE_20 = "ROUTE 20",
  MAPSEC_ROUTE_21 = "ROUTE 21",
  MAPSEC_ROUTE_22 = "ROUTE 22",
  MAPSEC_ROUTE_23 = "ROUTE 23",
  MAPSEC_ROUTE_24 = "ROUTE 24",
  MAPSEC_ROUTE_25 = "ROUTE 25",
  MAPSEC_VIRIDIAN_FOREST = "VIRIDIAN FOREST",
  MAPSEC_MT_MOON = "MT. MOON",
  MAPSEC_S_S_ANNE = "S.S. ANNE",
  MAPSEC_UNDERGROUND_PATH = "UNDERGROUND PATH",
  MAPSEC_UNDERGROUND_PATH_2 = "UNDERGROUND PATH",
  MAPSEC_DIGLETTS_CAVE = "DIGLETT'S CAVE",
  MAPSEC_KANTO_VICTORY_ROAD = "VICTORY ROAD",
  MAPSEC_ROCKET_HIDEOUT = "ROCKET HIDEOUT",
  MAPSEC_SILPH_CO = "SILPH CO.",
  MAPSEC_POKEMON_MANSION = "POKéMON MANSION",
  MAPSEC_KANTO_SAFARI_ZONE = "SAFARI ZONE",
  MAPSEC_POKEMON_TOWER = "POKéMON TOWER",
  MAPSEC_CERULEAN_CAVE = "CERULEAN CAVE",
  MAPSEC_POWER_PLANT = "POWER PLANT",
  MAPSEC_SEAFOAM_ISLANDS = "SEAFOAM ISLANDS",
  MAPSEC_ROCK_TUNNEL = "ROCK TUNNEL",
}

-- [y][x] 0-indexed layout (15 rows, 22 cols)
RegionMapExtract.KANTO_GRID = {
  [0] = { [0]=nil },
  [1] = { [14]="MAPSEC_ROUTE_24", [15]="MAPSEC_ROUTE_25", [16]="MAPSEC_ROUTE_25" },
  [2] = { [14]="MAPSEC_ROUTE_24" },
  [3] = { [2]="MAPSEC_INDIGO_PLATEAU", [8]="MAPSEC_ROUTE_4_POKECENTER", [9]="MAPSEC_ROUTE_4", [10]="MAPSEC_ROUTE_4", [11]="MAPSEC_ROUTE_4", [12]="MAPSEC_ROUTE_4", [13]="MAPSEC_ROUTE_4", [14]="MAPSEC_CERULEAN_CITY", [15]="MAPSEC_ROUTE_9", [16]="MAPSEC_ROUTE_9", [17]="MAPSEC_ROUTE_9", [18]="MAPSEC_ROUTE_10_POKECENTER" },
  [4] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_PEWTER_CITY", [5]="MAPSEC_ROUTE_3", [6]="MAPSEC_ROUTE_3", [7]="MAPSEC_ROUTE_3", [8]="MAPSEC_ROUTE_3", [14]="MAPSEC_ROUTE_5", [18]="MAPSEC_ROUTE_10" },
  [5] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [14]="MAPSEC_ROUTE_5", [18]="MAPSEC_ROUTE_10" },
  [6] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [7]="MAPSEC_ROUTE_16", [8]="MAPSEC_ROUTE_16", [9]="MAPSEC_ROUTE_16", [10]="MAPSEC_ROUTE_16", [11]="MAPSEC_CELADON_CITY", [12]="MAPSEC_ROUTE_7", [13]="MAPSEC_ROUTE_7", [14]="MAPSEC_SAFFRON_CITY", [15]="MAPSEC_ROUTE_8", [16]="MAPSEC_ROUTE_8", [17]="MAPSEC_ROUTE_8", [18]="MAPSEC_LAVENDER_TOWN" },
  [7] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_ROUTE_6", [18]="MAPSEC_ROUTE_12" },
  [8] = { [2]="MAPSEC_ROUTE_22", [3]="MAPSEC_ROUTE_22", [4]="MAPSEC_VIRIDIAN_CITY", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_ROUTE_6", [18]="MAPSEC_ROUTE_12" },
  [9] = { [4]="MAPSEC_ROUTE_1", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_VERMILION_CITY", [15]="MAPSEC_ROUTE_11", [16]="MAPSEC_ROUTE_11", [17]="MAPSEC_ROUTE_11", [18]="MAPSEC_ROUTE_12" },
  [10] = { [4]="MAPSEC_ROUTE_1", [7]="MAPSEC_ROUTE_17", [18]="MAPSEC_ROUTE_12" },
  [11] = { [4]="MAPSEC_PALLET_TOWN", [7]="MAPSEC_ROUTE_17", [15]="MAPSEC_ROUTE_14", [16]="MAPSEC_ROUTE_13", [17]="MAPSEC_ROUTE_13", [18]="MAPSEC_ROUTE_12" },
  [12] = { [4]="MAPSEC_ROUTE_21", [7]="MAPSEC_ROUTE_18", [8]="MAPSEC_ROUTE_18", [9]="MAPSEC_ROUTE_18", [10]="MAPSEC_ROUTE_18", [11]="MAPSEC_ROUTE_18", [12]="MAPSEC_FUCHSIA_CITY", [13]="MAPSEC_ROUTE_15", [14]="MAPSEC_ROUTE_15", [15]="MAPSEC_ROUTE_14" },
  [13] = { [4]="MAPSEC_ROUTE_21", [12]="MAPSEC_ROUTE_19" },
  [14] = { [4]="MAPSEC_CINNABAR_ISLAND", [5]="MAPSEC_ROUTE_20", [6]="MAPSEC_ROUTE_20", [7]="MAPSEC_ROUTE_20", [8]="MAPSEC_ROUTE_20", [9]="MAPSEC_ROUTE_20", [10]="MAPSEC_ROUTE_20", [11]="MAPSEC_ROUTE_20", [12]="MAPSEC_ROUTE_19" },
}

-- Dungeon layer [y][x] 0-indexed layout from pokefirered LAYER_DUNGEON
RegionMapExtract.DUNGEON_GRID = {
  [3] = { [9] = "MAPSEC_MT_MOON", [14] = "MAPSEC_CERULEAN_CAVE", [18] = "MAPSEC_ROCK_TUNNEL" },
  [4] = { [2] = "MAPSEC_KANTO_VICTORY_ROAD", [18] = "MAPSEC_POWER_PLANT" },
  [5] = { [4] = "MAPSEC_DIGLETTS_CAVE" },
  [6] = { [4] = "MAPSEC_VIRIDIAN_FOREST", [18] = "MAPSEC_POKEMON_TOWER" },
  [9] = { [15] = "MAPSEC_DIGLETTS_CAVE" },
  [12] = { [12] = "MAPSEC_KANTO_SAFARI_ZONE" },
  [14] = { [4] = "MAPSEC_POKEMON_MANSION", [8] = "MAPSEC_SEAFOAM_ISLANDS" },
}

-- Host Map ID -> (x, y) grid coords for player icon
RegionMapExtract.HOST_MAP_TO_GRID = {
  PALLET_TOWN = { 4, 11 },
  REDS_HOUSE_1F = { 4, 11 },
  REDS_HOUSE_2F = { 4, 11 },
  BLUES_HOUSE = { 4, 11 },
  OAKS_LAB = { 4, 11 },
  VIRIDIAN_CITY = { 4, 8 },
  PEWTER_CITY = { 4, 4 },
  CERULEAN_CITY = { 14, 3 },
  LAVENDER_TOWN = { 18, 6 },
  VERMILION_CITY = { 14, 9 },
  CELADON_CITY = { 11, 6 },
  FUCHSIA_CITY = { 12, 12 },
  CINNABAR_ISLAND = { 4, 14 },
  INDIGO_PLATEAU = { 2, 3 },
  SAFFRON_CITY = { 14, 6 },
  ROUTE_1 = { 4, 9 },
  ROUTE_2 = { 4, 5 },
  ROUTE_3 = { 6, 4 },
  ROUTE_4 = { 11, 3 },
  ROUTE_5 = { 14, 4 },
  ROUTE_6 = { 14, 7 },
  ROUTE_7 = { 12, 6 },
  ROUTE_8 = { 16, 6 },
  ROUTE_9 = { 16, 3 },
  ROUTE_10 = { 18, 5 },
  ROUTE_11 = { 16, 9 },
  ROUTE_12 = { 18, 8 },
  ROUTE_13 = { 17, 11 },
  ROUTE_14 = { 15, 12 },
  ROUTE_15 = { 13, 12 },
  ROUTE_16 = { 9, 6 },
  ROUTE_17 = { 7, 8 },
  ROUTE_18 = { 9, 12 },
  ROUTE_19 = { 12, 13 },
  ROUTE_20 = { 8, 14 },
  ROUTE_21 = { 4, 13 },
  ROUTE_22 = { 3, 8 },
  ROUTE_23 = { 2, 5 },
  ROUTE_24 = { 14, 2 },
  ROUTE_25 = { 15, 1 },
  VIRIDIAN_FOREST = { 4, 6 },
  MT_MOON = { 9, 3 },
  ROCK_TUNNEL = { 18, 3 },
  POWER_PLANT = { 18, 4 },
  POKEMON_TOWER = { 18, 6 },
  DIGLETTS_CAVE = { 4, 5 },
  KANTO_VICTORY_ROAD = { 2, 4 },
  POKEMON_MANSION = { 4, 14 },
  KANTO_SAFARI_ZONE = { 12, 12 },
  SEAFOAM_ISLANDS = { 8, 14 },
  CERULEAN_CAVE = { 14, 3 },
}

function RegionMapExtract.resolveLocation(mapId, mapSec)
  if mapSec and RegionMapExtract.SECTION_NAMES[mapSec] then
    local name = RegionMapExtract.SECTION_NAMES[mapSec]
    -- 1. Check DUNGEON_GRID first for dungeon mapsecs
    for y = 0, RegionMapExtract.MAP_HEIGHT - 1 do
      local dRow = RegionMapExtract.DUNGEON_GRID[y]
      if dRow then
        for x = 0, RegionMapExtract.MAP_WIDTH - 1 do
          if dRow[x] == mapSec then
            return { x = x, y = y, name = name, mapsec = mapSec }
          end
        end
      end
    end
    -- 2. Check overworld KANTO_GRID
    for y = 0, RegionMapExtract.MAP_HEIGHT - 1 do
      local row = RegionMapExtract.KANTO_GRID[y]
      if row then
        for x = 0, RegionMapExtract.MAP_WIDTH - 1 do
          if row[x] == mapSec then
            return { x = x, y = y, name = name, mapsec = mapSec }
          end
        end
      end
    end
  end

  if mapId then
    local u = tostring(mapId):upper()
    local g = RegionMapExtract.HOST_MAP_TO_GRID[u]
    if g then
      local dSec = RegionMapExtract.DUNGEON_GRID[g[2]] and RegionMapExtract.DUNGEON_GRID[g[2]][g[1]]
      local oSec = RegionMapExtract.KANTO_GRID[g[2]] and RegionMapExtract.KANTO_GRID[g[2]][g[1]]
      local sec = dSec or oSec
      if RegionMapExtract.SECTION_NAMES["MAPSEC_" .. u] then
        sec = "MAPSEC_" .. u
      end
      local name = sec and RegionMapExtract.SECTION_NAMES[sec] or u:gsub("_", " ")
      return { x = g[1], y = g[2], name = name, mapsec = sec }
    end
    -- Sub-locations / Buildings lookup
    for hostKey, grid in pairs(RegionMapExtract.HOST_MAP_TO_GRID) do
      if u:find(hostKey, 1, true) then
        local dSec = RegionMapExtract.DUNGEON_GRID[grid[2]] and RegionMapExtract.DUNGEON_GRID[grid[2]][grid[1]]
        local oSec = RegionMapExtract.KANTO_GRID[grid[2]] and RegionMapExtract.KANTO_GRID[grid[2]][grid[1]]
        local sec = dSec or oSec
        if RegionMapExtract.SECTION_NAMES["MAPSEC_" .. hostKey] then
          sec = "MAPSEC_" .. hostKey
        end
        local name = sec and RegionMapExtract.SECTION_NAMES[sec] or hostKey:gsub("_", " ")
        return { x = grid[1], y = grid[2], name = name, mapsec = sec }
      end
    end
  end

  return { x = 4, y = 11, name = "PALLET TOWN", mapsec = "MAPSEC_PALLET_TOWN" }
end

return RegionMapExtract
