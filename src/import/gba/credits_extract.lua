-- src/credits.c:815, :1101

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")
local Lz77 = require("src.import.gba.lz77")
local TextIR = require("src.core.game3.scripting.text_ir")

local CreditsExtract = {}

CreditsExtract.CACHE_SUB = "credits"
CreditsExtract.FORMAT_VERSION = 1

-- src/credits.c:1084
CreditsExtract.MONS = {
  { key = "charizard", species = 6, frames = { "charizard_1", "charizard_2" }, windows = "windows_charizard" },
  { key = "venusaur", species = 3, frames = { "venusaur_1", "venusaur_2" }, windows = "windows_venusaur" },
  { key = "blastoise", species = 9, frames = { "blastoise_1", "blastoise_2" }, windows = "windows_blastoise" },
  { key = "pikachu", species = 25, frames = { "pikachu_1", "pikachu_2" }, windows = "windows_pikachu" },
}

-- src/credits.c:466
CreditsExtract.SPRITES = {
  { key = "player_male", w = 64, h = 64, frames = 6 },
  { key = "player_female", w = 64, h = 64, frames = 6 },
  { key = "rival", w = 64, h = 64, frames = 6 },
  { key = "ground_grass", w = 64, h = 32, frames = 8 },
  { key = "ground_dirt", w = 64, h = 32, frames = 8 },
  { key = "ground_city", w = 64, h = 32, frames = 8 },
}

CreditsExtract.FILES = {
  "manifest.lua", "pack.lua", "copyright.rgba", "the_end.rgba", "circle.rgba",
  "pokeball_0.rgba", "pokeball_1.rgba", "pokeball_2.rgba", "pokeball_3.rgba",
  "mon_0_1.rgba", "mon_0_2.rgba", "mon_1_1.rgba", "mon_1_2.rgba",
  "mon_2_1.rgba", "mon_2_2.rgba", "mon_3_1.rgba", "mon_3_2.rgba",
  "player_male.rgba", "player_female.rgba", "rival.rgba",
  "ground_grass.rgba", "ground_dirt.rgba", "ground_city.rgba",
}

local SCREEN_W, SCREEN_H = 240, 160
-- include/overworld.h:38
local SCENE_ROW = 8

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

local function s16(v)
  if v >= 0x8000 then return v - 0x10000 end
  return v
end

local function pointer(rom, off)
  local p = rom:ptrOffset(rom:u32(off))
  assert(p and p < rom.size, string.format("credits: bad pointer at 0x%X", off))
  return p
end

-- src/credits.c:925
local function decode_text(rom, off)
  local bytes = {}
  for i = 0, 1023 do
    local b = rom:get(off + i)
    bytes[#bytes + 1] = string.char(b)
    if b == 0xFF then break end
  end
  local out = {}
  for _, seg in ipairs(TextIR.decode(table.concat(bytes))) do
    if seg.t == "nl" then
      out[#out + 1] = "\n"
    elseif seg.t == "ext" and seg.cmd == 0x13 then
      out[#out + 1] = string.format("{CLEAR_TO %d}", seg.args[1])
    elseif seg.t == "text" then
      out[#out + 1] = seg.s
    elseif seg.t ~= "eos" then
      error("credits: unexpected text control " .. tostring(seg.t) .. string.format(" at 0x%X", off))
    end
  end
  return table.concat(out)
end

local function quote(s)
  local lit = string.format("%q", s)
  return (lit:gsub("\\\n", "\\n"))
end

local function fill(color, w, h)
  local r, g, b = BgBake.bgr555ToRgb8(color)
  return string.rep(string.char(r, g, b, 255), w * h)
end

local function over(base, top)
  local out = {}
  for i = 1, #base / 4 do
    local o = (i - 1) * 4
    if top:byte(o + 4) > 0 then
      out[i] = top:sub(o + 1, o + 4)
    else
      out[i] = base:sub(o + 1, o + 4)
    end
  end
  return table.concat(out)
end

-- src/credits.c:1230
local function bake_bg4(gfx, banks, map, mapW)
  local top = BgBake.bakeRegionRgba(gfx, banks, map, SCREEN_W, SCREEN_H,
    { mapW = mapW or 32, alpha0 = true })
  return over(fill(banks[0][0], SCREEN_W, SCREEN_H), top)
end

local function used_banks(map)
  local hi = 0
  for i = 1, BgBake.byteLen(map), 2 do
    local entry = (map[i] or 0) + (map[i + 1] or 0) * 256
    hi = math.max(hi, math.floor(entry / 4096) % 16)
  end
  return hi + 1
end

local function closing_screen(rom, palOff, tilesOff, mapOff)
  local gfx = lz(rom, tilesOff)
  local map = lz(rom, mapOff)
  local banks = BgBake.loadPalBanks(rom_bytes(rom, palOff, used_banks(map) * 32))
  return bake_bg4(gfx, banks, map, 32)
end

-- src/credits.c:1128
local function bake_circle(rom)
  local C = Versions.CREDITS
  local tiles = lz(rom, C.circle_tiles)
  local map = lz(rom, C.circle_map)
  local pal = BgBake.loadPalBanks(rom_bytes(rom, C.circle_pal, 32), 1)[0]
  local size = 256
  local tilesPerRow = size / 8
  local out = {}
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local tile = map[math.floor(y / 8) * tilesPerRow + math.floor(x / 8) + 1] or 0
      local v = tiles[tile * 64 + (y % 8) * 8 + (x % 8) + 1] or 0
      if v == 0 then
        out[#out + 1] = "\0\0\0\0"
      else
        assert(v >= 0xF0, string.format("credits: circle pixel %d outside BG palette 15", v))
        local r, g, b = BgBake.bgr555ToRgb8(pal[v - 0xF0])
        out[#out + 1] = string.char(r, g, b, 255)
      end
    end
  end
  return table.concat(out), size
end

local function mon_palette(rom, species)
  local tbl = Versions.INTRO.mon_palette_table
  local pal = lz(rom, pointer(rom, tbl + species * 8))
  return BgBake.loadPalBanks(pal, 1)[0]
end

local function read_windows(rom, off)
  local out = {}
  for i = 0, 3 do
    local b = off + i * 8
    if rom:get(b) == 0xFF then break end
    out[#out + 1] = {
      bg = rom:get(b),
      left = rom:get(b + 1),
      top = rom:get(b + 2),
      width = rom:get(b + 3),
      height = rom:get(b + 4),
      palette = rom:get(b + 5),
      baseBlock = rom:u16(b + 6),
    }
  end
  assert(#out == 3, "credits: mon scene window templates")
  return out
end

-- src/credits.c:383
local function read_script(rom)
  local C = Versions.CREDITS
  local rows = {}
  for i = 0, C.script_max - 1 do
    local b = C.script + i * 4
    local row = { cmd = rom:get(b), param = rom:get(b + 1), duration = rom:u16(b + 2) }
    rows[#rows + 1] = row
    if row.cmd == 5 then return rows end
    assert(row.cmd <= 5, string.format("credits: unknown script cmd %d", row.cmd))
  end
  error("credits: script has no WAITBUTTON")
end

-- src/overworld.c:2384
local function read_scene(rom, off)
  local rows = {}
  local i = 0
  while true do
    local b = off + i * SCENE_ROW
    local a0, a2, a4 = s16(rom:u16(b)), s16(rom:u16(b + 2)), s16(rom:u16(b + 4))
    if a0 == 0xFD then break end
    if a0 == 0xFE then
      local n = off + (i + 1) * SCENE_ROW
      rows[#rows + 1] = {
        op = "loadmap", mapGroup = a2, mapNum = a4,
        x = s16(rom:u16(n)), y = s16(rom:u16(n + 2)), delay = s16(rom:u16(n + 4)),
      }
      i = i + 2
    else
      rows[#rows + 1] = { op = "scroll", xspeed = a0, yspeed = a2, length = a4 }
      i = i + 1
    end
    assert(i < 16, "credits: overworld scene has no end")
  end
  return rows
end

local function write_pack(rom, game)
  local C = Versions.CREDITS
  local L = {
    "return {",
    string.format("  format_version = %d,", CreditsExtract.FORMAT_VERSION),
    string.format("  title = %s,",
      quote(decode_text(rom, game == "leafgreen" and C.staff_leafgreen or C.staff_firered))),
    "  script = {",
  }
  for _, r in ipairs(read_script(rom)) do
    L[#L + 1] = string.format("    { cmd = %d, param = %d, duration = %d },", r.cmd, r.param, r.duration)
  end
  L[#L + 1] = "  },"
  L[#L + 1] = "  texts = {"
  for i = 0, C.text_count - 1 do
    local b = C.texts + i * 12
    L[#L + 1] = string.format("    [%d] = { title = %s, names = %s, unused = %s },", i,
      quote(decode_text(rom, pointer(rom, b))), quote(decode_text(rom, pointer(rom, b + 4))),
      tostring(rom:get(b + 8) ~= 0))
  end
  L[#L + 1] = "  },"
  L[#L + 1] = "  scenes = {"
  for i = 0, C.scene_count - 1 do
    local parts = {}
    for _, r in ipairs(read_scene(rom, pointer(rom, C.scenes + i * 4))) do
      if r.op == "loadmap" then
        parts[#parts + 1] = string.format(
          '{ op = "loadmap", mapGroup = %d, mapNum = %d, x = %d, y = %d, delay = %d }',
          r.mapGroup, r.mapNum, r.x, r.y, r.delay)
      else
        parts[#parts + 1] = string.format('{ op = "scroll", xspeed = %d, yspeed = %d, length = %d }',
          r.xspeed, r.yspeed, r.length)
      end
    end
    L[#L + 1] = string.format("    [%d] = { %s },", i, table.concat(parts, ", "))
  end
  L[#L + 1] = "  },"
  L[#L + 1] = "  spriteParams = {"
  for i = 0, C.sprite_param_count - 1 do
    local b = C.sprite_params + i * 6
    L[#L + 1] = string.format("    [%d] = { character = %d, ground = %d, motion = %d },",
      i, rom:u16(b), rom:u16(b + 2), rom:u16(b + 4))
  end
  L[#L + 1] = "  },"
  L[#L + 1] = "  mons = {"
  for i, m in ipairs(CreditsExtract.MONS) do
    local wins = {}
    for _, w in ipairs(read_windows(rom, C[m.windows])) do
      wins[#wins + 1] = string.format(
        "{ left = %d, top = %d, width = %d, height = %d }", w.left, w.top, w.width, w.height)
    end
    L[#L + 1] = string.format("    [%d] = { key = %q, species = %d, windows = { %s } },",
      i - 1, m.key, m.species, table.concat(wins, ", "))
  end
  L[#L + 1] = "  },"
  L[#L + 1] = "}"
  return table.concat(L, "\n") .. "\n"
end

function CreditsExtract.run(rom, cache, opts)
  opts = opts or {}
  local C = Versions.CREDITS
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. CreditsExtract.CACHE_SUB
  local game = opts.game
  if not game then
    local ver, why = Versions.lookup(rom.md5)
    game = assert(ver and ver.game, "credits: unknown FRLG edition: " .. tostring(why))
  end
  local function put(name, body) assert(cache:write(root .. "/" .. name, body)) end

  put("pack.lua", write_pack(rom, game))
  put("copyright.rgba", closing_screen(rom, C.copyright_pal, C.copyright_tiles, C.copyright_map))
  put("the_end.rgba", closing_screen(rom, C.the_end_pal, C.the_end_tiles, C.the_end_map))
  local circle, circleSize = bake_circle(rom)
  put("circle.rgba", circle)

  local ballGfx = lz(rom, C.pokeball_tiles)
  local ballMap = lz(rom, C.pokeball_map)
  local wins = {}
  for i, m in ipairs(CreditsExtract.MONS) do
    local banks = BgBake.loadPalBanks(rom_bytes(rom, C.pokeball_pals + (i - 1) * 32, 32), 1)
    put(string.format("pokeball_%d.rgba", i - 1), bake_bg4(ballGfx, banks, ballMap, 32))
    local pal = mon_palette(rom, m.species)
    local tmpl = read_windows(rom, C[m.windows])
    wins[i] = tmpl
    for f = 1, 2 do
      local w, h = tmpl[f + 1].width * 8, tmpl[f + 1].height * 8
      local gfx = lz(rom, C[m.frames[f]])
      assert(BgBake.byteLen(gfx) == w * h / 2,
        string.format("credits: %s is %d bytes, window is %dx%d", m.frames[f], BgBake.byteLen(gfx), w, h))
      put(string.format("mon_%d_%d.rgba", i - 1, f), BgBake.bakeSpriteRgba(gfx, pal, 0, w, h, false, false))
    end
  end

  local sheets = {}
  for _, s in ipairs(CreditsExtract.SPRITES) do
    local gfx = lz(rom, C[s.key .. "_tiles"])
    local tilesPerFrame = (s.w / 8) * (s.h / 8)
    assert(BgBake.byteLen(gfx) >= tilesPerFrame * 32 * s.frames,
      string.format("credits: %s holds %d bytes", s.key, BgBake.byteLen(gfx)))
    local bank = BgBake.loadPalBanks(rom_bytes(rom, C[s.key .. "_pal"], 32), 1)[0]
    local parts = {}
    for f = 0, s.frames - 1 do
      parts[#parts + 1] = BgBake.bakeSpriteRgba(gfx, bank, f * tilesPerFrame, s.w, s.h, false, false)
    end
    put(s.key .. ".rgba", table.concat(parts))
    sheets[#sheets + 1] = string.format("    %s = { w = %d, h = %d, frames = %d },", s.key, s.w, s.h, s.frames)
  end

  local monLines = {}
  for i, tmpl in ipairs(wins) do
    monLines[#monLines + 1] = string.format(
      "    [%d] = { frame1 = { w = %d, h = %d }, frame2 = { w = %d, h = %d } },", i - 1,
      tmpl[2].width * 8, tmpl[2].height * 8, tmpl[3].width * 8, tmpl[3].height * 8)
  end
  put("manifest.lua", table.concat({
    "return {",
    string.format("  format_version = %d,", CreditsExtract.FORMAT_VERSION),
    string.format("  screen = { w = %d, h = %d },", SCREEN_W, SCREEN_H),
    string.format("  circle = { w = %d, h = %d },", circleSize, circleSize),
    "  sheets = {",
    table.concat(sheets, "\n"),
    "  },",
    "  mons = {",
    table.concat(monLines, "\n"),
    "  },",
    "}",
    "",
  }, "\n"))

  print(string.format("[credits_extract] staff roll, closing screens and scene art -> %s", root))
  return { root = root }
end

function CreditsExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. CreditsExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs(CreditsExtract.FILES) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return CreditsExtract
