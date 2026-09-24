local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BallOpenExtract = {}

BallOpenExtract.FORMAT_VERSION = 2
BallOpenExtract.CACHE_SUB = "pokemon/battle/ball_open"
BallOpenExtract.BALL_COUNT = 12
BallOpenExtract.TAG_PARTICLES_POKEBALL = 55020
BallOpenExtract.TAG_POKE_BALL = 55000
BallOpenExtract.SINE_COUNT = 320
BallOpenExtract.BALL_SHEET_BYTES = 384
BallOpenExtract.BALL_SHEET = "balls.rgba"
BallOpenExtract.BALL_SHEET_W = 16 * 12
BallOpenExtract.BALL_SHEET_H = 48
-- pokefirered/src/pokeball.c:1310
BallOpenExtract.NO_OPEN_SPLICE = { [6] = true, [10] = true, [11] = true }

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

function BallOpenExtract.spliceOpenFrame(gfx, openGfx)
  local out = {}
  for i = 1, BallOpenExtract.BALL_SHEET_BYTES do out[i] = gfx[i] or 0 end
  for i = 1, 128 do out[256 + i] = openGfx[i] or 0 end
  return out
end

function BallOpenExtract.bakeBallStrip(sheets, pals)
  local W, H = BallOpenExtract.BALL_SHEET_W, BallOpenExtract.BALL_SHEET_H
  local pixels = {}
  local clear = string.char(0, 0, 0, 0)
  for i = 1, W * H do pixels[i] = clear end
  for ball = 0, BallOpenExtract.BALL_COUNT - 1 do
    local gfx, pal = sheets[ball], pals[ball]
    for ti = 0, 11 do
      local frame, sub = math.floor(ti / 4), ti % 4
      local ox = ball * 16 + (sub % 2) * 8
      local oy = frame * 16 + math.floor(sub / 2) * 8
      for row = 0, 7 do
        for bx = 0, 3 do
          local byte = gfx[ti * 32 + row * 4 + bx + 1] or 0
          for n = 0, 1 do
            local idx = (n == 0) and (byte % 16) or math.floor(byte / 16)
            if idx ~= 0 then
              local c = (pal[idx * 2 + 1] or 0) + (pal[idx * 2 + 2] or 0) * 256
              local r, g, b = rgb555(c)
              pixels[(oy + row) * W + ox + bx * 2 + n + 1] = string.char(to8(r), to8(g), to8(b), 255)
            end
          end
        end
      end
    end
  end
  return table.concat(pixels), W, H
end

function BallOpenExtract.extractBalls(rom)
  local cfg = Versions.BALL_OPEN
  local function get(i) return rom:get(i) end
  -- pokefirered/src/pokeball.c:1316
  local openGfx = bytes_to_array(Lz77.decompress(get, cfg.open_ball_gfx))
  if #openGfx ~= 128 then error("ball_open: gOpenPokeballGfx size " .. #openGfx) end
  local sheets, pals = {}, {}
  for i = 0, BallOpenExtract.BALL_COUNT - 1 do
    -- pokefirered/src/pokeball.c:59
    local sbase = cfg.sprite_sheets + i * 8
    if rom:u16(sbase + 4) ~= BallOpenExtract.BALL_SHEET_BYTES
      or rom:u16(sbase + 6) ~= BallOpenExtract.TAG_POKE_BALL + i then
      error("ball_open: gBallSpriteSheets mismatch at entry " .. i)
    end
    -- pokefirered/src/pokeball.c:75
    local pbase = cfg.sprite_palettes + i * 8
    if rom:u16(pbase + 4) ~= BallOpenExtract.TAG_POKE_BALL + i then
      error("ball_open: gBallSpritePalettes mismatch at entry " .. i)
    end
    local gfx = bytes_to_array(Lz77.decompress(get, rom:ptrOffset(rom:u32(sbase))))
    if #gfx ~= BallOpenExtract.BALL_SHEET_BYTES then
      error("ball_open: ball sheet " .. i .. " size " .. #gfx)
    end
    if not BallOpenExtract.NO_OPEN_SPLICE[i] then
      gfx = BallOpenExtract.spliceOpenFrame(gfx, openGfx)
    end
    sheets[i] = gfx
    pals[i] = bytes_to_array(Lz77.decompress(get, rom:ptrOffset(rom:u32(pbase))))
  end
  return sheets, pals
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

  local ballSheets, ballPals = BallOpenExtract.extractBalls(rom)
  local ballRgba, ballW, ballH = BallOpenExtract.bakeBallStrip(ballSheets, ballPals)
  cache:write(root .. "/" .. BallOpenExtract.BALL_SHEET, ballRgba)

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
  ballSheet = %q,
  ballSheetW = %d, ballSheetH = %d,
  fadeColors = { %s },
  sine = { %s },
}
]], BallOpenExtract.FORMAT_VERSION, w, h, BallOpenExtract.BALL_SHEET, ballW, ballH,
    table.concat(colors, ", "), table.concat(sine, ", "))
  cache:write(root .. "/manifest.lua", manifest)
  return { root = root, w = w, h = h }
end

return BallOpenExtract
