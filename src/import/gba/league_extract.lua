-- src/field_specials.c:2133, src/diploma.c:119

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")
local Lz77 = require("src.import.gba.lz77")

local LeagueExtract = {}

LeagueExtract.FORMAT_VERSION = 1
LeagueExtract.LIGHTING = "league/lighting.lua"
LeagueExtract.FILES = {
  "league/lighting.lua",
  "diploma/manifest.lua",
  "diploma/kanto.rgba",
  "diploma/national.rgba",
  "hall_of_fame/manifest.lua",
  "hall_of_fame/bands.rgba",
  "hall_of_fame/stripes.rgba",
  "hall_of_fame/confetti.rgba",
}

local SCREEN_W, SCREEN_H = 240, 160

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

local function lz(rom, off)
  local out = Lz77.decompress(function(i) return rom:get(i) end, off)
  out._len = Lz77.len(out)
  return out
end

local function pal_list(rom, off, count)
  local rows = {}
  for p = 0, count - 1 do
    local cols = {}
    for c = 0, 15 do cols[#cols + 1] = string.format("0x%04X", rom:u16(off + p * 32 + c * 2)) end
    rows[#rows + 1] = "      { " .. table.concat(cols, ", ") .. " },"
  end
  return table.concat(rows, "\n")
end

local function byte_list(rom, off, count)
  local out = {}
  for i = 0, count - 1 do out[#out + 1] = tostring(rom:get(off + i)) end
  return table.concat(out, ", ")
end

-- src/field_specials.c:2133
local function lighting(rom)
  local L = Versions.LEAGUE_LIGHTING
  return table.concat({
    "return {",
    string.format("  format_version = %d,", LeagueExtract.FORMAT_VERSION),
    "  palette_slot = 7,",
    "  e4 = {",
    "    pals = {",
    pal_list(rom, L.e4_pals, L.e4_pal_count),
    "    },",
    "    timers = { " .. byte_list(rom, L.e4_timers, L.e4_steps) .. " },",
    "  },",
    "  champion = {",
    "    pals = {",
    pal_list(rom, L.champ_pals, L.champ_pal_count),
    "    },",
    "    timers = { " .. byte_list(rom, L.champ_timers, L.champ_steps) .. " },",
    "  },",
    "}",
    "",
  }, "\n")
end

-- src/diploma.c:137
local function diploma_screen(gfx, banks, map, block)
  local sub = {}
  local base = block * 2048
  for i = 1, 2048 do sub[i] = map[base + i] or 0 end
  sub._len = 2048
  local top = BgBake.bakeRegionRgba(gfx, banks, sub, SCREEN_W, SCREEN_H, { mapW = 32, alpha0 = true })
  local r, g, b = BgBake.bgr555ToRgb8(banks[0][0])
  local backdrop = string.char(r, g, b, 255)
  local out = {}
  for i = 1, SCREEN_W * SCREEN_H do
    local o = (i - 1) * 4
    if top:byte(o + 4) > 0 then
      out[i] = top:sub(o + 1, o + 4)
    else
      out[i] = backdrop
    end
  end
  return table.concat(out)
end

local function fill_map(rows)
  local map = {}
  for i = 1, 32 * 32 * 2 do map[i] = 0 end
  for _, r in ipairs(rows) do
    for y = r.y, r.y + r.h - 1 do
      for x = 0, 31 do
        map[(y * 32 + x) * 2 + 1] = r.tile
      end
    end
  end
  map._len = 32 * 32 * 2
  return map
end

-- src/hall_of_fame.c:1181, :1163
local function hall_of_fame(rom, put)
  local H = Versions.HALL_OF_FAME
  local gfx = lz(rom, H.gfx)
  local banks = BgBake.loadPalBanks(rom_bytes(rom, H.pal, 32), 1)
  put("hall_of_fame/bands.rgba", BgBake.bakeRegionRgba(gfx, banks, fill_map({
    { y = 0, h = 2, tile = 1 },
    { y = 3, h = 11, tile = 0 },
    { y = 14, h = 6, tile = 1 },
  }), SCREEN_W, SCREEN_H, { alpha0 = true }))
  put("hall_of_fame/stripes.rgba", BgBake.bakeRegionRgba(gfx, banks,
    fill_map({ { y = 0, h = 32, tile = 2 } }), SCREEN_W, SCREEN_H, {}))
  local sheet = lz(rom, H.confetti_sheet)
  assert(BgBake.byteLen(sheet) == H.confetti_frames * 32, "confetti sheet is not 17 8x8 tiles")
  local pal = BgBake.loadPalBanks(lz(rom, H.confetti_pal), 1)[0]
  local frames = {}
  for f = 0, H.confetti_frames - 1 do
    frames[#frames + 1] = BgBake.bakeSpriteRgba(sheet, pal, f, 8, 8, false, false)
  end
  put("hall_of_fame/confetti.rgba", table.concat(frames))
  put("hall_of_fame/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  confetti = { w = 8, h = 8, frames = %d },
}
]], LeagueExtract.FORMAT_VERSION, SCREEN_W, SCREEN_H, H.confetti_frames))
end

function LeagueExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.cacheRoot or default_cache_root()
  local function put(name, body) assert(cache:write(root .. "/" .. name, body)) end
  put(LeagueExtract.LIGHTING, lighting(rom))

  local D = Versions.DIPLOMA
  local gfx = lz(rom, D.gfx)
  local map = lz(rom, D.tilemap)
  assert(BgBake.byteLen(map) == 4096, "diploma tilemap is not 64x32")
  local banks = BgBake.loadPalBanks(rom_bytes(rom, D.pal, 64), 2)
  put("diploma/kanto.rgba", diploma_screen(gfx, banks, map, 0))
  put("diploma/national.rgba", diploma_screen(gfx, banks, map, 1))
  put("diploma/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
}
]], LeagueExtract.FORMAT_VERSION, SCREEN_W, SCREEN_H))
  hall_of_fame(rom, put)
  print(string.format("[league_extract] league lighting palettes, diploma and hall of fame screens -> %s", root))
  return { root = root }
end

function LeagueExtract.ready(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs(LeagueExtract.FILES) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return LeagueExtract
