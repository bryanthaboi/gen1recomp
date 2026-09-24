local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local AssetPack = {}

function AssetPack.defaultRoot()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

function AssetPack.raw(rom, off, n)
  local out = {}
  for i = 1, n do out[i] = rom:get(off + i - 1) end
  out._len = n
  return out
end

function AssetPack.lz(rom, off)
  local out = Lz77.decompress(function(i) return rom:get(i) end, off)
  return out
end

function AssetPack.len(buf)
  return BgBake.byteLen(buf)
end

function AssetPack.pad(buf, n)
  local out = {}
  for i = 1, n do out[i] = buf[i] or 0 end
  out._len = n
  return out
end

function AssetPack.bytes(buf)
  return Lz77.toString(buf)
end

function AssetPack.banks(rom, off, count)
  return BgBake.loadPalBanks(AssetPack.raw(rom, off, count * 32), count)
end

function AssetPack.placeBanks(slots)
  local banks = {}
  for slot, bank in pairs(slots) do banks[slot] = bank end
  return banks
end

function AssetPack.palRgb(banks, first, count)
  local parts = {}
  for b = first, first + count - 1 do
    local bank = banks[b] or {}
    for c = 0, 15 do
      local r, g, bl = BgBake.bgr555ToRgb8(bank[c] or 0)
      parts[#parts + 1] = string.char(r, g, bl)
    end
  end
  return table.concat(parts)
end

function AssetPack.frame(gfx, bank, tile, fw, fh, hflip, vflip)
  return BgBake.bakeSpriteRgba(gfx, bank, tile, fw, fh, hflip and true or false, vflip and true or false)
end

function AssetPack.frames(gfx, bank, list, fw, fh)
  local parts = {}
  for i, f in ipairs(list) do
    parts[i] = AssetPack.frame(gfx, bank, f.tile, fw, fh, f.hflip, f.vflip)
  end
  return table.concat(parts)
end

function AssetPack.strip(gfx, bank, first, step, fw, fh, count)
  local list = {}
  for i = 0, count - 1 do list[#list + 1] = { tile = first + i * step } end
  return AssetPack.frames(gfx, bank, list, fw, fh)
end

function AssetPack.tileSheet(gfx, bank, count, cols)
  local rows = math.ceil(count / cols)
  local map = { _len = cols * rows * 2 }
  for i = 0, cols * rows - 1 do
    local entry = i < count and i or 0x3FF
    map[i * 2 + 1] = entry % 256
    map[i * 2 + 2] = math.floor(entry / 256)
  end
  return BgBake.bakeRegionRgba(gfx, { [0] = bank }, map, cols * 8, rows * 8, { mapW = cols, alpha0 = true }),
    cols * 8, rows * 8
end

-- include/gba/io_reg.h:538
local SCREEN_BLOCKS = {
  [0] = { w = 32, h = 32, blocks = { { 0, 0 } } },
  [1] = { w = 64, h = 32, blocks = { { 0, 0 }, { 32, 0 } } },
  [2] = { w = 32, h = 64, blocks = { { 0, 0 }, { 0, 32 } } },
  [3] = { w = 64, h = 64, blocks = { { 0, 0 }, { 32, 0 }, { 0, 32 }, { 32, 32 } } },
}

function AssetPack.linearize(map, screenSize)
  local layout = SCREEN_BLOCKS[screenSize or 0]
  local n = AssetPack.len(map)
  local out = { _len = layout.w * layout.h * 2 }
  local filled = {}
  for i = 0, math.floor(n / 2) - 1 do
    local block = math.floor(i / 1024)
    local origin = layout.blocks[block + 1]
    if origin then
      local within = i % 1024
      local x = origin[1] + within % 32
      local y = origin[2] + math.floor(within / 32)
      local di = (y * layout.w + x) * 2
      out[di + 1] = map[i * 2 + 1]
      out[di + 2] = map[i * 2 + 2]
      filled[y * layout.w + x] = true
    end
  end
  return out, layout.w, layout.h, filled
end

function AssetPack.bg(gfx, banks, map, mapW, w, h, opts)
  opts = opts or {}
  local rgba = BgBake.bakeRegionRgba(gfx, banks, map, w, h, {
    mapW = mapW, alpha0 = opts.alpha0 or opts.backdrop ~= nil, x0 = opts.x0, y0 = opts.y0,
  })
  if opts.backdrop ~= nil then
    local r, g, b = BgBake.bgr555ToRgb8(opts.backdrop)
    local solid = string.char(r, g, b, 255)
    rgba = rgba:gsub("....", function(px)
      if px:byte(4) == 0 then return solid end
      return px
    end)
  end
  return rgba
end

local READERS = {
  u8 = { 1, function(rom, off) return rom:get(off) end },
  s8 = { 1, function(rom, off)
    local v = rom:get(off)
    return v >= 128 and v - 256 or v
  end },
  u16 = { 2, function(rom, off) return rom:u16(off) end },
  s16 = { 2, function(rom, off)
    local v = rom:u16(off)
    return v >= 32768 and v - 65536 or v
  end },
  u32 = { 4, function(rom, off) return rom:u32(off) end },
  s32 = { 4, function(rom, off)
    local v = rom:u32(off)
    return v >= 2147483648 and v - 4294967296 or v
  end },
}

function AssetPack.sizeOf(kind)
  return READERS[kind][1]
end

function AssetPack.read(rom, off, kind)
  return READERS[kind][2](rom, off)
end

function AssetPack.array(rom, off, kind, count)
  local size, fn = READERS[kind][1], READERS[kind][2]
  local out = {}
  for i = 0, count - 1 do out[i + 1] = fn(rom, off + i * size) end
  return out
end

function AssetPack.grid(rom, off, kind, dims)
  local size = READERS[kind][1]
  local function build(base, depth)
    local n = dims[depth]
    if depth == #dims then return AssetPack.array(rom, base, kind, n) end
    local stride = size
    for d = depth + 1, #dims do stride = stride * dims[d] end
    local out = {}
    for i = 0, n - 1 do out[i + 1] = build(base + i * stride, depth + 1) end
    return out
  end
  return build(off, 1)
end

function AssetPack.structs(rom, off, stride, count, fields)
  local out = {}
  for i = 0, count - 1 do
    local row = {}
    for _, f in ipairs(fields) do
      row[f[1]] = AssetPack.read(rom, off + i * stride + f[3], f[2])
    end
    out[i + 1] = row
  end
  return out
end

-- include/window.h:28
function AssetPack.windowTemplates(rom, off, count)
  return AssetPack.structs(rom, off, 8, count, {
    { "bg", "u8", 0 }, { "left", "u8", 1 }, { "top", "u8", 2 },
    { "width", "u8", 3 }, { "height", "u8", 4 }, { "paletteNum", "u8", 5 },
    { "baseBlock", "u16", 6 },
  })
end

-- include/bg.h:67
function AssetPack.bgTemplates(rom, off, count)
  local out = {}
  for i = 0, count - 1 do
    local v = rom:u32(off + i * 4)
    local function bits(lo, n) return math.floor(v / 2 ^ lo) % 2 ^ n end
    out[i + 1] = {
      bg = bits(0, 2), charBaseIndex = bits(2, 2), mapBaseIndex = bits(4, 5),
      screenSize = bits(9, 2), paletteMode = bits(11, 1), priority = bits(12, 2),
      baseTile = bits(16, 10),
    }
  end
  return out
end

local function isIdent(k)
  return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function isArray(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  for i = 1, count do
    if t[i] == nil then return false end
  end
  return true
end

local function serialize(v, indent)
  local tv = type(v)
  if tv == "number" then
    if v % 1 == 0 then return string.format("%d", v) end
    return string.format("%.17g", v)
  elseif tv == "string" then
    return string.format("%q", v)
  elseif tv == "boolean" then
    return tostring(v)
  elseif tv ~= "table" then
    error("asset_pack: cannot serialize " .. tv)
  end
  local pad = string.rep("  ", indent + 1)
  local close = string.rep("  ", indent)
  if isArray(v) then
    local flat = true
    for _, x in ipairs(v) do if type(x) == "table" then flat = false break end end
    local parts = {}
    for i, x in ipairs(v) do parts[i] = serialize(x, indent + 1) end
    if flat then return "{ " .. table.concat(parts, ", ") .. " }" end
    return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. ",\n" .. close .. "}"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    local key = isIdent(k) and k or ("[" .. serialize(k, 0) .. "]")
    parts[#parts + 1] = key .. " = " .. serialize(v[k], indent + 1)
  end
  return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. ",\n" .. close .. "}"
end

function AssetPack.serialize(v)
  return "return " .. serialize(v, 0) .. "\n"
end

function AssetPack.loadManifest(cache, path)
  if not (cache and cache.exists and cache.read) then return nil end
  local body = cache:exists(path) and cache:read(path)
  if type(body) ~= "string" then return nil end
  local chunk = load(body, "@" .. path, "t", {})
  if not chunk then return nil end
  local ok, man = pcall(chunk)
  if not ok or type(man) ~= "table" then return nil end
  return man
end

function AssetPack.sizedFile(cache, path, n)
  if not cache:exists(path) then return false end
  local body = cache:read(path)
  return type(body) == "string" and #body == n
end

return AssetPack
