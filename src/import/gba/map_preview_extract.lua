-- Bake FRLG location preview screens and region-map text from ROM.
-- Source: pret/pokefirered src/map_preview_screen.c (sMapPreviewScreenData) and
-- src/region_map.c (sMapsecName_*, sDungeonInfo).
--
-- Output:
--   <root>/map_preview/manifest.lua      entry table + mapsec → artwork map
--   <root>/map_preview/<mapsec>.rgba     240x160 RGBA artwork (deduplicated)
--   <root>/region_map/names.lua          mapsec 88..196 display names
--   <root>/region_map/dungeon_info.lua   sDungeonInfo name + flavour text

local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")
local RegionMapTables = require("src.import.gba.region_map_tables")

local MapPreviewExtract = {}

MapPreviewExtract.CACHE_SUB = "map_preview"
MapPreviewExtract.REGION_MAP_SUB = "region_map"
MapPreviewExtract.FORMAT_VERSION = 2
MapPreviewExtract.WIDTH = 240
MapPreviewExtract.HEIGHT = 160

-- sMapPreviewScreenData palettes are 0x40 bytes = 32 BGR555 colours, loaded at
-- BG palette bank 13 (map_preview_screen.c: MapPreview_LoadGfx). Across the
-- visible tilemap columns 0-29 the 28 entries reference only banks 13 and 14;
-- the sole bank-0 references sit in the off-screen padding columns 30-31, so
-- bank 0 never reaches the screen (it is still mapped to bank 13's ramp so the
-- baked image is total).
MapPreviewExtract.PALETTE_COLORS = 32
MapPreviewExtract.PALETTE_BANK_LO = 13
MapPreviewExtract.PALETTE_BANK_HI = 14
MapPreviewExtract.PALETTE_BANKS = 2

MapPreviewExtract.TYPE_CAVE = 0
MapPreviewExtract.TYPE_FOREST = 1

local TILEMAP_WIDTH = 32
local TILEMAP_HEIGHT = 20
local TILEMAP_BYTES = TILEMAP_WIDTH * TILEMAP_HEIGHT * 2 -- CopyToBgTilemapBufferRect(2, tilemap, 0, 0, 32, 20)

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function luaStr(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub('"', '\\"')
  return '"' .. s .. '"'
end

local function readBgr555(get, offset, count)
  local out = {}
  for i = 1, count * 2 do
    out[i] = get(offset + i - 1)
  end
  return out
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

--- Decode every preview artwork plus the region-map text tables.
-- Returns a plan table, or nil + error message. Performs no cache writes.
function MapPreviewExtract.build(rom)
  local tables, err = RegionMapTables.load(rom)
  if not tables then
    return nil, err or RegionMapTables.NOT_FOUND
  end

  local get = function(i) return rom:get(i) end

  local entries = {}
  local byMapsec = {}
  local files = {}
  local canonicalByKey = {}
  local artworkCount = 0
  local nameWindow = nil

  for i, e in ipairs(tables.previews) do
    local key = ("%d:%d:%d"):format(e.tilesOffset, e.tilemapOffset, e.paletteOffset)
    local artworkSec = canonicalByKey[key]
    if not artworkSec then
      artworkSec = e.mapsec
      canonicalByKey[key] = artworkSec
      artworkCount = artworkCount + 1

      local gfx = Lz77.decompress(get, e.tilesOffset)
      local map = Lz77.decompress(get, e.tilemapOffset)
      if #gfx == 0 or #gfx % 32 ~= 0 then
        return nil, ("map preview 0x%X: bad tile data (%d bytes)"):format(e.mapsec, #gfx)
      end
      if #map ~= TILEMAP_BYTES then
        return nil, ("map preview 0x%X: bad tilemap (%d bytes, expected %d)")
          :format(e.mapsec, #map, TILEMAP_BYTES)
      end

      local ramp = BgBake.loadPalBanks(
        readBgr555(get, e.paletteOffset, MapPreviewExtract.PALETTE_COLORS),
        MapPreviewExtract.PALETTE_BANKS)
      local palBanks = {
        [0] = ramp[0],
        [MapPreviewExtract.PALETTE_BANK_LO] = ramp[0],
        [MapPreviewExtract.PALETTE_BANK_HI] = ramp[1],
      }
      files[artworkSec .. ".rgba"] =
        BgBake.bakeBgRgba(gfx, palBanks, map, MapPreviewExtract.WIDTH, MapPreviewExtract.HEIGHT)

      -- MapPreview_CreateMapNameWindow fills the window with PIXEL_FILL(1) and
      -- prints with sTextColor_White[] = {TEXT_COLOR_WHITE(1), TEXT_COLOR_RED(4),
      -- TEXT_COLOR_LIGHT_GRAY(3)} = {fg, shadow, bg}. Bank 14 entries 1/3/4 are a
      -- reserved UI ramp shared by every artwork, so record it once.
      if not nameWindow then
        nameWindow = {
          fill = { BgBake.bgr555ToRgb8(ramp[1][1]) },
          fg = { BgBake.bgr555ToRgb8(ramp[1][1]) },
          shadow = { BgBake.bgr555ToRgb8(ramp[1][4]) },
          bg = { BgBake.bgr555ToRgb8(ramp[1][3]) },
        }
      end
    end

    entries[i] = {
      mapsec = e.mapsec,
      name = tables.names[e.mapsec] or "",
      type = e.type,
      flagId = e.flagId,
      artwork = artworkSec,
    }
    byMapsec[e.mapsec] = i
  end

  return {
    entries = entries,
    byMapsec = byMapsec,
    files = files,
    artworkCount = artworkCount,
    nameWindow = nameWindow,
    names = tables.names,
    nameCount = countKeys(tables.names),
    namesVerified = tables.namesVerified,
    dungeonInfo = tables.dungeonInfo,
  }
end

local function formatRgb(c)
  return ("{ %d, %d, %d }"):format(c[1] or 0, c[2] or 0, c[3] or 0)
end

local function formatManifest(plan)
  local nw = plan.nameWindow or {}
  local lines = {
    "-- Generated location preview screen data (sMapPreviewScreenData).",
    "-- Sourced from pret/pokefirered src/map_preview_screen.c.",
    "return {",
    "  format_version = " .. MapPreviewExtract.FORMAT_VERSION .. ",",
    "  width = " .. MapPreviewExtract.WIDTH .. ",",
    "  height = " .. MapPreviewExtract.HEIGHT .. ",",
    "  type_cave = " .. MapPreviewExtract.TYPE_CAVE .. ",",
    "  type_forest = " .. MapPreviewExtract.TYPE_FOREST .. ",",
    "  artwork_count = " .. plan.artworkCount .. ",",
    "  entry_count = " .. #plan.entries .. ",",
    "  -- Palette bank 14 indices used by MapPreview_CreateMapNameWindow: the",
    "  -- window fill (PIXEL_FILL(1)) and the sTextColor_White fg/shadow/bg roles.",
    "  name_window = {",
    "    fill = " .. formatRgb(nw.fill or {}) .. ",",
    "    fg = " .. formatRgb(nw.fg or {}) .. ",",
    "    shadow = " .. formatRgb(nw.shadow or {}) .. ",",
    "    bg = " .. formatRgb(nw.bg or {}) .. ",",
    "  },",
    "  entries = {",
  }
  for i, e in ipairs(plan.entries) do
    lines[#lines + 1] = ("    { mapsec = %d, name = %s, type = %d, flagId = %d, artwork = %d },")
      :format(e.mapsec, luaStr(e.name), e.type, e.flagId, e.artwork)
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  by_mapsec = {"
  local secs = {}
  for sec in pairs(plan.byMapsec) do secs[#secs + 1] = sec end
  table.sort(secs)
  for _, sec in ipairs(secs) do
    lines[#lines + 1] = ("    [%d] = %d,"):format(sec, plan.byMapsec[sec])
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function formatNames(plan)
  local lines = {
    "-- Generated region map section names (sMapsecName_*).",
    "-- Sourced from pret/pokefirered src/region_map.c.",
    "return {",
    "  first = 88,",
    "  last = 196,",
    "  names = {",
  }
  local secs = {}
  for sec in pairs(plan.names) do secs[#secs + 1] = sec end
  table.sort(secs)
  for _, sec in ipairs(secs) do
    lines[#lines + 1] = ("    [%d] = %s,"):format(sec, luaStr(plan.names[sec]))
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function formatDungeonInfo(plan)
  local lines = {
    "-- Generated dungeon map GUIDE text (sDungeonInfo).",
    "-- Sourced from pret/pokefirered src/region_map.c. Missing mapsecs show",
    '-- "No data" in-game, matching GetDungeonName/GetDungeonFlavorText.',
    "return {",
  }
  for _, e in ipairs(plan.dungeonInfo) do
    lines[#lines + 1] = ("  [%d] = { name = %s, desc = %s },")
      :format(e.mapsec, luaStr(e.name), luaStr(e.desc))
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

MapPreviewExtract.formatManifest = formatManifest
MapPreviewExtract.formatNames = formatNames
MapPreviewExtract.formatDungeonInfo = formatDungeonInfo

--- Read a generated Lua cache file. Returns nil when absent or invalid.
local function readLua(cache, rel)
  local src = cache and cache.read and cache:read(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  if not ok then return nil end
  return data
end

MapPreviewExtract.loadManifest = function(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  return readLua(cache, root .. "/" .. MapPreviewExtract.CACHE_SUB .. "/manifest.lua")
end

MapPreviewExtract.loadNames = function(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  local data = readLua(cache, root .. "/" .. MapPreviewExtract.REGION_MAP_SUB .. "/names.lua")
  return data and data.names or nil
end

MapPreviewExtract.loadDungeonInfo = function(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  return readLua(cache, root .. "/" .. MapPreviewExtract.REGION_MAP_SUB .. "/dungeon_info.lua")
end

function MapPreviewExtract.ready(cache, cacheRoot)
  if not (cache and cache.exists) then return false end
  local root = cacheRoot or default_cache_root()
  if not cache:exists(root .. "/" .. MapPreviewExtract.CACHE_SUB .. "/manifest.lua") then
    return false
  end
  if not cache:exists(root .. "/" .. MapPreviewExtract.REGION_MAP_SUB .. "/names.lua") then
    return false
  end
  if not cache:exists(root .. "/" .. MapPreviewExtract.REGION_MAP_SUB .. "/dungeon_info.lua") then
    return false
  end
  local manifest = MapPreviewExtract.loadManifest(cache, root)
  local first = manifest and manifest.entries and manifest.entries[1]
  if not first then return false end
  return cache:exists(root .. "/" .. MapPreviewExtract.CACHE_SUB .. "/" .. first.artwork .. ".rgba")
    and true or false
end

function MapPreviewExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local previewRoot = cacheRoot .. "/" .. MapPreviewExtract.CACHE_SUB
  local textRoot = cacheRoot .. "/" .. MapPreviewExtract.REGION_MAP_SUB

  if not opts.force and MapPreviewExtract.ready(cache, cacheRoot) then
    return true, { skipped = true }
  end

  local plan, err = MapPreviewExtract.build(rom)
  if not plan then
    return false, err
  end

  cache:write(previewRoot .. "/manifest.lua", formatManifest(plan))
  local written = 0
  for name, bytes in pairs(plan.files) do
    cache:write(previewRoot .. "/" .. name, bytes)
    written = written + 1
  end
  cache:write(textRoot .. "/names.lua", formatNames(plan))
  cache:write(textRoot .. "/dungeon_info.lua", formatDungeonInfo(plan))

  print(("[map_preview_extract] %d preview artworks (%d entries) + %d mapsec names " ..
    "+ %d dungeon entries -> %s"):format(
    written, #plan.entries, plan.nameCount, #plan.dungeonInfo, previewRoot))

  return true, {
    artworks = written,
    entries = #plan.entries,
    names = plan.nameCount,
    dungeonInfo = #plan.dungeonInfo,
    namesVerified = plan.namesVerified,
  }
end

return MapPreviewExtract
