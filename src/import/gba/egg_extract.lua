-- src/daycare.c:137 sEggPalette, :138 sEggHatchTiles, :139 sEggShardTiles

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local EggExtract = {}

EggExtract.CACHE_SUB = "pokemon/egg"
EggExtract.MANIFEST_VERSION = 1

EggExtract.SPECIES_EGG = 412

-- src/daycare.c:141 sOamData_EggHatch is SPRITE_SIZE(32x32), :158 four frames 16 tiles apart
local HATCH_W, HATCH_H, HATCH_FRAMES = 32, 32, 4
-- src/daycare.c:221 sOamData_EggShard is SPRITE_SIZE(8x8), :243 four frames one tile apart
local SHARD_W, SHARD_H, SHARD_FRAMES = 8, 8, 4
local PIC_W, PIC_H = 64, 64

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function raw_bytes(rom, off, n)
  local out = {}
  for i = 1, n do out[i] = rom:get(off + i - 1) end
  out._len = n
  return out
end

-- src/daycare.c:138
local function stack_frames(gfx, bank, frames, tilesPerFrame, w, h, acrossRow)
  local parts = {}
  for f = 0, frames - 1 do
    parts[f + 1] = BgBake.bakeSpriteRgba(gfx, bank, f * tilesPerFrame, w, h, false, false)
  end
  if not acrossRow then return table.concat(parts) end
  local rows = {}
  for y = 0, h - 1 do
    for f = 1, frames do
      rows[#rows + 1] = parts[f]:sub(y * w * 4 + 1, (y + 1) * w * 4)
    end
  end
  return table.concat(rows)
end

function EggExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. EggExtract.CACHE_SUB
  local function get(i) return rom:get(i) end

  local palBytes = raw_bytes(rom, Versions.EGG_PALETTE, 32)
  local bank = BgBake.loadPalBanks(palBytes, 1)[0]

  local hatch = raw_bytes(rom, Versions.EGG_HATCH_GFX, HATCH_W * HATCH_H / 2 * HATCH_FRAMES)
  cache:write(root .. "/hatch.rgba",
    stack_frames(hatch, bank, HATCH_FRAMES, (HATCH_W / 8) * (HATCH_H / 8), HATCH_W, HATCH_H))

  local shard = raw_bytes(rom, Versions.EGG_SHARD_GFX, SHARD_W * SHARD_H / 2 * SHARD_FRAMES)
  cache:write(root .. "/shard.rgba",
    stack_frames(shard, bank, SHARD_FRAMES, 1, SHARD_W, SHARD_H, true))

  local picTable = (Versions.OAK_SPEECH and Versions.OAK_SPEECH.mon_front_pic_table) or 0x2350AC
  local palTable = (Versions.OAK_SPEECH and Versions.OAK_SPEECH.mon_palette_table) or 0x23730C
  local picOff = rom:ptrOffset(rom:u32(picTable + EggExtract.SPECIES_EGG * 8))
  local picPalOff = rom:ptrOffset(rom:u32(palTable + EggExtract.SPECIES_EGG * 8))
  if not (picOff and picPalOff) then error("egg_extract: no SPECIES_EGG pic entry") end
  local tiles = Lz77.decompress(get, picOff)
  local picPal = Lz77.decompress(get, picPalOff)
  if not (tiles and picPal) then error("egg_extract: the SPECIES_EGG pic did not decompress") end
  local picBank = BgBake.loadPalBanks(picPal, 1)[0]
  cache:write(cacheRoot .. "/pokemon/front/" .. EggExtract.SPECIES_EGG .. ".rgba",
    BgBake.bakeSpriteRgba(tiles, picBank, 0, PIC_W, PIC_H, false, false))

  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  species = %d,
  pic = { width = %d, height = %d },
  hatch = { width = %d, height = %d, frames = %d, sheetWidth = %d, sheetHeight = %d },
  shard = { width = %d, height = %d, frames = %d, sheetWidth = %d, sheetHeight = %d },
}
]], EggExtract.MANIFEST_VERSION, EggExtract.SPECIES_EGG, PIC_W, PIC_H,
    HATCH_W, HATCH_H, HATCH_FRAMES, HATCH_W, HATCH_H * HATCH_FRAMES,
    SHARD_W, SHARD_H, SHARD_FRAMES, SHARD_W * SHARD_FRAMES, SHARD_H))

  print(string.format(
    "[egg_extract] EGG front pic %dx%d, %d hatch frames, %d shard frames -> %s",
    PIC_W, PIC_H, HATCH_FRAMES, SHARD_FRAMES, root))
  return { root = root, frames = HATCH_FRAMES }
end

function EggExtract.ready(cache, cacheRoot)
  cacheRoot = cacheRoot or default_cache_root()
  if not (cache and cache.exists) then return false end
  local root = cacheRoot .. "/" .. EggExtract.CACHE_SUB
  for _, rel in ipairs({ "hatch.rgba", "shard.rgba", "manifest.lua" }) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return cache:exists(cacheRoot .. "/pokemon/front/" .. EggExtract.SPECIES_EGG .. ".rgba")
end

return EggExtract
