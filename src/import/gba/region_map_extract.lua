-- Bake Kanto Region Map background, cursor, and map section grid from ROM / pret assets.
-- Outputs to data/generated/gba/region_map/:
--   kanto_map.rgba (240x160)
--   cursor.rgba (16x16)
--   player_red.rgba (16x16), player_leaf.rgba (16x16)
--   map_sections.lua

local RegionMapExtract = {}

RegionMapExtract.CACHE_SUB = "region_map"
RegionMapExtract.FORMAT_VERSION = 1

RegionMapExtract.FILES = {
  "kanto_map.png",
  "cursor.png",
  "dungeon_icon.png",
  "player_red.png",
  "player_leaf.png",
}

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

-- Fallback-only text.  The authoritative section names and area descriptions
-- are read from the ROM by src/import/gba/map_preview_extract.lua; these tables
-- keep the module usable when no ROM was imported (ROM-free CI, unit tests).
-- See RegionMapExtract.ensureGenerated.
RegionMapExtract.FALLBACK_SECTION_NAMES = {
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

-- Authentic FRLG Area Descriptions (pokefirered/src/strings.c gText_RegionMap_AreaDesc_*)
RegionMapExtract.FALLBACK_DUNGEON_DESCRIPTIONS = {
  MAPSEC_VIRIDIAN_FOREST = "A deep and sprawling forest that extends around VIRIDIAN CITY. A natural maze, many people become lost inside.",
  MAPSEC_MT_MOON = "A mystical mountain that is known for its frequent meteor falls. The shards of stars that fall here are known as MOON STONES.",
  MAPSEC_DIGLETTS_CAVE = "A seemingly plain tunnel that was dug by wild DIGLETT. It is famous for connecting ROUTES 2 and 11.",
  MAPSEC_KANTO_VICTORY_ROAD = "A tunnel situated on ROUTE 23. It earned its name because it must be traveled by all TRAINERS aiming for the top.",
  MAPSEC_POKEMON_MANSION = "A decrepit, burned-down mansion on CINNABAR ISLAND. It got its name because a famous POKéMON researcher lived there.",
  MAPSEC_KANTO_SAFARI_ZONE = "An amusement park outside FUCHSIA CITY where many rare POKéMON can be observed in the wild. Catch them in a popular game!",
  MAPSEC_ROCK_TUNNEL = "A naturally formed underground tunnel. Because it has not been developed, it is inky dark inside. A light is needed to get through.",
  MAPSEC_SEAFOAM_ISLANDS = "A pair of islands that is situated on ROUTE 20. The two islands are shaped the same, as if they were twins.",
  MAPSEC_POKEMON_TOWER = "A tower that houses the graves of countless POKéMON. Many people visit it daily to pay their respects to the fallen.",
  MAPSEC_CERULEAN_CAVE = "A mysterious cave that is filled with terribly tough POKéMON. It is so dangerous, the POKéMON LEAGUE is in charge of it.",
  MAPSEC_POWER_PLANT = "A power plant that was abandoned years ago, though some of the machines still work. It is infested with electric POKéMON.",
}

-- Effective tables the UI reads.  Seeded from the fallbacks and overlaid with
-- ROM-derived text by ensureGenerated.
local function copyTable(src)
  local out = {}
  for k, v in pairs(src) do out[k] = v end
  return out
end

RegionMapExtract.SECTION_NAMES = copyTable(RegionMapExtract.FALLBACK_SECTION_NAMES)
RegionMapExtract.DUNGEON_DESCRIPTIONS = copyTable(RegionMapExtract.FALLBACK_DUNGEON_DESCRIPTIONS)

local generatedLoaded = false
local generatedOk = false

--- Overlay ROM-derived names/descriptions onto the effective tables.
-- `names` is keyed by numeric mapsec (88..196) and `dungeonInfo` by the same,
-- so both are bridged to the symbolic MAPSEC_* keys the UI uses via `sections`
-- (map_sections_extract.SECTIONS).  Returns the number of sections updated.
function RegionMapExtract.applyGeneratedText(names, dungeonInfo, sections)
  if not sections then return 0 end
  local updated = 0
  if names then
    for secId, name in pairs(names) do
      local info = sections[secId]
      if info and info.id and name and name ~= "" then
        RegionMapExtract.SECTION_NAMES[info.id] = name
        updated = updated + 1
      end
    end
  end
  if dungeonInfo then
    for secId, entry in pairs(dungeonInfo) do
      local info = sections[secId]
      if info and info.id and entry then
        if entry.name and entry.name ~= "" then
          RegionMapExtract.SECTION_NAMES[info.id] = entry.name
        end
        if entry.desc and entry.desc ~= "" then
          RegionMapExtract.DUNGEON_DESCRIPTIONS[info.id] = entry.desc
        end
        updated = updated + 1
      end
    end
  end
  return updated
end

--- Load the generated region-map text from the cache and apply it, once.
-- Falls back silently to the hand-authored tables when the cache has no
-- generated text (ROM-free checkouts).  Returns true when ROM text was applied.
function RegionMapExtract.ensureGenerated()
  if generatedLoaded then return generatedOk end
  generatedLoaded = true
  generatedOk = pcall(function()
    local CacheFs = require("src.import.CacheFs")
    local MapPreviewExtract = require("src.import.gba.map_preview_extract")
    local MapSectionsExtract = require("src.import.gba.map_sections_extract")
    local names = MapPreviewExtract.loadNames(CacheFs)
    local dungeonInfo = MapPreviewExtract.loadDungeonInfo(CacheFs)
    if not names and not dungeonInfo then return end
    RegionMapExtract.applyGeneratedText(names, dungeonInfo, MapSectionsExtract.SECTIONS)
  end) and true or false
  return generatedOk
end


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
  RegionMapExtract.ensureGenerated()
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

local function decode_tile_4bpp(tileBytes, out, baseX, baseY, stride, hflip, vflip)
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for bx = 0, 3 do
      local byte = tileBytes[srcRow * 4 + bx + 1] or 0
      local p0 = byte % 16
      local p1 = math.floor(byte / 16) % 16
      local x0 = bx * 2
      local x1 = x0 + 1
      if hflip then x0, x1 = 7 - x0, 7 - x1 end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function load_pal_banks(bytes, count)
  local banks = {}
  local n = count or math.floor(#bytes / 32)
  for b = 0, n - 1 do
    local colors = {}
    local off = b * 32
    for c = 0, 15 do
      local i = off + c * 2 + 1
      colors[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
    end
    banks[b] = colors
  end
  return banks
end

local function bake_tilemap(gfx, banks, map, mapW, mapH)
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  local W, H = mapW * 8, mapH * 8
  local tileCount = math.floor(#gfx / 32)
  local px = {}
  for i = 1, W * H * 4 do px[i] = 0 end
  local tmp = {}
  for ty = 0, mapH - 1 do
    for tx = 0, mapW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palBank = math.floor(entry / 4096) % 16
      local bank = banks[palBank] or banks[0]
      if tileId < tileCount then
        local tile = {}
        local base = tileId * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        for i = 1, 64 do tmp[i] = 0 end
        decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
        for row = 0, 7 do
          for col = 0, 7 do
            local idx = tmp[row * 8 + col + 1] or 0
            local c = bank[idx] or 0
            local r, g, b = bgr555_to_rgb8(c)
            local o = ((ty * 8 + row) * W + (tx * 8 + col)) * 4 + 1
            px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
          end
        end
      end
    end
  end
  local rgba = {}
  for i = 1, W * H * 4 do rgba[i] = string.char(px[i]) end
  local rgbaStr = table.concat(rgba)
  local pngStr = BattleAnimExtract.encodePng and BattleAnimExtract.encodePng(px, W, H)
  return rgbaStr, pngStr, W, H
end

local function bake_sprite_16x16(gfx, palBytes, tileOffset)
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  tileOffset = tileOffset or 0
  local W, H = 16, 16
  local pal = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    pal[c] = (palBytes[i] or 0) + (palBytes[i + 1] or 0) * 256
  end
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local tiles = {
    { tileOffset + 0, 0, 0 },
    { tileOffset + 1, 8, 0 },
    { tileOffset + 2, 0, 8 },
    { tileOffset + 3, 8, 8 },
  }
  for _, t in ipairs(tiles) do
    local tileNum, ox, oy = t[1], t[2], t[3]
    local base = tileNum * 32
    local tile = {}
    for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
    decode_tile_4bpp(tile, pixels, ox, oy, W, false, false)
  end
  local px = {}
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    local o = (i - 1) * 4 + 1
    if idx == 0 then
      px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  local rgbaStr = table.concat(chunks)
  local pngStr = BattleAnimExtract.encodePng and BattleAnimExtract.encodePng(px, W, H)
  return rgbaStr, pngStr, W, H
end

local function bake_sprite_8x8(gfx, palBytes, tileOffset)
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  tileOffset = tileOffset or 0
  local W, H = 8, 8
  local pal = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    pal[c] = (palBytes[i] or 0) + (palBytes[i + 1] or 0) * 256
  end
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local base = tileOffset * 32
  local tile = {}
  for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
  decode_tile_4bpp(tile, pixels, 0, 0, W, false, false)
  local px = {}
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    local o = (i - 1) * 4 + 1
    if idx == 0 then
      px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  local rgbaStr = table.concat(chunks)
  local pngStr = BattleAnimExtract.encodePng and BattleAnimExtract.encodePng(px, W, H)
  return rgbaStr, pngStr, W, H
end

local function write_file(cache, path, bytes)
  if not (bytes and #bytes > 0) then return false end
  if cache and cache.write then
    return cache:write(path, bytes)
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.write then
    local ok = pcall(CacheFs.write, path, bytes)
    if ok then return true end
  end
  if love and love.filesystem and love.filesystem.write then
    local ok = pcall(love.filesystem.write, path, bytes)
    if ok then return true end
  end
  local f = io.open(path, "wb")
  if f then
    f:write(bytes)
    f:close()
    return true
  end
  return false
end

function RegionMapExtract.run(rom, cache, opts)
  opts = opts or {}
  local Versions = require("src.import.gba.versions")
  local Lz77 = require("src.import.gba.lz77")
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB

  if not rom then
    return { ok = false, root = root, err = "missing ROM handle" }
  end

  local function get(i) return rom:get(i) end
  local function read_bytes(off, len)
    local t = {}
    for i = 1, len do t[i] = get(off + i - 1) end
    return t
  end

  local mapGfx = Lz77.decompress(get, Versions.REGION_MAP_BG_GFX or 0x3EF61C)
  local mapPalBytes = read_bytes(Versions.REGION_MAP_BG_PAL or 0x3EF2DC, 160)
  local mapBanks = load_pal_banks(mapPalBytes, 5)

  local count = 0

  -- 1. Kanto Tilemap
  local kantoTilemap = Lz77.decompress(get, Versions.REGION_MAP_KANTO_TILEMAP or 0x3F089C)
  if mapGfx and kantoTilemap then
    local rgba, png = bake_tilemap(mapGfx, mapBanks, kantoTilemap, 30, 20)
    write_file(cache, root .. "/kanto_map.rgba", rgba)
    if png then write_file(cache, root .. "/kanto_map.png", png) end
    count = count + 1
  end

  -- 2. Sevii 1-3 Tilemap
  local sevii123Tilemap = Lz77.decompress(get, Versions.REGION_MAP_SEVII123_TILEMAP or 0x3F0AFC)
  if mapGfx and sevii123Tilemap then
    local rgba, png = bake_tilemap(mapGfx, mapBanks, sevii123Tilemap, 30, 20)
    write_file(cache, root .. "/sevii123_map.rgba", rgba)
    if png then write_file(cache, root .. "/sevii123_map.png", png) end
    count = count + 1
  end

  -- 3. Sevii 4-5 Tilemap
  local sevii45Tilemap = Lz77.decompress(get, Versions.REGION_MAP_SEVII45_TILEMAP or 0x3F0C0C)
  if mapGfx and sevii45Tilemap then
    local rgba, png = bake_tilemap(mapGfx, mapBanks, sevii45Tilemap, 30, 20)
    write_file(cache, root .. "/sevii45_map.rgba", rgba)
    if png then write_file(cache, root .. "/sevii45_map.png", png) end
    count = count + 1
  end

  -- 4. Sevii 6-7 Tilemap
  local sevii67Tilemap = Lz77.decompress(get, Versions.REGION_MAP_SEVII67_TILEMAP or 0x3F0CF0)
  if mapGfx and sevii67Tilemap then
    local rgba, png = bake_tilemap(mapGfx, mapBanks, sevii67Tilemap, 30, 20)
    write_file(cache, root .. "/sevii67_map.rgba", rgba)
    if png then write_file(cache, root .. "/sevii67_map.png", png) end
    count = count + 1
  end

  -- 5. Cursor
  local cursorGfx = Lz77.decompress(get, Versions.REGION_MAP_CURSOR_GFX or 0x3EF4E0)
  local cursorPalBytes = read_bytes(Versions.REGION_MAP_CURSOR_PAL or 0x3EF25C, 32)
  if cursorGfx and cursorPalBytes then
    local rgba, png = bake_sprite_16x16(cursorGfx, cursorPalBytes, 0)
    write_file(cache, root .. "/cursor.rgba", rgba)
    if png then write_file(cache, root .. "/cursor.png", png) end
    count = count + 1
  end

  -- 6. Player Red Icon
  local redGfx = Lz77.decompress(get, Versions.REGION_MAP_PLAYER_RED_GFX or 0x3EF524)
  local redPalBytes = read_bytes(Versions.REGION_MAP_PLAYER_RED_PAL or 0x3EF27C, 32)
  if redGfx and redPalBytes then
    local rgba, png = bake_sprite_16x16(redGfx, redPalBytes, 0)
    write_file(cache, root .. "/player_red.rgba", rgba)
    if png then write_file(cache, root .. "/player_red.png", png) end
    count = count + 1
  end

  -- 7. Player Leaf Icon
  local leafGfx = Lz77.decompress(get, Versions.REGION_MAP_PLAYER_LEAF_GFX or 0x3EF59C)
  local leafPalBytes = read_bytes(Versions.REGION_MAP_PLAYER_LEAF_PAL or 0x3EF29C, 32)
  if leafGfx and leafPalBytes then
    local rgba, png = bake_sprite_16x16(leafGfx, leafPalBytes, 0)
    write_file(cache, root .. "/player_leaf.rgba", rgba)
    if png then write_file(cache, root .. "/player_leaf.png", png) end
    count = count + 1
  end

  -- 8. Dungeon Icon (8x8)
  local dungGfx = Lz77.decompress(get, Versions.REGION_MAP_DUNGEON_ICON_GFX or 0x3F18D8)
  local miscPalBytes = read_bytes(Versions.REGION_MAP_MISC_ICON_PAL or 0x3EF2BC, 32)
  if dungGfx and miscPalBytes then
    local rgba, png = bake_sprite_8x8(dungGfx, miscPalBytes, 0)
    write_file(cache, root .. "/dungeon_icon.rgba", rgba)
    if png then write_file(cache, root .. "/dungeon_icon.png", png) end
    count = count + 1
  end

  -- 9. Fly Icon (16x16)
  local flyGfx = Lz77.decompress(get, Versions.REGION_MAP_FLY_ICON_GFX or 0x3F1908)
  if flyGfx and miscPalBytes then
    local rgba, png = bake_sprite_16x16(flyGfx, miscPalBytes, 0)
    write_file(cache, root .. "/fly_icon.rgba", rgba)
    if png then write_file(cache, root .. "/fly_icon.png", png) end
    count = count + 1
  end

  local manifest = string.format([[
return {
  version = %d,
  width = 240,
  height = 160,
  cursorSize = 16,
  playerIconSize = 16,
  dungeonIconSize = 8,
  flyIconSize = 16,
}
]], RegionMapExtract.FORMAT_VERSION)
  write_file(cache, root .. "/manifest.lua", manifest)

  return {
    ok = true,
    root = root,
    count = count,
  }
end

local function baked(cache, rel)
  if cache then
    if cache.read then
      local d = cache:read(rel)
      return (d ~= nil and #d > 8)
    elseif cache.exists then
      return cache:exists(rel) and true or false
    end
    return false
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if d and #d > 8 then return true end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if d and #d > 8 then return true end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 8 then return true end
  end
  return false
end

function RegionMapExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  for _, name in ipairs(RegionMapExtract.FILES) do
    if not baked(cache, root .. "/" .. name) then return false end
  end
  return true
end

function RegionMapExtract.extract(rom, opts)
  return RegionMapExtract.run(rom, opts and opts.cache, opts)
end

return RegionMapExtract
