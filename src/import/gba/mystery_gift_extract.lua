-- src/mystery_gift_show_card.c:150, src/mystery_gift_show_news.c:99

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local MysteryGiftExtract = {}

MysteryGiftExtract.CACHE_SUB = "mystery_gift"
MysteryGiftExtract.MANIFEST_VERSION = 1

local W, H = 240, 160
local MAP_W = 30
local ENTRY_STRIDE = 16

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function rom_bytes(rom, off, len)
  local out = {}
  for i = 1, len do out[i] = rom:get(off + i - 1) end
  out._len = len
  return out
end

-- include/mystery_gift.h:40
local function graphics_entry(rom, base, index)
  local off = base + index * ENTRY_STRIDE
  local b0 = rom:get(off)
  local b1 = rom:get(off + 1)
  return {
    titleTextPal = b0 % 16,
    bodyTextPal = math.floor(b0 / 16),
    footerTextPal = b1 % 16,
    stampShadowPal = math.floor(b1 / 16),
    tiles = rom:ptrOffset(rom:u32(off + 4)),
    map = rom:ptrOffset(rom:u32(off + 8)),
    pal = rom:ptrOffset(rom:u32(off + 12)),
  }
end

-- src/mystery_gift_show_card.c:219
local function bake_entry(rom, entry)
  local function get(i) return rom:get(i) end
  local gfx = Lz77.decompress(get, entry.tiles)
  local map = Lz77.decompress(get, entry.map)
  local banks = BgBake.loadPalBanks(rom_bytes(rom, entry.pal, 32), 1)
  return BgBake.bakeRegionRgba(gfx, banks, map, W, H, { mapW = MAP_W })
end

function MysteryGiftExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. MysteryGiftExtract.CACHE_SUB
  local count = Versions.WONDER_BG_COUNT

  local groups = {
    { prefix = "card_bg", base = Versions.WONDER_CARD_GRAPHICS },
    { prefix = "news_bg", base = Versions.WONDER_NEWS_GRAPHICS },
  }
  local rows = {}
  for _, group in ipairs(groups) do
    for i = 0, count - 1 do
      local entry = graphics_entry(rom, group.base, i)
      if not (entry.tiles and entry.map and entry.pal) then
        error(string.format("mystery_gift: %s%d has a bad pointer", group.prefix, i))
      end
      cache:write(string.format("%s/%s%d.rgba", root, group.prefix, i), bake_entry(rom, entry))
      rows[#rows + 1] = string.format(
        "  { key = \"%s%d\", titleTextPal = %d, bodyTextPal = %d, footerTextPal = %d, stampShadowPal = %d },",
        group.prefix, i, entry.titleTextPal, entry.bodyTextPal,
        entry.footerTextPal, entry.stampShadowPal)
    end
  end

  local OnlineUi = require("src.import.gba.online_ui_extract")
  local stampRows = OnlineUi.giftArt(rom, function(path, data) cache:write(path, data) end, root)

  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  count = %d,
  entries = {
%s
  },
%s
}
]], MysteryGiftExtract.MANIFEST_VERSION, W, H, count, table.concat(rows, "\n"),
    OnlineUi.manifestRows(stampRows)))

  print(string.format("[mystery_gift_extract] %d wonder card and %d wonder news backgrounds %dx%d -> %s",
    count, count, W, H, root))
  return { root = root, count = count }
end

function MysteryGiftExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. MysteryGiftExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  if not cache:exists(root .. "/manifest.lua") then return false end
  for i = 0, (Versions.WONDER_BG_COUNT or 8) - 1 do
    if not cache:exists(string.format("%s/card_bg%d.rgba", root, i)) then return false end
    if not cache:exists(string.format("%s/news_bg%d.rgba", root, i)) then return false end
  end
  return true
end

return MysteryGiftExtract
