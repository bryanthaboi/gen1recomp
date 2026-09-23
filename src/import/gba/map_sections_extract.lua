-- Map Sections & Location Name Popup Theme Extractor / Registry for Game3.
-- Maps GBA regionMapSectionId (0x58 = PALLET_TOWN ...) to names & themes.

local MapSectionsExtract = {}

MapSectionsExtract.KANTO_MAPSEC_START = 88 -- 0x58 = MAPSEC_PALLET_TOWN

MapSectionsExtract.SECTIONS = {
  [88]  = { id = "MAPSEC_PALLET_TOWN", theme = "marble" },
  [89]  = { id = "MAPSEC_VIRIDIAN_CITY", theme = "marble" },
  [90]  = { id = "MAPSEC_PEWTER_CITY", theme = "stone" },
  [91]  = { id = "MAPSEC_CERULEAN_CITY", theme = "marble" },
  [92]  = { id = "MAPSEC_LAVENDER_TOWN", theme = "marble" },
  [93]  = { id = "MAPSEC_VERMILION_CITY", theme = "marble" },
  [94]  = { id = "MAPSEC_CELADON_CITY", theme = "brick" },
  [95]  = { id = "MAPSEC_FUCHSIA_CITY", theme = "wood" },
  [96]  = { id = "MAPSEC_CINNABAR_ISLAND", theme = "stone" },
  [97]  = { id = "MAPSEC_INDIGO_PLATEAU", theme = "marble" },
  [98]  = { id = "MAPSEC_SAFFRON_CITY", theme = "brick" },
  [99]  = { id = "MAPSEC_ROUTE_4_POKECENTER", theme = "stone" },
  [100] = { id = "MAPSEC_ROUTE_10_POKECENTER", theme = "stone" },
  [101] = { id = "MAPSEC_ROUTE_1", theme = "marble" },
  [102] = { id = "MAPSEC_ROUTE_2", theme = "marble" },
  [103] = { id = "MAPSEC_ROUTE_3", theme = "stone" },
  [104] = { id = "MAPSEC_ROUTE_4", theme = "stone" },
  [105] = { id = "MAPSEC_ROUTE_5", theme = "marble" },
  [106] = { id = "MAPSEC_ROUTE_6", theme = "marble" },
  [107] = { id = "MAPSEC_ROUTE_7", theme = "brick" },
  [108] = { id = "MAPSEC_ROUTE_8", theme = "brick" },
  [109] = { id = "MAPSEC_ROUTE_9", theme = "stone" },
  [110] = { id = "MAPSEC_ROUTE_10", theme = "stone" },
  [111] = { id = "MAPSEC_ROUTE_11", theme = "marble" },
  [112] = { id = "MAPSEC_ROUTE_12", theme = "wood" },
  [113] = { id = "MAPSEC_ROUTE_13", theme = "wood" },
  [114] = { id = "MAPSEC_ROUTE_14", theme = "wood" },
  [115] = { id = "MAPSEC_ROUTE_15", theme = "wood" },
  [116] = { id = "MAPSEC_ROUTE_16", theme = "marble" },
  [117] = { id = "MAPSEC_ROUTE_17", theme = "marble" },
  [118] = { id = "MAPSEC_ROUTE_18", theme = "marble" },
  [119] = { id = "MAPSEC_ROUTE_19", theme = "marble" },
  [120] = { id = "MAPSEC_ROUTE_20", theme = "stone" },
  [121] = { id = "MAPSEC_ROUTE_21", theme = "marble" },
  [122] = { id = "MAPSEC_ROUTE_22", theme = "marble" },
  [123] = { id = "MAPSEC_ROUTE_23", theme = "marble" },
  [124] = { id = "MAPSEC_ROUTE_24", theme = "marble" },
  [125] = { id = "MAPSEC_ROUTE_25", theme = "marble" },
  [126] = { id = "MAPSEC_VIRIDIAN_FOREST", theme = "wood" },
  [127] = { id = "MAPSEC_MT_MOON", theme = "stone" },
  [128] = { id = "MAPSEC_S_S_ANNE", theme = "wood" },
  [129] = { id = "MAPSEC_UNDERGROUND_PATH", theme = "stone" },
  [130] = { id = "MAPSEC_UNDERGROUND_PATH_2", theme = "stone" },
  [131] = { id = "MAPSEC_DIGLETTS_CAVE", theme = "stone" },
  [132] = { id = "MAPSEC_KANTO_VICTORY_ROAD", theme = "stone" },
  [133] = { id = "MAPSEC_ROCKET_HIDEOUT", theme = "brick" },
  [134] = { id = "MAPSEC_SILPH_CO", theme = "brick" },
  [135] = { id = "MAPSEC_POKEMON_MANSION", theme = "brick" },
  [136] = { id = "MAPSEC_KANTO_SAFARI_ZONE", theme = "wood" },
  [137] = { id = "MAPSEC_POKEMON_LEAGUE", theme = "marble" },
  [138] = { id = "MAPSEC_ROCK_TUNNEL", theme = "stone" },
  [139] = { id = "MAPSEC_SEAFOAM_ISLANDS", theme = "stone" },
  [140] = { id = "MAPSEC_POKEMON_TOWER", theme = "brick" },
  [141] = { id = "MAPSEC_CERULEAN_CAVE", theme = "stone" },
  [142] = { id = "MAPSEC_POWER_PLANT", theme = "brick" },
  [143] = { id = "MAPSEC_ONE_ISLAND", theme = "marble" },
  [144] = { id = "MAPSEC_TWO_ISLAND", theme = "marble" },
  [145] = { id = "MAPSEC_THREE_ISLAND", theme = "marble" },
  [146] = { id = "MAPSEC_FOUR_ISLAND", theme = "marble" },
  [147] = { id = "MAPSEC_FIVE_ISLAND", theme = "marble" },
  [148] = { id = "MAPSEC_SEVEN_ISLAND", theme = "marble" },
  [149] = { id = "MAPSEC_SIX_ISLAND", theme = "marble" },
  [150] = { id = "MAPSEC_KINDLE_ROAD", theme = "stone" },
  [151] = { id = "MAPSEC_TREASURE_BEACH", theme = "marble" },
  [152] = { id = "MAPSEC_CAPE_BRINK", theme = "wood" },
  [153] = { id = "MAPSEC_BOND_BRIDGE", theme = "wood" },
  [154] = { id = "MAPSEC_THREE_ISLE_PORT", theme = "wood" },
  [155] = { id = "MAPSEC_SEVII_ISLE_6", theme = "marble" },
  [156] = { id = "MAPSEC_SEVII_ISLE_7", theme = "marble" },
  [157] = { id = "MAPSEC_SEVII_ISLE_8", theme = "marble" },
  [158] = { id = "MAPSEC_SEVII_ISLE_9", theme = "marble" },
  [159] = { id = "MAPSEC_RESORT_GORGEOUS", theme = "marble" },
  [160] = { id = "MAPSEC_WATER_LABYRINTH", theme = "marble" },
  [161] = { id = "MAPSEC_FIVE_ISLE_MEADOW", theme = "wood" },
  [162] = { id = "MAPSEC_MEMORIAL_PILLAR", theme = "stone" },
  [163] = { id = "MAPSEC_OUTCAST_ISLAND", theme = "marble" },
  [164] = { id = "MAPSEC_GREEN_PATH", theme = "wood" },
  [165] = { id = "MAPSEC_WATER_PATH", theme = "marble" },
  [166] = { id = "MAPSEC_RUIN_VALLEY", theme = "stone" },
  [167] = { id = "MAPSEC_TRAINER_TOWER", theme = "brick" },
  [168] = { id = "MAPSEC_CANYON_ENTRANCE", theme = "stone" },
  [169] = { id = "MAPSEC_SEVAULT_CANYON", theme = "stone" },
  [170] = { id = "MAPSEC_TANOBY_RUINS", theme = "stone" },
  [171] = { id = "MAPSEC_SEVII_ISLE_22", theme = "marble" },
  [172] = { id = "MAPSEC_SEVII_ISLE_23", theme = "marble" },
  [173] = { id = "MAPSEC_SEVII_ISLE_24", theme = "marble" },
  [174] = { id = "MAPSEC_NAVEL_ROCK", theme = "stone" },
  [175] = { id = "MAPSEC_MT_EMBER", theme = "stone" },
  [176] = { id = "MAPSEC_BERRY_FOREST", theme = "wood" },
  [177] = { id = "MAPSEC_ICEFALL_CAVE", theme = "stone" },
  [178] = { id = "MAPSEC_ROCKET_WAREHOUSE", theme = "brick" },
  [179] = { id = "MAPSEC_TRAINER_TOWER_2", theme = "brick" },
  [180] = { id = "MAPSEC_DOTTED_HOLE", theme = "stone" },
  [181] = { id = "MAPSEC_LOST_CAVE", theme = "stone" },
  [182] = { id = "MAPSEC_PATTERN_BUSH", theme = "wood" },
  [183] = { id = "MAPSEC_ALTERING_CAVE", theme = "stone" },
  [184] = { id = "MAPSEC_TANOBY_CHAMBERS", theme = "stone" },
  [185] = { id = "MAPSEC_THREE_ISLE_PATH", theme = "wood" },
  [186] = { id = "MAPSEC_TANOBY_KEY", theme = "stone" },
  [187] = { id = "MAPSEC_BIRTH_ISLAND", theme = "stone" },
  [188] = { id = "MAPSEC_MONEAN_CHAMBER", theme = "stone" },
  [189] = { id = "MAPSEC_LIPTOO_CHAMBER", theme = "stone" },
  [190] = { id = "MAPSEC_WEEPTH_CHAMBER", theme = "stone" },
  [191] = { id = "MAPSEC_DILFORD_CHAMBER", theme = "stone" },
  [192] = { id = "MAPSEC_SCUFIB_CHAMBER", theme = "stone" },
  [193] = { id = "MAPSEC_RIXY_CHAMBER", theme = "stone" },
  [194] = { id = "MAPSEC_VIAPOIS_CHAMBER", theme = "stone" },
  [195] = { id = "MAPSEC_EMBER_SPA", theme = "stone" },
  [196] = { id = "MAPSEC_SPECIAL_AREA", theme = "brick" },
}

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

-- Reverse index: symbolic MAPSEC_* name -> numeric mapsec.  Built once; only
-- `name` is ever overlaid from the ROM, so `id` stays a stable key.
MapSectionsExtract.ID_TO_SECTION = {}
for secId, info in pairs(MapSectionsExtract.SECTIONS) do
  MapSectionsExtract.ID_TO_SECTION[info.id] = secId
end

local _mapToSecCache = nil
local generatedLoaded = false

local function decode_name_from_rom(rom, off, maxLen)
  maxLen = maxLen or 32
  local chars = {}
  for i = 0, maxLen - 1 do
    local b = rom:get(off + i)
    if b == 0xFF then break end
    if TextIR.CHARMAP[b] then
      chars[#chars + 1] = TextIR.CHARMAP[b]
    elseif b >= 0xBB and b <= 0xD4 then
      chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
    elseif b >= 0xD5 and b <= 0xEE then
      chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
    end
  end
  return table.concat(chars)
end

--- Extract authentic place names directly from ROM's sMapNames pointer table.
function MapSectionsExtract.extractNamesFromRom(rom)
  if not rom or not rom.u32 then return end
  local base = Versions.MAPSEC_NAME_POINTERS
  local count = Versions.KANTO_MAPSEC_COUNT
  local start = Versions.KANTO_MAPSEC_START
  for i = 0, count - 1 do
    local secId = start + i
    local ptr = rom:u32(base + i * 4)
    local off = rom:ptrOffset(ptr)
    if off then
      local name = decode_name_from_rom(rom, off)
      if name and name ~= "" then
        if not MapSectionsExtract.SECTIONS[secId] then
          MapSectionsExtract.SECTIONS[secId] = {
            id = string.format("MAPSEC_%d", secId),
            theme = "marble",
          }
        end
        MapSectionsExtract.SECTIONS[secId].name = name
      end
    end
  end
end

--- Overlay ROM-derived section names onto SECTIONS, once.
function MapSectionsExtract.installNames(names)
  for secId, name in pairs(names) do
    assert(MapSectionsExtract.SECTIONS[secId], "no map section " .. tostring(secId)).name = name
  end
  generatedLoaded = true
end

function MapSectionsExtract.ensureGenerated()
  if generatedLoaded then return end
  local cache = require("src.core.game3.dataset").cache()
  MapSectionsExtract.installNames(assert(require("src.import.gba.map_preview_extract").loadNames(cache),
    "region_map/names.lua is not in the cache"))
end

local function normalize_map_name(mapId)
  if type(mapId) ~= "string" then return "" end
  local s = mapId:gsub("^FR_", ""):gsub("^SEVII_", "")
  s = s:gsub("(%l)(%u)", "%1_%2")
  s = s:gsub("(%a)(%d)", "%1_%2")
  s = s:gsub("(%d)(%a)", "%1_%2")
  s = s:gsub("-", "_"):upper()
  return s
end

local function map_tree_root()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  return root .. "/map_tree"
end

local function load_map_tree_cache()
  if _mapToSecCache then return _mapToSecCache end
  _mapToSecCache = {}

  local Json = nil
  pcall(function() Json = require("src.link.Json") end)
  if not Json then return _mapToSecCache end

  local treeRoot = map_tree_root()
  local okFs, CacheFs = pcall(require, "src.import.CacheFs")
  local rawCensus = nil
  if okFs and CacheFs and CacheFs.read then
    rawCensus = CacheFs.read("data/generated/gba/map_tree/census.json")
      or CacheFs.read("map_tree/census.json")
  end
  if not rawCensus and love and love.filesystem and love.filesystem.read then
    rawCensus = love.filesystem.read("data/generated/gba/map_tree/census.json")
  end
  if not rawCensus then
    local f = io.open(treeRoot .. "/census.json", "r")
      or io.open("data/generated/gba/map_tree/census.json", "r")
    if f then rawCensus = f:read("*a"); f:close() end
  end

  if rawCensus then
    local okC, census = pcall(Json.decode, rawCensus)
    if okC and census and census.groups then
      for _, g in ipairs(census.groups) do
        for _, m in ipairs(g.maps or {}) do
          local slot = m.slot
          local rawH = nil
          if okFs and CacheFs and CacheFs.read then
            rawH = CacheFs.read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
              or CacheFs.read("map_tree/maps/" .. slot .. "/header.json")
          end
          if not rawH and love and love.filesystem and love.filesystem.read then
            rawH = love.filesystem.read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
          end
          if not rawH then
            local fH = io.open(treeRoot .. "/maps/" .. slot .. "/header.json", "r")
              or io.open("data/generated/gba/map_tree/maps/" .. slot .. "/header.json", "r")
            if fH then rawH = fH:read("*a"); fH:close() end
          end
          if rawH then
            local okH, h = pcall(Json.decode, rawH)
            if okH and h and h.regionMapSectionId then
              local sid = h.regionMapSectionId
              _mapToSecCache[m.id] = sid
              _mapToSecCache[slot] = sid
              _mapToSecCache[m.id:upper()] = sid
              local norm = normalize_map_name(m.id)
              _mapToSecCache[norm] = sid
              _mapToSecCache["FR_" .. norm] = sid
            end
          end
        end
      end
    end
  end

  return _mapToSecCache
end

--- Get section info for mapsec ID, applying Celadon Dept Store override rule.
function MapSectionsExtract.getInfo(secId, mapId, floorNum)
  MapSectionsExtract.ensureGenerated()
  secId = tonumber(secId)

  if (not secId or secId < 88) and mapId then
    local cache = load_map_tree_cache()
    if cache and cache[mapId] then
      secId = cache[mapId]
    elseif cache and cache[mapId:upper()] then
      secId = cache[mapId:upper()]
    end
  end

  if (not secId or secId < 88) and mapId then
    local norm = normalize_map_name(mapId)
    if norm ~= "" then
      local cache = load_map_tree_cache()
      if cache and cache[norm] then
        secId = cache[norm]
      elseif cache and cache["FR_" .. norm] then
        secId = cache["FR_" .. norm]
      end
    end
    if not secId or secId < 88 then
      -- Match against SECTIONS.  pairs() order is arbitrary, so a plain
      -- substring test let "ROUTE_22" land on MAPSEC_ROUTE_2 (name "ROUTE 2").
      -- Pick the exact match, else the longest match, so the result is stable.
      local bestId, bestLen
      for id, info in pairs(MapSectionsExtract.SECTIONS) do
        local secKey = info.id:sub(8)
        if norm == secKey then
          bestId, bestLen = id, #secKey
          break
        end
        if (norm:find("^" .. secKey) or norm:find(secKey, 1, true))
          and (not bestLen or #secKey > bestLen) then
          bestId, bestLen = id, #secKey
        end
      end
      if bestId then secId = bestId end
    end
  end

  -- `resolved` tells callers whether the map was actually identified; the
  -- Pallet Town table below is the historical default for anything unknown.
  local found = secId and MapSectionsExtract.SECTIONS[secId]
  local info = found or MapSectionsExtract.SECTIONS[MapSectionsExtract.KANTO_MAPSEC_START]

  local name = info.name
  local theme = info.theme or "marble"

  -- pokefirered/src/region_map.c:3782 IsCeladonDeptStoreMapsec
  if mapId and type(mapId) == "string" then
    local upper = mapId:upper()
    if upper:find("CELADON") and (upper:find("DEPARTMENT") or upper:find("DEPT")) then
      name = MapSectionsExtract.SECTIONS[196].name
      theme = MapSectionsExtract.SECTIONS[196].theme
    end
  end

  local rawName = name

  -- Append floor suffix (pokefirered/src/map_name_popup.c:205)
  local floor = tonumber(floorNum) or 0
  if floor == 127 then
    name = name .. " ROOFTOP"
  elseif floor < 0 then
    name = string.format("%s B%dF", name, -floor)
  elseif floor > 0 then
    name = string.format("%s %dF", name, floor)
  end

  return {
    secId = secId or 88,
    id = info.id,
    name = name,
    rawName = rawName,
    theme = theme,
    floorNum = floor,
    resolved = found ~= nil,
  }
end

--- Resolve a clean place name (without floor suffix) for any mapId or secId.
function MapSectionsExtract.getPlaceName(mapId, secId)
  local info = MapSectionsExtract.getInfo(secId, mapId, 0)
  return info and info.rawName or (info and info.name)
end

--- Format Lua file content
function MapSectionsExtract.formatLua()
  local lines = {
    "-- Generated map section definitions and popup themes.",
    "-- Extracted directly from ROM sMapNames table.",
    "return {",
    "  KANTO_MAPSEC_START = " .. MapSectionsExtract.KANTO_MAPSEC_START .. ",",
    "  sections = {",
  }
  for secId = 88, 196 do
    local s = MapSectionsExtract.SECTIONS[secId]
    if s then
      lines[#lines + 1] = string.format(
        "    [%d] = { id = %q, name = %q, theme = %q },",
        secId, s.id, s.name, s.theme
      )
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- Extract from ROM and write to cache root
function MapSectionsExtract.run(rom, cache, opts)
  opts = opts or {}
  if rom then
    MapSectionsExtract.extractNamesFromRom(rom)
  end
  local root = opts.cacheRoot or "data/generated/gba"
  local content = MapSectionsExtract.formatLua()
  if cache and cache.write then
    cache:write(root .. "/region_map/map_sections.lua", content)
    cache:write(root .. "/map_sections.lua", content)
  else
    local okFs, CacheFs = pcall(require, "src.import.CacheFs")
    local wrote = false
    if okFs and CacheFs and CacheFs.write then
      local ok1 = pcall(CacheFs.write, root .. "/region_map/map_sections.lua", content)
      local ok2 = pcall(CacheFs.write, root .. "/map_sections.lua", content)
      if ok1 or ok2 then wrote = true end
    end
    if not wrote then
      local function write_file(path, str)
        local dir = path:match("^(.*)/[^/]+$")
        if dir then pcall(os.execute, "mkdir -p '" .. dir .. "'") end
        local f = io.open(path, "w")
        if f then f:write(str); f:close(); return true end
        return false
      end
      write_file(root .. "/region_map/map_sections.lua", content)
      write_file(root .. "/map_sections.lua", content)
    end
  end
  return true
end

return MapSectionsExtract
