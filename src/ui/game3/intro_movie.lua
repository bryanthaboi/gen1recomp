local Display = require("src.core.game3.display")
local Audio = require("src.core.game3.audio")
local Bg = require("src.core.game3.bg")
local Oam = require("src.core.game3.oam")
local Pal = require("src.core.game3.pal_fade")
local Trig = require("src.core.game3.trig")

local IntroMovie = {}
IntroMovie.__index = IntroMovie

IntroMovie.GBA_HZ = 16777216 / 280896

local MUS_INTRO_FIGHT = 277
local MUS_GAME_FREAK = 321
local SPECIES_NIDORINO = 33

local BG_GF_TEXT_LOGO = 2
local BG_GF_BACKGROUND = 3
local BG_SCENE1_GRASS = 0
local BG_SCENE1_BACKGROUND = 1
local BG_SCENE2_PLANTS = 0
local BG_SCENE2_NIDORINO = 1
local BG_SCENE2_GENGAR = 2
local BG_SCENE2_BACKGROUND = 3
local BG_SCENE3_GENGAR = 0
local BG_SCENE3_BACKGROUND = 1

local OBJ_STAR, OBJ_SPARKLES, OBJ_GF = 0, 1, 2
local OBJ_GENGAR, OBJ_NIDORINO, OBJ_GRASS, OBJ_SWIPE, OBJ_DUST = 0, 1, 2, 3, 4

local ALL_BUT_0 = Pal.ALL - 1

local function idiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end

local function s16(v)
  v = v % 65536
  if v >= 32768 then v = v - 65536 end
  return v
end

local function mulU32(a, b)
  local aL, aH = a % 65536, math.floor(a / 65536) % 65536
  local bL, bH = b % 65536, math.floor(b / 65536) % 65536
  return (aL * bL + ((aL * bH + aH * bL) % 65536) * 65536) % 4294967296
end

local RAND_MULT = 1103515245

local function isoRandomize1(v)
  return (mulU32(v, RAND_MULT) + 24691) % 4294967296
end

------------------------------------------------------------------------
-- Sprite anim tables (pokefirered/src/intro.c:474)
------------------------------------------------------------------------

local ANIM_SPARKLE_LOOP, ANIM_SPARKLE_ONCE = 0, 1
local ANIMS_SPARKLES_SMALL = {
  [0] = { { img = 0, dur = 4 }, { img = 1, dur = 4 }, { img = 2, dur = 4 }, { img = 3, dur = 4 }, { jump = 0 } },
  [1] = { { img = 0, dur = 4 }, { img = 1, dur = 4 }, { img = 2, dur = 4 }, { img = 3, dur = 4 }, "end" },
}
-- pokefirered/src/intro.c:528
local ANIMS_SPARKLES_BIG = {
  [0] = { { img = 0, dur = 8 }, { img = 16, dur = 8 }, { img = 32, dur = 8 }, { img = 48, dur = 8 }, "end" },
}
local ANIM_NIDORINO_NORMAL, ANIM_NIDORINO_CRY, ANIM_NIDORINO_CROUCH, ANIM_NIDORINO_HOP, ANIM_NIDORINO_ATTACK = 0, 1, 2, 3, 4
-- pokefirered/src/intro.c:609
local ANIMS_NIDORINO = {
  [0] = { { img = 0, dur = 1 }, "end" },
  [1] = { { img = 64, dur = 1 }, "end" },
  [2] = { { img = 128, dur = 1 }, "end" },
  [3] = { { img = 192, dur = 1 }, "end" },
  [4] = { { img = 256, dur = 1 }, "end" },
}
-- pokefirered/src/intro.c:803
local ANIMS_SWIPE = {
  [0] = { { img = 0, dur = 8 }, { img = 32, dur = 4 }, "end" },
  [1] = { { img = 64, dur = 8 }, { img = 72, dur = 4 }, "end" },
}
-- pokefirered/src/intro.c:843
local ANIMS_RECOIL_DUST = {
  [0] = { { img = 0, dur = 10 }, { img = 4, dur = 10 }, { img = 8, dur = 10 }, { img = 12, dur = 8 }, "end" },
}
-- pokefirered/src/intro.c:647
local AFFINE_ZOOM = { { v = 256, dur = 0 }, { v = 32, dur = 8 }, "end" }

-- pokefirered/src/intro.c:436
local TEXT_SPARKLE_COORDS = {
  { 72, 80 }, { 136, 74 }, { 168, 80 }, { 120, 80 }, { 104, 86 },
  { 88, 74 }, { 184, 74 }, { 56, 86 }, { 152, 86 },
}

-- pokefirered/src/intro.c:414
local GENGAR_ZOOM_ANCHORS = { { 63, 63 }, { 0, 63 }, { 63, 0 }, { 0, 0 } }

------------------------------------------------------------------------
-- Asset helpers
------------------------------------------------------------------------

local function tileQuads(img, tileW, tileH, frameTiles, count, startTile)
  if not (img and love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = img:getDimensions()
  local sheetCols = iw / 8
  local quads = {}
  for i = 0, count - 1 do
    local t = (startTile or 0) + i * frameTiles
    local x = (t % sheetCols) * 8
    local y = math.floor(t / sheetCols) * 8
    quads[t] = love.graphics.newQuad(x, y, tileW * 8, tileH * 8, iw, ih)
  end
  return quads
end

local function relayoutTiles(img, startTile, wTiles, hTiles)
  if not (img and love and love.graphics and love.graphics.newCanvas) then return nil end
  local iw, ih = img:getDimensions()
  local sheetCols = iw / 8
  local canvas = love.graphics.newCanvas(wTiles * 8, hTiles * 8)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  local q = love.graphics.newQuad(0, 0, 8, 8, iw, ih)
  for ty = 0, hTiles - 1 do
    for tx = 0, wTiles - 1 do
      local t = startTile + ty * wTiles + tx
      q:setViewport((t % sheetCols) * 8, math.floor(t / sheetCols) * 8, 8, 8, iw, ih)
      love.graphics.draw(img, q, tx * 8, ty * 8)
    end
  end
  love.graphics.pop()
  return canvas
end

local function composeGfWindow(text, logo)
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  local canvas = love.graphics.newCanvas(Display.W, Display.H)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  -- pokefirered/src/intro.c:1251
  if logo then love.graphics.draw(logo, 104, 38) end
  -- pokefirered/src/intro.c:1127
  if text then love.graphics.draw(text, 48, 72) end
  love.graphics.pop()
  return canvas
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function IntroMovie.new(assets)
  local self = setmetatable({
    assets = assets or {},
    pal = Pal.new(),
    tasks = {},
    accum = 0,
    pendingSkip = false,
    phase = "copyright",
    state = 0,
    isDone = false,
    bgPal = {},
    win1 = nil,
    win0 = nil,
    bld = nil,
    frames = 0,
  }, IntroMovie)
  local A = self.assets
  if love and love.graphics and love.graphics.newQuad then
    self.q = {
      sparkSmall = tileQuads(A.introSparklesSmall, 1, 1, 1, 4),
      sparkBig = tileQuads(A.introSparklesBig, 4, 4, 16, 4),
      nidorino = tileQuads(A.introScene3Nidorino, 8, 8, 64, 5),
      swipeTop = tileQuads(A.introScene3Swipe, 4, 8, 32, 2),
      swipeBottom = tileQuads(A.introScene3Swipe, 4, 2, 8, 2, 64),
      dust = tileQuads(A.introScene3RecoilDust, 2, 2, 4, 4),
      grass = tileQuads(A.introScene3Grass, 8, 4, 32, 1),
      presents = tileQuads(A.introPresents, 4, 1, 4, 2),
      gengarTL = tileQuads(A.introScene3GengarStatic, 8, 8, 64, 1),
      gengarBL = tileQuads(A.introScene3GengarStatic, 8, 8, 64, 1, 96),
    }
    self.gengarTR = relayoutTiles(A.introScene3GengarStatic, 64, 4, 8)
    self.gengarBR = relayoutTiles(A.introScene3GengarStatic, 160, 4, 8)
    self.gfText = composeGfWindow(A.introGfText, nil)
    self.gfTextLogo = composeGfWindow(A.introGfText, A.introGfLogo)
  else
    self.q = {}
  end
  Oam.destroyAll()
  Bg.reset()
  return self
end

function IntroMovie:destroy()
  Oam.destroyAll()
  Bg.reset()
  self.tasks = {}
end

------------------------------------------------------------------------
-- Task runner (pokefirered/src/task.c)
------------------------------------------------------------------------

function IntroMovie:createTask(fn, priority)
  local t = { fn = fn, priority = priority, data = {}, alive = true }
  local list = self.tasks
  local pos = #list + 1
  for i, other in ipairs(list) do
    if other.priority > priority then
      pos = i
      break
    end
  end
  table.insert(list, pos, t)
  if self._runIdx and pos <= self._runIdx then
    self._runIdx = self._runIdx + 1
  end
  return t
end

function IntroMovie:findTask(fn)
  for _, t in ipairs(self.tasks) do
    if t.alive and t.fn == fn then return t end
  end
  return nil
end

function IntroMovie:destroyTask(t)
  if t then t.alive = false end
end

function IntroMovie:runTasks()
  self._runIdx = 1
  while self._runIdx <= #self.tasks do
    local t = self.tasks[self._runIdx]
    if t.alive then t.fn(self, t) end
    self._runIdx = self._runIdx + 1
  end
  self._runIdx = nil
  local keep = {}
  for _, t in ipairs(self.tasks) do
    if t.alive then keep[#keep + 1] = t end
  end
  self.tasks = keep
end

------------------------------------------------------------------------
-- Sprites
------------------------------------------------------------------------

local function createSprite(self, tmpl, x, y, sub)
  local id, spr = Oam.createSprite(tmpl, x, y, sub)
  if not spr then return nil end
  spr._id = id
  spr.palSlot = Pal.objSlot(tmpl.palSlot or 0)
  spr.objBlend = tmpl.objBlend
  if tmpl.double then
    spr.oam.affineMode = Oam.AFFINE_DOUBLE
    Oam.applyCenterToCorner(spr)
    spr.affineScale = 1
  end
  return spr
end

local function destroySprite(spr)
  if spr and spr.inUse then Oam.destroySprite(spr._id) end
end

------------------------------------------------------------------------
-- Blend task (pokefirered/src/menu2.c:591)
------------------------------------------------------------------------

local function Task_SmoothBlendLayers(self, t)
  local d = t.data
  if d.steps ~= 0 then
    if d.which == 0 then
      d.evA = d.evA + d.dA
      d.which = 1
    else
      d.steps = d.steps - 1
      if d.steps ~= 0 then
        d.evB = d.evB + d.dB
      else
        d.evA = d.endA * 256
        d.evB = d.endB * 256
      end
      d.which = 0
    end
    self.bldAlpha = { eva = math.floor(s16(d.evA) % 65536 / 256), evb = math.floor(d.evB / 256) }
    if d.steps == 0 then self:destroyTask(t) end
  end
end

function IntroMovie:startBlendTask(evaStart, evbStart, evaEnd, evbEnd, step)
  local t = self:createTask(Task_SmoothBlendLayers, 0)
  t.data = {
    evA = evaStart * 256, evB = evbStart * 256, endA = evaEnd, endB = evbEnd,
    dA = idiv((evaEnd - evaStart) * 256, step), dB = idiv((evbEnd - evbStart) * 256, step),
    steps = step, which = 0,
  }
  self.bldAlpha = { eva = evaStart, evb = evbStart }
end

function IntroMovie:isBlendTaskActive()
  return self:findTask(Task_SmoothBlendLayers) ~= nil
end

------------------------------------------------------------------------
-- Copyright (pokefirered/src/intro.c:916)
------------------------------------------------------------------------

function IntroMovie:copyrightFrame()
  local st = self.state
  if st == 0 then
    Oam.destroyAll()
    Bg.reset()
    self.pal:reset()
    Bg.initFromTemplates({ { bg = 0, priority = 0 } })
    if self.assets.introCopyright then
      Bg.setImage(0, self.assets.introCopyright, nil)
      Bg.show(0)
    end
    self.bgPal = { [0] = 0 }
    self.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.WHITE)
  end
  if st < 140 then
    self.pal:updateFade()
    self.state = st + 1
  elseif st == 140 then
    self.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    self.state = 141
  elseif st == 141 then
    if not self.pal:updateFade() then
      self.state = 142
    end
  elseif st == 142 then
    self.phase = "wait_fade"
    self.state = 0
  end
end

------------------------------------------------------------------------
-- CB2_SetUpIntro (pokefirered/src/intro.c:1018)
------------------------------------------------------------------------

function IntroMovie:setupFrame()
  local st = self.state
  if st == 0 then
    Oam.destroyAll()
    Bg.reset()
    self.tasks = {}
    self.pal:reset()
    Bg.initFromTemplates({
      { bg = BG_GF_BACKGROUND, priority = 3 },
      { bg = BG_GF_TEXT_LOGO, priority = 2 },
    })
    if self.assets.introGfBg then Bg.setImage(BG_GF_BACKGROUND, self.assets.introGfBg, nil) end
    if self.gfText then Bg.setImage(BG_GF_TEXT_LOGO, self.gfText, nil) end
    self.bgPal = { [BG_GF_BACKGROUND] = 0, [BG_GF_TEXT_LOGO] = 13 }
    self.state = 1
  elseif st == 1 then
    self.state = 2
  else
    self.ptr = { cb = "Init", state = 0, timer = 0 }
    self:createTask(IntroMovie.Task_CallIntroCallback, 3)
    self.pal:blend(Pal.ALL, 16, Pal.BLACK)
    self.phase = "intro"
    self.state = 0
  end
end

function IntroMovie:setCB(name)
  self.ptr.cb = name
  self.ptr.state = 0
end

-- pokefirered/src/intro.c:1106
function IntroMovie.Task_CallIntroCallback(self, t)
  local ptr = self.ptr
  if self._skipThisFrame and ptr.cb ~= "ExitToTitleScreen" then
    self:setCB("ExitToTitleScreen")
  end
  IntroMovie["IntroCB_" .. ptr.cb](self, ptr, t)
end

-- pokefirered/src/intro.c:1117
function IntroMovie.IntroCB_Init(self, p)
  if p.state == 0 then
    p.state = 1
  else
    self:setCB("GF_OpenWindow")
  end
end

-- pokefirered/src/intro.c:1139
function IntroMovie.IntroCB_GF_OpenWindow(self, p)
  if p.state == 0 then
    self.win1 = { y0 = 0, y1 = 0 }
    p.timer = 0
    p.state = 1
  elseif p.state == 1 then
    Bg.show(BG_GF_BACKGROUND)
    self.pal:blend(Pal.ALL, 0, Pal.BLACK)
    p.state = 2
  else
    p.timer = math.min(48, p.timer + 8)
    self.win1 = { y0 = 80 - p.timer, y1 = 80 + p.timer }
    if p.timer == 48 then self:setCB("GF_Star") end
  end
end

------------------------------------------------------------------------
-- Game Freak scene sprites
------------------------------------------------------------------------

local function SpriteCB_SparklesSmall_Star(sprite)
  local d = sprite.data
  -- pokefirered/src/intro.c:2305
  d[1] = s16(d[1] + d[3])
  d[2] = s16(d[2] + d[4])
  d[5] = d[5] + 1
  d[6] = s16(d[6] + d[5])
  d[8] = d[8] + 1
  sprite.x = math.floor((d[1] % 65536) / 32)
  sprite.y = math.floor(d[2] / 32)
  if d[8] > 90 then
    sprite.invisible = not sprite.invisible
    if d[8] > 120 then
      Oam.destroySprite(sprite._id)
      return
    end
  end
  if sprite.y + sprite.y2 < 0 or sprite.y + sprite.y2 > Display.H then
    Oam.destroySprite(sprite._id)
  end
end

function IntroMovie:createStarSparkle(x, y, random)
  -- pokefirered/src/intro.c:1995
  local xMod = (random % 8) + 2
  local yMod = self.sparkleYMod
  self.sparkleYMod = self.sparkleYMod + 1
  if self.sparkleYMod > 3 then self.sparkleYMod = -3 end
  x = x + xMod
  y = y + yMod
  if x > 0 and x < Display.W then
    local spr = createSprite(self, {
      dims = Oam.SQUARE_8, priority = 2, image = self.assets.introSparklesSmall,
      anims = ANIMS_SPARKLES_SMALL, animQuads = self.q.sparkSmall,
      callback = SpriteCB_SparklesSmall_Star, palSlot = OBJ_SPARKLES,
    }, x, y, 1)
    if spr then
      spr.data[1] = s16(x * 32)
      spr.data[2] = s16(y * 32)
      spr.data[3] = xMod
      spr.data[4] = yMod
    end
  end
end

function IntroMovie:loadGfxCreateStar()
  -- pokefirered/src/intro.c:1953
  local movie = self
  self.sparkleYMod = self.sparkleYMod or 0
  local spr = createSprite(self, {
    dims = Oam.SQUARE_16, priority = 2, image = self.assets.introStar, palSlot = OBJ_STAR,
    callback = function(sprite)
      -- pokefirered/src/intro.c:2282
      local d = sprite.data
      d[1] = s16(d[1] - 96)
      d[2] = s16(d[2] + 16)
      d[5] = s16(d[5] + 48)
      sprite.x = math.floor(d[1] / 16)
      sprite.y = math.floor(d[2] / 16)
      sprite.y2 = math.floor(Trig.SINE[math.floor(d[5] / 16) + 64 + 1] / 32)
      d[6] = s16(d[6] + 1)
      if d[6] % 8 ~= 0 then
        movie.starSeed = isoRandomize1(movie.starSeed)
        movie:createStarSparkle(sprite.x, sprite.y + sprite.y2, math.floor(movie.starSeed / 65536))
      end
      if sprite.x < -8 then Oam.destroySprite(sprite._id) end
    end,
  }, 248, 55, 0)
  if spr then
    spr.data[1] = 248 * 16
    spr.data[2] = 55 * 16
  end
  self.starSeed = 354128453
end

local function SpriteCB_SparklesSmall_Name(sprite)
  -- pokefirered/src/intro.c:2326
  local d = sprite.data
  if d[3] ~= 0 then
    d[3] = d[3] - 1
    d[2] = d[2] + 1
    sprite.y = math.floor(d[2] / 16)
    if sprite.y > 86 then
      sprite.y = 74
      d[2] = 74 * 16
    end
    if sprite.animEnded then
      if d[1] == 0 then
        sprite.x = sprite.x + 26
        if sprite.x > 188 then
          sprite.x = 188 * 2 - sprite.x
          d[1] = 1
        end
      else
        sprite.x = sprite.x - 26
        if sprite.x < 52 then
          sprite.x = 52 * 2 - sprite.x
          d[1] = 0
        end
      end
      Oam.startAnim(sprite, ANIM_SPARKLE_ONCE)
    end
  else
    if d[4] ~= 0 then
      Oam.destroySprite(sprite._id)
      return
    end
    if sprite.animEnded then Oam.startAnim(sprite, ANIM_SPARKLE_LOOP) end
    d[2] = d[2] + 4
    sprite.y = math.floor(d[2] / 16)
    d[5] = d[5] + 1
    if d[5] > 50 then Oam.destroySprite(sprite._id) end
  end
end

local function GFScene_Task_NameSparklesSmall(self, t)
  -- pokefirered/src/intro.c:2035
  local d = t.data
  d.timer = (d.timer or 0) + 1
  d.idx = d.idx or 0
  d.loops = d.loops or 0
  if d.timer > 6 then
    d.timer = 0
    local c = TEXT_SPARKLE_COORDS[d.idx + 1]
    local spr = createSprite(self, {
      dims = Oam.SQUARE_8, priority = 2, image = self.assets.introSparklesSmall,
      anims = ANIMS_SPARKLES_SMALL, animQuads = self.q.sparkSmall,
      callback = SpriteCB_SparklesSmall_Name, palSlot = OBJ_SPARKLES,
    }, c[1], c[2], 2)
    if spr then
      Oam.startAnim(spr, ANIM_SPARKLE_ONCE)
      spr.data[2] = c[2] * 16
      spr.data[3] = 120
      spr.data[4] = d.loops
    end
    d.idx = d.idx + 1
    if d.idx >= #TEXT_SPARKLE_COORDS then
      d.loops = d.loops + 1
      if d.loops > 1 then
        self:destroyTask(t)
      else
        d.idx = 0
      end
    end
  end
end

local function GFScene_Task_NameSparklesBig(self, t)
  -- pokefirered/src/intro.c:2078
  local d = t.data
  d.timer = d.timer or 0
  d.idx = d.idx or 0
  d.count = d.count or 0
  if d.timer == 0 then
    local c = TEXT_SPARKLE_COORDS[d.idx + 1]
    d.idx = d.idx + 4
    if d.idx >= #TEXT_SPARKLE_COORDS then d.idx = d.idx - #TEXT_SPARKLE_COORDS end
    createSprite(self, {
      dims = Oam.SQUARE_32, priority = 2, image = self.assets.introSparklesBig,
      anims = ANIMS_SPARKLES_BIG, animQuads = self.q.sparkBig, palSlot = OBJ_SPARKLES,
      callback = function(sprite)
        if sprite.animEnded then Oam.destroySprite(sprite._id) end
      end,
    }, c[1], c[2], 3)
    d.count = d.count + 1
    if d.count >= #TEXT_SPARKLE_COORDS then self:destroyTask(t) end
  end
  d.timer = d.timer + 1
  if d.timer > 9 then d.timer = 0 end
end

-- pokefirered/src/intro.c:1169
function IntroMovie.IntroCB_GF_Star(self, p)
  if p.state == 0 then
    Audio.playSong(MUS_GAME_FREAK, { restart = true })
    self:loadGfxCreateStar()
    p.timer = 0
    p.state = 1
  elseif p.state == 1 then
    p.timer = p.timer + 1
    if p.timer == 30 then
      self:createTask(GFScene_Task_NameSparklesSmall, 1)
      p.timer = 0
      p.state = 2
    end
  else
    p.timer = p.timer + 1
    if p.timer == 90 then self:setCB("GF_RevealName") end
  end
end

-- pokefirered/src/intro.c:1195
function IntroMovie.IntroCB_GF_RevealName(self, p)
  local st = p.state
  if st == 0 then
    self:createTask(GFScene_Task_NameSparklesBig, 2)
    p.timer = 0
    p.state = 1
  elseif st == 1 then
    p.timer = p.timer + 1
    if p.timer >= 40 then p.state = 2 end
  elseif st == 2 then
    self.bld = { bg2 = true }
    self:startBlendTask(0, 16, 16, 0, 48)
    p.state = 3
  elseif st == 3 then
    Bg.show(BG_GF_TEXT_LOGO)
    p.state = 4
  elseif st == 4 then
    if not self:isBlendTaskActive() then
      self.bld = nil
      p.timer = 0
      p.state = 5
    end
  else
    p.timer = p.timer + 1
    if p.timer > 50 then self:setCB("GF_RevealLogo") end
  end
end

-- pokefirered/src/intro.c:1232
function IntroMovie.IntroCB_GF_RevealLogo(self, p)
  local st = p.state
  if st == 0 then
    self.bld = { obj = true }
    self:startBlendTask(0, 16, 16, 0, 16)
    p.timer = 0
    p.state = 1
  elseif st == 1 then
    self.logoSprite = createSprite(self, {
      dims = Oam.VRECT_32x64, priority = 3, image = self.assets.introGfLogo,
      palSlot = OBJ_GF, objBlend = true,
    }, 120, 70, 4)
    p.state = 2
  elseif st == 2 then
    if not self:isBlendTaskActive() then
      if self.gfTextLogo then Bg.setImage(BG_GF_TEXT_LOGO, self.gfTextLogo, nil) end
      p.state = 3
    end
  elseif st == 3 then
    destroySprite(self.logoSprite)
    self.logoSprite = nil
    -- pokefirered/src/intro.c:2108
    for i = 0, 1 do
      createSprite(self, {
        dims = Oam.HRECT_32x8, priority = 3, image = self.assets.introPresents,
        quad = self.q.presents and self.q.presents[i * 4], palSlot = OBJ_GF, objBlend = true,
      }, 104 + 32 * i, 108, 5)
    end
    p.timer = 0
    p.state = 4
  elseif st == 4 then
    p.timer = p.timer + 1
    if p.timer > 90 then
      self.bld = { obj = true, bg2 = true }
      self:startBlendTask(16, 0, 0, 16, 20)
      p.state = 5
    end
  elseif st == 5 then
    if not self:isBlendTaskActive() then
      Bg.hide(BG_GF_TEXT_LOGO)
      p.state = 6
    end
  elseif st == 6 then
    Oam.destroyAll()
    p.timer = 0
    p.state = 7
  else
    p.timer = p.timer + 1
    if p.timer > 20 then
      self.bld = nil
      self:setCB("Scene1")
    end
  end
end

------------------------------------------------------------------------
-- Scene 1 (pokefirered/src/intro.c:1299)
------------------------------------------------------------------------

local function Scene1_Task_AnimateGrass(self, t)
  -- pokefirered/src/intro.c:1379
  local d = t.data
  d.timer = (d.timer or 0) + 1
  d.frame = d.frame or 0
  d.scroll = d.scroll or 0
  if d.timer > 5 then
    d.timer = 0
    d.frame = d.frame + 1
    if d.frame >= 3 then d.frame = 0 end
    Bg.changeBgY(BG_SCENE1_GRASS, d.frame * 0x8000, Bg.COORD_SET)
  end
  if d.exiting then
    d.scroll = s16(d.scroll + 0x120)
    Bg.changeBgY(BG_SCENE1_GRASS, d.scroll, Bg.COORD_SUB)
  end
end

local function Scene1_Task_BgZoom(self, t)
  -- pokefirered/src/intro.c:1419
  local d = t.data
  d.timer = (d.timer or 0) + 1
  d.frame = d.frame or 0
  if d.timer > 3 then
    d.timer = 0
    if d.frame < 2 then d.frame = d.frame + 1 end
    Bg.changeBgY(BG_SCENE1_BACKGROUND, d.frame * 0x8000, Bg.COORD_SET)
  end
end

function IntroMovie.IntroCB_Scene1(self, p)
  local A = self.assets
  local st = p.state
  if st == 0 then
    self.pal:blend(Pal.mask({ 1, 2 }), 16, Pal.WHITE)
    Bg.initFromTemplates({
      { bg = BG_SCENE1_GRASS, priority = 0 },
      { bg = BG_SCENE1_BACKGROUND, priority = 0 },
    })
    if A.introScene1Bg then
      Bg.setImage(BG_SCENE1_BACKGROUND, A.introScene1Bg, nil)
      Bg.setWrap(BG_SCENE1_BACKGROUND, 256, 512)
    end
    if A.introScene1Grass then
      Bg.setImage(BG_SCENE1_GRASS, A.introScene1Grass, nil)
      Bg.setWrap(BG_SCENE1_GRASS, 256, 512)
    end
    self.bgPal = { [BG_SCENE1_GRASS] = 1, [BG_SCENE1_BACKGROUND] = 2 }
    Bg.show(BG_SCENE1_BACKGROUND)
    Bg.hide(BG_SCENE1_GRASS)
    p.state = 1
  elseif st == 1 then
    Bg.changeBgX(BG_SCENE1_GRASS, 0, Bg.COORD_SET)
    Bg.changeBgY(BG_SCENE1_GRASS, 0, Bg.COORD_SET)
    Bg.changeBgX(BG_SCENE1_BACKGROUND, 0, Bg.COORD_SET)
    Bg.changeBgY(BG_SCENE1_BACKGROUND, 0, Bg.COORD_SET)
    Bg.show(BG_SCENE1_BACKGROUND)
    p.state = 2
  elseif st == 2 then
    Bg.show(BG_SCENE1_GRASS)
    self:createTask(Scene1_Task_AnimateGrass, 0)
    self.pal:beginFade(Pal.mask({ 1, 2 }), -2, 16, 0, Pal.WHITE)
    p.state = 3
  elseif st == 3 then
    if not self.pal:fadeActive() then
      Audio.playSong(MUS_INTRO_FIGHT, { restart = true })
      p.timer = 0
      p.state = 4
    end
  elseif st == 4 then
    p.timer = p.timer + 1
    if p.timer == 20 then
      self:createTask(Scene1_Task_BgZoom, 0)
      local g = self:findTask(Scene1_Task_AnimateGrass)
      if g then g.data.exiting = true end
    end
    if p.timer >= 30 then
      self.pal:blend(ALL_BUT_0, 16, Pal.WHITE)
      self:destroyTask(self:findTask(Scene1_Task_AnimateGrass))
      self:destroyTask(self:findTask(Scene1_Task_BgZoom))
      self:setCB("Scene2")
    end
  end
end

------------------------------------------------------------------------
-- Scene 2 (pokefirered/src/intro.c:1435)
------------------------------------------------------------------------

local function Scene2_Task_PanForest(self)
  Bg.changeBgX(BG_SCENE2_BACKGROUND, 0x0E0, Bg.COORD_SUB)
  Bg.changeBgX(BG_SCENE2_PLANTS, 0x110, Bg.COORD_ADD)
end

local function Scene2_Task_PanMons(self)
  Bg.changeBgY(BG_SCENE2_GENGAR, 0x020, Bg.COORD_ADD)
  Bg.changeBgY(BG_SCENE2_NIDORINO, 0x024, Bg.COORD_SUB)
end

local function wrapWidth(img)
  local w = img and img:getWidth() or 256
  return w
end

function IntroMovie.IntroCB_Scene2(self, p)
  local A = self.assets
  local st = p.state
  if st == 0 then
    self.pal:blend(ALL_BUT_0, 16, Pal.WHITE)
    Bg.initFromTemplates({
      { bg = BG_SCENE2_BACKGROUND, priority = 3 },
      { bg = BG_SCENE2_PLANTS, priority = 0 },
      { bg = BG_SCENE2_GENGAR, priority = 2 },
      { bg = BG_SCENE2_NIDORINO, priority = 1 },
    })
    if A.introScene2Bg then
      Bg.setImage(BG_SCENE2_BACKGROUND, A.introScene2Bg, nil)
      Bg.setWrap(BG_SCENE2_BACKGROUND, 256, 512)
    end
    self.bgPal = { [BG_SCENE2_BACKGROUND] = 1, [BG_SCENE2_PLANTS] = 1,
      [BG_SCENE2_GENGAR] = 5, [BG_SCENE2_NIDORINO] = 6 }
    Bg.show(BG_SCENE2_BACKGROUND)
    p.state = 1
  elseif st == 1 then
    self.pal:blend(ALL_BUT_0, 16, Pal.WHITE)
    if A.introScene2Plants then
      Bg.setImage(BG_SCENE2_PLANTS, A.introScene2Plants, nil)
      Bg.setWrap(BG_SCENE2_PLANTS, wrapWidth(A.introScene2Plants), nil)
    end
    if A.introScene2NidorinoClose then
      Bg.setImage(BG_SCENE2_NIDORINO, A.introScene2NidorinoClose, nil)
      Bg.setWrap(BG_SCENE2_NIDORINO, 256, 256)
    end
    if A.introScene2GengarClose then
      Bg.setImage(BG_SCENE2_GENGAR, A.introScene2GengarClose, nil)
      Bg.setWrap(BG_SCENE2_GENGAR, 256, 256)
    end
    for i = 0, 3 do
      Bg.changeBgX(i, 0, Bg.COORD_SET)
      Bg.changeBgY(i, 0, Bg.COORD_SET)
    end
    Bg.show(BG_SCENE2_PLANTS)
    Bg.hide(BG_SCENE2_NIDORINO)
    Bg.hide(BG_SCENE2_GENGAR)
    Bg.changeBgY(BG_SCENE2_GENGAR, 0x0001CE00, Bg.COORD_SET)
    Bg.changeBgY(BG_SCENE2_NIDORINO, 0x00002800, Bg.COORD_SET)
    self:createTask(Scene2_Task_PanForest, 0)
    -- pokefirered/src/intro.c:1535
    self.s2Nidorino = createSprite(self, {
      dims = Oam.SQUARE_64, priority = 1, image = A.introScene2Nidorino, palSlot = OBJ_NIDORINO,
    }, 168, 80, 11)
    self.s2Gengar = createSprite(self, {
      dims = Oam.SQUARE_64, priority = 1, image = A.introScene2Gengar, palSlot = OBJ_GENGAR,
    }, 72, 80, 12)
    self.pal:blend(ALL_BUT_0, 16, Pal.WHITE)
    p.state = 2
  elseif st == 2 then
    self.pal:beginFade(ALL_BUT_0, -2, 16, 0, Pal.WHITE)
    p.state = 3
  elseif st == 3 then
    if not self.pal:fadeActive() then
      p.timer = 0
      p.state = 4
    end
  elseif st == 4 then
    p.timer = p.timer + 1
    if p.timer >= 60 then
      p.timer = 0
      self:destroyTask(self:findTask(Scene2_Task_PanForest))
      destroySprite(self.s2Gengar)
      destroySprite(self.s2Nidorino)
      self:createTask(Scene2_Task_PanMons, 0)
      Bg.changeBgY(BG_SCENE2_BACKGROUND, 0x00010000, Bg.COORD_SET)
      Bg.hide(BG_SCENE2_PLANTS)
      Bg.show(BG_SCENE2_BACKGROUND)
      Bg.show(BG_SCENE2_NIDORINO)
      Bg.show(BG_SCENE2_GENGAR)
      p.state = 5
    end
  elseif st == 5 then
    p.timer = 0
    p.state = 6
  else
    p.timer = p.timer + 1
    if p.timer >= 60 then
      self:destroyTask(self:findTask(Scene2_Task_PanMons))
      self:setCB("Scene3_Entrance")
    end
  end
end

------------------------------------------------------------------------
-- Scene 3 (pokefirered/src/intro.c:1560)
------------------------------------------------------------------------

local function Scene3_Task_BgScroll(self, t)
  -- pokefirered/src/intro.c:1623
  if not t.data.slow then
    Bg.changeBgX(BG_SCENE3_BACKGROUND, 0x400, Bg.COORD_SUB)
  else
    Bg.changeBgX(BG_SCENE3_BACKGROUND, 0x020, Bg.COORD_SUB)
  end
end

local function Scene3_Task_GengarBounce(self, t)
  -- pokefirered/src/intro.c:1649
  local d = t.data
  d.timer = d.timer or 0
  d.state = d.state or 0
  if not d.paused then
    d.timer = d.timer + 1
    if d.timer >= 30 then
      d.timer = 0
      d.state = 1 - d.state
      Bg.changeBgY(BG_SCENE3_GENGAR, d.state * 0x8000 + 0x1F000, Bg.COORD_SET)
    end
  end
end

local function Scene3_Task_GengarEnter(self, t)
  -- pokefirered/src/intro.c:2249
  local d = t.data
  if not d.speed then d.speed = 0x400 end
  d.moves = (d.moves or 0) + 1
  if d.moves >= 40 and d.speed > 16 then d.speed = d.speed - 16 end
  Bg.changeBgX(BG_SCENE3_GENGAR, d.speed, Bg.COORD_ADD)
  local scroll = Bg.get(BG_SCENE3_GENGAR).scrollX * 256
  if scroll >= 0x8000 then self.win0 = nil end
  if scroll >= 0xEF00 then
    Bg.changeBgX(BG_SCENE3_GENGAR, 0xEF00, Bg.COORD_SET)
    self:destroyTask(t)
  end
end

local function SpriteCB_Grass(movie)
  return function(sprite)
    -- pokefirered/src/intro.c:1702
    local d = sprite.data
    if d[1] == 0 then
      d[2] = sprite.x * 32
      d[3] = 160
      d[1] = 1
    end
    if d[1] == 1 then
      d[2] = d[2] - d[3]
      sprite.x = math.floor(d[2] / 32)
      if sprite.x <= 52 then
        local t = movie:findTask(Scene3_Task_BgScroll)
        if t then t.data.slow = true end
        d[1] = 2
      end
    elseif d[1] == 2 then
      d[2] = d[2] - 32
      sprite.x = math.floor(d[2] / 32)
      if sprite.x <= -32 then
        sprite.invisible = true
        Oam.destroySprite(sprite._id)
      end
    end
  end
end

local function Scene3_SpriteCB_NidorinoEnter(sprite)
  -- pokefirered/src/intro.c:2405
  local d = sprite.data
  d[5] = d[5] + 1
  if d[5] >= 40 and d[2] > 1 then d[2] = d[2] - 1 end
  d[1] = d[1] + d[2]
  sprite.x = math.floor(d[1] / 16)
  if sprite.x >= d[4] then
    sprite.x = d[4]
    sprite.callback = Oam.DUMMY_CALLBACK
  end
end

local function nidoRunning(self)
  local s = self.nido
  return s ~= nil and s.callback ~= Oam.DUMMY_CALLBACK
end

local SpriteCB_NidorinoHop

local function startNidorinoHop(sprite, time, targetX, heightShift)
  -- pokefirered/src/intro.c:2655
  local d = sprite.data
  d[1] = 0
  d[2] = time
  d[3] = s16(sprite.x2 * 16)
  d[4] = idiv(targetX * 16, time)
  d[5] = 0
  d[6] = idiv(0x800, time)
  d[7] = 0
  d[8] = heightShift
  Oam.startAnim(sprite, ANIM_NIDORINO_CROUCH)
  sprite.callback = SpriteCB_NidorinoHop
end

SpriteCB_NidorinoHop = function(sprite)
  -- pokefirered/src/intro.c:2669
  local d = sprite.data
  if d[1] == 0 then
    d[7] = d[7] + 1
    if d[7] > 4 then
      Oam.startAnim(sprite, ANIM_NIDORINO_HOP)
      d[7] = 0
      d[1] = 1
    end
  elseif d[1] == 1 then
    d[2] = (d[2] - 1) % 65536
    if d[2] ~= 0 then
      d[3] = s16(d[3] + d[4])
      d[5] = s16(d[5] + d[6])
      sprite.x2 = math.floor(d[3] / 16)
      sprite.y2 = -math.floor(Trig.SINE[math.floor(d[5] / 16) + 1] / 2 ^ d[8])
    else
      sprite.x2 = s16(math.floor((d[3] % 65536) / 16))
      sprite.y2 = 0
      Oam.startAnim(sprite, ANIM_NIDORINO_CROUCH)
      if d[8] == 5 then
        sprite.callback = Oam.DUMMY_CALLBACK
      else
        d[7] = 0
        d[1] = 2
      end
    end
  else
    d[7] = d[7] + 1
    if d[7] > 4 then
      Oam.startAnim(sprite, ANIM_NIDORINO_NORMAL)
      sprite.callback = Oam.DUMMY_CALLBACK
    end
  end
end

local function startNidorinoCry(self)
  -- pokefirered/src/intro.c:2438
  local sprite = self.nido
  Oam.startAnim(sprite, ANIM_NIDORINO_CROUCH)
  sprite.data[1] = 0
  sprite.data[2] = 0
  sprite.y2 = 3
  sprite.callback = function(s)
    local d = s.data
    if d[1] == 0 then
      d[2] = d[2] + 1
      if d[2] > 8 then
        Oam.startAnim(s, ANIM_NIDORINO_CRY)
        s.y2 = 0
        d[1] = 1
      end
    elseif d[1] == 1 then
      Audio.playCry(SPECIES_NIDORINO, 1, 0x3F)
      d[2] = 0
      d[1] = 2
    else
      d[3] = d[3] + 1
      if d[3] > 1 then
        d[3] = 0
        s.y2 = (s.y2 == 0) and 1 or 0
      end
      d[2] = d[2] + 1
      if d[2] > 48 then
        Oam.startAnim(s, ANIM_NIDORINO_NORMAL)
        s.y2 = 0
        s.callback = Oam.DUMMY_CALLBACK
      end
    end
  end
end

function IntroMovie:createRecoilDust(x, y, seed)
  -- pokefirered/src/intro.c:2590
  for i = 0, 1 do
    local spr = createSprite(self, {
      dims = Oam.SQUARE_16, priority = 1, image = self.assets.introScene3RecoilDust,
      anims = ANIMS_RECOIL_DUST, animQuads = self.q.dust, palSlot = OBJ_DUST,
      callback = function(sprite)
        -- pokefirered/src/intro.c:2610
        local d = sprite.data
        if d[1] == 0 then
          d[2] = sprite.x * 16
          d[3] = sprite.y * 16
          d[1] = 1
        end
        d[2] = d[2] - d[4]
        d[3] = d[3] + d[5]
        sprite.x = math.floor(d[2] / 16)
        sprite.y = math.floor(d[3] / 16)
        if sprite.animEnded then
          Oam.destroySprite(sprite._id)
          return
        end
        d[8] = d[8] + 1
        if d[8] > 1 then
          d[8] = 0
          sprite.invisible = not sprite.invisible
        end
      end,
    }, x - 22, y + 24, 10)
    if spr then
      local cs = s16(seed)
      spr.data[4] = math.fmod(cs, 13) + 8
      spr.data[5] = math.fmod(cs, 3)
      spr.data[8] = i
      seed = s16(mulU32(seed % 65536, RAND_MULT))
    end
  end
end

local function startNidorinoRecoil(self)
  -- pokefirered/src/intro.c:2494
  local sprite = self.nido
  local movie = self
  Oam.startAnim(sprite, ANIM_NIDORINO_CROUCH)
  local d = sprite.data
  d[1], d[2], d[3], d[4], d[5] = 0, 0, 0, 0, 0
  d[8] = 40
  sprite.callback = function(s)
    local dd = s.data
    if dd[1] == 0 then
      dd[2] = dd[2] + 1
      if dd[2] > 4 then
        Oam.startAnim(s, ANIM_NIDORINO_HOP)
        dd[1] = 1
      end
    elseif dd[1] == 1 then
      dd[3] = s16(dd[3] + dd[8])
      dd[4] = dd[4] + 8
      s.x2 = math.floor(dd[3] / 16)
      s.y2 = -math.floor((Trig.SINE[dd[4] + 1] * 3) / 32)
      dd[6] = dd[6] + 1
      if dd[6] > 0 then
        dd[6] = 0
        dd[8] = dd[8] - 1
      end
      dd[5] = dd[5] + 1
      if dd[5] > 15 then
        Oam.startAnim(s, ANIM_NIDORINO_CROUCH)
        dd[2] = 0
        dd[7] = 0x4757
        dd[8] = 28
        dd[1] = 2
      end
    elseif dd[1] == 2 then
      dd[3] = s16(dd[3] + dd[8])
      s.x2 = math.floor(dd[3] / 16)
      dd[2] = dd[2] + 1
      if dd[2] > 6 then
        movie:createRecoilDust(s.x + s.x2, s.y + s.y2, dd[7])
        dd[7] = s16(mulU32(dd[7] % 65536, RAND_MULT))
      end
      if dd[2] > 12 then
        Oam.startAnim(s, ANIM_NIDORINO_NORMAL)
        dd[2] = 0
        dd[1] = 3
      end
    else
      dd[2] = dd[2] + 1
      if dd[2] > 16 then
        startNidorinoHop(s, 16, -s.x2, 4)
      end
    end
  end
end

local function startNidorinoAttack(self)
  -- pokefirered/src/intro.c:2733
  local sprite = self.nido
  local d = sprite.data
  d[1], d[2], d[3], d[4], d[5], d[6] = 0, 0, 0, 0, 0, 0
  sprite.x = sprite.x + sprite.x2
  sprite.x2 = 0
  d[8] = 36
  Oam.startAnim(sprite, ANIM_NIDORINO_CROUCH)
  sprite.callback = function(s)
    local dd = s.data
    if dd[1] == 0 then
      dd[2] = dd[2] + 1
      if dd[2] % 2 == 1 then
        dd[3] = dd[3] + 1
        if dd[3] % 2 == 1 then s.x2 = s.x2 + 1 else s.x2 = s.x2 - 1 end
      end
      if dd[2] > 17 then
        dd[2] = 0
        dd[1] = 1
      end
    elseif dd[1] == 1 then
      dd[2] = dd[2] + 1
      if dd[2] >= 40 then
        Oam.startAnim(s, ANIM_NIDORINO_ATTACK)
        dd[2] = 0
        dd[3] = 0
        dd[1] = 2
      end
    else
      dd[2] = dd[2] + dd[8]
      s.x2 = -math.floor(dd[2] / 16)
      s.y2 = -math.floor((Trig.SINE[math.floor(dd[2] / 16) + 1] * 3) / 16)
      dd[3] = dd[3] + 1
      if dd[8] > 12 then dd[8] = dd[8] - 1 end
      if math.floor(dd[2] / 16) > 63 then s.callback = Oam.DUMMY_CALLBACK end
    end
  end
end

local function applyGengarAnim(frame, xSub, ySub, xBase)
  -- pokefirered/src/intro.c:2135
  Bg.changeBgY(BG_SCENE3_GENGAR, frame * 0x8000 + 0x1F000, Bg.COORD_SET)
  Bg.changeBgX(BG_SCENE3_GENGAR, xBase, Bg.COORD_SET)
  Bg.changeBgX(BG_SCENE3_GENGAR, xSub * 256, Bg.COORD_SUB)
  Bg.changeBgY(BG_SCENE3_GENGAR, ySub * 256, Bg.COORD_SUB)
end

local function Scene3_Task_GengarAttack(self, t)
  -- pokefirered/src/intro.c:2143
  local d = t.data
  local st = d.state
  if st == 0 then
    d.frame = 2
    d.timer = 0
    d.multY = 6
    d.multX = 32
    d.state = 1
  elseif st == 1 then
    d.sinIdx = d.sinIdx - 2
    d.timer = d.timer + 1
    if d.timer > 15 then
      d.timer = 0
      d.state = 2
    end
  elseif st == 2 then
    d.timer = d.timer + 1
    if d.timer == 14 then self.ptr.gengarAttackLanded = true end
    if d.timer > 15 then
      d.timer = 0
      d.state = 3
    end
  elseif st == 3 then
    d.sinIdx = d.sinIdx + 8
    d.timer = d.timer + 1
    if d.timer == 4 then
      self:createGengarSwipeSprites()
      d.multY = 32
      d.multX = 48
      d.frame = 3
    end
    if d.timer > 7 then
      d.timer = 0
      d.state = 4
    end
  elseif st == 4 then
    d.sinIdx = d.sinIdx - 8
    d.timer = d.timer + 1
    if d.timer > 3 then
      d.frame = 0
      d.sinIdx = 64
      d.timer = 0
      d.state = 5
    end
  else
    self:destroyTask(t)
    return
  end
  local xSub = -math.floor((Trig.SINE[d.sinIdx + 64 + 1] * d.multX) / 256)
  local ySub = d.multY - math.floor((Trig.SINE[d.sinIdx + 1] * d.multY) / 256)
  applyGengarAnim(d.frame, xSub, ySub, d.baseX)
end

function IntroMovie:createGengarSwipeSprites()
  -- pokefirered/src/intro.c:2224
  local A = self.assets
  local function cb(sprite)
    sprite.invisible = not sprite.invisible
    if sprite.animEnded then Oam.destroySprite(sprite._id) end
  end
  createSprite(self, {
    dims = Oam.VRECT_32x64, priority = 1, image = A.introScene3Swipe,
    anims = ANIMS_SWIPE, animQuads = self.q.swipeTop, callback = cb, palSlot = OBJ_SWIPE,
  }, 132, 78, 6)
  local spr = createSprite(self, {
    dims = Oam.VRECT_32x64, priority = 1, image = A.introScene3Swipe,
    anims = ANIMS_SWIPE, animQuads = self.q.swipeBottom, callback = cb, palSlot = OBJ_SWIPE,
  }, 132, 118, 6)
  if spr then
    spr.oam.shape = Oam.HRECT_32x16.shape
    spr.oam.size = Oam.HRECT_32x16.size
    Oam.applyCenterToCorner(spr)
    Oam.startAnim(spr, 1)
  end
end

function IntroMovie.IntroCB_Scene3_Entrance(self, p)
  local A = self.assets
  local st = p.state
  if st == 0 then
    self.pal:blend(ALL_BUT_0, 16, Pal.WHITE)
    Bg.initFromTemplates({
      { bg = BG_SCENE3_BACKGROUND, priority = 1 },
      { bg = BG_SCENE3_GENGAR, priority = 0 },
    })
    if A.introScene3Bg then
      Bg.setImage(BG_SCENE3_BACKGROUND, A.introScene3Bg, nil)
      Bg.setWrap(BG_SCENE3_BACKGROUND, wrapWidth(A.introScene3Bg), nil)
    end
    self.bgPal = { [BG_SCENE3_BACKGROUND] = 1, [BG_SCENE3_GENGAR] = 5 }
    Bg.show(BG_SCENE3_BACKGROUND)
    Bg.hide(BG_SCENE3_GENGAR)
    p.state = 1
    self.win0 = { x0 = 0, x1 = 120, y0 = 32, y1 = 128 }
  elseif st == 1 then
    if A.introScene3GengarAnim then
      Bg.setImage(BG_SCENE3_GENGAR, A.introScene3GengarAnim, nil)
      Bg.setWrap(BG_SCENE3_GENGAR, 256, 512)
    end
    Bg.changeBgX(BG_SCENE3_GENGAR, 0x00001800, Bg.COORD_SET)
    Bg.changeBgY(BG_SCENE3_GENGAR, 0x0001F000, Bg.COORD_SET)
    p.state = 2
  elseif st == 2 then
    self.pal:blend(ALL_BUT_0, 0, Pal.WHITE)
    Bg.show(BG_SCENE3_GENGAR)
    self:createTask(Scene3_Task_GengarBounce, 0)
    -- pokefirered/src/intro.c:2381
    self.nido = createSprite(self, {
      dims = Oam.SQUARE_64, priority = 1, image = A.introScene3Nidorino,
      anims = ANIMS_NIDORINO, animQuads = self.q.nidorino, palSlot = OBJ_NIDORINO, double = true,
    }, 0, 0, 9)
    if self.nido then
      local d = self.nido.data
      d[1] = 0
      d[2] = idiv((180 - 0) * 16, 52)
      d[3] = 52
      d[4] = 180
      d[5] = 0
      self.nido.x = 0
      self.nido.y = 100
      self.nido.callback = Scene3_SpriteCB_NidorinoEnter
    end
    self:createTask(Scene3_Task_GengarEnter, 0)
    self:createTask(Scene3_Task_BgScroll, 0)
    p.timer = 0
    p.state = 3
  else
    p.timer = p.timer + 1
    if p.timer == 16 then
      local spr = createSprite(self, {
        dims = Oam.HRECT_64x32, priority = 0, image = A.introScene3Grass,
        animQuads = self.q.grass, palSlot = OBJ_GRASS,
      }, 296, 112, 7)
      if spr then
        spr.quad = self.q.grass and self.q.grass[0]
        spr.callback = SpriteCB_Grass(self)
      end
    end
    local entering = self.nido and self.nido.callback == Scene3_SpriteCB_NidorinoEnter
    if not entering and not self:findTask(Scene3_Task_GengarEnter) then
      self:setCB("Scene3_Fight")
    end
  end
end

function IntroMovie:createGengarSprites()
  -- pokefirered/src/intro.c:1877
  local A = self.assets
  local imgs = {
    { A.introScene3GengarStatic, self.q.gengarTL and self.q.gengarTL[0] },
    { self.gengarTR, nil },
    { A.introScene3GengarStatic, self.q.gengarBL and self.q.gengarBL[96] },
    { self.gengarBR, nil },
  }
  self.gengarSprites = {}
  for i = 0, 3 do
    local x = (i % 2) * 48 + 49
    local y = math.floor(i / 2) * 64 + 72
    local spr = createSprite(self, {
      dims = Oam.SQUARE_64, priority = 1, image = imgs[i + 1][1], quad = imgs[i + 1][2],
      palSlot = OBJ_GENGAR, double = true,
    }, x, y, 8)
    if spr then
      if i % 2 == 1 then
        spr.oam.shape = Oam.SHAPE_V_RECT
        Oam.applyCenterToCorner(spr)
      end
      self.gengarSprites[i + 1] = spr
    end
  end
end

function IntroMovie.IntroCB_Scene3_Fight(self, p)
  -- pokefirered/src/intro.c:1739
  local st = p.state
  if st == 0 then
    p.timer = 0
    p.state = 1
  elseif st == 1 then
    p.timer = p.timer + 1
    if p.timer > 30 then
      startNidorinoCry(self)
      p.state = 2
    end
  elseif st == 2 then
    if not nidoRunning(self) then
      p.timer = 0
      p.state = 3
    end
  elseif st == 3 then
    p.timer = p.timer + 1
    if p.timer > 30 then
      local b = self:findTask(Scene3_Task_GengarBounce)
      if b then b.data.paused = true end
      p.gengarAttackLanded = false
      local t = self:createTask(Scene3_Task_GengarAttack, 4)
      t.data = { state = 0, sinIdx = 64, baseX = Bg.get(BG_SCENE3_GENGAR).scrollX * 256 }
      p.timer = 0
      p.state = 4
    end
  elseif st == 4 then
    if p.gengarAttackLanded then
      startNidorinoRecoil(self)
      p.state = 5
    end
  elseif st == 5 then
    if not nidoRunning(self) then
      local b = self:findTask(Scene3_Task_GengarBounce)
      if b then b.data.paused = false end
      p.timer = 0
      p.state = 6
    end
  elseif st == 6 then
    p.timer = p.timer + 1
    if p.timer > 16 then
      startNidorinoHop(self.nido, 8, 12, 5)
      p.state = 7
    end
  elseif st == 7 then
    if not nidoRunning(self) then
      startNidorinoHop(self.nido, 8, 12, 5)
      p.state = 8
    end
  elseif st == 8 then
    if not nidoRunning(self) then
      p.timer = 0
      p.state = 9
    end
  elseif st == 9 then
    p.timer = p.timer + 1
    if p.timer > 20 then
      startNidorinoAttack(self)
      p.timer = 0
      p.state = 10
    end
  elseif st == 10 then
    local b = self:findTask(Scene3_Task_GengarBounce)
    if not b or (b.data.state or 0) == 0 then
      if b then b.data.paused = true end
      self:createGengarSprites()
      p.state = 11
    end
  elseif st == 11 then
    Bg.hide(BG_SCENE3_GENGAR)
    p.timer = 0
    p.state = 12
  elseif st == 12 then
    p.timer = p.timer + 1
    if p.timer == 48 then
      self.pal:beginFade(Pal.mask({ 1, 2 }), 2, 0, 16, Pal.WHITE)
    end
    if p.timer > 120 then
      -- pokefirered/src/intro.c:1898
      local n = self.nido
      if n then
        n.x = n.x + n.x2
        n.y = n.y + n.y2
        Oam.setMatrixAnchor(n, 0, 42)
        n.callback = Oam.DUMMY_CALLBACK
        Oam.startAffineAnim(n, AFFINE_ZOOM)
      end
      for i, spr in ipairs(self.gengarSprites or {}) do
        Oam.startAffineAnim(spr, AFFINE_ZOOM)
        spr.callback = Oam.DUMMY_CALLBACK
        Oam.setMatrixAnchor(spr, GENGAR_ZOOM_ANCHORS[i][1], GENGAR_ZOOM_ANCHORS[i][2])
      end
      p.state = 13
      p.timer = 0
    end
  elseif st == 13 then
    p.timer = p.timer + 1
    if p.timer > 8 then
      self.pal:setBase(1, Pal.WHITE)
      self.pal:setBase(2, Pal.WHITE)
      self.pal:beginFade(ALL_BUT_0, -2, 0, 16, Pal.BLACK)
      p.state = 14
    end
  elseif st == 14 then
    if not self.pal:fadeActive() then
      p.timer = 0
      p.state = 15
    end
  elseif st == 15 then
    p.timer = p.timer + 1
    if p.timer > 60 then self:setCB("ExitToTitleScreen") end
  end
end

-- pokefirered/src/intro.c:1923
function IntroMovie.IntroCB_ExitToTitleScreen(self, p, t)
  if p.state == 0 then
    self.blackout = true
    p.state = 1
  else
    self:destroyTask(t)
    self.tasks = {}
    Oam.destroyAll()
    Bg.reset()
    self.isDone = true
    self.phase = "done"
  end
end

------------------------------------------------------------------------
-- Frame driver
------------------------------------------------------------------------

function IntroMovie:frame()
  self.frames = self.frames + 1
  if self.phase == "copyright" then
    self:copyrightFrame()
    return
  elseif self.phase == "wait_fade" then
    if not self.pal:updateFade() then
      self.phase = "setup"
      self.state = 0
    end
    return
  elseif self.phase == "setup" then
    self:setupFrame()
    return
  elseif self.phase ~= "intro" then
    return
  end
  -- pokefirered/src/intro.c:1060
  self:runTasks()
  if self.isDone then return end
  Oam.animateSprites()
  self.pal:updateFade()
end

function IntroMovie:update(input, dt)
  if input and input.wasPressed
      and (input:wasPressed("a") or input:wasPressed("start") or input:wasPressed("select")) then
    self.pendingSkip = true
  end
  self.accum = self.accum + (dt or 1 / 60)
  local step = 1 / IntroMovie.GBA_HZ
  while self.accum >= step and not self.isDone do
    self.accum = self.accum - step
    self._skipThisFrame = self.pendingSkip and self.phase == "intro"
    if self._skipThisFrame then self.pendingSkip = false end
    if self.phase ~= "intro" then self.pendingSkip = false end
    self:frame()
  end
  return self.isDone
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------

function IntroMovie:applyFx()
  local pal = self.pal
  local bld = self.bld
  local alpha = self.bldAlpha or { eva = 0, evb = 16 }
  for bg = 0, 3 do
    local L = Bg.get(bg)
    local slot = self.bgPal[bg]
    L.fx = slot and pal:fx(slot) or nil
    L.blend = (bld and bld["bg" .. bg]) and alpha or nil
    L.clip = self:bgClip(bg)
  end
  local objClip = self:bgClip("obj")
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    if s.inUse then
      s.fx = s.palSlot and pal:fx(s.palSlot) or nil
      s.blend = ((bld and bld.obj) or s.objBlend) and alpha or nil
      s.clip = objClip
    end
  end
end

function IntroMovie:bgClip(layer)
  if not self.win1 then return nil end
  local y0, y1 = self.win1.y0, self.win1.y1
  local clip = { x = 0, y = y0, w = Display.W, h = math.max(0, y1 - y0) }
  if layer == BG_SCENE3_GENGAR and self.win0 then
    clip = { x = self.win0.x1, y = y0, w = Display.W - self.win0.x1, h = clip.h }
  end
  return clip
end

function IntroMovie:draw()
  if self.blackout or self.isDone then
    love.graphics.clear(0, 0, 0, 1)
    return
  end
  self:applyFx()
  Display.composeHardware({
    clear = { 0, 0, 0, 1 },
    animate = false,
    build = true,
    pretOrder = true,
  })
end

return IntroMovie
