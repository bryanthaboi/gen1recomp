-- src/learn_move.c:384 MoveRelearnerLoadBgGfx

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local MoveRelearnerExtract = {}

MoveRelearnerExtract.CACHE_SUB = "move_relearner"
MoveRelearnerExtract.MANIFEST_VERSION = 1
MoveRelearnerExtract.FILES = { "bg.rgba", "manifest.lua" }

local W, H = 240, 160

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

function MoveRelearnerExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. MoveRelearnerExtract.CACHE_SUB
  local function get(i) return rom:get(i) end

  local gfx = Lz77.decompress(get, Versions.MOVE_RELEARNER_GFX)
  local map = Lz77.decompress(get, Versions.MOVE_RELEARNER_TILEMAP)
  local palBytes = {}
  for i = 1, 32 do palBytes[i] = rom:get(Versions.MOVE_RELEARNER_PAL + i - 1) end
  palBytes._len = 32
  local banks = BgBake.loadPalBanks(palBytes, 1)

  cache:write(root .. "/bg.rgba", BgBake.bakeBgRgba(gfx, banks, map, W, H))
  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  tiles = %d,
}
]], MoveRelearnerExtract.MANIFEST_VERSION, W, H, math.floor(BgBake.byteLen(gfx) / 32)))

  print(string.format("[move_relearner_extract] bg %dx%d -> %s", W, H, root))
  return { root = root, width = W, height = H }
end

function MoveRelearnerExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. MoveRelearnerExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs(MoveRelearnerExtract.FILES) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return MoveRelearnerExtract
