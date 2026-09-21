-- src/teachy_tv.c:526 TeachyTvLoadGraphic, src/graphics.c:1117

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local TeachyTvExtract = {}

TeachyTvExtract.CACHE_SUB = "teachy_tv"
TeachyTvExtract.MANIFEST_VERSION = 1

local W, H = 240, 160

-- src/teachy_tv.c:1026
local END_X, END_Y, END_W, END_H = 20, 10, 8, 2

-- src/teachy_tv.c:637 tilemapBuffer[32 * i + j] = ((Random() & 3) << 10) + 0x301F
local STATIC_TILE = 0x1F
local STATIC_BANK = 3
local STATIC_FRAMES = 4

-- src/teachy_tv.c:1218 TeachyTvLoadBg3Map, Route1_Layout blocks (6..14, 8..23)
local BG3_W, BG3_H = 256, 256
local BG3_LAYOUT = 89              -- include/constants/layouts.h:79 LAYOUT_ROUTE1
local BG3_COL0, BG3_ROW0 = 8, 6
local BG3_COLS, BG3_ROWS = 16, 9

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function static_rgba(gfx, banks)
  local parts = {}
  for f = 0, STATIC_FRAMES - 1 do
    parts[#parts + 1] = BgBake.bakeSpriteRgba(gfx, banks[STATIC_BANK], STATIC_TILE, 8, 8,
      f % 2 == 1, math.floor(f / 2) % 2 == 1)
  end
  local out = {}
  for y = 0, 7 do
    for f = 0, STATIC_FRAMES - 1 do
      local row = parts[f + 1]:sub(y * 8 * 4 + 1, (y + 1) * 8 * 4)
      out[#out + 1] = row
    end
  end
  return table.concat(out)
end

local function bg3_rgba(rom)
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Tileset = require("src.import.gba.tileset")
  local Metatile = require("src.import.gba.metatile")
  local NativePack = require("src.import.gba.native_pack")

  local base = Versions.G_MAP_LAYOUTS
  local layoutOff = rom:ptrOffset(rom:u32(base + (BG3_LAYOUT - 1) * 4))
  local layout = layoutOff and MapTree.parseLayout(rom, layoutOff)
  local mapOff = layout and rom:ptrOffset(layout.mapPtr)
  if not mapOff then error("teachy_tv: no Route 1 layout at id " .. BG3_LAYOUT) end
  local pairName = MapCatalog.pairForLayout(rom, layout)
  local bundle = assert(Tileset.loadPair(rom, {}, pairName))
  local rgb = NativePack.palsToRgb8(bundle.mapPals)

  local px = {}
  for i = 1, BG3_W * BG3_H * 4 do px[i] = 0 end
  for i = 0, BG3_ROWS - 1 do
    for j = 0, BG3_COLS - 1 do
      local cell = BG3_COL0 + (i + BG3_ROW0) * layout.width + j
      local mid = rom:u16(mapOff + cell * 2) % 1024
      local idx = Metatile.compositeIndexed(bundle, mid)
      for y = 0, 15 do
        for x = 0, 15 do
          local v = idx[y * 16 + x + 1] or 0
          local ci = v % 16
          if ci ~= 0 then
            local bank = rgb[math.floor(v / 16) % 16] or rgb[0]
            local c = bank[ci]
            local o = ((i * 16 + y) * BG3_W + (j * 16 + x)) * 4
            px[o + 1], px[o + 2], px[o + 3], px[o + 4] = c[1], c[2], c[3], 255
          end
        end
      end
    end
  end
  local chunks = {}
  for i = 1, BG3_W * BG3_H do
    local o = (i - 1) * 4
    chunks[i] = string.char(px[o + 1], px[o + 2], px[o + 3], px[o + 4])
  end
  return table.concat(chunks)
end

-- src/bg.c:1151
local function end_tilemap(rom)
  local map = {}
  for i = 1, 2048 do map[i] = 0 end
  map._len = 2048
  for row = 0, END_H - 1 do
    for col = 0, END_W - 1 do
      -- src/teachy_tv.c:869
      local entry = rom:u16(Versions.TEACHY_TV_END_TILES + (row * END_W + col) * 2)
      local mi = ((END_Y + row) * 32 + (END_X + col)) * 2 + 1
      map[mi] = entry % 256
      map[mi + 1] = math.floor(entry / 256)
    end
  end
  return map
end

function TeachyTvExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. TeachyTvExtract.CACHE_SUB
  local function get(i) return rom:get(i) end

  local gfx = Lz77.decompress(get, Versions.TEACHY_TV_GFX)
  local screen = Lz77.decompress(get, Versions.TEACHY_TV_SCREEN_TILEMAP)
  local title = Lz77.decompress(get, Versions.TEACHY_TV_TITLE_TILEMAP)
  local pal = Lz77.decompress(get, Versions.TEACHY_TV_PAL)
  local banks = BgBake.loadPalBanks(pal, 4)
  -- src/teachy_tv.c:534 LoadPalette(&src, BG_PLTT_ID(0), sizeof(src)), src = RGB_BLACK
  if banks[0] then banks[0][0] = 0 end

  -- src/teachy_tv.c:118 sBgTemplates, BG1 and BG2 sit over BG3 and the backdrop
  cache:write(root .. "/screen.rgba",
    BgBake.bakeRegionRgba(gfx, banks, screen, W, H, { alpha0 = true }))
  cache:write(root .. "/title.rgba",
    BgBake.bakeRegionRgba(gfx, banks, title, W, H, { alpha0 = true }))
  cache:write(root .. "/end.rgba",
    BgBake.bakeRegionRgba(gfx, banks, end_tilemap(rom), W, H, { alpha0 = true }))
  cache:write(root .. "/static.rgba", static_rgba(gfx, banks))
  cache:write(root .. "/bg3.rgba", bg3_rgba(rom))

  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  endRect = { x = %d, y = %d, w = %d, h = %d },
  tiles = %d,
  staticWidth = %d,
  staticHeight = %d,
  staticFrames = %d,
  bg3Width = %d,
  bg3Height = %d,
}
]], TeachyTvExtract.MANIFEST_VERSION, W, H,
    END_X * 8, END_Y * 8, END_W * 8, END_H * 8,
    math.floor(BgBake.byteLen(gfx) / 32),
    STATIC_FRAMES * 8, 8, STATIC_FRAMES, BG3_W, BG3_H))

  print(string.format(
    "[teachy_tv_extract] screen %dx%d, title, end plate %dx%d, static %dx8, bg3 %dx%d -> %s",
    W, H, END_W * 8, END_H * 8, STATIC_FRAMES * 8, BG3_W, BG3_H, root))
  return { root = root, width = W, height = H }
end

function TeachyTvExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. TeachyTvExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs({ "screen.rgba", "title.rgba", "end.rgba", "static.rgba",
    "bg3.rgba", "manifest.lua" }) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return TeachyTvExtract
