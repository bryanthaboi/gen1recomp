-- FRLG tileset load: LZ tiles (4bpp), uncompressed palettes (BGR555), metatiles, attrs.

local Lz77 = require("src.import.gba.lz77")

local Tileset = {}

Tileset.NUM_PRIMARY_TILES = 640
Tileset.NUM_PRIMARY_METATILES = 640
-- pret fieldmap.h — LoadPrimaryTilesetPalette / LoadSecondaryTilesetPalette
Tileset.NUM_PALS_IN_PRIMARY = 7  -- BG slots 0..6
Tileset.NUM_PALS_TOTAL = 13      -- BG slots 0..12

local function bytes_to_array(str)
  local t = {}
  for i = 1, #str do t[i] = str:byte(i) end
  return t
end

--- Decode one BGR555 colour → r,g,b in 0..31 (5-bit) and 0..255.
function Tileset.bgr555(c)
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return r5, g5, b5, r5 * 255 / 31, g5 * 255 / 31, b5 * 255 / 31
end

function Tileset.loadPalettes(rom, offset, count)
  count = count or 16
  local pals = {}
  for p = 0, count - 1 do
    local colors = {}
    local base = offset + p * 32
    for i = 0, 15 do
      colors[i] = rom:u16(base + i * 2) -- 0-based index for GBA
    end
    pals[p] = colors
  end
  return pals
end

--- Merge map BG palettes the way FRLG LoadMapTilesetPalettes does.
-- Primary: slots 0..6 from primaryPals[0..6] (color 0 forced black).
-- Secondary: slots 7..12 from secondaryPals[7..12] (full array in ROM;
-- LoadSecondaryTilesetPalette starts at palettes[NUM_PALS_IN_PRIMARY]).
function Tileset.mergeMapPalettes(primaryPals, secondaryPals)
  local map = {}
  local nPri = Tileset.NUM_PALS_IN_PRIMARY
  local nTot = Tileset.NUM_PALS_TOTAL
  for i = 0, nPri - 1 do
    local src = primaryPals[i] or primaryPals[0]
    local copy = {}
    for c = 0, 15 do copy[c] = src and src[c] or 0 end
    copy[0] = 0 -- LoadTilesetPalette forces slot0 colour0 to black
    map[i] = copy
  end
  for i = nPri, nTot - 1 do
    local src = secondaryPals[i] or secondaryPals[nPri] or primaryPals[0]
    local copy = {}
    for c = 0, 15 do copy[c] = src and src[c] or 0 end
    map[i] = copy
  end
  -- Unused high slots: keep defined so a bad palSlot never nil-indexes.
  for i = nTot, 15 do
    map[i] = map[0]
  end
  return map
end

--- Decompress 4bpp tiles → array of tileCount entries, each 64 nybbles (8×8).
function Tileset.loadTiles4bpp(rom, lzOffset)
  local raw, _consumed = Lz77.decompress(function(i) return rom:get(i) end, lzOffset)
  local nbytes = type(raw) == "table" and (raw._len or #raw) or #raw
  local tileCount = math.floor(nbytes / 32)
  local tiles = { count = tileCount, raw = raw }
  return tiles
end

--- Uncompressed 4bpp tile sheet (isCompressed=0 tilesets, e.g. cable club).
function Tileset.loadTiles4bppRaw(rom, offset, nbytes)
  nbytes = tonumber(nbytes) or 0
  if nbytes < 32 then return { count = 0, raw = {} } end
  local raw = rom:readBytes(offset, nbytes)
  return { count = math.floor(nbytes / 32), raw = raw }
end

--- Read 4bpp pixel index at (x,y) within tile `tid` (0-based tile id in this sheet).
function Tileset.tileIndex(tiles, tid, x, y)
  local raw = tiles.raw
  local tileOff = tid * 32 -- bytes
  -- GBA 4bpp: each row is 4 bytes (8 pixels); low nybble first
  local row = y
  local byteIndex = tileOff + row * 4 + math.floor(x / 2) -- 0-based in raw
  local b
  if raw._ffi then
    b = raw._ffi[byteIndex]
  else
    b = raw[byteIndex + 1]
  end
  if x % 2 == 0 then
    return b % 16
  end
  return math.floor(b / 16) % 16
end

function Tileset.loadMetatiles(rom, offset, nbytes)
  local data = rom:readBytes(offset, nbytes)
  local count = math.floor(nbytes / 16)
  return { data = data, count = count }
end

function Tileset.loadAttributes(rom, offset, nbytes)
  local data = rom:readBytes(offset, nbytes)
  local count = math.floor(nbytes / 4)
  return { data = data, count = count }
end

--- Behavior (low 9 bits of attr word0) and collision (bits from FRLG).
-- FRLG metatile attribute: u32 — behavior in low bits (see pret).
function Tileset.attrOf(attrs, mid, primaryCount)
  primaryCount = primaryCount or Tileset.NUM_PRIMARY_METATILES
  local idx = mid
  if mid >= primaryCount then
    idx = mid - primaryCount
  end
  if idx < 0 or idx >= attrs.count then
    return 0, 0
  end
  local off = idx * 4 -- 1-based data
  local d = attrs.data
  local w = d[off + 1] + d[off + 2] * 256 + d[off + 3] * 65536 + d[off + 4] * 16777216
  local behavior = w % 512 -- 0x1FF
  -- Collision in map cells is separate; metatile attr also encodes layer type etc.
  -- Use bit 0x200 area: pret stores collision in map grid, behavior here.
  return behavior, w
end

--- 8 tile entries (u16) for metatile mid across primary+secondary blobs.
function Tileset.metatileEntries(primaryMt, secondaryMt, mid)
  local data, localMid
  if mid < Tileset.NUM_PRIMARY_METATILES then
    data, localMid = primaryMt.data, mid
  else
    data = secondaryMt.data
    localMid = mid - Tileset.NUM_PRIMARY_METATILES
  end
  local off = localMid * 16 -- 1-based: 16 bytes = 8 u16
  if off + 16 > #data then return nil end
  local entries = {}
  for i = 0, 7 do
    local b = off + i * 2
    entries[i + 1] = data[b + 1] + data[b + 2] * 256
  end
  return entries
end

function Tileset.loadOne(rom, spec)
  if not spec then return nil, "missing tileset spec" end
  local tiles
  if spec.compressed == false then
    local nbytes = spec.tiles_bytes
    if not nbytes and spec.palettes and spec.tiles and spec.palettes > spec.tiles then
      nbytes = spec.palettes - spec.tiles
    end
    tiles = Tileset.loadTiles4bppRaw(rom, spec.tiles, nbytes or 0)
  else
    tiles = Tileset.loadTiles4bpp(rom, spec.tiles)
  end
  local pals = Tileset.loadPalettes(rom, spec.palettes, spec.palette_count or 16)
  local mt = Tileset.loadMetatiles(rom, spec.metatiles, spec.metatile_bytes)
  local attr = Tileset.loadAttributes(rom, spec.attributes, spec.attr_bytes)
  return {
    tiles = tiles,
    pals = pals,
    mt = mt,
    attr = attr,
    secondary = spec.secondary == true,
  }
end

--- Load a primary+secondary pair by name from Versions.TILESETS / TILESET_PAIRS.
function Tileset.loadPair(rom, version, pairName)
  pairName = pairName or "sevii_outdoor"
  local Versions = require("src.import.gba.versions")
  local pair = (version.tileset_pairs or Versions.TILESET_PAIRS)[pairName]
  local catalog = version.tilesets or Versions.TILESETS
  if not pair then return nil, "unknown tileset pair " .. tostring(pairName) end
  local primary = Tileset.loadOne(rom, catalog[pair.primary])
  local secondary = Tileset.loadOne(rom, catalog[pair.secondary])
  if not primary or not secondary then
    return nil, "failed loading tileset pair " .. pairName
  end
  local mapPals = Tileset.mergeMapPalettes(primary.pals, secondary.pals)
  return {
    pairName = pairName,
    primaryTiles = primary.tiles,
    secondaryTiles = secondary.tiles,
    mapPals = mapPals,
    primaryMt = primary.mt,
    secondaryMt = secondary.mt,
    primaryAttr = primary.attr,
    secondaryAttr = secondary.attr,
  }
end

--- Back-compat: outdoor Sevii pair.
function Tileset.loadOutdoorPair(rom, version)
  return Tileset.loadPair(rom, version, "sevii_outdoor")
end

function Tileset.behaviorOf(bundle, mid)
  if mid < Tileset.NUM_PRIMARY_METATILES then
    return Tileset.attrOf(bundle.primaryAttr, mid)
  end
  return Tileset.attrOf(bundle.secondaryAttr, mid, Tileset.NUM_PRIMARY_METATILES)
end

return Tileset
