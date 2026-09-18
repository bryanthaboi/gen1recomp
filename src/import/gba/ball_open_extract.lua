local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BallOpenExtract = {}

BallOpenExtract.FORMAT_VERSION = 1
BallOpenExtract.CACHE_SUB = "pokemon/battle/ball_open"
BallOpenExtract.BALL_COUNT = 12
BallOpenExtract.TAG_PARTICLES_POKEBALL = 55020
BallOpenExtract.SINE_COUNT = 320

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function bytes_to_array(tbl)
  if type(tbl) == "string" then
    local t = {}
    for i = 1, #tbl do t[i] = tbl:byte(i) end
    return t
  end
  if type(tbl) == "table" and tbl._ffi and tbl._len then
    local t = {}
    for i = 1, tbl._len do t[i] = tbl._ffi[i - 1] end
    return t
  end
  return tbl
end

local function rgb555(c)
  return c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
end

local function to8(v5)
  return math.floor(v5 * 255 / 31 + 0.5)
end

function BallOpenExtract.bakeSheet(gfx, palBytes)
  gfx = bytes_to_array(gfx)
  palBytes = bytes_to_array(palBytes)
  local tiles = math.floor(#gfx / 32)
  local w, h = tiles * 8, 8
  local pixels = {}
  for i = 1, w * h do pixels[i] = string.char(0, 0, 0, 0) end
  for ti = 0, tiles - 1 do
    for row = 0, 7 do
      for bx = 0, 3 do
        local byte = gfx[ti * 32 + row * 4 + bx + 1] or 0
        for n = 0, 1 do
          local idx = (n == 0) and (byte % 16) or math.floor(byte / 16)
          if idx ~= 0 then
            local c = (palBytes[idx * 2 + 1] or 0) + (palBytes[idx * 2 + 2] or 0) * 256
            local r, g, b = rgb555(c)
            pixels[row * w + ti * 8 + bx * 2 + n + 1] = string.char(to8(r), to8(g), to8(b), 255)
          end
        end
      end
    end
  end
  return table.concat(pixels), w, h
end

local function s16(v)
  if v >= 32768 then return v - 65536 end
  return v
end

function BallOpenExtract.run(rom, cache, opts)
  opts = opts or {}
  local cfg = Versions.BALL_OPEN
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. BallOpenExtract.CACHE_SUB
  local function get(i) return rom:get(i) end

  -- pokefirered/src/battle_anim_special.c:117
  local sheetPtr = rom:u32(cfg.particle_sheets)
  for i = 0, BallOpenExtract.BALL_COUNT - 1 do
    local base = cfg.particle_sheets + i * 8
    if rom:u32(base) ~= sheetPtr or rom:u16(base + 4) ~= 0x100
      or rom:u16(base + 6) ~= BallOpenExtract.TAG_PARTICLES_POKEBALL + i then
      error("ball_open: gBallParticleSpritesheets mismatch at entry " .. i)
    end
  end
  -- pokefirered/src/battle_anim_special.c:133
  local palPtr = rom:u32(cfg.particle_palettes)
  if rom:u16(cfg.particle_palettes + 4) ~= BallOpenExtract.TAG_PARTICLES_POKEBALL then
    error("ball_open: gBallParticlePalettes mismatch")
  end
  local gfx = Lz77.decompress(get, rom:ptrOffset(sheetPtr))
  local pal = Lz77.decompress(get, rom:ptrOffset(palPtr))
  local rgba, w, h = BallOpenExtract.bakeSheet(gfx, pal)
  cache:write(root .. "/particles.rgba", rgba)

  -- pokefirered/src/battle_anim_special.c:345
  local colors = {}
  for i = 0, BallOpenExtract.BALL_COUNT - 1 do
    local r, g, b = rgb555(rom:u16(cfg.fade_colors + i * 2))
    colors[#colors + 1] = string.format("{ %d, %d, %d }", r, g, b)
  end

  -- pokefirered/src/trig.c:4
  local sine = {}
  for i = 0, BallOpenExtract.SINE_COUNT - 1 do
    sine[#sine + 1] = tostring(s16(rom:u16(cfg.sine_table + i * 2)))
  end

  local manifest = string.format([[return {
  format = %d,
  sheet = "particles.rgba",
  sheetW = %d, sheetH = %d,
  frameW = 8, frameH = 8,
  fadeColors = { %s },
  sine = { %s },
}
]], BallOpenExtract.FORMAT_VERSION, w, h, table.concat(colors, ", "), table.concat(sine, ", "))
  cache:write(root .. "/manifest.lua", manifest)
  return { root = root, w = w, h = h }
end

return BallOpenExtract
