-- Yellow's boot attract movie, a faithful port of PlayIntroScene
-- (pokeyellow engine/movie/intro_yellow.asm) over the extracted atlases
-- (gfx/intro/yellow_intro_1.2bpp -> intro/yellow_intro_1.png, atlas1,
-- 16x8 tiles; yellow_intro_2.2bpp -> yellow_intro_2.png, atlas2, 16x16
-- tiles; clouds.2bpp -> intro/clouds.png, two 4-tile frames).
--
-- Faithful pieces: the 18-scene jumptable with its 128/88-frame timers,
-- the animated-object system (YellowIntro_AnimatedObjectSpawnStateData /
-- Jumptable / FramesData / OAMData, data/sprite_anims/intro_frames.asm +
-- intro_oam.asm), the scene-7 per-scanline SCY sine wave
-- (YellowIntro_Copy8BitSineWave, +-4px period 32, rotated 1 line/frame),
-- the scene-3 SCX ramp to $68, the scene-11 cloud tile flip every 8
-- frames, and the scene-14/15/16 BGP strobe / fade sequences
-- (YellowIntroPalSequence_f9dd6 / _f9e0a).  BGP composes with the SGB
-- colorization through sgbPalettes (PalPacket_Generic = MEWMON,
-- PalPacket_PikachusBeach = PIKACHUS_BEACH), like the title screen.
--
-- Deliberately dropped: the CGB-only OBJ-palette pokes of scenes 7/11
-- (Func_f98a2 / Func_f98cb recolor 5-6 tiles of the surf/fly sprite),
-- OBP-vs-BGP divergence during the strobes (one whole-screen shade map
-- stands in for both), and the never-spawned objects $0/$4 (dead code,
-- intro_yellow.asm:173).
--
-- Any of A/B/START skips the whole movie (PlayIntroScene:16-19).  Pops
-- itself and calls onDone() when finished or skipped.

local Music = require("src.core.Music")

local YellowIntro = {}
YellowIntro.__index = YellowIntro
YellowIntro.isOpaque = true

-- ------- data tables (data/sprite_anims/intro_oam.asm) ----------------

-- OAM lists: rows of { dy, dx, tileDelta, flip }
local function grid(rows, cols, dy0, dx0, tileForRC)
  local list = {}
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      list[#list + 1] = { dy0 + r * 8, dx0 + c * 8, tileForRC(r, c), false }
    end
  end
  return list
end

local OAM = {}

-- Unkn_fa17e: 2x2, tiles +0/+1 over +$10/+$11
OAM.fa17e = grid(2, 2, -8, -8, function(r, c) return r * 0x10 + c end)

-- Unkn_fa18f: 16x32; bottom two rows mirror their left half
OAM.fa18f = {
  { -16, -8, 0x00 }, { -16, 0, 0x01 },
  { -8, -8, 0x10 }, { -8, 0, 0x11 },
  { 0, -8, 0x20 }, { 0, 0, 0x20, true },
  { 8, -8, 0x21 }, { 8, 0, 0x21, true },
}

-- Unkn_fa1b0: 32x40 (16-wide head rows, 32-wide mirrored body rows)
OAM.fa1b0 = {
  { -24, -8, 0x00 }, { -24, 0, 0x01 },
  { -16, -8, 0x02 }, { -16, 0, 0x03 },
  { -8, -16, 0x04 }, { -8, -8, 0x05 }, { -8, 0, 0x06 }, { -8, 8, 0x04, true },
  { 0, -16, 0x07 }, { 0, -8, 0x08 }, { 0, 0, 0x08, true }, { 0, 8, 0x07, true },
  { 8, -16, 0x09 }, { 8, -8, 0x0a }, { 8, 0, 0x0a, true }, { 8, 8, 0x09, true },
  { 16, -16, 0x0b }, { 16, -8, 0x0c }, { 16, 0, 0x0c, true }, { 16, 8, 0x0b, true },
}

-- Unkn_fa201: 6x6 = 48x48, row r uses tiles +$r0..+$r5
OAM.fa201 = grid(6, 6, -24, -24, function(r, c) return r * 0x10 + c end)

-- Unkn_fa292: 5x5 = 40x40, row bases $00,$05,$10,$15,$20
local FA292_ROW = { 0x00, 0x05, 0x10, 0x15, 0x20 }
OAM.fa292 = {}
for r = 0, 4 do
  for c = 0, 4 do
    OAM.fa292[#OAM.fa292 + 1] =
      { -20 + r * 8, -16 + c * 8, FA292_ROW[r + 1] + c, false }
  end
end

-- Unkn_fa2f7: 32x8 mirrored streak
OAM.fa2f7 = {
  { -4, -16, 0x00 }, { -4, -8, 0x01 },
  { -4, 0, 0x01, true }, { -4, 8, 0x00, true },
}

-- Unkn_fa308: two mirrored 16x16 clusters, 32px apart
OAM.fa308 = {
  { -8, -24, 0x00 }, { -8, -16, 0x01 },
  { 0, -24, 0x02 }, { 0, -16, 0x03 },
  { -8, 8, 0x01, true }, { -8, 16, 0x00, true },
  { 0, 8, 0x03, true }, { 0, 16, 0x02, true },
}

-- Unkn_fa329: two mirrored 24x16 clusters
OAM.fa329 = {
  { -8, -40, 0x00 }, { -8, -32, 0x01 }, { -8, -24, 0x02 },
  { 0, -40, 0x10 }, { 0, -32, 0x11 }, { 0, -24, 0x12 },
  { -8, 16, 0x02, true }, { -8, 24, 0x01, true }, { -8, 32, 0x00, true },
  { 0, 16, 0x12, true }, { 0, 24, 0x11, true }, { 0, 32, 0x10, true },
}

-- frameId -> { atlas2 tile offset, OAM list }
local FRAMES = {
  [0x01] = { 0x96, OAM.fa17e }, [0x02] = { 0x98, OAM.fa17e },
  [0x03] = { 0x9a, OAM.fa17e },
  [0x04] = { 0x0c, OAM.fa18f }, [0x05] = { 0x0e, OAM.fa18f },
  [0x06] = { 0x3c, OAM.fa18f },
  [0x07] = { 0x60, OAM.fa1b0 }, [0x08] = { 0x70, OAM.fa1b0 },
  [0x09] = { 0x80, OAM.fa1b0 },
  [0x0a] = { 0x90, OAM.fa201 }, [0x0b] = { 0x00, OAM.fa201 },
  [0x0c] = { 0x06, OAM.fa201 },
  [0x0d] = { 0xc6, OAM.fa292 },
  [0x0e] = { 0x6d, OAM.fa2f7 },
  [0x0f] = { 0xf0, OAM.fa308 }, [0x10] = { 0xf4, OAM.fa308 },
  [0x11] = { 0xf8, OAM.fa308 },
  [0x12] = { 0x9c, OAM.fa329 }, [0x13] = { 0xec, OAM.fa329 },
}

-- frame scripts (intro_frames.asm): { {frameId, duration}, ..., loop=bool }
local FRAMESETS = {
  [1] = { { 0x01, 4 }, { 0x02, 4 }, { 0x03, 4 }, loop = true },
  [2] = { { 0x04, 4 }, { 0x05, 4 }, { 0x06, 4 }, loop = true },
  [3] = { { 0x07, 4 }, { 0x08, 4 }, { 0x09, 4 }, loop = true },
  [5] = { { 0x0b, 32 } },
  [6] = { { 0x0c, 32 } },
  [7] = { { 0x0d, 32 } },
  [8] = { { 0x0e, 32 } },
  [9] = { { 0x0f, 31 }, { 0x11, 2 }, { 0x0f, 2 }, { 0x11, 2 },
          { 0x0f, 31 }, { 0x11, 2 }, { 0x0f, 23 }, { 0x10, 32 } },
  [10] = { { 0x12, 4 }, { 0x13, 4 }, loop = true },
}

-- object id -> { frameset, seq } (YellowIntro_AnimatedObjectSpawnStateData;
-- seq indexes the movement jumptable)
local SPAWN = {
  [1] = { 1, "static" }, [2] = { 2, "static" }, [3] = { 3, "static" },
  [5] = { 5, "surf" }, [6] = { 6, "fly" }, [7] = { 7, "static" },
  [8] = { 8, "bar" }, [9] = { 9, "static" }, [10] = { 10, "static" },
}

-- speed-bar spawn rows (YellowIntroFlyingSpeedBarData; first byte is X --
-- the source's "; y, x, speed" comment is wrong)
local SPEED_BARS = {
  { 0xD0, 0x20, 2 }, { 0xF0, 0x30, 4 }, { 0xD0, 0x40, 6 },
  { 0xC0, 0x50, 8 }, { 0xE0, 0x60, 8 }, { 0xC0, 0x70, 6 },
  { 0xE0, 0x80, 4 }, { 0xF0, 0x90, 2 },
}

-- PlayIntroScene's .loop (pokeyellow engine/movie/intro_yellow.asm) ends
-- every iteration with its own `call DelayFrame`, so one scene handler costs
-- one frame plus whatever DelayFrame calls it makes itself.  The port runs a
-- handler inside a single update() tick, so every one of those internal
-- DelayFrame calls has to be spent explicitly or the movie runs short of
-- hardware.  Three places owe frames:
--
--   SETUP_SCENE_DELAY  scenes 2/4/6/8/10/12 open with
--                      YellowIntro_BlankPalsDelay2AndDisableLCD: rBGP/rOBP0/
--                      rOBP1 to $00 (color 0 in every shade -- the lightest,
--                      white on DMG), two DelayFrame calls, then DisableLCD.
--                      Two internal plus the loop's own is a 3-frame
--                      iteration, after which the next wait scene takes its
--                      first timer decrement.  Func_f9e9a restores rBGP $e4
--                      at the end of the same handler.
--   HEAD_FRAMES        PlayIntroScene spends a DelayFrame between
--                      InitYellowIntroGFXAndMusic (which ends in PlayMusic)
--                      and the first .loop pass, and YellowIntroScene0 then
--                      owns a whole iteration of its own.
--   EXIT_FRAMES        .go_to_title_screen blanks the palettes and spends
--                      four DelayFrame calls clearing the tilemap and OAM
--                      before the title screen is built.
--
-- These restore the movie's real elapsed length; they do NOT lengthen the
-- intro song.  title.asm's StopAllMusic before MUSIC_TITLE_SCREEN is
-- unconditional (only PikachuCry1 is waited on), so hardware cuts
-- Music_YellowIntro off mid-phrase too (#523).
local SETUP_SCENE_DELAY = 3
local HEAD_FRAMES = 2
local EXIT_FRAMES = 4

-- scene-6 sine (YellowIntro_Copy8BitSineWave.SineWave), signed SCY deltas
local WAVE = { 0, 0, 1, 2, 2, 3, 3, 3, 4, 3, 3, 3, 2, 2, 1, 0,
               0, 0, -1, -2, -2, -3, -3, -3, -4, -3, -3, -3, -2, -2, -1, 0 }

-- scene-10 BG tilemaps (gfx/intro/unknown_f9b6e/f9be6/f9bf2.tilemap)
local SKY_MAP = {
  { 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x60,0x61,0x62 },
  { 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x62,0x00,0x00,0x00 },
  { 0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x62,0x00,0x00,0x00,0x00 },
  { 0x60,0x61,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x02,0x62,0x00,0x00,0x00,0x00,0x00 },
  { 0x00,0x00,0x63,0x60,0x61,0x60,0x61,0x02,0x02,0x02,0x02,0x60,0x61,0x62,0x00,0x00,0x00,0x00,0x00,0x00 },
  { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x63,0x62,0x63,0x62,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 },
}
local BADGE_MAP = {
  { 0x30, 0x31, 0x32, 0x33 }, { 0x40, 0x41, 0x42, 0x43 },
  { 0x50, 0x51, 0x52, 0x53 },
}
local MARK_MAP = { { 0x12, 0x13 }, { 0x22, 0x23 } }

-- scene-14 strobe (YellowIntroPalSequence_f9dd6): 13 groups of
-- $e4,$c0,$c0,$e4 with the 52nd byte replaced by the terminator
local STROBE_SEQ = {}
for i = 1, 51 do
  local m = (i - 1) % 4
  STROBE_SEQ[i] = (m == 1 or m == 2) and 0xC0 or 0xE4
end
-- scene-16 fade to white (YellowIntroPalSequence_f9e0a)
local FADE_SEQ = { 0xE4, 0x90, 0x90, 0x40, 0x40, 0x00, 0x00 }

-- Func_fa079's sine bob (Unkn_fa0aa, sine_table 32).  The ROM table's
-- `dw sin(x)` truncates the 1.0 peak to $0000, which pops the sprite 8px
-- for one frame at every crest (a=16 / a=48) on hardware; the true peak
-- is restored here so the balloon glide loops smoothly.
local function bobOffset(phase)
  local a = phase % 64
  local half = a % 32
  local v = math.floor(8 * math.sin(math.pi * half / 32))
  return a < 32 and v or -v
end

local function tryImage(path)
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

-- ------- state --------------------------------------------------------

function YellowIntro.new(game, onDone)
  local self = setmetatable({}, YellowIntro)
  self.game = game
  self.onDone = onDone
  self.finished = false
  self.scene = 0
  self.timer = 0
  self.seqIndex = 0
  self.scx = 0
  self.bgp = 0xE4
  self.palName = "MEWMON" -- PalPacket_Generic
  self.objects = {}
  self.cloudFrame = 0
  self.pendingThen = nil  -- what enterDelay runs once pendingDelay hits 0 (#523)
  self.pendingDelay = 0

  self.atlas1 = tryImage("assets/generated/intro/yellow_intro_1.png")
  self.atlas2 = tryImage("assets/generated/intro/yellow_intro_2.png")
  self.clouds = tryImage("assets/generated/intro/clouds.png")
  self.quads = {}

  -- 32x32 BG tile grid (vBGMap0); signed addressing: id < $80 -> atlas1,
  -- id >= $80 -> atlas2 (LCDC $e3, bit4 = 0)
  self.bg = {}
  self:bgLetterbox()
  self.bgDirty = true
  self.wave = nil
  local ok, canvas = pcall(love.graphics.newCanvas, 256, 256)
  self.bgCanvas = ok and canvas or nil

  -- intro.asm:311 copyright card, splash.asm:29 shooting star
  local IntroMovie = require("src.ui.IntroMovie")
  local pre = IntroMovie.new(game, nil)
  local baseStart = pre.startPhase
  pre.finish = function(m)
    if m.finished then return end
    m.finished = true
    self.pre = nil
    self:finish()
  end
  pre.startPhase = function(m, phase)
    if phase == 3 then
      m.finished = true
      self.pre = nil
      self:beginScenes()
    else
      baseStart(m, phase)
    end
  end
  self.pre = pre
  return self
end

function YellowIntro:sgbPalettes(game)
  if self.pre then return self.pre:sgbPalettes(game) end
  local P = require("src.render.PaletteFX")
  local pal = P.pal(game.data, self.palName)
  if not pal then return nil end
  -- rBGP composed with the SGB colors: shade i displays palette color
  -- ((bgp >> 2i) & 3), whole screen (one map stands in for BGP and OBP)
  local bgp = self.bgp
  local map = {}
  for i = 0, 3 do
    map[i] = math.floor(bgp / 4 ^ i) % 4
  end
  return { P.whole(P.permute(pal, map)) }
end

-- ------- BG helpers ---------------------------------------------------

function YellowIntro:bgFill(id)
  for y = 0, 31 do
    local row = self.bg[y] or {}
    self.bg[y] = row
    for x = 0, 31 do row[x] = id end
  end
  self.bgDirty = true
end

-- Func_f9e5f: rows 0-3 / 14-17 tile $01, rows 4-13 tile $00
function YellowIntro:bgLetterbox()
  self:bgFill(0x01)
  for y = 4, 13 do
    for x = 0, 31 do self.bg[y][x] = 0x00 end
  end
  for y = 18, 31 do
    for x = 0, 31 do self.bg[y][x] = 0x00 end
  end
  self.bgDirty = true
end

function YellowIntro:bgBlit(col, row, map)
  for r, line in ipairs(map) do
    for c, id in ipairs(line) do
      self.bg[(row + r - 1) % 32][(col + c - 1) % 32] = id
    end
  end
  self.bgDirty = true
end

function YellowIntro:quadFor(image, tile)
  local key = image
  local cacheByImage = self.quads[key]
  if not cacheByImage then
    cacheByImage = {}
    self.quads[key] = cacheByImage
  end
  local quad = cacheByImage[tile]
  if not quad then
    local iw, ih = image:getDimensions()
    quad = love.graphics.newQuad(
      (tile % 16) * 8, math.floor(tile / 16) * 8, 8, 8, iw, ih)
    cacheByImage[tile] = quad
  end
  return quad
end

function YellowIntro:rebuildBgCanvas()
  if not self.bgCanvas then return end
  love.graphics.push("all")
  love.graphics.setCanvas(self.bgCanvas)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  for y = 0, 31 do
    for x = 0, 31 do
      local id = self.bg[y][x]
      local image, tile
      if id < 0x80 then
        image, tile = self.atlas1, id
      else
        image, tile = self.atlas2, id
      end
      if image then
        -- scene-11 cloud animation retargets BG tiles $60-$63 at the
        -- clouds sheet (VBlank copy to $9600); frame = clouds row 0/1
        if self.clouds and id >= 0x60 and id <= 0x63 then
          local cw, ch = self.clouds:getDimensions()
          love.graphics.draw(self.clouds,
            love.graphics.newQuad((id - 0x60) * 8, self.cloudFrame * 8,
              8, 8, cw, ch), x * 8, y * 8)
        else
          love.graphics.draw(image, self:quadFor(image, tile), x * 8, y * 8)
        end
      end
    end
  end
  love.graphics.pop()
  self.bgDirty = false
end

-- ------- objects ------------------------------------------------------

function YellowIntro:spawn(id, x, y)
  local spec = SPAWN[id]
  local obj = {
    id = id, frameset = spec[1], seq = spec[2],
    x = x, y = y, xoff = 0, yoff = 0,
    step = 1, wait = 0, held = false,
    fieldB = 0, fieldC = 0,
  }
  local script = FRAMESETS[obj.frameset]
  obj.wait = script[1][2]
  self.objects[#self.objects + 1] = obj
  return obj
end

function YellowIntro:clearObjects()
  self.objects = {}
end

local function updateFrameScript(obj)
  if obj.held then return end
  obj.wait = obj.wait - 1
  if obj.wait > 0 then return end
  local script = FRAMESETS[obj.frameset]
  if obj.step >= #script then
    if script.loop then
      obj.step = 1
      obj.wait = script[1][2]
    else
      obj.held = true -- endanim: hold last frame forever
    end
    return
  end
  obj.step = obj.step + 1
  obj.wait = script[obj.step][2]
end

function YellowIntro:updateObjects()
  for _, obj in ipairs(self.objects) do
    if obj.seq == "bar" then
      -- Func_fa062: constant velocity, 8-bit wrap
      obj.x = (obj.x + obj.fieldB) % 256
    elseif obj.seq == "surf" then
      -- Func_fa014, including the original's Y = X + 1 quirk: the
      -- comparison register still holds X when Y is written, so the
      -- sprite rides a 45-degree diagonal until X parks at $58
      if obj.x ~= 0x58 then
        obj.x = (obj.x + 4) % 256
        obj.y = (obj.x + 1) % 256
      end
    elseif obj.seq == "fly" then
      -- Func_fa02b: rise 2px/frame to Y=$58, then a +-8px sine bob
      -- with a 64-frame period (and the truncated-peak notch)
      if obj.fieldB == 0 then
        if obj.y ~= 0x58 then
          obj.y = (obj.y - 2) % 256
        else
          obj.fieldB = 1
        end
      end
      if obj.fieldB == 1 then
        obj.yoff = bobOffset(obj.fieldC)
        obj.fieldC = obj.fieldC + 1
      end
    end
    updateFrameScript(obj)
  end
end

function YellowIntro:drawObjects()
  if not self.atlas2 then return end
  for _, obj in ipairs(self.objects) do
    local frameId = FRAMESETS[obj.frameset][obj.step][1]
    local frame = FRAMES[frameId]
    if frame then
      local base, list = frame[1], frame[2]
      for _, entry in ipairs(list) do
        local dy, dx, delta, flip = entry[1], entry[2], entry[3], entry[4]
        -- OAM position: screen = (X + dx - 8, Y + dy - 16)
        local px = (obj.x + obj.xoff + dx - 8) % 256
        local py = (obj.y + obj.yoff + dy - 16) % 256
        if px < 160 and py < 144 then
          local quad = self:quadFor(self.atlas2, base + delta)
          if flip then
            love.graphics.draw(self.atlas2, quad, px + 8, py, 0, -1, 1)
          else
            love.graphics.draw(self.atlas2, quad, px, py)
          end
        end
      end
    end
  end
end

-- ------- scenes -------------------------------------------------------

-- setup scenes run once and advance immediately; wait scenes count their
-- timer down (YellowIntro_CheckFrameTimerDecrement: N running frames,
-- expiry actions on frame N+1)
function YellowIntro:startScene(scene)
  self.scene = scene
  local t = self
  if scene == 0 then
    -- running pika 1 over the boot letterbox
    t.palName = "MEWMON"
    t.scx = 0
    t:bgLetterbox()
    t:spawn(1, 0x58, 0x58)
    t.timer = 130
    t.scene = 1
  elseif scene == 2 then
    -- pikachu kick: 6x6 atlas2 block parked at BG col 20 row 6 (scrolled
    -- in by scene 3) + 8 speed bars
    t:bgFill(0x00)
    local block = {}
    for r = 0, 5 do
      local line = {}
      for c = 0, 5 do line[c + 1] = 0x90 + r * 0x10 + c end
      block[r + 1] = line
    end
    t:bgBlit(20, 6, block)
    for _, bar in ipairs(SPEED_BARS) do
      local obj = t:spawn(8, bar[1], bar[2])
      obj.fieldB = bar[3]
    end
    t.palName = "PIKACHUS_BEACH"
    t.timer = 128
    t.scene = 3
  elseif scene == 4 then
    -- running pika 2
    t:clearObjects()
    t.scx = 0
    t:bgLetterbox()
    t:spawn(2, 0x58, 0x58)
    t.palName = "MEWMON"
    t.timer = 128
    t.scene = 5
  elseif scene == 6 then
    -- surfing pika over the wavy sea (per-scanline SCY sine)
    t.scx = 0
    t.wave = {}
    for i = 0, 255 do t.wave[i] = WAVE[i % 32 + 1] end
    t:bgFill(0x10)
    for y = 0, 2 do
      for x = 0, 31 do t.bg[y][x] = 0x00 end
    end
    for x = 0, 31 do t.bg[3][x] = x % 2 == 0 and 0x20 or 0x21 end
    t:spawn(5, 0xF8, 0x40)
    t.palName = "PIKACHUS_BEACH"
    t.bgDirty = true
    t.timer = 88
    t.scene = 7
  elseif scene == 8 then
    -- running pika 3
    t:clearObjects()
    t.wave = nil
    t.scx = 0
    t:bgLetterbox()
    t:spawn(3, 0x58, 0x58)
    t.palName = "MEWMON"
    t.timer = 128
    t.scene = 9
  elseif scene == 10 then
    -- flying pika over clouds + badge + mark
    t:clearObjects()
    t.scx = 0
    t:bgFill(0x00)
    for y = 0, 7 do
      for x = 0, 31 do t.bg[y][x] = 0x02 end
    end
    t:bgBlit(0, 8, SKY_MAP)
    t:bgBlit(12, 4, BADGE_MAP)
    t:bgBlit(3, 7, MARK_MAP)
    t:spawn(6, 0x58, 0x98)
    t.palName = "PIKACHUS_BEACH"
    t.timer = 128
    t.scene = 11
  elseif scene == 12 then
    -- pika close-up: 12x8 atlas1 paste at BG (5,6) + fixups
    t:clearObjects()
    t.scx = 0
    t:bgLetterbox()
    local paste = {}
    for r = 0, 7 do
      local line = {}
      for c = 0, 11 do line[c + 1] = 0x04 + r * 0x10 + c end
      paste[r + 1] = line
    end
    t:bgBlit(5, 6, paste)
    t.bg[6][4] = 0x03
    t.bg[7][4] = 0x74
    t.bg[13][5] = 0x00
    t:spawn(9, 0x58, 0x60)
    t.palName = "MEWMON"
    t.timer = 128
    t.scene = 13
  elseif scene == 14 then
    -- thunderbolt strobe; timer reused as the sequence index
    t.seqIndex = 0
    t.scene = 14
  elseif scene == 15 then
    t.timer = 40
    t.scene = 15
  elseif scene == 16 then
    t.seqIndex = 0
    t.scene = 16
  elseif scene == 17 then
    t.timer = 64
    t.scene = 17
  end
end

-- Spend `frames` real frames, then run fn: the port's stand-in for the
-- DelayFrame calls a pokeyellow scene handler makes inside its own
-- PlayIntroScene .loop iteration (#523).  fn may be nil to just burn time.
function YellowIntro:enterDelay(frames, fn)
  self.pendingDelay = frames
  self.pendingThen = fn
end

-- YellowIntro_BlankPalsDelay2AndDisableLCD blanks the palettes for the
-- delay; Func_f9e9a puts rBGP back to $e4 at the tail of the same handler.
function YellowIntro:enterSetupScene(scene)
  self.bgp = 0x00
  self:enterDelay(SETUP_SCENE_DELAY, function()
    self.bgp = 0xE4
    self:startScene(scene)
  end)
end

function YellowIntro:enter()
  if self.pre then return end -- pre-roll first; beginScenes takes over
  self:beginScenes()
end

-- InitYellowIntroGFXAndMusic: the movie's own music starts with scene 0
function YellowIntro:beginScenes()
  local data = self.game.data
  local songs = data.audio and data.audio.songs
  local song = songs and (songs.Music_YellowIntro and "Music_YellowIntro"
                          or songs.Music_IntroBattle and "Music_IntroBattle")
  if song then pcall(Music.play, data, song, false) end
  -- HEAD_FRAMES: the DelayFrame between PlayMusic and the first .loop pass
  -- plus YellowIntroScene0's own iteration.  new() already laid down the
  -- Func_f9e5f letterbox that InitYellowIntroGFXAndMusic writes, so these
  -- frames show what hardware shows: the letterbox with no pika yet.
  self:enterDelay(HEAD_FRAMES, function() self:startScene(0) end)
end

-- The movie's exit never stops the song (intro_yellow.asm PlayIntroScene
-- .go_to_title_screen, where the A/B/START skip lands too): Music_YellowIntro
-- outlasts the scenes and plays on into the title setup until title.asm's
-- StopAllMusic before MUSIC_TITLE_SCREEN, which TitleState:startMusic stands
-- in for (#436)
function YellowIntro:finish()
  if self.finished then return end
  self.finished = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- Both scene-loop exits (scene 17 running out, and the A/B/START skip) land
-- on .go_to_title_screen, which calls YellowIntro_BlankPalettes and then
-- spends EXIT_FRAMES DelayFrame calls clearing the tilemap and the OAM
-- buffers before the title screen is built (#523).  A press during the
-- pre-roll splash starts the scenes instead of reaching here.
function YellowIntro:exitToTitle()
  if self.finished or self.exiting then return end
  self.exiting = true
  self.bgp = 0x00
  self:clearObjects()
  self:enterDelay(EXIT_FRAMES, function() self:finish() end)
end

function YellowIntro:update(dt)
  if self.finished then return end
  if self.pre then
    self.pre:update(dt)
    return
  end
  -- Ahead of the skip poll on purpose: JoypadLowSensitivity runs once at the
  -- top of each .loop iteration, never inside a handler, so hardware is deaf
  -- for the DelayFrame calls these ticks stand in for (#523).
  if self.pendingDelay > 0 then
    self.pendingDelay = self.pendingDelay - 1
    if self.pendingDelay == 0 then
      local fn = self.pendingThen
      self.pendingThen = nil
      if fn then fn() end
    end
    self:updateObjects()
    if self.bgDirty then self:rebuildBgCanvas() end
    return
  end

  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    self:exitToTitle()
    return
  end

  local scene = self.scene
  if scene == 1 or scene == 5 or scene == 9 then
    if self.timer > 0 then
      self.timer = self.timer - 1
    else
      self:clearObjects()
      self:enterSetupScene(scene + 1) -- BlankPalsDelay2AndDisableLCD (#523)
    end
  elseif scene == 3 then
    if self.timer > 0 then
      self.timer = self.timer - 1
      if self.scx ~= 0x68 then self.scx = self.scx + 4 end
    else
      self:clearObjects()
      self:enterSetupScene(4) -- BlankPalsDelay2AndDisableLCD (#523)
    end
  elseif scene == 7 then
    if self.timer > 0 then
      self.timer = self.timer - 1
      self.scx = (self.scx + 2) % 256
      -- rotate the sine phase 1 scanline per frame
      local first = self.wave[0]
      for i = 0, 254 do self.wave[i] = self.wave[i + 1] end
      self.wave[255] = first
    else
      self:clearObjects()
      self:enterSetupScene(8) -- BlankPalsDelay2AndDisableLCD (#523)
    end
  elseif scene == 11 then
    if self.timer > 0 then
      -- cloud tiles swap every 8 frames (YellowIntroScene11)
      if self.timer % 8 == 0 then
        local frame = math.floor(self.timer / 8) % 2
        if frame ~= self.cloudFrame then
          self.cloudFrame = frame
          self.bgDirty = true
        end
      end
      self.timer = self.timer - 1
    else
      self:clearObjects()
      self:enterSetupScene(12) -- BlankPalsDelay2AndDisableLCD (#523)
    end
  elseif scene == 13 then
    if self.timer > 0 then
      self.timer = self.timer - 1
    else
      -- spawn the thunderbolt over the close-up (object $A stays with $9)
      self:spawn(10, 0x58, 0x68)
      self:startScene(14)
    end
  elseif scene == 14 then
    self.seqIndex = self.seqIndex + 1
    local v = STROBE_SEQ[self.seqIndex]
    if v then
      self.bgp = v
    else
      -- .expired: everything despawns and the letterbox returns, then the
      -- handler spends three DelayFrame calls with hAutoBGTransferEnabled
      -- pushing that rebuilt tilemap to VRAM before it restores rBGP $e4
      -- and spawns the logo/face object $7 for the strobe scene (#523).
      self:clearObjects()
      self:bgLetterbox()
      self:enterDelay(3, function()
        self.bgp = 0xE4
        self:spawn(7, 0x58, 0x58)
        self:startScene(15)
      end)
    end
  elseif scene == 15 then
    if self.timer > 0 then
      if self.timer % 4 == 0 then
        -- rBGP ^= $03: flips how the two lightest shades display
        self.bgp = self.bgp == 0xE4 and 0xE7 or 0xE4
      end
      self.timer = self.timer - 1
    else
      self.bgp = 0xE4
      self:startScene(16)
    end
  elseif scene == 16 then
    self.seqIndex = self.seqIndex + 1
    local v = FADE_SEQ[self.seqIndex]
    if v then
      self.bgp = v
    else
      self:startScene(17)
    end
  elseif scene == 17 then
    if self.timer > 0 then
      self.timer = self.timer - 1
    else
      self:exitToTitle()
      return
    end
  end

  self:updateObjects()
  if self.bgDirty then self:rebuildBgCanvas() end
end

function YellowIntro:draw()
  if self.pre then
    self.pre:draw()
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if self.bgCanvas then
    if self.wave then
      -- per-scanline SCY override, LY $10-$7F only (scene 7's VBlank
      -- copy covers just that band; the rest render unshifted).  Each
      -- strip wraps horizontally like the BG map: SCX climbs past 96
      -- during the scene and a single quad would clamp at the canvas
      -- edge and smear the right of the screen.
      local cw, ch = self.bgCanvas:getDimensions()
      local sx = self.scx % 256
      local w1 = math.min(160, 256 - sx)
      for ly = 0, 143 do
        local dy = (ly >= 16 and ly < 128) and self.wave[ly] or 0
        local sy = (ly + dy) % 256
        love.graphics.draw(self.bgCanvas,
          love.graphics.newQuad(sx, sy, w1, 1, cw, ch), 0, ly)
        if w1 < 160 then
          love.graphics.draw(self.bgCanvas,
            love.graphics.newQuad(0, sy, 160 - w1, 1, cw, ch), w1, ly)
        end
      end
    else
      local cw, ch = self.bgCanvas:getDimensions()
      local sx = self.scx % 256
      love.graphics.draw(self.bgCanvas,
        love.graphics.newQuad(sx, 0, math.min(160, 256 - sx), 144, cw, ch),
        0, 0)
      if sx > 96 then
        -- horizontal wrap (scene 3 scrolls the kick block in from col 20)
        love.graphics.draw(self.bgCanvas,
          love.graphics.newQuad(0, 0, 160 - (256 - sx), 144, cw, ch),
          256 - sx, 0)
      end
    end
  end
  self:drawObjects()
  love.graphics.setColor(1, 1, 1, 1)
end

return YellowIntro
