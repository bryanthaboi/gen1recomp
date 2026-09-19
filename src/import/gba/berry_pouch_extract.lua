-- Bake FRLG Berry Pouch chrome from ROM into CacheFS (data/generated/gba/items/berry_pouch/).
-- Source: pret graphics/berry_pouch/ (background.4bpp.lz, background.bin.lz, background.gbapal.lz, background_female.gbapal.lz, berry_pouch.4bpp.lz, berry_pouch.gbapal.lz).

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

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

local bgr555_to_rgb8 = BgBake.bgr555ToRgb8
local byte_len = BgBake.byteLen
local decode_tile_4bpp = BgBake.decodeTile4bpp
local load_pal_banks = BgBake.loadPalBanks
local bake_bg_rgba = BgBake.bakeBgRgba

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
