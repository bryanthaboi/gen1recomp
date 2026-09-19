local Display = require("src.core.game3.display")
local Bg = require("src.core.game3.bg")
local Oam = require("src.core.game3.oam")
local Pal = require("src.core.game3.pal_fade")
local Audio = require("src.core.game3.audio")

local Title = {}

local GBA_HZ = 16777216 / 280896

local MUS_TITLE = 278
local SPECIES_CHARIZARD = 6

local BG_LOGO = 0
local BG_MON = 1
local BG_COPYRIGHT = 2
local BG_BORDER = 3

local PAL_MON = 13
local PAL_BORDER = 14
local PAL_COPYRIGHT = 15
local OBJ_FLAME = 0
local OBJ_SLASH = 1

local FLASH_WHITE = { 30, 30, 31 }

Title.SCENE = { INIT = 0, FLASHSPRITE = 1, FADEIN = 2, RUN = 3, RESTART = 4, CRY = 5 }
local S = Title.SCENE

-- pokefirered/src/title_screen.c:303
local FLAME_X = { 4, 16, 26, 32, 48, 200, 216, 224, 232, 60, 76, 92, 108, 128, 144 }

-- pokefirered/src/title_screen.c:106
local ANIMS_FLAME = {
  [0] = {
    { img = 0, dur = 3 }, { img = 4, dur = 6 }, { img = 8, dur = 6 }, { img = 12, dur = 6 },
    { img = 16, dur = 6 }, { img = 20, dur = 6 }, { img = 24, dur = 6 }, { img = 28, dur = 6 },
    { img = 32, dur = 6 }, { img = 36, dur = 6 }, "end",
  },
}

local function mulU32(a, b)
  local aL, aH = a % 65536, math.floor(a / 65536) % 65536
  local bL, bH = b % 65536, math.floor(b / 65536) % 65536
  return (aL * bL + ((aL * bH + aH * bL) % 65536) * 65536) % 4294967296
end

-- pokefirered/src/title_screen.c:1212
local function titleRand(t)
  t.seed = (mulU32(t.seed, 1103515245) + 24691) % 4294967296
  return math.floor(t.seed / 65536)
end

local function cmod(a, n)
  return math.fmod(a, n)
end

local function composite(images)
  if not (love and love.graphics and love.graphics.newCanvas) then return images[1] end
  local canvas = love.graphics.newCanvas(Display.W, Display.H)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  for _, img in ipairs(images) do
    if img then love.graphics.draw(img, 0, 0) end
  end
  love.graphics.pop()
  return canvas
end

------------------------------------------------------------------------
-- Tasks
------------------------------------------------------------------------

local function createTask(T, fn, priority)
  local t = { fn = fn, priority = priority, data = {}, alive = true }
  local pos = #T.tasks + 1
  for i, other in ipairs(T.tasks) do
    if other.priority > priority then
      pos = i
      break
    end
  end
  table.insert(T.tasks, pos, t)
  if T.runIdx and pos <= T.runIdx then T.runIdx = T.runIdx + 1 end
  return t
end

local function findTask(T, fn)
  for _, t in ipairs(T.tasks) do
    if t.alive and t.fn == fn then return t end
  end
  return nil
end

local function destroyTask(t)
  if t then t.alive = false end
end

local function runTasks(T)
  T.runIdx = 1
  while T.runIdx <= #T.tasks do
    local t = T.tasks[T.runIdx]
    if t.alive then t.fn(T, t) end
    T.runIdx = T.runIdx + 1
  end
  T.runIdx = nil
  local keep = {}
  for _, t in ipairs(T.tasks) do
    if t.alive then keep[#keep + 1] = t end
  end
  T.tasks = keep
end

------------------------------------------------------------------------
-- Sprites
------------------------------------------------------------------------

local function SpriteCallback_TitleScreenFlame(sprite)
  -- pokefirered/src/title_screen.c:956
  local d = sprite.data
  d[1] = d[1] - d[2]
  sprite.x = math.floor(d[1] / 16)
  if sprite.x < -8 then
    Oam.destroySprite(sprite._id)
    return
  end
  d[3] = d[3] + d[4]
  sprite.y = math.floor(d[3] / 16)
  if sprite.y < 16 or sprite.y > 200 then
    Oam.destroySprite(sprite._id)
    return
  end
  if sprite.animEnded then
    Oam.destroySprite(sprite._id)
  end
end

local function createFlameSprite(T, x, y, xspeed, yspeed, visible)
  -- pokefirered/src/title_screen.c:985
  local _, spr = Oam.createSprite({
    dims = Oam.SQUARE_16, priority = 3,
    image = visible and T.assets.titleFlames or nil,
    anims = ANIMS_FLAME, animQuads = T.flameQuads,
    callback = SpriteCallback_TitleScreenFlame,
  }, x, y, 0)
  if not spr then return false end
  spr.palSlot = Pal.objSlot(OBJ_FLAME)
  spr.data[1] = x * 16
  spr.data[2] = xspeed
  spr.data[3] = y * 16
  spr.data[4] = yspeed
  return true
end

local function Task_FlameSpawner(T, t)
  -- pokefirered/src/title_screen.c:1019
  local d = t.data
  if not d.started then
    d.seed = 30840
    d.timer = 0
    d.delay = 0
    d.offsetX = 0
    d.started = true
    return
  end
  d.timer = d.timer + 1
  if d.timer >= d.delay then
    d.timer = 0
    titleRand(d)
    d.delay = 18
    local xspeed = cmod(titleRand(d), 4) - 2
    local yspeed = cmod(titleRand(d), 8) - 16
    local y = cmod(titleRand(d), 3) + 116
    local x = cmod(titleRand(d), Display.W)
    createFlameSprite(T, x, y, xspeed, yspeed, cmod(titleRand(d), 16) >= 8)
    for i = 1, 15 do
      createFlameSprite(T, d.offsetX + FLAME_X[i], y, xspeed, yspeed, true)
      xspeed = cmod(titleRand(d), 4) - 2
      yspeed = cmod(titleRand(d), 8) - 16
    end
    d.offsetX = d.offsetX + 1
    if d.offsetX > 3 then d.offsetX = 0 end
  end
end

local function SpriteCallback_Slash(sprite)
  -- pokefirered/src/title_screen.c:1270
  local d = sprite.data
  if d[1] == 0 then
    if d[3] ~= 0 then
      sprite.invisible = true
      d[1] = 2
    end
    d[2] = d[2] - 1
    if d[2] == 0 then
      sprite.invisible = false
      d[1] = 1
    end
  elseif d[1] == 1 then
    sprite.x = sprite.x + 9
    if sprite.x == 67 then sprite.y = sprite.y - 7 end
    if sprite.x == 148 then sprite.y = sprite.y + 7 end
    if sprite.x > Display.W + 32 then
      sprite.invisible = true
      if d[3] ~= 0 then
        d[1] = 2
      else
        sprite.x = -32
        d[2] = 540
        d[1] = 0
      end
    end
  end
end

local function createSlashSprite(T)
  -- pokefirered/src/title_screen.c:1245
  local _, spr = Oam.createSprite({
    dims = Oam.SQUARE_64, priority = 0, callback = SpriteCallback_Slash,
  }, -32, 27, 1)
  if spr then
    spr.data[2] = 540
    spr.objWindow = true
  end
  return spr
end

local function slashDeactivated(spr)
  return spr ~= nil and spr.inUse and spr.data[1] == 2
end

local function deactivateSlash(spr)
  if spr and spr.inUse then spr.data[3] = 1 end
end

------------------------------------------------------------------------
-- Window slide / press start blink
------------------------------------------------------------------------

local function Task_TitleScreen_SlideWin0(T, t)
  -- pokefirered/src/title_screen.c:756
  local d = t.data
  d.state = d.state or 0
  d.pos = d.pos or 0
  if d.state == 0 then
    T.win0 = { mode = "border", x = 0 }
    T.pal:blend(Pal.mask({ PAL_BORDER }), 0, Pal.BLACK)
    d.state = 1
  elseif d.state == 1 then
    d.pos = d.pos + 24 * 16
    local x = math.floor(d.pos / 16)
    if x >= Display.W then
      x = Display.W
      d.state = 2
    end
    T.win0.x = x
  elseif d.state == 2 then
    d.wait = (d.wait or 0) + 1
    if d.wait >= 10 then
      d.wait = 0
      d.state = 3
    end
  elseif d.state == 3 then
    T.win0 = { mode = "copyright", x = Display.W }
    T.pal:blend(Pal.mask({ PAL_COPYRIGHT }), 0, Pal.BLACK)
    d.pos = 10 * 24 * 16
    d.state = 4
  elseif d.state == 4 then
    d.pos = d.pos - 24 * 16
    local x = math.floor(d.pos / 16)
    if x <= 0 then
      x = 0
      d.state = 5
    end
    T.win0.x = x
  else
    T.win0 = nil
    destroyTask(t)
  end
end

local function Task_TitleScreen_BlinkPressStart(T, t)
  -- pokefirered/src/title_screen.c:815
  local d = t.data
  d.timer = d.timer or 0
  d.hidden = d.hidden or false
  if d.signal and T.pal:fadeActive() then d.fading = true end
  if d.fading and not T.pal:fadeActive() then
    destroyTask(t)
    return
  end
  local limit = d.hidden and 30 or 60
  d.timer = d.timer + 1
  if d.timer >= limit then
    d.timer = 0
    d.hidden = not d.hidden
    T.pressStartHidden = d.hidden
    if d.fading and T.pal.fade then
      T.pal:blend(Pal.mask({ PAL_COPYRIGHT }), T.pal.fade.y, T.pal.fade.color)
    end
  end
end

local function signalEndBlink(T)
  local t = findTask(T, Task_TitleScreen_BlinkPressStart)
  if t then t.data.signal = true end
end

------------------------------------------------------------------------
-- Scenes (pokefirered/src/title_screen.c:472)
------------------------------------------------------------------------

local function setScene(T, scene)
  T.sceneState = 0
  T.scene = scene
end

local function loadMainPalsAndResetBgs(T)
  -- pokefirered/src/title_screen.c:903
  destroyTask(findTask(T, Task_TitleScreen_SlideWin0))
  T.pal:clearGradual()
  T.pal:resetFade()
  for i = 0, 15 do T.pal:restore(i) end
  T.win0 = nil
  T.slashWin = false
  for i = 0, 3 do Bg.show(i) end
end

local function sceneInit(T)
  Bg.hide(BG_LOGO)
  Bg.show(BG_MON)
  Bg.show(BG_COPYRIGHT)
  Bg.show(BG_BORDER)
  setScene(T, S.FLASHSPRITE)
end

local function sceneFlashSprite(T)
  -- pokefirered/src/title_screen.c:494
  if T.sceneState == 0 then
    T.band = 128
    T.sceneState = 1
  elseif T.sceneState == 1 then
    T.band = T.band - 4
    if T.band < 0 then
      T.bandStop = true
      T.sceneState = 2
    end
  else
    T.band = nil
    T.bandStop = nil
    setScene(T, S.FADEIN)
  end
end

local function sceneFadeIn(T)
  -- pokefirered/src/title_screen.c:521
  local st = T.sceneState
  local pal = T.pal
  local monMask = Pal.mask({ PAL_MON })
  if st == 0 then
    T.d2 = 0
    T.sceneState = 1
  elseif st == 1 then
    T.d2 = T.d2 + 1
    if T.d2 > 10 then
      pal:setGray(PAL_MON, true)
      pal:beginFade(monMask, 9, 16, 0, Pal.BLACK)
      T.sceneState = 2
    end
  elseif st == 2 then
    if not pal:fadeActive() then
      T.d2 = 0
      T.sceneState = 3
    end
  elseif st == 3 then
    T.d2 = T.d2 + 1
    if T.d2 > 36 then
      createTask(T, Task_TitleScreen_SlideWin0, 3)
      pal:blendGradually(monMask, -4, 1, 16, FLASH_WHITE)
      T.d2 = 0
      T.sceneState = 4
    end
  elseif st == 4 then
    if not pal:gradualActive() then
      pal:blendGradually(monMask, -4, 15, 0, FLASH_WHITE)
      T.sceneState = 5
    end
  elseif st == 5 then
    T.d2 = T.d2 + 1
    if T.d2 > 20 then
      T.d2 = 0
      pal:blendGradually(monMask, -4, 1, 16, FLASH_WHITE)
      T.sceneState = 6
    end
  elseif st == 6 then
    if not pal:gradualActive() then
      pal:blendGradually(monMask, -4, 15, 0, FLASH_WHITE)
      T.sceneState = 7
    end
  elseif st == 7 then
    T.d2 = T.d2 + 1
    if T.d2 > 20 then
      T.d2 = 0
      pal:blendGradually(monMask, -3, 0, 16, FLASH_WHITE)
      T.sceneState = 8
    end
  elseif st == 8 then
    if not pal:gradualActive() then
      local logoMask = Pal.mask({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, { OBJ_SLASH })
      pal:blend(logoMask, 16, FLASH_WHITE)
      pal:beginFade(logoMask, 1, 16, 0, FLASH_WHITE)
      Bg.show(BG_LOGO)
      pal:setGray(PAL_MON, false)
      pal:blendGradually(monMask, 1, 15, 0, FLASH_WHITE)
      T.sceneState = 9
    end
  else
    if not pal:gradualActive() and not pal:fadeActive() then
      setScene(T, S.RUN)
    end
  end
end

local function sceneRun(T, pressed)
  -- pokefirered/src/title_screen.c:613
  if T.sceneState == 0 then
    createTask(T, Task_TitleScreen_BlinkPressStart, 0)
    T.pressStartHidden = false
    createTask(T, Task_FlameSpawner, 5)
    T.slashWin = true
    T.slash = createSlashSprite(T)
    T.sceneState = 1
  end
  if pressed.a or pressed.start then
    local okR, Rng = pcall(require, "src.core.game3.rng")
    if okR and Rng and Rng.seedNewGame then
      -- pokefirered/src/title_screen.c:632: SetTitleScreenScene_Cry → SeedRngAndSetTrainerId
      Rng.seedNewGame()
    end
    setScene(T, S.CRY)
  elseif not findTask(T, Title.Task_TitleScreenTimer) then
    setScene(T, S.RESTART)
  end
end

local function sceneRestart(T)
  -- pokefirered/src/title_screen.c:667
  local st = T.sceneState
  if st == 0 then
    deactivateSlash(T.slash)
    T.sceneState = 1
  elseif st == 1 then
    if not T.pal:fadeActive() and slashDeactivated(T.slash) then
      Audio.fadeOutBgm(10)
      T.pal:beginFade(Pal.ALL, 3, 0, 16, Pal.BLACK)
      signalEndBlink(T)
      T.sceneState = 2
    end
  elseif st == 2 then
    if Audio.isBgmStopped() and not T.pal:fadeActive() then
      destroyTask(findTask(T, Task_TitleScreen_BlinkPressStart))
      T.d2 = 0
      T.sceneState = 3
    end
  elseif st == 3 then
    T.d2 = T.d2 + 1
    if T.d2 >= 20 then
      destroyTask(findTask(T, Task_TitleScreen_BlinkPressStart))
      T.sceneState = 4
    end
  else
    T.result = "restart"
  end
end

local function sceneCry(T)
  -- pokefirered/src/title_screen.c:708
  local st = T.sceneState
  if st == 0 then
    if not T.pal:fadeActive() then
      Audio.playCry(SPECIES_CHARIZARD, 0)
      deactivateSlash(T.slash)
      T.d2 = 0
      T.sceneState = 1
    end
  elseif st == 1 then
    if T.d2 < 90 then
      T.d2 = T.d2 + 1
    elseif slashDeactivated(T.slash) then
      T.pal:beginFade(Pal.ALL - Pal.mask(nil, { 12, 13, 14, 15 }), 0, 0, 16, Pal.WHITE)
      signalEndBlink(T)
      Audio.fadeOutBgm(4)
      T.sceneState = 2
    end
  else
    if not T.pal:fadeActive() then
      T.result = "menu"
    end
  end
end

-- pokefirered/src/title_screen.c:431
function Title.Task_TitleScreenTimer(T, t)
  if T.vblanks >= 2700 then destroyTask(t) end
end

local function Task_TitleScreenMain(T, t)
  -- pokefirered/src/title_screen.c:448
  local pressed = T.input
  if (pressed.a or pressed.b or pressed.start)
      and T.scene ~= S.RUN and T.scene ~= S.RESTART and T.scene ~= S.CRY then
    local okR, Rng = pcall(require, "src.core.game3.rng")
    if okR and Rng and Rng.perturb then Rng.perturb() end
    T.band = nil
    loadMainPalsAndResetBgs(T)
    setScene(T, S.RUN)
    return
  end
  if T.scene == S.INIT then
    sceneInit(T)
  elseif T.scene == S.FLASHSPRITE then
    sceneFlashSprite(T)
  elseif T.scene == S.FADEIN then
    sceneFadeIn(T)
  elseif T.scene == S.RUN then
    sceneRun(T, pressed)
  elseif T.scene == S.RESTART then
    sceneRestart(T)
  elseif T.scene == S.CRY then
    sceneCry(T)
  end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function Title.buildQuads(state)
  local img = state.assets and state.assets.titleFlames
  if not (img and love and love.graphics and love.graphics.newQuad) then return end
  local iw, ih = img:getDimensions()
  state.flameQuads = {}
  for f = 0, math.floor(ih / 16) - 1 do
    state.flameQuads[f * 4] = love.graphics.newQuad(0, f * 16, 16, 16, iw, ih)
  end
end

function Title.enter(state)
  Oam.destroyAll()
  Bg.reset()
  Title.buildQuads(state)
  local T = {
    assets = state.assets or {},
    flameQuads = state.flameQuads,
    pal = Pal.new(),
    tasks = {},
    accum = 0,
    initState = 0,
    vblanks = 0,
    input = {},
  }
  if not state._titleCanvases then
    state._titleCanvases = {
      withPress = composite({ state.copyrightLayer, state.pressStart }),
      noPress = state.copyrightLayer,
    }
  end
  T.copyWithPress = state._titleCanvases.withPress
  T.copyNoPress = state._titleCanvases.noPress
  T.slashImage = T.assets.titleSlash
  state.title = T
  state._titleActive = true
  return T
end

function Title.leave(state)
  state._titleActive = false
  state.title = nil
  Oam.destroyAll()
  Bg.reset()
end

local function initFrame(T, state)
  -- pokefirered/src/title_screen.c:342
  if T.initState == 0 then
    Oam.destroyAll()
    Bg.reset()
    Bg.initFromTemplates({
      { bg = BG_LOGO, priority = 0 },
      { bg = BG_MON, priority = 1 },
      { bg = BG_COPYRIGHT, priority = 2 },
      { bg = BG_BORDER, priority = 3 },
    })
    T.initState = 1
  elseif T.initState == 1 then
    if state.titleLogo then Bg.setImage(BG_LOGO, state.titleLogo, nil) end
    if state.titleMon then Bg.setImage(BG_MON, state.titleMon, nil) end
    if T.copyWithPress then Bg.setImage(BG_COPYRIGHT, T.copyWithPress, nil) end
    if state.titleBorder then Bg.setImage(BG_BORDER, state.titleBorder, nil) end
    T.initState = 2
  else
    T.pal:blend(Pal.BG, 16, Pal.BLACK)
    setScene(T, S.INIT)
    createTask(T, Task_TitleScreenMain, 4)
    createTask(T, Title.Task_TitleScreenTimer, 2)
    Audio.playSong(MUS_TITLE, { restart = true })
    T.running = true
  end
end

local function frame(T, state)
  if not T.running then
    initFrame(T, state)
    return
  end
  T.vblanks = T.vblanks + 1
  -- pokefirered/src/title_screen.c:412
  runTasks(T)
  T.pal:runGradual()
  Oam.animateSprites()
  T.pal:updateFade()
end

function Title.update(state, input, dt)
  local T = state.title
  if not T then return nil end
  if input and input.wasPressed then
    for _, k in ipairs({ "a", "b", "start", "select" }) do
      if input:wasPressed(k) then T.pending = T.pending or {}; T.pending[k] = true end
    end
  end
  T.accum = T.accum + (dt or 1 / 60)
  local step = 1 / GBA_HZ
  while T.accum >= step and not T.result do
    T.accum = T.accum - step
    T.input = T.pending or {}
    T.pending = nil
    frame(T, state)
  end
  return T.result
end

function Title.scene(state)
  return state.title and state.title.scene
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------

local function applyFx(T)
  local pal = T.pal
  local slot = { [BG_LOGO] = 0, [BG_MON] = PAL_MON, [BG_COPYRIGHT] = PAL_COPYRIGHT, [BG_BORDER] = PAL_BORDER }
  for bg = 0, 3 do
    local L = Bg.get(bg)
    L.fx = pal:fx(slot[bg])
    L.clip = nil
    L.offsetX = 0
  end
  local L = Bg.get(BG_COPYRIGHT)
  L.image = T.pressStartHidden and T.copyNoPress or T.copyWithPress
  if T.band and not T.bandStop then
    local mon = Bg.get(BG_MON)
    mon.fx = pal:fx(PAL_MON, { band = T.band }) or { band = T.band }
  end
  local s = T.slash
  if T.slashWin and s and s.inUse and not s.invisible and T.slashImage then
    local logo = Bg.get(BG_LOGO)
    logo.fx = pal:fx(0, { objWin = { image = T.slashImage, x = s.x - 32, y = s.y - 32, w = 64, h = 64, bldy = 13 } })
  end
  local w = T.win0
  if w and w.mode == "border" then
    Bg.get(BG_BORDER).clip = { x = 0, y = 0, w = w.x, h = Display.H }
  elseif w and w.mode == "copyright" then
    local c = Bg.get(BG_COPYRIGHT)
    c.clip = { x = w.x, y = 0, w = Display.W - w.x, h = Display.H }
    c.offsetX = w.x
  end
  for i = 0, Oam.MAX_SPRITES - 1 do
    local spr = Oam._sprites[i]
    if spr.inUse and spr.palSlot then spr.fx = pal:fx(spr.palSlot) end
  end
end

function Title.draw(state)
  local T = state.title
  if not T then
    love.graphics.clear(0, 0, 0, 1)
    return
  end
  if not T.running then
    love.graphics.clear(0, 0, 0, 1)
    return
  end
  applyFx(T)
  Display.composeHardware({
    clear = { 0, 0, 0, 1 },
    animate = false,
    build = true,
    pretOrder = true,
  })
end

return Title
