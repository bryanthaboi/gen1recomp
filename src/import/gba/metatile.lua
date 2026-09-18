-- Dual-layer FRLG metatile composite (indexed + BGR555).
-- pret DrawMetatile (field_camera.c): bottom entries 0–3, top 4–7.
-- Layer type (attr bits 29–30) picks which BG gets each half:
--   NORMAL  → bottom BG1 (under sprites), top BG2 (covers sprites)
--   COVERED → bottom BG3, top BG1 (both under sprites)
--   SPLIT   → bottom BG3, top BG2 (covers sprites)

local Tileset = require("src.import.gba.tileset")

local Metatile = {}

Metatile.LAYER_NORMAL = 0
Metatile.LAYER_COVERED = 1
Metatile.LAYER_SPLIT = 2

local function flip_coords(x, y, hflip, vflip)
  if hflip then x = 7 - x end
  if vflip then y = 7 - y end
  return x, y
end

--- pret METATILE_ATTRIBUTE_LAYER_TYPE (bits 29–30 of metatile attr u32).
function Metatile.layerType(bundle, mid)
  local attrs
  if mid < Tileset.NUM_PRIMARY_METATILES then
    attrs = bundle.primaryAttr
  else
    attrs = bundle.secondaryAttr
  end
  if not attrs then return Metatile.LAYER_NORMAL end
  local _, w = Tileset.attrOf(attrs, mid,
    mid < Tileset.NUM_PRIMARY_METATILES and nil or Tileset.NUM_PRIMARY_METATILES)
  return math.floor((tonumber(w) or 0) / 0x20000000) % 4
end

--- Blit one metatile half (layer 0=bottom, 1=top) into idxBuf.
-- Top: colorIndex 0 leaves dest unchanged. Bottom: colorIndex 0 writes 0.
local function blit_layer(bundle, entries, layer, idxBuf)
  local isTop = layer == 1
  for slot = 0, 3 do
    local e = entries[layer * 4 + slot + 1]
    local tid = e % 1024
    local hflip = math.floor(e / 1024) % 2 == 1
    local vflip = math.floor(e / 2048) % 2 == 1
    local palSlot = math.floor(e / 4096) % 16
    local tiles
    local localTid = tid
    if tid < Tileset.NUM_PRIMARY_TILES then
      tiles = bundle.primaryTiles
    else
      tiles = bundle.secondaryTiles
      localTid = tid - Tileset.NUM_PRIMARY_TILES
    end
    if localTid >= 0 and localTid < (tiles.count or 0) then
      local ox = (slot % 2) * 8
      local oy = math.floor(slot / 2) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local sx, sy = flip_coords(x, y, hflip, vflip)
          local colorIndex = Tileset.tileIndex(tiles, localTid, sx, sy)
          local di = (oy + y) * 16 + (ox + x) + 1
          if isTop then
            if colorIndex ~= 0 then
              idxBuf[di] = (palSlot % 16) * 16 + (colorIndex % 16)
            end
          elseif colorIndex == 0 then
            idxBuf[di] = 0
          else
            idxBuf[di] = (palSlot % 16) * 16 + (colorIndex % 16)
          end
        end
      end
    end
  end
end

local function empty_idx()
  local idxBuf = {}
  for i = 1, 256 do idxBuf[i] = 0 end
  return idxBuf
end

--- Bottom half only (entries 0–3).
function Metatile.compositeIndexedBottom(bundle, mid)
  local entries = Tileset.metatileEntries(bundle.primaryMt, bundle.secondaryMt, mid)
  local idxBuf = empty_idx()
  if not entries then return idxBuf end
  blit_layer(bundle, entries, 0, idxBuf)
  return idxBuf
end

--- Top half only (entries 4–7). Transparent (0) where colorIndex 0.
function Metatile.compositeIndexedTop(bundle, mid)
  local entries = Tileset.metatileEntries(bundle.primaryMt, bundle.secondaryMt, mid)
  local idxBuf = empty_idx()
  if not entries then return idxBuf end
  blit_layer(bundle, entries, 1, idxBuf)
  return idxBuf
end

--- Pixels drawn under object sprites (BG3 + BG1).
-- COVERED: bottom+top. NORMAL/SPLIT: bottom only.
function Metatile.compositeIndexedUnder(bundle, mid)
  local idxBuf = Metatile.compositeIndexedBottom(bundle, mid)
  if Metatile.layerType(bundle, mid) == Metatile.LAYER_COVERED then
    local top = Metatile.compositeIndexedTop(bundle, mid)
    for i = 1, 256 do
      local t = top[i]
      if t and t ~= 0 then idxBuf[i] = t end
    end
  end
  return idxBuf
end

--- Pixels drawn over object sprites (BG2). NORMAL/SPLIT top; COVERED empty.
function Metatile.compositeIndexedOver(bundle, mid)
  local lt = Metatile.layerType(bundle, mid)
  if lt == Metatile.LAYER_COVERED then
    return empty_idx()
  end
  return Metatile.compositeIndexedTop(bundle, mid)
end

--- Flat composite (bottom then top). Used by demake/quantize paths.
function Metatile.compositeIndexed(bundle, mid)
  local entries = Tileset.metatileEntries(bundle.primaryMt, bundle.secondaryMt, mid)
  local idxBuf = empty_idx()
  if not entries then return idxBuf end
  blit_layer(bundle, entries, 0, idxBuf)
  blit_layer(bundle, entries, 1, idxBuf)
  return idxBuf
end

--- Composite mid → 256 BGR555 colours (0..0x7FFF); index 0 top = keep bottom.
-- Also returns palBuf[i] = FRLG map palette slot that last wrote that pixel.
-- Implemented via compositeIndexed so quantize and native share one composite.
function Metatile.compositeBgr555(bundle, mid)
  local idxBuf = Metatile.compositeIndexed(bundle, mid)
  local buf, palBuf = {}, {}
  local mapPals = bundle.mapPals or {}
  for i = 1, 256 do
    local byte = idxBuf[i] or 0
    local palSlot = math.floor(byte / 16) % 16
    local colorIndex = byte % 16
    local pal = mapPals[palSlot] or mapPals[0]
    local c = (pal and pal[colorIndex]) or 0
    buf[i] = c % 32768
    palBuf[i] = palSlot
  end
  return buf, palBuf
end

--- Crop one 8×8 quadrant (0=TL,1=TR,2=BL,3=BR) from a 16×16 buffer.
function Metatile.quadrant(buf16, q)
  local ox = (q % 2) * 8
  local oy = math.floor(q / 2) * 8
  local out = {}
  for y = 0, 7 do
    for x = 0, 7 do
      out[y * 8 + x + 1] = buf16[(oy + y) * 16 + (ox + x) + 1]
    end
  end
  return out
end

--- True when every pixel is BGR555 0 (FRLG in-map void / solid black).
function Metatile.isExactBlackBuf(buf, n)
  n = n or (buf and #buf) or 0
  if n < 1 then return false end
  for i = 1, n do
    local c = buf[i] or 0
    if (c % 0x8000) ~= 0 then return false end
  end
  return true
end

--- Majority FRLG palette slot among an 8×8 palBuf quadrant.
function Metatile.quadrantPal(palBuf16, q)
  local ox = (q % 2) * 8
  local oy = math.floor(q / 2) * 8
  local counts = {}
  local best, bestN = 0, 0
  for y = 0, 7 do
    for x = 0, 7 do
      local p = palBuf16[(oy + y) * 16 + (ox + x) + 1] or 0
      local n = (counts[p] or 0) + 1
      counts[p] = n
      if n > bestN then best, bestN = p, n end
    end
  end
  return best
end

return Metatile
