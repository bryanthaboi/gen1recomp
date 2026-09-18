-- Bake FRLG Berry Pouch chrome from ROM into CacheFS (data/generated/gba/items/berry_pouch/).
-- Source: pret graphics/berry_pouch/ (background.4bpp.lz, background.bin.lz, background.gbapal.lz, background_female.gbapal.lz, berry_pouch.4bpp.lz, berry_pouch.gbapal.lz).

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BerryPouchExtract = {}

BerryPouchExtract.CACHE_SUB = "items/berry_pouch"
BerryPouchExtract.FORMAT_VERSION = 1

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

local function byte_len(buf)
  if type(buf) ~= "table" then return 0 end
  return buf._len or #buf
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
      if hflip then
        x0, x1 = 7 - x0, 7 - x1
      end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function load_pal_banks(bytes, count)
  local banks = {}
  local n = count or math.floor(byte_len(bytes) / 32)
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

--- Render 240x160 background from 4bpp tiles + tilemap + palette banks.
local function bake_bg_rgba(gfx, palBanks, map, W, H)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local mapW = 32
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end

  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId < tileCount then
        local tile = {}
        local base = tileId * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        local tmp = {}
        for i = 1, 64 do tmp[i] = 0 end
        decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
        for row = 0, 7 do
          for col = 0, 7 do
            local px, py = tx * 8 + col, ty * 8 + row
            if px < W and py < H then
              local di = py * W + px + 1
              indices[di] = tmp[row * 8 + col + 1] or 0
              pals[di] = palNum
            end
          end
        end
      end
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local bank = palBanks[pals[i]] or palBanks[0] or {}
    local col = bank[indices[i]] or 0
    local r, g, b = bgr555_to_rgb8(col)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

--- Render 64x64 Berry Pouch animated sprite.
local function bake_pouch_sprite_rgba(gfx, palBytes)
  local W, H = 64, 64
  local banks = load_pal_banks(palBytes, 1)
  local pal = banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  local ti = 0
  for ty = 0, 7 do
    for tx = 0, 7 do
      if ti < tileCount then
        local tile = {}
        local base = ti * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, false, false)
      end
      ti = ti + 1
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

function BerryPouchExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. BerryPouchExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom:get(i) end

  local gfx = Lz77.decompress(get, Versions.BERRY_POUCH_BG_GFX)
  local map = Lz77.decompress(get, Versions.BERRY_POUCH_BG_TILEMAP)
  local palMale = Lz77.decompress(get, Versions.BERRY_POUCH_BG_PAL)
  local palFemaleOverride = Lz77.decompress(get, Versions.BERRY_POUCH_BG_PAL_FEMALE)

  local maleBanks = load_pal_banks(palMale, 3)
  local femaleBanks = load_pal_banks(palMale, 3)
  local overrideBank = load_pal_banks(palFemaleOverride, 1)[0]
  if overrideBank then
    femaleBanks[0] = overrideBank
  end

  -- 1. Backgrounds
  local rgbaMale = bake_bg_rgba(gfx, maleBanks, map, W, H)
  local rgbaFemale = bake_bg_rgba(gfx, femaleBanks, map, W, H)
  cache:write(root .. "/bg_male.rgba", rgbaMale)
  cache:write(root .. "/bg_female.rgba", rgbaFemale)

  -- 2. Berry Pouch Sprite (64x64)
  local spriteGfx = Lz77.decompress(get, Versions.BERRY_POUCH_SPRITE_GFX)
  local spritePal = Lz77.decompress(get, Versions.BERRY_POUCH_SPRITE_PAL)
  local pouchRgba = bake_pouch_sprite_rgba(spriteGfx, spritePal)
  cache:write(root .. "/pouch.rgba", pouchRgba)

  local manifest = string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  pouchW = 64,
  pouchH = 64,
}
]], BerryPouchExtract.FORMAT_VERSION, W, H)
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format("[berry_pouch_extract] Berry Pouch chrome baked (2 backgrounds, 64x64 pouch sprite) -> %s", root))
  return {
    root = root,
    width = W,
    height = H,
  }
end

function BerryPouchExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. BerryPouchExtract.CACHE_SUB
  if cache and cache.exists then
    return cache:exists(root .. "/bg_male.rgba") and cache:exists(root .. "/pouch.rgba")
  end
  return false
end

return BerryPouchExtract
