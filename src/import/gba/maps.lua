-- Load Island 1 FRLG map grids (metatile id + collision) from ROM.

local Maps = {}

--- Parse map.bin: u16 per cell = metatileId | (collision << 10) | (elevation << 12)
function Maps.loadGrid(rom, layoutSpec)
  local w, h = layoutSpec.width, layoutSpec.height
  local n = w * h
  local cells = {}
  local offset = layoutSpec.offset
  for i = 0, n - 1 do
    local v = rom:u16(offset + i * 2)
    local mid = v % 1024
    local coll = math.floor(v / 1024) % 4
    local elev = math.floor(v / 4096) % 16
    cells[i + 1] = { mid = mid, coll = coll, elev = elev }
  end
  return { width = w, height = h, cells = cells }
end

function Maps.loadIsland1(rom, version)
  local Versions = require("src.import.gba.versions")
  local out = {}
  for mapId, spec in pairs(Versions.MAPS) do
    local layoutName = spec.layout
    local layoutSpec = version.layouts[layoutName]
    if layoutSpec then
      local grid = Maps.loadGrid(rom, layoutSpec)
      grid.map_id = mapId
      grid.kind = spec.kind
      grid.pair = spec.pair
      grid.environment = spec.environment
      out[mapId] = grid
    end
  end
  return out
end

--- Read FRLG MapLayout border block (pret map.json border).
-- @return { width, height, mids } or 1×1 mid-0 fallback
function Maps.loadBorder(rom, version, mapId)
  local Versions = require("src.import.gba.versions")
  local ExtractMapEvents = require("src.import.gba.extract_map_events")
  local headers = (version and version.map_headers) or Versions.MAP_HEADERS
  local headerOff = headers and headers[mapId]
  if not headerOff then
    return { width = 1, height = 1, mids = { 0 } }
  end
  local hdr = ExtractMapEvents.parseHeader(rom, headerOff)
  local layoutOff = Versions.gbaToFile(hdr and hdr.layout)
  if not layoutOff then
    return { width = 1, height = 1, mids = { 0 } }
  end
  -- MapLayout: +8 border ptr, +24 borderWidth, +25 borderHeight
  local borderPtr = rom:u32(layoutOff + 8)
  local bw = rom:get(layoutOff + 24) or 0
  local bh = rom:get(layoutOff + 25) or 0
  local borderOff = Versions.gbaToFile(borderPtr)
  if not borderOff or bw < 1 or bh < 1 or bw > 16 or bh > 16 then
    return { width = 1, height = 1, mids = { 0 } }
  end
  local mids = {}
  for i = 0, bw * bh - 1 do
    local v = rom:u16(borderOff + i * 2)
    mids[i + 1] = v % 1024
  end
  return { width = bw, height = bh, mids = mids }
end

function Maps.loadBordersIsland1(rom, version)
  local Versions = require("src.import.gba.versions")
  local out = {}
  for mapId in pairs(Versions.MAPS) do
    out[mapId] = Maps.loadBorder(rom, version, mapId)
  end
  return out
end

return Maps
