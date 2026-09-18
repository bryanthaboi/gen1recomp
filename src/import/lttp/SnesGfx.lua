local SnesGfx = {}

SnesGfx.TILE_PIXELS = 8

function SnesGfx.loRomOffset(bank, high, low)
  local addr = high * 0x100 + low
  if addr < 0x8000 then return nil end
  return (bank % 0x80) * 0x8000 + (addr % 0x8000)
end

function SnesGfx.color(word)
  local r = word % 32
  local g = math.floor(word / 32) % 32
  local b = math.floor(word / 1024) % 32
  return r * 255 / 31, g * 255 / 31, b * 255 / 31
end

function SnesGfx.readPalette(rom, offset, count)
  local out = {}
  for i = 0, count - 1 do
    local lo = rom:byte(offset + i * 2 + 1)
    local hi = rom:byte(offset + i * 2 + 2)
    if not lo or not hi then return nil, "palette runs past the end of the rom" end
    local r, g, b = SnesGfx.color(hi * 256 + lo)
    out[i + 1] = { math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5) }
  end
  return out
end

local function planeBit(value, x)
  return math.floor(value / (2 ^ (7 - x))) % 2
end

function SnesGfx.decodeTile3bpp(raw, tile)
  local base = tile * 24
  local out = {}
  for y = 0, 7 do
    local p0 = raw:byte(base + y * 2 + 1)
    local p1 = raw:byte(base + y * 2 + 2)
    local p2 = raw:byte(base + 16 + y + 1)
    if not p0 or not p1 or not p2 then return nil end
    for x = 0, 7 do
      out[y * 8 + x + 1] = planeBit(p0, x)
        + planeBit(p1, x) * 2
        + planeBit(p2, x) * 4
    end
  end
  return out
end

function SnesGfx.decodeTile2bpp(raw, tile)
  local base = tile * 16
  local out = {}
  for y = 0, 7 do
    local p0 = raw:byte(base + y * 2 + 1)
    local p1 = raw:byte(base + y * 2 + 2)
    if not p0 or not p1 then return nil end
    for x = 0, 7 do
      out[y * 8 + x + 1] = planeBit(p0, x) + planeBit(p1, x) * 2
    end
  end
  return out
end

function SnesGfx.decodeTile4bpp(raw, tile)
  local base = tile * 32
  local out = {}
  for y = 0, 7 do
    local p0 = raw:byte(base + y * 2 + 1)
    local p1 = raw:byte(base + y * 2 + 2)
    local p2 = raw:byte(base + 16 + y * 2 + 1)
    local p3 = raw:byte(base + 16 + y * 2 + 2)
    if not (p0 and p1 and p2 and p3) then return nil end
    for x = 0, 7 do
      out[y * 8 + x + 1] = planeBit(p0, x)
        + planeBit(p1, x) * 2
        + planeBit(p2, x) * 4
        + planeBit(p3, x) * 8
    end
  end
  return out
end

function SnesGfx.decodeTiles(raw, bits)
  local perTile = bits == 4 and 32 or (bits == 3 and 24 or 16)
  local decode = bits == 4 and SnesGfx.decodeTile4bpp
    or (bits == 3 and SnesGfx.decodeTile3bpp or SnesGfx.decodeTile2bpp)
  if #raw % perTile ~= 0 then
    return nil, "data is not a whole number of " .. bits .. "bpp tiles"
  end
  local out = {}
  for tile = 0, #raw / perTile - 1 do
    local pixels = decode(raw, tile)
    if not pixels then return nil, "tile " .. tile .. " runs past the data" end
    out[tile + 1] = pixels
  end
  return out
end

function SnesGfx.sheetFormat(size)
  if size % 24 == 0 and size >= 24 then return 3, size / 24 end
  if size % 16 == 0 and size >= 16 then return 2, size / 16 end
  return nil
end

function SnesGfx.decodeSheet(raw)
  local bits, tiles = SnesGfx.sheetFormat(#raw)
  if not bits then return nil, "sheet is not a whole number of tiles" end
  local decode = bits == 3 and SnesGfx.decodeTile3bpp or SnesGfx.decodeTile2bpp
  local out = {}
  for tile = 0, tiles - 1 do
    local pixels = decode(raw, tile)
    if not pixels then return nil, "tile " .. tile .. " runs past the sheet" end
    out[tile + 1] = pixels
  end
  return out, bits
end

return SnesGfx
