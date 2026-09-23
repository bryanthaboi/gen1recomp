local Display = require("src.core.game3.display")
local Audio = require("src.core.game3.audio")
local RomText = require("src.core.game3.rom_text")
local Oam = require("src.core.game3.oam")
local Pal = require("src.core.game3.pal_fade")
local Fx = require("src.core.game3.gba_fx")
local Trig = require("src.core.game3.trig")
local MapIds = require("src.core.game3.map_ids")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local Window = require("src.ui.game3.window")
local Naming = require("src.ui.game3.naming")
local BallOpen = require("src.core.game3.battle.ball_open")
local ModRuntime = require("src.mods.Runtime")

local Scene = {}
Scene.__index = Scene

Scene.GBA_HZ = 16777216 / 280896

local proxyPressed, proxyInput
local INPUT_PROXY = {
  wasPressed = function(_, k) return proxyPressed ~= nil and proxyPressed[k] == true end,
  isDown = function(_, k) return proxyInput ~= nil and proxyInput.isDown and proxyInput:isDown(k) or false end,
}

local MUS_ROUTE24 = 292
local MUS_NEW_GAME_INSTRUCT = 323
local MUS_NEW_GAME_INTRO = 324
local MUS_NEW_GAME_EXIT = 325
local SE_SELECT = 5
local SE_WARP_IN = 39
local SE_BALL_TRADE = 53
local SPECIES_NIDORAN_F = 29

local GUIDE_BLUE = { 0, 15, 24 }
local GUIDE_FADE_MASK = Pal.OBJ + (Pal.BG - Pal.mask({ 13 }))

local SLOT_BACKDROP = 0
local SLOT_BG1 = 0
local SLOT_TOPBAR = 13
local SLOT_TEXT = 15
local SLOT_PLAYER_PIC = 4
local SLOT_OAK_PIC = 6
local OBJ_MON, OBJ_BALL, OBJ_PARTICLES, OBJ_PLATFORM, OBJ_PIKACHU, OBJ_CURSOR = 0, 1, 2, 3, 4, 5

local MALE, FEMALE = 0, 1

local HINT_NEXT = "gText_ABUTTONNext"
local HINT_NEXT_BACK = "gText_ABUTTONNext_BBUTTONBack"

-- pokefirered/src/text.c:36
local ARROW_FRAMES = { 0, 1, 2, 1 }
local CURSOR_DELAY = 8

-- pokefirered/src/oak_speech.c:412
local ANIMS_PLATFORM = {
  { [0] = { { img = 0, dur = 0 }, "end" } },
  { [0] = { { img = 16, dur = 0 }, "end" } },
  { [0] = { { img = 32, dur = 0 }, "end" } },
}
-- pokefirered/src/oak_speech.c:479
local ANIMS_PIKA_BODY = { [0] = { { img = 0, dur = 30 }, { img = 16, dur = 30 }, { jump = 0 } } }
-- pokefirered/src/oak_speech.c:486
local ANIMS_PIKA_EARS = { [0] = {
  { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 },
  { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 8, dur = 12 }, { img = 0, dur = 12 },
  { img = 8, dur = 12 }, { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 },
  { img = 8, dur = 12 }, { img = 0, dur = 12 }, { img = 8, dur = 12 }, { jump = 0 },
} }
-- pokefirered/src/oak_speech.c:506
local ANIMS_PIKA_EYES = { [0] = {
  { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 },
  { img = 0, dur = 60 }, { img = 2, dur = 8 }, { img = 0, dur = 8 }, { img = 2, dur = 8 },
  { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 0, dur = 60 }, { img = 2, dur = 8 },
  { img = 0, dur = 8 }, { img = 2, dur = 8 }, { jump = 0 },
} }
-- pokefirered/src/pokeball.c:132
local ANIMS_BALL = {
  [0] = { { img = 0, dur = 1 }, "end" },
  [1] = { { img = 4, dur = 5 }, { img = 8, dur = 5 }, "end" },
  [2] = { { img = 4, dur = 5 }, { img = 0, dur = 5 }, "end" },
}
-- pokefirered/src/data.c:124
local AFFINE_EMERGE = { { v = 0x28, dur = 0 }, { v = 0x12, dur = 12 }, "end" }
-- pokefirered/src/data.c:131
local AFFINE_RETURN = { { v = -0x2, dur = 18 }, { v = -0x10, dur = 15 }, "end" }
local AFFINE_NORMAL = { { v = 0x100, dur = 0 }, "end" }

-- pokefirered/src/oak_speech.c:201
local CONTROLS_WINDOWS = {
  [2] = { { 6, 3 }, { 6, 10 }, { 6, 15 } },
  [3] = { { 6, 3 }, { 6, 8 }, { 6, 13 } },
}
-- pokefirered/src/oak_speech.c:576
local CONTROLS_PAGES = "sControlsGuide_Pages2And3_Strings"
-- pokefirered/src/oak_speech.c:342
local PIKA_PAGES = "sPikachuIntro_Strings"
local OAK_TEXT = {
  welcome = "gOakSpeech_Text_WelcomeToTheWorld",
  this_world = "gOakSpeech_Text_ThisWorld",
  inhabited = "gOakSpeech_Text_IsInhabitedFarAndWide",
  study = "gOakSpeech_Text_IStudyPokemon",
  tell_me = "gOakSpeech_Text_TellMeALittleAboutYourself",
  ask_gender = "gOakSpeech_Text_AskPlayerGender",
  your_name = "gOakSpeech_Text_YourNameWhatIsIt",
  confirm_player = "gOakSpeech_Text_SoYourNameIsPlayer",
  rival_intro = "gOakSpeech_Text_WhatWasHisName",
  rival_name_ask = "gOakSpeech_Text_YourRivalsNameWhatWasIt",
  confirm_rival = "gOakSpeech_Text_ConfirmRivalName",
  remember_rival = "gOakSpeech_Text_RememberRivalsName",
  lets_go = "gOakSpeech_Text_LetsGo",
}
-- pokefirered/src/oak_speech.c:2128
local function nameChoices(gender, rival)
  if rival then return RomText.list("sRivalNameChoices") end
  return RomText.list(gender == MALE and "sMaleNameChoices" or "sFemaleNameChoices")
end
Scene.nameChoices = nameChoices

local function idiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end

local function tileQuads(img, tileW, tileH, frameTiles, count)
  if not (img and love and love.graphics and love.graphics.newQuad) then return nil end
  local iw, ih = img:getDimensions()
  local cols = iw / 8
  local quads = {}
  for i = 0, count - 1 do
    local t = i * frameTiles
    quads[t] = love.graphics.newQuad((t % cols) * 8, math.floor(t / cols) * 8, tileW * 8, tileH * 8, iw, ih)
  end
  return quads
end

local function utf8Chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

------------------------------------------------------------------------
-- Text printer (pokefirered/src/text.c:629)
------------------------------------------------------------------------

local Printer = {}
Printer.__index = Printer

local function newPrinter(text, speed, canSpeedUp)
  local p = setmetatable({
    pages = {}, page = 1, revealed = 0, tokens = {}, pos = 1,
    active = true, state = "char", delay = 0, spedUp = false,
    canSpeedUp = canSpeedUp, arrowIdx = 0, arrowDelay = 0, arrowFrame = nil,
  }, Printer)
  local pageText = ""
  for _, ch in ipairs(utf8Chars(text)) do
    if ch == "\f" then
      p.pages[#p.pages + 1] = pageText
      pageText = ""
      p.tokens[#p.tokens + 1] = "P"
    elseif ch == "\n" then
      pageText = pageText .. ch
      p.tokens[#p.tokens + 1] = "N"
    else
      pageText = pageText .. ch
      p.tokens[#p.tokens + 1] = "C"
    end
  end
  p.pages[#p.pages + 1] = pageText
  p.tokens[#p.tokens + 1] = "E"
  if speed == 0 then
    p.textSpeed = 0
    while p.active do
      local tok = p.tokens[p.pos]
      p.pos = p.pos + 1
      if tok == "C" or tok == "N" then p.revealed = p.revealed + 1
      elseif tok == "E" or tok == nil then p.active = false end
    end
  else
    p.textSpeed = speed - 1
  end
  return p
end

function Printer:render(newAB, heldAB)
  if self.state == "char" then
    if heldAB and self.spedUp then self.delay = 0 end
    if self.delay > 0 and self.textSpeed > 0 then
      self.delay = self.delay - 1
      if self.canSpeedUp and newAB then
        self.spedUp = true
        self.delay = 0
      end
      return "update"
    end
    self.delay = self.textSpeed
    local tok = self.tokens[self.pos]
    self.pos = self.pos + 1
    if tok == "N" then
      self.revealed = self.revealed + 1
      return "repeat"
    end
    if tok == "P" then
      self.state = "clear"
      self.arrowIdx, self.arrowDelay = 0, 0
      return "update"
    end
    if tok == "E" or tok == nil then
      self.active = false
      return "finish"
    end
    self.revealed = self.revealed + 1
    return "print"
  else
    -- pokefirered/src/text.c:471
    if self.arrowDelay ~= 0 then
      self.arrowDelay = self.arrowDelay - 1
    else
      self.arrowFrame = ARROW_FRAMES[self.arrowIdx + 1]
      self.arrowDelay = CURSOR_DELAY
      self.arrowIdx = (self.arrowIdx + 1) % 4
    end
    if newAB then
      Audio.playSe(SE_SELECT)
      self.page = self.page + 1
      self.revealed = 0
      self.arrowFrame = nil
      self.state = "char"
    end
    return "update"
  end
end

function Printer:run(newAB, heldAB)
  if not self.active then return end
  for _ = 1, 64 do
    if self:render(newAB, heldAB) ~= "repeat" then return end
  end
end

function Printer:draw(x, y, opts)
  local text = self.pages[self.page] or ""
  local _, endX, endY = FrlgFont.draw(text, x, y, {
    maxWidth = opts.maxWidth or 240,
    limitChars = self.revealed,
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
    linePitch = opts.linePitch,
  })
  if self.state == "clear" and self.arrowFrame and endX then
    Chrome.promptArrow(endX, endY, self.arrowFrame)
  end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function Scene.new(assets, opts)
  opts = opts or {}
  local A = assets or {}
  local self = setmetatable({
    assets = A,
    pal = Pal.new(),
    tasks = {},
    accum = 0,
    pending = {},
    frames = 0,
    section = "controls",
    textSpeedOption = tonumber(opts.textSpeed) or 1,
    gender = MALE,
    playerName = nameChoices(MALE, false)[1],
    rivalName = nameChoices(MALE, true)[1],
    hasPlayerBeenNamed = false,
    coordOffsetX = 0,
    bg2X = 0,
    bld = nil,
    bldAlpha = { eva = 0, evb = 0 },
    backdrop = Pal.BLACK,
    bg1 = nil,
    pic = nil,
    win = {},
    bgVisible = { [0] = false, false, false },
    namingFade = nil,
    result = nil,
  }, Scene)
  if love and love.graphics and love.graphics.newQuad then
    self.q = {
      platform = tileQuads(A.platform, 4, 4, 16, 3),
      body = tileQuads(A.pikachuBody, 4, 4, 16, 2),
      ears = tileQuads(A.pikachuEars, 4, 2, 8, 2),
      eyes = tileQuads(A.pikachuEyes, 2, 1, 2, 2),
      ball = tileQuads(A.ballPoke, 2, 2, 4, 3),
    }
  else
    self.q = {}
  end
  self.textSpeed = ({ [0] = 8, 4, 1 })[self.textSpeedOption] or 4
  Oam.destroyAll()
  BallOpen.reset()
  self:createTask(Scene.Task_NewGameScene, 0)
  return self
end

function Scene:destroy()
  Oam.destroyAll()
  BallOpen.reset()
  self.tasks = {}
end

function Scene:createTask(fn, priority)
  local t = { func = fn, priority = priority, data = {}, alive = true, state = 0 }
  local pos = #self.tasks + 1
  for i, other in ipairs(self.tasks) do
    if other.priority > priority then
      pos = i
      break
    end
  end
  table.insert(self.tasks, pos, t)
  if self.runIdx and pos <= self.runIdx then self.runIdx = self.runIdx + 1 end
  return t
end

function Scene:findTask(fn)
  for _, t in ipairs(self.tasks) do
    if t.alive and t.func == fn then return t end
  end
  return nil
end

local function destroyTask(t)
  if t then t.alive = false end
end

function Scene:runTasks()
  self.runIdx = 1
  while self.runIdx <= #self.tasks do
    local t = self.tasks[self.runIdx]
    if t.alive then t.func(self, t) end
    self.runIdx = self.runIdx + 1
  end
  self.runIdx = nil
  local keep = {}
  for _, t in ipairs(self.tasks) do
    if t.alive then keep[#keep + 1] = t end
  end
  self.tasks = keep
end

local function createSprite(self, tmpl, x, y, sub)
  local id, spr = Oam.createSprite(tmpl, x, y, sub)
  if not spr then return nil end
  spr._id = id
  spr.palSlot = Pal.objSlot(tmpl.palSlot or 0)
  spr.objBlend = tmpl.objBlend
  spr.coordOffset = tmpl.coordOffset
  if tmpl.affine then
    spr.oam.affineMode = Oam.AFFINE_NORMAL
    spr.affineScale = 1
  end
  return spr
end

local function destroySprite(spr)
  if spr and spr.inUse then Oam.destroySprite(spr._id) end
end

function Scene:fadeActive()
  return self.pal:fadeActive()
end

function Scene:printerActive()
  return self.printer ~= nil and self.printer.active
end

-- pokefirered/src/oak_speech.c:1124
function Scene:_answered(label, value, saveKey)
  if not ModRuntime.wants("intro.oak_speech.answered") then return end
  ModRuntime.emit("intro.oak_speech.answered", {
    speech = self, step = { id = label }, index = self._oakStep or 0,
    label = label, value = value, saveKey = saveKey,
  })
end

function Scene:oakPrint(key, speed)
  local text = RomText.ascii(assert(OAK_TEXT[key], key), { playerName = self.playerName, rivalName = self.rivalName })
  text = text:gsub("\\p", "\f"):gsub("\\l", "\n")
  if self.section == "oak" then
    self._oakStep = (self._oakStep or 0) + 1
    if ModRuntime.wants("intro.oak_speech.step") then
      ModRuntime.emit("intro.oak_speech.step", {
        speech = self, step = { id = key, text = text }, index = self._oakStep,
      })
    end
  end
  self.win.dialog = true
  self.printer = newPrinter(text, speed == nil and self.textSpeed or speed, true)
end

function Scene:clearDialog()
  self.win.dialog = false
  self.printer = nil
end

------------------------------------------------------------------------
-- Sprites
------------------------------------------------------------------------

local function SpriteCB_TextCursor(s)
  -- pokefirered/src/text.c:1284
  local d = s.data
  if d[1] ~= 0 then
    d[1] = d[1] - 1
  else
    d[1] = CURSOR_DELAY
    if d[2] == 0 then s.y2 = 0
    elseif d[2] == 1 then s.y2 = 1
    elseif d[2] == 2 then s.y2 = 2
    else
      s.y2 = 1
      d[2] = 0
      return
    end
    d[2] = d[2] + 1
  end
end

function Scene:createTextCursor(x, y, priority)
  -- pokefirered/src/text.c:1313
  local spr = createSprite(self, {
    dims = Oam.SQUARE_16, priority = priority, image = Chrome.textCursorImage(),
    callback = SpriteCB_TextCursor, palSlot = OBJ_CURSOR,
  }, x + 3, y + 4, 0)
  if spr then spr.data[1] = CURSOR_DELAY end
  return spr
end

function Scene:createPikachuOrPlatform(t, kind)
  -- pokefirered/src/oak_speech.c:1904
  local A = self.assets
  local ids = {}
  if kind == "pikachu" then
    local body = createSprite(self, {
      dims = Oam.SQUARE_32, priority = 0, image = A.pikachuBody,
      anims = ANIMS_PIKA_BODY, animQuads = self.q.body, palSlot = OBJ_PIKACHU,
    }, 16, 17, 2)
    local function follow(s)
      s.y2 = body and (body.animCmdIndex or 1) - 1 or 0
    end
    local ears = createSprite(self, {
      dims = Oam.HRECT_32x16, priority = 0, image = A.pikachuEars,
      anims = ANIMS_PIKA_EARS, animQuads = self.q.ears, palSlot = OBJ_PIKACHU, callback = follow,
    }, 16, 9, 3)
    local eyes = createSprite(self, {
      dims = Oam.HRECT_16x8, priority = 0, image = A.pikachuEyes,
      anims = ANIMS_PIKA_EYES, animQuads = self.q.eyes, palSlot = OBJ_PIKACHU, callback = follow,
    }, 24, 13, 1)
    ids = { body, ears, eyes }
  else
    for i = 0, 2 do
      local spr = createSprite(self, {
        dims = Oam.SQUARE_32, priority = 2, image = A.platform,
        anims = ANIMS_PLATFORM[i + 1], animQuads = self.q.platform,
        palSlot = OBJ_PLATFORM, objBlend = true, coordOffset = true,
      }, i * 32 + 88, 112, 1)
      if spr then spr.animPaused = true end
      ids[i + 1] = spr
    end
  end
  t.data.platform = ids
end

function Scene:destroyPikachuOrPlatform(t)
  for _, spr in ipairs(t.data.platform or {}) do destroySprite(spr) end
end

------------------------------------------------------------------------
-- Pic fade tasks (pokefirered/src/oak_speech.c:2014)
------------------------------------------------------------------------

local function Task_SlowFadeIn(self, t)
  local d = t.data
  if d.bt1 == 0 then
    d.parent.data.picFadeState = 1
    destroyTask(t)
    for _, spr in ipairs(d.platform or {}) do spr.invisible = true end
  elseif d.fadeTimer ~= 0 then
    d.fadeTimer = d.fadeTimer - 1
  else
    d.fadeTimer = d.delay
    d.bt1 = d.bt1 - 1
    d.bt2 = d.bt2 + 1
    if d.bt1 == 8 then
      for _, spr in ipairs(d.platform or {}) do spr.invisible = not spr.invisible end
    end
    self.bldAlpha = { eva = d.bt1, evb = d.bt2 }
  end
end

local function Task_SlowFadeOut(self, t)
  local d = t.data
  if d.bt1 == 16 then
    if not self:fadeActive() then
      d.parent.data.picFadeState = 1
      destroyTask(t)
    end
  elseif d.fadeTimer ~= 0 then
    d.fadeTimer = d.fadeTimer - 1
  else
    d.fadeTimer = d.delay
    d.bt1 = d.bt1 + 2
    d.bt2 = d.bt2 - 2
    if d.bt1 == 8 then
      for _, spr in ipairs(d.platform or {}) do spr.invisible = not spr.invisible end
    end
    self.bldAlpha = { eva = d.bt1, evb = d.bt2 }
  end
end

function Scene:createFadeInTask(t, delay)
  -- pokefirered/src/oak_speech.c:2045
  self.bld = { pic = true }
  self.bldAlpha = { eva = 16, evb = 0 }
  t.data.picFadeState = 0
  local t2 = self:createTask(Task_SlowFadeIn, 0)
  t2.data = { parent = t, bt1 = 16, bt2 = 0, delay = delay, fadeTimer = delay, platform = t.data.platform }
end

function Scene:createFadeOutTask(t, delay)
  -- pokefirered/src/oak_speech.c:2097
  self.bld = { pic = true }
  self.bldAlpha = { eva = 0, evb = 16 }
  t.data.picFadeState = 0
  local t2 = self:createTask(Task_SlowFadeOut, 0)
  t2.data = { parent = t, bt1 = 0, bt2 = 16, delay = delay, fadeTimer = delay, platform = t.data.platform }
end

-- pokefirered/src/oak_speech.c:1966
function Scene:loadTrainerPic(which)
  local A = self.assets
  if which == "male" then
    self.pic = { image = A.boySprite, slot = SLOT_PLAYER_PIC }
  elseif which == "female" then
    self.pic = { image = A.girlSprite, slot = SLOT_PLAYER_PIC }
  elseif which == "rival" then
    self.pic = { image = A.rivalSprite, slot = SLOT_OAK_PIC }
  else
    self.pic = { image = A.oakSprite, slot = SLOT_OAK_PIC }
  end
  self.pal:restore(self.pic.slot)
  self.pal:restore(self.pic.slot + 1)
end

function Scene:loadPlayerPic()
  self:loadTrainerPic(self.gender == MALE and "male" or "female")
end

function Scene:clearTrainerPic()
  if self.pic then self.pic.hidden = true end
end

------------------------------------------------------------------------
-- Poke Ball (pokefirered/src/pokeball.c:1026)
------------------------------------------------------------------------

function Scene:ballFadeColor()
  local d = BallOpen.data()
  local c = d and d.fadeColors and d.fadeColors[1]
  return c or { 31, 31, 31 }
end

local function Task_FadeMon_ToNormal_Step(self, t)
  -- pokefirered/src/battle_anim_special.c:1920
  local d = t.data
  if d.d2 <= 16 then
    self.pal:blend(Pal.mask(nil, { OBJ_MON }), d.d0, self:ballFadeColor())
    d.d0 = d.d0 + d.d1
    d.d2 = d.d2 + 1
  else
    destroyTask(t)
  end
end

local function Task_FadeMon_ToNormal(self, t)
  -- pokefirered/src/battle_anim_special.c:1910
  if not self:fadeActive() then
    self.pal:beginFade(t.data.mask, 0, 16, 0, Pal.WHITE)
    t.func = Task_FadeMon_ToNormal_Step
  end
end

function Scene:launchBallFadeMon(mask)
  -- pokefirered/src/battle_anim_special.c:1865
  local t = self:createTask(Task_FadeMon_ToNormal, 5)
  t.data = { mask = mask, d0 = 16, d1 = -1, d2 = 0 }
  self.pal:blend(Pal.mask(nil, { OBJ_MON }), 16, self:ballFadeColor())
  self.pal:beginFade(mask, 0, 0, 16, Pal.WHITE)
end

function Scene:ballOpen(ball, mask)
  Oam.startAnim(ball, 1)
  BallOpen.startParticles(ball.x, ball.y)
  self:launchBallFadeMon(mask)
end

function Scene:createReleaseBall(mon, x, y, delay, mask)
  -- pokefirered/src/pokeball.c:1026
  local ball = createSprite(self, {
    dims = Oam.SQUARE_16, priority = 0, image = self.assets.ballPoke,
    anims = ANIMS_BALL, animQuads = self.q.ball, palSlot = OBJ_BALL,
  }, x, y, 0)
  if not ball then return end
  local finalX, finalY = mon.x, mon.y
  mon.x, mon.y = x, y
  mon.invisible = true
  local scene = self
  local trig = 0
  local function flyOut(s)
    -- pokefirered/src/pokeball.c:1076
    local emerged, atFinal = false, false
    if s.animEnded then s.invisible = true end
    if mon.affineAnimEnded then
      Oam.startAffineAnim(mon, AFFINE_NORMAL)
      emerged = true
    end
    mon.x = idiv((finalX - s.x) * trig, 128) + s.x
    mon.y = idiv((finalY - s.y) * trig, 128) + s.y
    if trig < 128 then
      local sine = -idiv(Trig.SINE[trig % 256 + 1], 8)
      trig = trig + 4
      mon.x2, mon.y2 = sine, sine
    else
      mon.x, mon.y = finalX, finalY
      mon.x2, mon.y2 = 0, 0
      atFinal = true
    end
    if s.animEnded and emerged and atFinal then destroySprite(s) end
  end
  ball.callback = function(s)
    if delay == 0 then
      scene:ballOpen(s, mask)
      s.callback = flyOut
      mon.invisible = false
      Oam.startAffineAnim(mon, AFFINE_EMERGE)
      Oam.animateSprite(mon)
      trig = 0
    else
      delay = delay - 1
    end
  end
  return ball
end

function Scene:createTradeBall(mon, x, y, delay, mask)
  -- pokefirered/src/pokeball.c:1138
  local ball = createSprite(self, {
    dims = Oam.SQUARE_16, priority = 0, image = self.assets.ballPoke,
    anims = ANIMS_BALL, animQuads = self.q.ball, palSlot = OBJ_BALL,
  }, x, y, 0)
  if not ball then return nil end
  local scene = self
  local timer, rise = 0, 0
  local function ending(s)
    if s.animEnded then s.callback = Oam.DUMMY_CALLBACK end
  end
  local function sendOff(s)
    -- pokefirered/src/pokeball.c:1180
    timer = timer + 1
    if timer == 11 then Audio.playSe(SE_BALL_TRADE) end
    if mon.affineAnimEnded then
      Oam.startAnim(s, 2)
      mon.invisible = true
      timer = 0
      s.callback = ending
    else
      rise = rise + 96
      mon.y2 = math.floor(-rise / 256)
    end
  end
  ball.callback = function(s)
    if delay == 0 then
      scene:ballOpen(s, mask)
      s.callback = sendOff
      Oam.startAffineAnim(mon, AFFINE_RETURN)
      Oam.animateSprite(mon)
      rise = 0
    else
      delay = delay - 1
    end
  end
  return ball
end

------------------------------------------------------------------------
-- Controls guide (pokefirered/src/oak_speech.c:708)
------------------------------------------------------------------------

function Scene:setTopBar(title, hint)
  self.win.topbar = { title = title, hint = hint }
end

function Scene:controlsLoadPage1()
  -- pokefirered/src/oak_speech.c:797
  self:setTopBar("gText_Controls", HINT_NEXT)
  self.win.guide = { page = 1 }
  self.bg1 = { image = self.assets.controlsPage1, topbarSplit = true }
end

function Scene.Task_NewGameScene(self, t)
  local st = t.state
  if st == 0 then
    Oam.destroyAll()
    self.pal:reset()
    self.backdrop = Pal.BLACK
  elseif st == 7 then
    self.backdrop = GUIDE_BLUE
    self.currentPage = 1
    self:controlsLoadPage1()
    t.data.cursor = self:createTextCursor(230, 149, 0)
    self.pal:blend(Pal.ALL, 16, Pal.BLACK)
  elseif st == 10 then
    self.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    self.bgVisible[0], self.bgVisible[1] = true, true
    Audio.playSong(MUS_NEW_GAME_INSTRUCT, { restart = true })
    t.func = Scene.Task_ControlsGuide_HandleInput
    t.state = 0
    return
  end
  t.state = st + 1
end

function Scene.Task_ControlsGuide_LoadPage(self, t)
  -- pokefirered/src/oak_speech.c:809
  if self.currentPage == 1 then
    self:controlsLoadPage1()
  else
    self:setTopBar(nil, HINT_NEXT_BACK)
    self.win.guide = { page = self.currentPage }
    self.bg1 = { image = self.assets["controlsPage" .. self.currentPage], topbarSplit = true }
  end
  self.pal:beginFade(GUIDE_FADE_MASK, -1, 16, 0, GUIDE_BLUE)
  t.func = Scene.Task_ControlsGuide_HandleInput
end

function Scene.Task_ControlsGuide_HandleInput(self, t)
  -- pokefirered/src/oak_speech.c:839
  if self:fadeActive() then return end
  local p = self.input
  if p.a or p.b then
    if p.a then
      t.data.delta = 1
      if self.currentPage < 3 then
        self.pal:beginFade(GUIDE_FADE_MASK, -1, 0, 16, GUIDE_BLUE)
      end
    else
      if self.currentPage == 1 then return end
      t.data.delta = -1
      self.pal:beginFade(GUIDE_FADE_MASK, -1, 0, 16, GUIDE_BLUE)
    end
    Audio.playSe(SE_SELECT)
    t.func = Scene.Task_ControlsGuide_ChangePage
  end
end

function Scene.Task_ControlsGuide_ChangePage(self, t)
  -- pokefirered/src/oak_speech.c:867
  if self:fadeActive() then return end
  self.currentPage = self.currentPage + t.data.delta
  if self.currentPage <= 3 then
    self.win.guide = nil
    t.func = Scene.Task_ControlsGuide_LoadPage
  else
    self.pal:beginFade(Pal.ALL, 2, 0, 16, Pal.BLACK)
    t.func = Scene.Task_ControlsGuide_Clear
  end
end

function Scene.Task_ControlsGuide_Clear(self, t)
  -- pokefirered/src/oak_speech.c:907
  if self:fadeActive() then return end
  self.win.guide = nil
  self.bg1 = nil
  destroySprite(t.data.cursor)
  t.data.cursor = nil
  self.backdrop = Pal.BLACK
  t.data.timer = 32
  t.func = Scene.Task_PikachuIntro_LoadPage1
end

------------------------------------------------------------------------
-- Pikachu intro (pokefirered/src/oak_speech.c:941)
------------------------------------------------------------------------

function Scene.Task_PikachuIntro_LoadPage1(self, t)
  local d = t.data
  if d.timer ~= 0 then
    d.timer = d.timer - 1
    return
  end
  self.section = "pikachu"
  Audio.playSong(MUS_NEW_GAME_INTRO, { restart = true })
  self:setTopBar(nil, HINT_NEXT)
  self.bg1 = { image = self.assets.pikachuBg or self.assets.pikachuIntroBg }
  self.currentPage = 1
  t.state = 0
  d.blendTarget = 16
  self.win.pika = { text = RomText.at(PIKA_PAGES, 0) }
  d.cursor = self:createTextCursor(226, 145, 0)
  if d.cursor then d.cursor.objBlend = true end
  self:createPikachuOrPlatform(t, "pikachu")
  self.pal:beginFade(Pal.ALL, 2, 16, 0, Pal.BLACK)
  t.func = Scene.Task_PikachuIntro_HandleInput
end

function Scene.Task_PikachuIntro_HandleInput(self, t)
  -- pokefirered/src/oak_speech.c:977
  local d = t.data
  local st = t.state
  local p = self.input
  if st == 0 then
    if not self:fadeActive() then
      self.win0Pika = true
      t.state = 1
    end
  elseif st == 1 then
    if p.a or p.b then
      if p.a then
        self.currentPage = self.currentPage + 1
      else
        if self.currentPage == 1 then return end
        self.currentPage = self.currentPage - 1
      end
      Audio.playSe(SE_SELECT)
      if self.currentPage == 4 then
        t.state = 4
      else
        self.bld = { bg0 = true }
        self.bldAlpha = { eva = 16, evb = 0 }
        t.state = 2
      end
    end
  elseif st == 2 then
    d.blendTarget = d.blendTarget - 2
    self.bldAlpha = { eva = d.blendTarget, evb = 16 - d.blendTarget }
    if d.blendTarget <= 0 then
      self.win.pika = { text = RomText.at(PIKA_PAGES, self.currentPage - 1) }
      if self.currentPage == 1 then
        self:setTopBar(nil, HINT_NEXT)
      else
        self:setTopBar(nil, HINT_NEXT_BACK)
      end
      t.state = 3
    end
  elseif st == 3 then
    d.blendTarget = d.blendTarget + 2
    self.bldAlpha = { eva = d.blendTarget, evb = 16 - d.blendTarget }
    if d.blendTarget >= 16 then
      d.blendTarget = 16
      self.bld = nil
      t.state = 1
    end
  elseif st == 4 then
    destroySprite(d.cursor)
    d.cursor = nil
    Audio.playSong(MUS_NEW_GAME_EXIT, { restart = true })
    d.blendTarget = 24
    t.state = 5
  else
    if d.blendTarget ~= 0 then
      d.blendTarget = d.blendTarget - 1
    else
      t.state = 0
      self.currentPage = 0
      self.win0Pika = false
      self.pal:beginFade(Pal.ALL, 2, 0, 16, Pal.BLACK)
      t.func = Scene.Task_PikachuIntro_Clear
    end
  end
end

function Scene.Task_PikachuIntro_Clear(self, t)
  -- pokefirered/src/oak_speech.c:1080
  if self:fadeActive() then return end
  self.win.topbar = nil
  self.win.pika = nil
  self.bg1 = nil
  self:destroyPikachuOrPlatform(t)
  t.data.timer = 80
  t.func = Scene.Task_OakSpeech_Init
end

------------------------------------------------------------------------
-- Oak speech (pokefirered/src/oak_speech.c:1099)
------------------------------------------------------------------------

function Scene.Task_OakSpeech_Init(self, t)
  local d = t.data
  if d.timer ~= 0 then
    d.timer = d.timer - 1
    return
  end
  self.section = "oak"
  self._oakStep = 0
  if ModRuntime.wants("intro.oak_speech.started") then
    ModRuntime.emit("intro.oak_speech.started", { speech = self, steps = {} })
  end
  self.bg1 = { image = self.assets.oakSpeechBg }
  d.nidoran = createSprite(self, {
    dims = Oam.SQUARE_64, priority = 1, image = self.assets.nidoranFront,
    palSlot = OBJ_MON, affine = true,
  }, 96, 96, 1)
  if d.nidoran then d.nidoran.invisible = true end
  self:loadTrainerPic("oak")
  self:createPikachuOrPlatform(t, "platform")
  Audio.playSong(MUS_ROUTE24, { restart = true })
  self.pal:beginFade(Pal.ALL, 5, 16, 0, Pal.BLACK)
  d.timer = 80
  self.bgVisible[2] = true
  t.func = Scene.Task_OakSpeech_WelcomeToTheWorld
end

function Scene.Task_OakSpeech_WelcomeToTheWorld(self, t)
  local d = t.data
  if self:fadeActive() then return end
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    self:oakPrint("welcome")
    t.func = Scene.Task_OakSpeech_ThisWorld
  end
end

function Scene.Task_OakSpeech_ThisWorld(self, t)
  if self:printerActive() then return end
  self:oakPrint("this_world")
  t.data.timer = 30
  t.func = Scene.Task_OakSpeech_ReleaseNidoranFFromPokeBall
end

function Scene.Task_OakSpeech_ReleaseNidoranFFromPokeBall(self, t)
  -- pokefirered/src/oak_speech.c:1165
  local d = t.data
  if self:printerActive() then return end
  if d.timer ~= 0 then d.timer = d.timer - 1 end
  local mon = d.nidoran
  if mon then
    mon.invisible = false
    self:createReleaseBall(mon, 100, 66, 32, Pal.OBJ + 0x1FFF)
  end
  t.func = Scene.Task_OakSpeech_IsInhabitedFarAndWide
  d.timer = 0
end

function Scene.Task_OakSpeech_IsInhabitedFarAndWide(self, t)
  -- pokefirered/src/oak_speech.c:1183
  local d = t.data
  if Audio.isCryFinished() then
    if d.timer >= 96 then t.func = Scene.Task_OakSpeech_IStudyPokemon end
  end
  if d.timer < 0x4000 then
    d.timer = d.timer + 1
    if d.timer == 32 then
      self:oakPrint("inhabited")
      Audio.playCry(SPECIES_NIDORAN_F, 0)
    end
  end
end

function Scene.Task_OakSpeech_IStudyPokemon(self, t)
  if self:printerActive() then return end
  self:oakPrint("study")
  t.func = Scene.Task_OakSpeech_ReturnNidoranFToPokeBall
end

function Scene.Task_OakSpeech_ReturnNidoranFToPokeBall(self, t)
  -- pokefirered/src/oak_speech.c:1210
  local d = t.data
  if self:printerActive() then return end
  self:clearDialog()
  if d.nidoran then
    d.ball = self:createTradeBall(d.nidoran, 100, 66, 32, Pal.OBJ + 0x1F3F)
  end
  d.timer = 48
  d.spriteTimer = 64
  t.func = Scene.Task_OakSpeech_TellMeALittleAboutYourself
end

function Scene.Task_OakSpeech_TellMeALittleAboutYourself(self, t)
  -- pokefirered/src/oak_speech.c:1225
  local d = t.data
  if d.spriteTimer ~= 0 then
    if d.spriteTimer < 24 and d.nidoran then d.nidoran.y = d.nidoran.y - 1 end
    d.spriteTimer = d.spriteTimer - 1
  else
    if d.timer == 48 then
      destroySprite(d.nidoran)
      destroySprite(d.ball)
      d.nidoran, d.ball = nil, nil
    end
    if d.timer ~= 0 then
      d.timer = d.timer - 1
    else
      self:oakPrint("tell_me")
      t.func = Scene.Task_OakSpeech_FadeOutOak
    end
  end
end

function Scene.Task_OakSpeech_FadeOutOak(self, t)
  if self:printerActive() then return end
  self:clearDialog()
  self:createFadeInTask(t, 2)
  t.data.timer = 48
  t.func = Scene.Task_OakSpeech_AskPlayerGender
end

function Scene.Task_OakSpeech_AskPlayerGender(self, t)
  -- pokefirered/src/oak_speech.c:1267
  local d = t.data
  if d.picFadeState == 0 then return end
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    d.picPosX = -60
    self:clearTrainerPic()
    self:oakPrint("ask_gender")
    t.func = Scene.Task_OakSpeech_ShowGenderOptions
  end
end

function Scene.Task_OakSpeech_ShowGenderOptions(self, t)
  if self:printerActive() then return end
  -- pokefirered/src/oak_speech.c:1291
  self.win.menu = {
    kind = "gender", left = 18, top = 9, width = 9, height = 4,
    items = { { RomText.plain("gText_Boy"), 8, 1 }, { RomText.plain("gText_Girl"), 8, 17 } },
    cursorX = 0, cursorY = 1, pitch = 16, cursor = 0, wrap = false,
  }
  t.func = Scene.Task_OakSpeech_HandleGenderInput
end

function Scene:menuInput(wrap)
  -- pokefirered/src/menu.c:342
  local m = self.win.menu
  local p = self.input
  if not m then return "none" end
  if p.a then
    Audio.playSe(SE_SELECT)
    return m.cursor
  end
  if p.b then return "b" end
  local n = #m.items
  local delta = p.up and -1 or (p.down and 1 or 0)
  if delta ~= 0 then
    local old = m.cursor
    local pos = m.cursor + delta
    if wrap then
      if pos < 0 then pos = n - 1 elseif pos > n - 1 then pos = 0 end
      Audio.playSe(SE_SELECT)
    else
      pos = math.max(0, math.min(n - 1, pos))
      if pos ~= old then Audio.playSe(SE_SELECT) end
    end
    m.cursor = pos
  end
  return "none"
end

function Scene.Task_OakSpeech_HandleGenderInput(self, t)
  -- pokefirered/src/oak_speech.c:1309
  local r = self:menuInput(false)
  if r == 0 then
    self.gender = MALE
  elseif r == 1 then
    self.gender = FEMALE
  else
    return
  end
  self:_answered("gender", self.gender, "gender")
  t.func = Scene.Task_OakSpeech_ClearGenderWindows
end

function Scene.Task_OakSpeech_ClearGenderWindows(self, t)
  self.win.menu = nil
  self:clearDialog()
  t.func = Scene.Task_OakSpeech_LoadPlayerPic
end

function Scene.Task_OakSpeech_LoadPlayerPic(self, t)
  -- pokefirered/src/oak_speech.c:1340
  self:loadPlayerPic()
  self:createFadeOutTask(t, 2)
  t.data.timer = 32
  t.func = Scene.Task_OakSpeech_YourNameWhatIsIt
end

function Scene.Task_OakSpeech_YourNameWhatIsIt(self, t)
  local d = t.data
  if d.picFadeState == 0 then return end
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    d.picPosX = 0
    self:oakPrint("your_name")
    t.func = Scene.Task_OakSpeech_FadeOutForPlayerNamingScreen
  end
end

function Scene.Task_OakSpeech_FadeOutForPlayerNamingScreen(self, t)
  -- pokefirered/src/oak_speech.c:1370
  if self:printerActive() then return end
  self.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
  self.hasPlayerBeenNamed = false
  t.func = Scene.Task_OakSpeech_DoNamingScreen
end

function Scene.Task_OakSpeech_MoveRivalDisplayNameOptions(self, t)
  -- pokefirered/src/oak_speech.c:1380
  local d = t.data
  if self:printerActive() then return end
  if d.picPosX > -60 then
    d.picPosX = d.picPosX - 2
    self.coordOffsetX = self.coordOffsetX + 2
    self.bg2X = self.bg2X - 2
  else
    d.picPosX = -60
    self:printNameChoices()
    t.func = Scene.Task_OakSpeech_HandleRivalNameInput
  end
end

function Scene:printNameChoices()
  -- pokefirered/src/oak_speech.c:2117
  local names
  if not self.hasPlayerBeenNamed then
    names = nameChoices(self.gender, false)
  else
    names = nameChoices(self.gender, true)
  end
  local items = { { RomText.plain("gOtherText_NewName"), 8, 1 } }
  for i = 1, RomText.count("sRivalNameChoices") do items[#items + 1] = { names[i], 8, 16 * i + 1 } end
  self.win.menu = {
    kind = "names", left = 2, top = 2, width = 12, height = 10,
    items = items, cursorX = 0, cursorY = 1, pitch = 16, cursor = 0,
  }
end

function Scene.Task_OakSpeech_RepeatNameQuestion(self, t)
  -- pokefirered/src/oak_speech.c:1401
  self:printNameChoices()
  if not self.hasPlayerBeenNamed then
    self:oakPrint("your_name", 0)
  else
    self:oakPrint("rival_name_ask", 0)
  end
  t.func = Scene.Task_OakSpeech_HandleRivalNameInput
end

function Scene:getDefaultName(choice)
  -- pokefirered/src/oak_speech.c:2138
  if not self.hasPlayerBeenNamed then
    local list = nameChoices(self.gender, false)
    local r = require("src.core.game3.rng").Random()
    self.playerName = list[(r % #list) + 1]
    self:_answered("name", self.playerName, "name")
  else
    self.rivalName = nameChoices(self.gender, true)[choice + 1]
    self:_answered("rivalName", self.rivalName, "rivalName")
  end
end

function Scene.Task_OakSpeech_HandleRivalNameInput(self, t)
  -- pokefirered/src/oak_speech.c:1413
  local r = self:menuInput(true)
  if r == 0 then
    Audio.playSe(SE_SELECT)
    self.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    t.func = Scene.Task_OakSpeech_DoNamingScreen
  elseif type(r) == "number" and r >= 1 and r <= 4 then
    Audio.playSe(SE_SELECT)
    self.win.menu = nil
    self:getDefaultName(r - 1)
    t.data.nameNotConfirmed = true
    t.func = Scene.Task_OakSpeech_ConfirmName
  end
end

function Scene.Task_OakSpeech_DoNamingScreen(self, t)
  -- pokefirered/src/oak_speech.c:1440
  if self:fadeActive() then return end
  self:getDefaultName(0)
  local rival = self.hasPlayerBeenNamed
  if rival then self.win.menu = nil end
  self:destroyPikachuOrPlatform(t)
  self:enterNaming(rival)
  destroyTask(t)
end

------------------------------------------------------------------------
-- Naming screen hand-off (pokefirered/src/naming_screen.c)
------------------------------------------------------------------------

function Scene:enterNaming(rival)
  self.naming = { rival = rival, stage = "setup", timer = 8, pal = Pal.new() }
  self.naming.pal:blend(Pal.ALL, 16, Pal.BLACK)
  local scene = self
  Naming.open({
    title = RomText.plain(rival and "gText_RivalsName" or "gText_YourName"),
    maxLen = 7,
    seed = rival and self.rivalName or self.playerName,
    template = rival and "RIVAL" or "PLAYER",
    gender = self.gender,
    hold = true,
    onDone = function(name)
      if name and name ~= "" then
        if rival then scene.rivalName = name else scene.playerName = name end
        if rival then
          scene:_answered("rivalName", name, "rivalName")
        else
          scene:_answered("name", name, "name")
        end
      end
      scene.naming.stage = "fade_out"
      scene.naming.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    end,
  })
end

function Scene:namingFrame()
  local n = self.naming
  if n.stage == "setup" then
    n.timer = n.timer - 1
    if n.timer <= 0 then
      n.stage = "fade_in"
      n.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    end
  elseif n.stage == "fade_in" then
    n.pal:updateFade()
    if not n.pal:fadeActive() then n.stage = "input" end
  elseif n.stage == "input" then
    Naming.handleInput(self.inputProxy)
    Naming.update(1 / Scene.GBA_HZ)
  elseif n.stage == "fade_out" then
    n.pal:updateFade()
    if not n.pal:fadeActive() then
      Naming.dismiss()
      n.stage = "return"
      n.timer = 0
    end
  elseif n.stage == "return" then
    self:returnFromNamingFrame()
  end
end

function Scene:returnFromNamingFrame()
  -- pokefirered/src/oak_speech.c:1788
  local n = self.naming
  local st = n.timer
  if st == 0 then
    self.tasks = {}
    Oam.destroyAll()
    BallOpen.reset()
    self.pal:reset()
    self.pal:blend(Pal.ALL, 16, Pal.BLACK)
    self.bld = nil
    self:clearDialog()
    self.win.menu = nil
    self.bg2X = 0
  elseif st == 6 then
    local t = self:createTask(Scene.Task_OakSpeech_ConfirmName, 0)
    if not self.hasPlayerBeenNamed then
      self:loadPlayerPic()
    else
      self:loadTrainerPic("rival")
    end
    t.data.picPosX = -60
    self.coordOffsetX = 60
    self.bg2X = -60
    self:createPikachuOrPlatform(t, "platform")
    t.data.nameNotConfirmed = true
  elseif st == 7 then
    self.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    self.bgVisible[0], self.bgVisible[1], self.bgVisible[2] = true, true, true
    self.naming = nil
    return
  end
  n.timer = st + 1
end

------------------------------------------------------------------------
-- Name confirmation and rival
------------------------------------------------------------------------

function Scene.Task_OakSpeech_ConfirmName(self, t)
  -- pokefirered/src/oak_speech.c:1460
  local d = t.data
  if self:fadeActive() then return end
  if d.nameNotConfirmed then
    self:oakPrint(self.hasPlayerBeenNamed and "confirm_rival" or "confirm_player")
    d.nameNotConfirmed = false
    d.timer = 25
  elseif not self:printerActive() then
    if d.timer ~= 0 then
      d.timer = d.timer - 1
    else
      -- pokefirered/src/menu.c:531
      local yes, no = RomText.plain("gText_YesNo"):match("^(.-)\n(.*)$")
      self.win.menu = {
        kind = "yesno", left = 2, top = 2, width = 6, height = 4,
        items = { { yes, 8, 2 }, { no, 8, 2 + FrlgFont.LINE_PITCH } },
        cursorX = 0, cursorY = 2, pitch = 16, cursor = 0,
      }
      t.func = Scene.Task_OakSpeech_HandleConfirmNameInput
    end
  end
end

function Scene.Task_OakSpeech_HandleConfirmNameInput(self, t)
  -- pokefirered/src/oak_speech.c:1490
  local r = self:menuInput(false)
  if r == "none" then return end
  self.win.menu = nil
  if r == 0 then
    Audio.playSe(SE_SELECT)
    t.data.timer = 40
    if not self.hasPlayerBeenNamed then
      self:clearDialog()
      self:createFadeInTask(t, 2)
      t.func = Scene.Task_OakSpeech_FadeOutPlayerPic
    else
      self:oakPrint("remember_rival")
      t.func = Scene.Task_OakSpeech_FadeOutRivalPic
    end
  else
    Audio.playSe(SE_SELECT)
    if not self.hasPlayerBeenNamed then
      t.func = Scene.Task_OakSpeech_FadeOutForPlayerNamingScreen
    else
      t.func = Scene.Task_OakSpeech_RepeatNameQuestion
    end
  end
end

function Scene.Task_OakSpeech_FadeOutPlayerPic(self, t)
  local d = t.data
  if d.picFadeState == 0 then return end
  self:clearTrainerPic()
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    t.func = Scene.Task_OakSpeech_FadeInRivalPic
  end
end

function Scene.Task_OakSpeech_FadeOutRivalPic(self, t)
  if self:printerActive() then return end
  self:clearDialog()
  self:createFadeInTask(t, 2)
  t.func = Scene.Task_OakSpeech_ReshowPlayersPic
end

function Scene.Task_OakSpeech_FadeInRivalPic(self, t)
  -- pokefirered/src/oak_speech.c:1546
  self.bg2X = 0
  t.data.picPosX = 0
  self.coordOffsetX = 0
  self:loadTrainerPic("rival")
  self:createFadeOutTask(t, 2)
  t.func = Scene.Task_OakSpeech_AskRivalsName
end

function Scene.Task_OakSpeech_AskRivalsName(self, t)
  if t.data.picFadeState == 0 then return end
  self:oakPrint("rival_intro")
  self.hasPlayerBeenNamed = true
  t.func = Scene.Task_OakSpeech_MoveRivalDisplayNameOptions
end

function Scene.Task_OakSpeech_ReshowPlayersPic(self, t)
  -- pokefirered/src/oak_speech.c:1568
  local d = t.data
  if d.picFadeState == 0 then return end
  self:clearTrainerPic()
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    self:loadPlayerPic()
    d.picPosX = 0
    self.coordOffsetX = 0
    self.bg2X = 0
    self:createFadeOutTask(t, 2)
    t.func = Scene.Task_OakSpeech_LetsGo
  end
end

function Scene.Task_OakSpeech_LetsGo(self, t)
  if t.data.picFadeState == 0 then return end
  self:oakPrint("lets_go")
  t.data.timer = 30
  t.func = Scene.Task_OakSpeech_FadeOutBGM
end

function Scene.Task_OakSpeech_FadeOutBGM(self, t)
  -- pokefirered/src/oak_speech.c:1605
  if self:printerActive() then return end
  if t.data.timer ~= 0 then
    t.data.timer = t.data.timer - 1
  else
    Audio.fadeOutBgm(4)
    t.func = Scene.Task_OakSpeech_SetUpExitAnimation
  end
end

------------------------------------------------------------------------
-- Exit (pokefirered/src/oak_speech.c:1624)
------------------------------------------------------------------------

local function Task_OakSpeech_DestroyPlatformSprites(self, t)
  -- pokefirered/src/oak_speech.c:1685
  if self:fadeActive() then return end
  if t.data.bgFadeStarted then
    destroyTask(t)
    local first = Oam.get(0)
    if first then destroySprite(first) end
  else
    t.data.bgFadeStarted = true
    self.pal:beginFade(0xF000, 0, 0, 16, Pal.BLACK)
  end
end

local function Task_OakSpeech_FadePlayerPicWhite(self, t)
  -- pokefirered/src/oak_speech.c:1729
  local d = t.data
  if d.timer ~= 0 then
    d.timer = d.timer - 1
  else
    if d.under <= 0 and d.secondary ~= 0 then d.secondary = d.secondary - 1 end
    self.pal:blend(Pal.mask({ 4, 5 }), d.coeff, Pal.WHITE)
    d.coeff = d.coeff + 1
    d.under = d.under - 1
    d.timer = d.secondary
    if d.coeff > 14 then
      self.pal:setBase(4, Pal.WHITE)
      self.pal:setBase(5, Pal.WHITE)
      self.pal:blend(Pal.mask({ 4, 5 }), 0, Pal.WHITE)
      destroyTask(t)
    end
  end
end

function Scene.Task_OakSpeech_SetUpExitAnimation(self, t)
  self.shrinkTimer = 0
  local t2 = self:createTask(Task_OakSpeech_DestroyPlatformSprites, 1)
  t2.data.bgFadeStarted = false
  self.pal:beginFade(Pal.OBJ + 0x0FCF, 4, 0, 16, Pal.BLACK)
  local t3 = self:createTask(Task_OakSpeech_FadePlayerPicWhite, 2)
  t3.data = { timer = 8, under = 0, secondary = 8, coeff = 0 }
  t.data.scaleDelta = 256
  t.func = Scene.Task_OakSpeech_ShrinkPlayerPic
end

function Scene.Task_OakSpeech_ShrinkPlayerPic(self, t)
  -- pokefirered/src/oak_speech.c:1647
  local d = t.data
  self.shrinkTimer = self.shrinkTimer + 1
  if self.shrinkTimer % 20 == 0 then
    if self.shrinkTimer == 40 then Audio.playSe(SE_WARP_IN) end
    local old = d.scaleDelta
    d.scaleDelta = d.scaleDelta - 32
    self.bg2Affine = { pa = idiv(0x10000, old - 8), pd = idiv(0x10000, d.scaleDelta - 16) }
    if d.scaleDelta <= 96 then
      d.fadeOutTimer = 36
      t.func = Scene.Task_OakSpeech_FadePlayerPicToBlack
    end
  end
end

function Scene.Task_OakSpeech_FadePlayerPicToBlack(self, t)
  if t.data.fadeOutTimer ~= 0 then
    t.data.fadeOutTimer = t.data.fadeOutTimer - 1
  else
    self.pal:beginFade(0x0030, 2, 0, 16, Pal.BLACK)
    t.func = Scene.Task_OakSpeech_WaitForFade
  end
end

function Scene.Task_OakSpeech_WaitForFade(self, t)
  if not self:fadeActive() then t.func = Scene.Task_OakSpeech_FreeResources end
end

function Scene.Task_OakSpeech_FreeResources(self, t)
  -- pokefirered/src/oak_speech.c:1777
  destroyTask(t)
  local answers = { gender = self.gender, name = self.playerName, rivalName = self.rivalName }
  if ModRuntime.wants("intro.oak_speech.finished") then
    ModRuntime.emit("intro.oak_speech.finished", { speech = self, answers = answers })
  end
  self.result = {
    action = "new_game",
    gender = tonumber(answers.gender) or self.gender,
    name = type(answers.name) == "string" and answers.name ~= "" and answers.name or self.playerName,
    rivalName = type(answers.rivalName) == "string" and answers.rivalName ~= "" and answers.rivalName or self.rivalName,
    start = MapIds.NEW_GAME_START,
  }
end

------------------------------------------------------------------------
-- Frame driver (pokefirered/src/oak_speech.c:677)
------------------------------------------------------------------------

function Scene:frame()
  self.frames = self.frames + 1
  if self.naming then
    self:namingFrame()
    if self.naming then return end
    return
  end
  self:runTasks()
  if self.printer then self.printer:run(self.input.a or self.input.b, self.held) end
  BallOpen.tick()
  Oam.animateSprites()
  self.pal:updateFade()
end

local KEYS = { "a", "b", "up", "down", "left", "right", "start", "select" }

function Scene:update(input, dt)
  if input and input.wasPressed then
    for _, k in ipairs(KEYS) do
      if input:wasPressed(k) then self.pending[k] = true end
    end
  end
  local held = input and input.isDown and (input:isDown("a") or input:isDown("b")) or false
  self.accum = self.accum + (dt or 1 / 60)
  local step = 1 / Scene.GBA_HZ
  while self.accum >= step and not self.result do
    self.accum = self.accum - step
    self.input = self.pending
    self.pending = {}
    self.held = held
    proxyPressed, proxyInput = self.input, input
    self.inputProxy = INPUT_PROXY
    self:frame()
  end
  return self.result
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------

local function drawImageFx(img, x, y, fx, blend, clip, sx, sy, ox, oy)
  if not img then return end
  Fx.withClip(clip, function()
    Fx.draw(function()
      love.graphics.draw(img, x, y, 0, sx or 1, sy or 1, ox or 0, oy or 0)
    end, fx, blend)
  end)
end

function Scene:drawTopBar()
  -- pokefirered/src/menu.c:187
  local tb = self.win.topbar
  if not tb then return end
  local white = FrlgFont.COLOR.WHITE
  if tb.title then
    FrlgFont.draw(RomText.plain(tb.title), 4, 1, { colors = white, maxWidth = 120 })
  end
  if tb.hint then
    require("src.ui.game3.pokedex_chrome").drawControlInfo(RomText.plain(tb.hint), 236, 1)
  end
end

function Scene:drawBg0Text()
  local win = self.win
  local white = FrlgFont.COLOR.WHITE
  if win.guide then
    -- pokefirered/src/oak_speech.c:803
    if win.guide.page == 1 then
      FrlgFont.draw(RomText.plain("gControlsGuide_Text_Intro"), 2, 7 * 8, { colors = white, maxWidth = 238 })
    else
      local base = (win.guide.page - 2) * 3
      for i, w in ipairs(CONTROLS_WINDOWS[win.guide.page]) do
        FrlgFont.draw(RomText.at(CONTROLS_PAGES, base + i - 1), w[1] * 8 + 6, w[2] * 8, { colors = white, maxWidth = 192 })
      end
    end
  end
  if win.pika then
    -- pokefirered/src/oak_speech.c:967
    FrlgFont.draw(win.pika.text, 8 + 3, 32 + 5, {
      colors = FrlgFont.COLOR.DARK_GRAY, maxWidth = 221, linePitch = FrlgFont.GLYPH_HEIGHT,
    })
  end
  if win.dialog then
    Chrome.dialogueFrame()
    if self.printer then
      self.printer:draw(Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1, { maxWidth = Chrome.DLG_W * 8 })
    end
  end
  local m = win.menu
  if m then
    local tpl = Window.template(m.left, m.top, m.width, m.height)
    Window.stdFrame(tpl)
    Window.fill(tpl, 1, 1, 1, 1)
    local ox, oy = m.left * 8, m.top * 8
    for _, it in ipairs(m.items) do
      Window.printPx(it[1], ox + it[2], oy + it[3])
    end
    Window.cursorPx(ox + m.cursorX, oy + m.cursorY + m.cursor * m.pitch)
  end
end

function Scene:layerCanvas(key)
  self._canvases = self._canvases or {}
  local c = self._canvases[key]
  if not c then
    c = love.graphics.newCanvas(Display.W, Display.H)
    c:setFilter("nearest", "nearest")
    self._canvases[key] = c
  end
  return c
end

function Scene:renderToCanvas(key, fn)
  local c = self:layerCanvas(key)
  love.graphics.push("all")
  love.graphics.setCanvas(c)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  fn()
  love.graphics.pop()
  return c
end

function Scene:drawSprites(priority)
  for _, s in ipairs(Oam._buffer or {}) do
    if (s.oam.priority or 0) == priority then
      Oam.flushOne(s)
    end
  end
end

function Scene:prepareSprites()
  local blend = self.bld and self.bld.pic and self.bldAlpha or nil
  local pikaBlend = self.bld and self.bld.bg0 and self.bldAlpha or nil
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    if s.inUse then
      s.fx = s.palSlot and self.pal:fx(s.palSlot) or nil
      s.blend = nil
      if s.objBlend then
        if s.coordOffset then
          s.blend = blend
        else
          s.blend = pikaBlend
        end
      end
      if s.coordOffset then s.x2 = self.coordOffsetX end
    end
  end
  Oam.buildOamBuffer(true)
end

function Scene:drawPic()
  local pic = self.pic
  if not (pic and pic.image and not pic.hidden and self.bgVisible[2]) then return end
  local fx = self.pal:fx(pic.slot)
  local blend = self.bld and self.bld.pic and self.bldAlpha or nil
  local aff = self.bg2Affine
  if aff then
    -- pokefirered/src/oak_speech.c:1662
    local mx, my = 256 / aff.pa, 256 / aff.pd
    drawImageFx(pic.image, 120 + (88 - 120) * mx, 84 + (16 - 84) * my, fx, blend, nil, mx, my)
  else
    drawImageFx(pic.image, 88 - self.bg2X, 16, fx, blend)
  end
end

function Scene:draw()
  if self.naming then
    if self.naming.stage ~= "return" and Naming.isOpen() then Naming.draw() end
    local y = self.naming.pal.slots[0].y
    if self.naming.stage == "return" then y = 16 end
    if y > 0 then
      love.graphics.setColor(0, 0, 0, y / 16)
      love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end
  local W, H = Display.W, Display.H
  local bd = self.backdrop or Pal.BLACK
  local fxBd = self.pal:fx(SLOT_BACKDROP)
  local c = bd
  if fxBd then
    local y = fxBd.y or 0
    local col = fxBd.color or Pal.BLACK
    c = { bd[1] + math.floor((col[1] - bd[1]) * y / 16), bd[2] + math.floor((col[2] - bd[2]) * y / 16),
      bd[3] + math.floor((col[3] - bd[3]) * y / 16) }
  end
  love.graphics.clear(c[1] / 31, c[2] / 31, c[3] / 31, 1)

  self:prepareSprites()

  if self.bg1 and self.bg1.image and self.bgVisible[1] then
    local img = self.bg1.image
    if self.bg1.topbarSplit then
      drawImageFx(img, 0, 0, self.pal:fx(SLOT_TOPBAR), nil, { x = 0, y = 0, w = W, h = 24 })
      drawImageFx(img, 0, 0, self.pal:fx(SLOT_TOPBAR), nil, { x = 0, y = 152, w = W, h = 8 })
      drawImageFx(img, 0, 0, self.pal:fx(SLOT_BG1), nil, { x = 0, y = 24, w = W, h = 128 })
    else
      drawImageFx(img, 0, 0, self.pal:fx(SLOT_BG1))
    end
  end
  self:drawSprites(3)
  self:drawSprites(2)
  self:drawPic()
  self:drawSprites(1)
  if self.bgVisible[0] then
    if self.win.topbar then
      local tb = self:renderToCanvas("topbar", function() self:drawTopBar() end)
      drawImageFx(tb, 0, 0, self.pal:fx(SLOT_TOPBAR))
    end
    local text = self:renderToCanvas("bg0", function() self:drawBg0Text() end)
    local blend = self.bld and self.bld.bg0 and self.bldAlpha or nil
    local clip = blend and { x = 0, y = 16, w = W, h = H - 16 } or nil
    drawImageFx(text, 0, 0, self.pal:fx(SLOT_TEXT), blend, clip)
  end
  self:drawSprites(0)
  Fx.draw(function() BallOpen.draw() end, self.pal:fx(Pal.objSlot(OBJ_PARTICLES)))
end

return Scene
