-- Serialize MapTree census → CacheFS:
--   data/generated/gba/map_tree/census.json
--   data/generated/gba/map_tree/maps/{group}_{num}/header.json|events.json|grid.bin|border.bin
--   data/generated/gba/map_tree/tilesets/{ts_id}/meta.json|tiles.4bpp|palettes.bin|metatiles.bin|attributes.bin

local MapTree = require("src.import.gba.map_tree")
local Lz77 = require("src.import.gba.lz77")
local Json = require("src.link.Json")

local MapTreeExtract = {}

MapTreeExtract.ROOT = "data/generated/gba/map_tree"

local function bytes_to_string(bytes)
  if type(bytes) == "string" then return bytes end
  local n = bytes._len or #bytes
  local s = {}
  if bytes._ffi then
    for i = 1, n do
      s[i] = string.char(bytes._ffi[i - 1] or 0)
    end
  else
    for i = 1, n do
      s[i] = string.char(bytes[i] or 0)
    end
  end
  return table.concat(s)
end

local function rom_blob(rom, ptr, nbytes)
  local off = rom:ptrOffset(ptr)
  if not off or not nbytes or nbytes < 1 then return nil end
  local bytes = rom:readBytes(off, nbytes)
  local s = {}
  for i = 1, #bytes do
    s[i] = string.char(bytes[i])
  end
  return table.concat(s)
end

local function write_json(cache, rel, obj)
  cache:write(rel, Json.encode(obj) .. "\n")
end

local function simplify_events(ev)
  if not ev then
    return { objects = {}, warps = {}, bgEvents = {}, coordEvents = {} }
  end
  local function slim_obj(o)
    return {
      localId = o.localId,
      graphicsId = o.graphicsId,
      x = o.x,
      y = o.y,
      elevation = o.elevation,
      movementType = o.movementType,
      movement = o.movement,
      range = o.range,
      scriptKey = o.scriptKey,
      flag = o.flag,
    }
  end
  local objects = {}
  for _, o in ipairs(ev.objects or {}) do
    objects[#objects + 1] = slim_obj(o)
  end
  local warps = {}
  for _, w in ipairs(ev.warps or {}) do
    warps[#warps + 1] = {
      x = w.x,
      y = w.y,
      destMap = w.destMap,
      destWarp = w.destWarp,
      mapGroup = w.mapGroup,
      mapNum = w.mapNum,
    }
  end
  local bgs = {}
  for _, b in ipairs(ev.bgEvents or {}) do
    bgs[#bgs + 1] = {
      x = b.x,
      y = b.y,
      elevation = b.elevation,
      kind = b.kind,
      scriptKey = b.scriptKey,
    }
  end
  local coords = {}
  for _, c in ipairs(ev.coordEvents or {}) do
    coords[#coords + 1] = {
      x = c.x,
      y = c.y,
      elevation = c.elevation,
      trigger = c.trigger,
      index = c.index,
      scriptKey = c.scriptKey,
    }
  end
  return {
    objects = objects,
    warps = warps,
    bgEvents = bgs,
    coordEvents = coords,
  }
end

local function pack_tileset(rom, cache, root, ts)
  local dir = root .. "/tilesets/" .. ts.id
  local tilesOff = rom:ptrOffset(ts.tilesPtr)
  local tilesBlob
  if ts.compressed and tilesOff then
    local raw = Lz77.decompress(function(i) return rom:get(i) end, tilesOff)
    tilesBlob = bytes_to_string(raw)
  else
    -- Uncompressed tiles: unknown length; skip raw dump (meta still written).
    tilesBlob = nil
  end
  local pals = rom_blob(rom, ts.palettesPtr, ts.palette_count * 32)
  local mts = rom_blob(rom, ts.metatilesPtr, ts.metatile_bytes)
  local attrs = rom_blob(rom, ts.attributesPtr, ts.attr_bytes)

  write_json(cache, dir .. "/meta.json", {
    id = ts.id,
    ptr = ts.ptr,
    compressed = ts.compressed,
    secondary = ts.secondary,
    mid_count = ts.mid_count,
    metatile_bytes = ts.metatile_bytes,
    attr_bytes = ts.attr_bytes,
    palette_count = ts.palette_count,
    tiles_bytes = tilesBlob and #tilesBlob or 0,
  })
  if tilesBlob then cache:write(dir .. "/tiles.4bpp", tilesBlob) end
  if pals then cache:write(dir .. "/palettes.bin", pals) end
  if mts then cache:write(dir .. "/metatiles.bin", mts) end
  if attrs then cache:write(dir .. "/attributes.bin", attrs) end
  return dir
end

local function pack_map(rom, cache, root, entry)
  local dir = root .. "/maps/" .. entry.slot
  local h = entry.header
  local L = entry.layout
  write_json(cache, dir .. "/header.json", {
    id = entry.id,
    pretName = entry.pretName,
    group = entry.group,
    num = entry.num,
    groupName = entry.groupName,
    width = L.width,
    height = L.height,
    music = h.music,
    weather = h.weather,
    mapType = h.mapType,
    cave = h.cave,
    regionMapSectionId = h.regionMapSectionId,
    bikingAllowed = h.bikingAllowed,
    allowEscaping = h.allowEscaping,
    allowRunning = h.allowRunning,
    showMapName = h.showMapName,
    floorNum = h.floorNum,
    battleType = h.battleType,
    layoutId = h.layoutId,
    primaryTileset = entry.primaryTileset,
    secondaryTileset = entry.secondaryTileset,
    borderWidth = L.borderWidth,
    borderHeight = L.borderHeight,
    connections = entry.connections,
    headerOff = h.headerOff,
    layoutOff = L.layoutOff,
  })
  write_json(cache, dir .. "/events.json", simplify_events(entry.events))
  local grid = MapTree.readGridBytes(rom, L)
  if grid then cache:write(dir .. "/grid.bin", grid) end
  local border = MapTree.readBorderBytes(rom, L)
  if border then cache:write(dir .. "/border.bin", border) end
  return dir
end

--- Full procedural extract.
-- @return ok, detail
function MapTreeExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.root or MapTreeExtract.ROOT
  local census, err = MapTree.walk(rom, opts.version, opts)
  if not census then return false, err end

  local tilesetIds = {}
  for ptr, ts in pairs(census.tilesets) do
    pack_tileset(rom, cache, root, ts)
    tilesetIds[#tilesetIds + 1] = ts.id
  end
  table.sort(tilesetIds)

  local mapIndex = {}
  for _, entry in ipairs(census.maps) do
    if opts.progress then
      opts.progress("map_tree", #mapIndex, census.map_count)
    end
    pack_map(rom, cache, root, entry)
    mapIndex[#mapIndex + 1] = {
      slot = entry.slot,
      id = entry.id,
      group = entry.group,
      num = entry.num,
      width = entry.layout.width,
      height = entry.layout.height,
      primaryTileset = entry.primaryTileset,
      secondaryTileset = entry.secondaryTileset,
    }
  end

  write_json(cache, root .. "/census.json", {
    version = "map_tree_v1",
    g_map_groups = census.g_map_groups,
    map_count = census.map_count,
    tileset_count = census.tileset_count,
    tilesets = tilesetIds,
    groups = census.groups,
    maps = mapIndex,
  })

  return true, {
    root = root,
    map_count = census.map_count,
    tileset_count = census.tileset_count,
  }
end

return MapTreeExtract
