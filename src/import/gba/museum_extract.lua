-- src/script_menu.c:1149 OpenMuseumFossilPic, :647 sMuseumAerodactylSprTiles

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")

local MuseumExtract = {}

MuseumExtract.CACHE_SUB = "museum"
MuseumExtract.MANIFEST_VERSION = 1

MuseumExtract.SPECIES_KABUTOPS = 141
MuseumExtract.SPECIES_AERODACTYL = 142

MuseumExtract.FILES = { "kabutops.rgba", "aerodactyl.rgba", "manifest.lua" }

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

function MuseumExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. MuseumExtract.CACHE_SUB
  local size = Versions.MUSEUM_FOSSIL_SIZE or 64
  local tileBytes = size * size / 2

  local rows = {
    { name = "kabutops", gfx = Versions.MUSEUM_KABUTOPS_GFX, pal = Versions.MUSEUM_KABUTOPS_PAL },
    { name = "aerodactyl", gfx = Versions.MUSEUM_AERODACTYL_GFX, pal = Versions.MUSEUM_AERODACTYL_PAL },
  }
  for _, row in ipairs(rows) do
    local gfx = raw_bytes(rom, row.gfx, tileBytes)
    local bank = BgBake.loadPalBanks(raw_bytes(rom, row.pal, 32), 1)[0]
    cache:write(root .. "/" .. row.name .. ".rgba",
      BgBake.bakeSpriteRgba(gfx, bank, 0, size, size, false, false))
  end

  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  species = { kabutops = %d, aerodactyl = %d },
}
]], MuseumExtract.MANIFEST_VERSION, size, size,
    MuseumExtract.SPECIES_KABUTOPS, MuseumExtract.SPECIES_AERODACTYL))

  print(string.format("[museum_extract] kabutops and aerodactyl fossil pics %dx%d -> %s",
    size, size, root))
  return { root = root, width = size, height = size }
end

function MuseumExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. MuseumExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs(MuseumExtract.FILES) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return MuseumExtract
