-- pokefirered/src/teachy_tv.c:450 TeachyTvMainCallback

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local TeachyTv = require("src.core.game3.teachy_tv")
local SeIds = require("src.core.game3.se_ids")

local Ui = {}

Ui.open = false
Ui.state = "list"
Ui.cursor = 1
Ui.scroll = 0
Ui.page = 1
Ui.phase = "intro"
Ui.step = 1
Ui.frames = 0
Ui.suspended = false
-- pokefirered/src/teachy_tv.c:519 ChangeBgX(3, 0x1000, 2)
Ui.bg3X = -16
Ui.bg3Y = 40
-- pokefirered/src/teachy_tv.c:521 grassAnimCounterLo / grassAnimCounterHi
Ui.grassLo = 0
Ui.grassHi = 3
Ui.grass = {}
Ui.grassDx = 0
Ui.grassDy = 0
Ui.static = nil

-- pokefirered/src/teachy_tv.c:236 upText_Y
local ROW_PITCH = 16
-- pokefirered/src/teachy_tv.c:145 sWindowTemplates[1]
local LIST_TPL = { left = 4, top = 1, width = 22, height = 12 }
-- pokefirered/src/teachy_tv.c:145 sWindowTemplates[0]
local BODY_TPL = { left = 2, top = 15, width = 26, height = 4 }

local LIST_WIN = Window.template(LIST_TPL.left, LIST_TPL.top, LIST_TPL.width, LIST_TPL.height)
local BODY_WIN = Window.template(BODY_TPL.left, BODY_TPL.top, BODY_TPL.width, BODY_TPL.height)

-- pokefirered/src/teachy_tv.c:679 AddTextPrinterParameterized2(0, FONT_MALE, text, speed, 0, 1, 0xC, 3)
local BODY_COLOR = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] }
-- pokefirered/src/teachy_tv.c:237 cursorPal
local LIST_COLOR = FrlgFont.COLOR.WHITE

-- pokefirered/src/teachy_tv.c:620 TeachyTvSetWindowRegs
local WIN0_X0, WIN0_X1, WIN0_Y0, WIN0_Y1 = 0x1C, 0xD4, 0x0C, 0x64
-- pokefirered/src/teachy_tv.c:601 SetGpuReg(REG_OFFSET_BLDY, 0x5)
local LIST_DARKEN = 5 / 16
-- pokefirered/src/teachy_tv.c:247 sScrollIndicatorArrowPair
local ARROW_X, ARROW_UP_Y, ARROW_DOWN_Y = 0x78, 0x0C, 0x64

local LIST_CURSOR_OPTS = { colors = LIST_COLOR }
local LIST_TEXT_OPTS = { maxWidth = LIST_TPL.width * 8 - 8, colors = LIST_COLOR }
local BODY_TEXT_OPTS = { maxWidth = BODY_TPL.width * 8, linePitch = 16, colors = BODY_COLOR }

-- pokefirered/src/text.c:471 TextPrinterDrawDownArrow
local PROMPT_BOUNCE = { 0, 1, 2, 3, 2, 1 }

-- pokefirered/src/graphics.c:1117 gTeachyTv_Gfx
local CACHE_SUB = "teachy_tv"
local SCREEN_W, SCREEN_H = 240, 160
local FRAME = 1 / 60

-- pokefirered/src/teachy_tv.c:519 ChangeBgX(3, 0x1000, 2), ChangeBgY(3, 0x2800, 1)
local BG3_X0, BG3_Y0 = -16, 40
-- pokefirered/src/teachy_tv.c:1218 TeachyTvLoadBg3Map
local BG3_W, BG3_H = 256, 256
-- pokefirered/src/teachy_tv.c:632 TeachyTvBg2AnimController
local STATIC_LEFT, STATIC_TOP, STATIC_COLS, STATIC_ROWS = 2, 1, 26, 12
-- pokefirered/src/data/field_effects/field_effect_objects.h:73 sAnim_TallGrass
local GRASS_FRAME_TICKS, GRASS_FRAMES = 10, 5
local GRASS_W, GRASS_H = 16, 16

-- pokefirered/src/teachy_tv.c:907 sGrassAnimArray
local GRASS_MAP = {
  0, 0, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 0, 0,
}

-- pokefirered/include/constants/songs.h:354 MUS_TEACHY_TV_MENU
local MUS_TEACHY_TV_MENU = 346
-- pokefirered/include/constants/songs.h:280 MUS_FOLLOW_ME
local MUS_FOLLOW_ME = 272

local T = TeachyTv.TIMING

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

-- pokefirered/src/sound.c:129 PlayNewMapMusic
local function song(id)
  local Audio = require("src.core.game3.audio")
  Audio.playSong(id)
end

local function fade()
  return require("src.ui.game3.fade")
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local ok, d = pcall(function() return Dataset.cache():read(rel) end)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local ok, d = pcall(CacheFs.readActive, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local ok, d = pcall(love.filesystem.read, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function cache_root()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  return (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local okI, data = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okI and data) then return nil end
  local okG, img = pcall(love.graphics.newImage, data)
  if not okG then return nil end
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

Ui._images = {}

function Ui.artPath(name)
  return cache_root() .. "/" .. CACHE_SUB .. "/" .. name .. ".rgba"
end

local function art(name, w, h)
  if Ui._images[name] == nil then
    local bytes = read_bytes(Ui.artPath(name))
    Ui._images[name] = (bytes and rgba_to_image(bytes, w or SCREEN_W, h or SCREEN_H)) or false
    if name == "screen" then
      -- pokefirered/src/teachy_tv.c:530 LZDecompressWram(gTeachyTvScreen_Tilemap, ...)
      local at = ((SCREEN_H / 2) * SCREEN_W + SCREEN_W / 2) * 4 + 4
      Ui._chromeCutOut = (Ui._images[name] and #bytes >= at and bytes:byte(at) == 0) or false
    end
  end
  return Ui._images[name] or nil
end

-- pokefirered/src/data/field_effects/field_effect_objects.h:88 gFieldEffectObjectTemplate_TallGrass
local function grass_sheet()
  if Ui._grassSheet == nil then
    local rel = cache_root() .. "/field_effects/tall_grass.rgba"
    local bytes = read_bytes(rel)
    local img = bytes and rgba_to_image(bytes, GRASS_W, GRASS_H * GRASS_FRAMES)
    if img and love and love.graphics and love.graphics.newQuad then
      local quads = {}
      for i = 1, GRASS_FRAMES do
        quads[i] = love.graphics.newQuad(0, (i - 1) * GRASS_H, GRASS_W, GRASS_H,
          GRASS_W, GRASS_H * GRASS_FRAMES)
      end
      Ui._grassSheet = { image = img, quads = quads }
    else
      Ui._grassSheet = false
    end
  end
  return Ui._grassSheet or nil
end

function Ui.reloadAssets()
  Ui._images = {}
  Ui._grassSheet = nil
  Ui._staticQuads = nil
end

function Ui.isOpen()
  return Ui.open
end

function Ui.rows()
  return Ui._rows or {}
end

function Ui.pages()
  return Ui._pages or {}
end

local function maxShowed()
  return TeachyTv.maxShowed(Ui._session, Ui._bag)
end

local function clamp_cursor()
  local total = #Ui.rows()
  if total < 1 then total = 1 end
  if Ui.cursor > total then Ui.cursor = total end
  if Ui.cursor < 1 then Ui.cursor = 1 end
  local shown = maxShowed()
  if Ui.cursor <= Ui.scroll then Ui.scroll = Ui.cursor - 1 end
  if Ui.cursor > Ui.scroll + shown then Ui.scroll = Ui.cursor - shown end
  if Ui.scroll < 0 then Ui.scroll = 0 end
end

-- pokefirered/src/teachy_tv.c:713 TeachyTvOptionListController
local function sync_resources()
  local res = TeachyTv.resources(Ui._session)
  if not res then return end
  res.scrollOffset = Ui.scroll
  res.selectedRow = Ui.cursor - 1 - Ui.scroll
  if res.selectedRow < 0 then res.selectedRow = 0 end
end

function Ui.stepName()
  local cluster = TeachyTv.STEPS[TeachyTv.whichScript(Ui._session)]
  return cluster and cluster[Ui.step] or nil
end

-- pokefirered/src/teachy_tv.c:1163 TeachyTvGrassAnimationCheckIfNeedsToGenerateGrassObj
function Ui.grassAt(x, y)
  if x < 0 or y < 0 then return false end
  local high = (math.floor(y / 16) + Ui.grassHi) * 16
  local low = math.floor(x / 16) + Ui.grassLo
  return GRASS_MAP[high + low + 1] == 1
end

-- pokefirered/src/teachy_tv.c:1140 TeachyTvGrassAnimationMain
local function grass_spawn(x, y, seekEnd)
  if not Ui.grassAt(x - 0x10, y) then return end
  Ui.grass[#Ui.grass + 1] = {
    x = x,
    y = y + 8,
    -- pokefirered/src/teachy_tv.c:1120 SeekSpriteAnim(obj, 4)
    frames = seekEnd and (GRASS_FRAME_TICKS * 4) or 0,
    split = not seekEnd,
  }
end

-- pokefirered/src/data/field_effects/field_effect_objects.h:73 sAnim_TallGrass
local GRASS_ANIM = { 1, 2, 3, 4, 0 }

function Ui.grassAnimCmd(g)
  local cmd = math.floor((g.frames or 0) / GRASS_FRAME_TICKS)
  if cmd >= GRASS_FRAMES then cmd = GRASS_FRAMES - 1 end
  return cmd
end

function Ui.grassFrame(g)
  return GRASS_ANIM[Ui.grassAnimCmd(g) + 1]
end

-- pokefirered/src/teachy_tv.c:1122 TeachyTvGrassAnimationObjCallback
local function grass_step()
  if #Ui.grass == 0 then return end
  local keep = {}
  local hx, hy = Ui.hostX or 0, Ui.hostY or 0
  for _, g in ipairs(Ui.grass) do
    g.x = g.x + Ui.grassDx
    g.y = g.y + Ui.grassDy
    g.frames = g.frames + 1
    local alive = true
    if g.frames >= GRASS_FRAME_TICKS * GRASS_FRAMES then
      local dx, dy = g.x - hx, g.y - hy
      if dx <= -16 or dx >= 16 or dy <= -16 or dy >= 24 then alive = false end
    end
    if alive then keep[#keep + 1] = g end
  end
  Ui.grass = keep
end

-- pokefirered/src/teachy_tv.c:632 TeachyTvBg2AnimController
local function bg2_anim()
  local grid = Ui.static
  if not grid then
    grid = {}
    Ui.static = grid
  end
  for i = 1, STATIC_ROWS * STATIC_COLS do
    grid[i] = math.random(0, 3)
  end
end

-- pokefirered/src/teachy_tv.c:1059 ChangeBgX(3, 0x0, 0)
local function reset_bg3()
  Ui.bg3X = BG3_X0
  Ui.bg3Y = BG3_Y0
  Ui.grassLo = 0
  Ui.grassHi = 3
  Ui.grass = {}
  Ui.grassDx = 0
  Ui.grassDy = 0
end

-- pokefirered/src/teachy_tv.c:1043 TTVcmd_End
local function to_list()
  Ui.state = "list"
  Ui.page = 1
  Ui.phase = "intro"
  Ui._pages = nil
  Ui.step = 1
  Ui.frames = 0
  Ui.suspended = false
  Ui.title = false
  Ui.endCard = false
  Ui.hostVisible = false
  reset_bg3()
  Ui._rows = TeachyTv.menuItems(Ui._session, Ui._bag)
  clamp_cursor()
  sync_resources()
end

function Ui.show(session, bag, opts)
  opts = opts or {}
  Ui.open = true
  Ui._session = session or opts.session
  Ui._bag = bag or opts.bag or (session and session.bag)
  Ui._onClose = opts.onClose
  Ui._bagUnder = Stack.has("bag")
  Ui._rows = TeachyTv.menuItems(Ui._session, Ui._bag)
  local res = TeachyTv.resources(Ui._session)
  Ui.scroll = res and res.scrollOffset or 0
  Ui.cursor = (res and (res.scrollOffset + res.selectedRow) or 0) + 1
  to_list()
  Ui.closing = false
  Stack.push("teachy_tv", Ui, { hideBelow = true })
  -- pokefirered/src/teachy_tv.c:490 PlayNewMapMusic
  song(MUS_TEACHY_TV_MENU)
  -- pokefirered/src/teachy_tv.c:499 BeginNormalPaletteFade(PALETTES_ALL, 0, 0x10, 0, 0)
  local Fade = fade()
  Fade.begin(Fade.MODE.FROM_BLACK, 1)
end

-- pokefirered/src/teachy_tv.c:695 TeachyTvQuitFadeControlAndTaskDel
function Ui.finishClose()
  if not Ui.open then return end
  Ui.open = false
  Ui.closing = false
  Ui.state = "list"
  Ui._pages = nil
  Ui.suspended = false
  Ui.hostVisible = false
  Ui.static = nil
  Stack.pop("teachy_tv")
  -- pokefirered/src/teachy_tv.c:705 Overworld_PlaySpecialMapMusic
  require("src.core.game3.audio").restoreMapSong()
  local Fade = fade()
  Fade.begin(Fade.MODE.FROM_BLACK, 1)
  local cb = Ui._onClose
  Ui._onClose = nil
  if cb then cb() end
end

-- pokefirered/src/teachy_tv.c:689 TeachyTvQuitBeginFade
function Ui.close()
  if not Ui.open or Ui.closing then return end
  Ui.closing = true
  local Fade = fade()
  Fade.begin(Fade.MODE.TO_BLACK, 1, function()
    if Ui.closing then Ui.finishClose() end
  end)
end

local function set_printer(phase, pages)
  Ui.phase = phase
  Ui._pages = pages or {}
  Ui.page = 1
end

-- pokefirered/src/teachy_tv.c:804 RunTextPrinters_CheckActive
function Ui.printerActive()
  local pages = Ui._pages
  return pages ~= nil and Ui.page < #pages
end

local function step_advance()
  Ui.step = Ui.step + 1
  Ui.frames = 0
end

-- pokefirered/src/teachy_tv.c:612 TeachyTvSetSpriteCoordsAndSwitchFrame
local function host(x, y, facing, walking)
  if x then Ui.hostX = x end
  if y then Ui.hostY = y end
  Ui.hostFacing = facing or Ui.hostFacing or "down"
  Ui.hostWalk = walking and true or false
  Ui.hostVisible = true
end

local STEP = {}

-- pokefirered/src/teachy_tv.c:755 TTVcmd_TransitionRenderBg2TeachyTvGraphicInitNpcPos
STEP.transition_render_bg2 = function()
  -- pokefirered/src/teachy_tv.c:758 TeachyTvBg2AnimController
  bg2_anim()
  if Ui.frames > T.TITLE - 1 then
    -- pokefirered/src/teachy_tv.c:761 CopyToBgTilemapBufferRect_ChangePalette
    Ui.static = nil
    Ui.title = true
    host(T.DUDE_X_START, T.DUDE_Y, "right", true)
    song(MUS_FOLLOW_ME)
    step_advance()
  end
end

-- pokefirered/src/teachy_tv.c:770 TTVcmd_ClearBg2TeachyTvGraphic
STEP.clear_bg2 = function()
  if Ui.frames == T.CLEAR then
    Ui.title = false
    step_advance()
  end
end

-- pokefirered/src/teachy_tv.c:782 TTVcmd_NpcMoveAndSetupTextPrinter
STEP.npc_move_and_setup_text_printer = function()
  if Ui.frames <= T.NPC_WAIT then return end
  if (Ui.hostX or 0) < T.DUDE_X_END then
    Ui.hostX = (Ui.hostX or T.DUDE_X_START) + 1
    Ui.hostStep = (Ui.hostX % 16) < 8
    return
  end
  host(nil, nil, "down", false)
  set_printer("hello", TeachyTv.pagesOf(TeachyTv.HELLO))
  step_advance()
end

-- pokefirered/src/teachy_tv.c:801 TTVcmd_IdleIfTextPrinterIsActive
STEP.idle_if_text_printer_active = function()
  if not Ui.printerActive() then step_advance() end
end
STEP.idle_if_text_printer_active2 = STEP.idle_if_text_printer_active

-- pokefirered/src/teachy_tv.c:838 TTVcmd_TextPrinterSwitchStringByOptionChosen
STEP.text_printer_intro = function()
  set_printer("intro", TeachyTv.introPages(TeachyTv.whichScript(Ui._session)))
  step_advance()
end

-- pokefirered/src/teachy_tv.c:853 TTVcmd_TextPrinterSwitchStringByOptionChosen2
STEP.text_printer_outro = function()
  set_printer("outro", TeachyTv.outroPages(TeachyTv.whichScript(Ui._session)))
  step_advance()
end

-- pokefirered/src/teachy_tv.c:936 TTVcmd_EraseTextWindowIfKeyPressed
STEP.erase_text_window_if_key_pressed = function()
end

-- pokefirered/src/teachy_tv.c:947 TTVcmd_StartAnimNpcWalkIntoGrass
STEP.start_anim_npc_walk_into_grass = function()
  host(nil, nil, "up", true)
  Ui.grassDx = 0
  Ui.grassDy = 1
  step_advance()
end

-- pokefirered/src/teachy_tv.c:957 TTVcmd_DudeMoveUp
STEP.dude_move_up = function()
  -- pokefirered/src/teachy_tv.c:961 ChangeBgY(3, 0x100, 2)
  Ui.bg3Y = Ui.bg3Y - 1
  Ui.hostStep = (Ui.frames % 16) < 8
  if Ui.frames % 16 == 0 then
    Ui.grassHi = Ui.grassHi - 1
    grass_spawn(Ui.hostX or 0, Ui.hostY or 0)
  end
  if Ui.frames == T.MOVE_UP then
    Ui.grassDx = -1
    Ui.grassDy = 0
    host(nil, nil, "right", true)
    step_advance()
  end
end

-- pokefirered/src/teachy_tv.c:977 TTVcmd_DudeMoveRight
STEP.dude_move_right = function()
  -- pokefirered/src/teachy_tv.c:981 ChangeBgX(3, 0x100, 1)
  Ui.bg3X = Ui.bg3X + 1
  Ui.hostStep = (Ui.frames % 16) < 8
  if Ui.frames % 16 == 0 then Ui.grassLo = Ui.grassLo + 1 end
  if (Ui.frames + 8) % 16 == 0 then
    grass_spawn((Ui.hostX or 0) + 8, Ui.hostY or 0)
  end
  if Ui.frames == T.MOVE_RIGHT then
    Ui.grassDx = 0
    Ui.grassDy = 0
    host(nil, nil, "right", false)
    step_advance()
  end
end

-- pokefirered/src/teachy_tv.c:1069 TTVcmd_TaskBattleOrFadeByOptionChosen
STEP.battle_or_fade = function()
  local script = TeachyTv.whichScript(Ui._session)
  if TeachyTv.endsInBattle(script) then
    Ui.suspended = true
    local started = TeachyTv.startDemonstration(Ui._session, script, {
      transition = TeachyTv.battleTransition(script),
      resumeStep = TeachyTv.RESUME_STEP[script],
      bag = Ui._bag,
      onDone = Ui.resumeFromDemonstration,
    })
    if not started then
      Ui.suspended = false
      Ui.resumeFromDemonstration(nil)
    end
    return
  end
  Ui.openPokedudeBag(script)
end

-- pokefirered/src/teachy_tv.c:996 TTVcmd_DudeTurnLeft
STEP.dude_turn_left = function()
  host(nil, nil, "left", false)
  Ui.grassDx = 0
  Ui.grassDy = 0
  grass_spawn(Ui.hostX or 0, Ui.hostY or 0)
  step_advance()
end

-- pokefirered/src/teachy_tv.c:1008 TTVcmd_DudeMoveLeft
STEP.dude_move_left = function()
  if (Ui.hostX or 0) % 16 == 0 then
    grass_spawn((Ui.hostX or 0) - 8, Ui.hostY or 0)
  end
  if (Ui.hostX or 0) <= T.DUDE_X_START then
    step_advance()
    return
  end
  Ui.hostX = Ui.hostX - 1
  host(nil, nil, "left", true)
  Ui.hostStep = (Ui.hostX % 16) < 8
end

-- pokefirered/src/teachy_tv.c:1021 TTVcmd_RenderAndRemoveBg1EndGraphic
STEP.render_and_remove_bg1_end_graphic = function()
  Ui.endCard = true
  if Ui.frames > T.END_GRAPHIC - 1 then
    Ui.endCard = false
    step_advance()
  end
end

-- pokefirered/src/teachy_tv.c:1043 TTVcmd_End
STEP["end"] = function()
  if Ui.frames == 1 then
    song(MUS_TEACHY_TV_MENU)
    Ui.hostVisible = false
  end
  -- pokefirered/src/teachy_tv.c:1048 TeachyTvBg2AnimController
  bg2_anim()
  if Ui.frames > T.END - 1 then
    if not Ui.aborted then
      TeachyTv.markWatched(Ui._session, TeachyTv.whichScript(Ui._session))
    end
    to_list()
  end
end

-- pokefirered/src/teachy_tv.c:808 TeachyTvRenderMsgAndSwitchClusterFuncs
local function abort_to_end()
  local cluster = TeachyTv.STEPS[TeachyTv.whichScript(Ui._session)] or {}
  Ui.aborted = true
  Ui.hostVisible = false
  -- pokefirered/src/teachy_tv.c:813 grassAnimDisabled = 1
  Ui.grass = {}
  Ui._pages = nil
  Ui.title = false
  Ui.endCard = false
  Ui.step = #cluster
  Ui.frames = 0
end

-- pokefirered/src/teachy_tv.c:713 TeachyTvOptionListController
local function begin_lesson(scriptId)
  TeachyTv.selectLesson(Ui._session, scriptId)
  Ui.state = "lesson"
  Ui.phase = "intro"
  Ui.page = 1
  Ui._pages = nil
  Ui.step = 1
  Ui.frames = 0
  Ui.title = false
  Ui.endCard = false
  Ui.aborted = false
  Ui.hostVisible = false
end

function Ui.tick()
  if not Ui.open or Ui.suspended or Ui.closing then return end
  if Ui.state ~= "lesson" then
    -- pokefirered/src/teachy_tv.c:718 TeachyTvBg2AnimController
    bg2_anim()
    Ui._arrowK = ((Ui._arrowK or 0) + 1) % 256
    return
  end
  local name = Ui.stepName()
  if not name then
    to_list()
    return
  end
  Ui.frames = Ui.frames + 1
  local fn = STEP[name]
  if fn then fn() end
  grass_step()
end

function Ui.update(dt)
  if not Ui.open then return end
  if Ui.closing then
    -- pokefirered/src/teachy_tv.c:697 !gPaletteFade.active
    if not fade().isActive() then Ui.finishClose() end
    return
  end
  Ui._acc = (Ui._acc or 0) + (tonumber(dt) or 0)
  local n = 0
  while Ui._acc >= FRAME and n < 8 do
    Ui._acc = Ui._acc - FRAME
    n = n + 1
    Ui.tick()
  end
  if Ui._acc > FRAME then Ui._acc = 0 end
end

-- pokefirered/src/teachy_tv.c:1208 TeachyTvRestorePlayerPartyCallback
function Ui.resumeFromDemonstration(outcome)
  local session = Ui._session
  local script = TeachyTv.whichScript(session)
  local mode = TeachyTv.modeAfterBattle(outcome)
  if mode == TeachyTv.MODE.RESUME_LIST then
    TeachyTv.setModeToResume(session)
  end
  TeachyTv.returnToTv(session)
  Ui.suspended = false
  Ui.closing = false
  Ui.open = true
  Ui.static = nil
  if not Stack.has("teachy_tv") then
    Stack.push("teachy_tv", Ui, { hideBelow = true })
  end
  -- pokefirered/src/teachy_tv.c:499 BeginNormalPaletteFade(PALETTES_ALL, 0, 0x10, 0, 0)
  local Fade = fade()
  Fade.begin(Fade.MODE.FROM_BLACK, 1)
  if mode == TeachyTv.MODE.RESUME_LIST then
    -- pokefirered/src/teachy_tv.c:490 PlayNewMapMusic
    song(MUS_TEACHY_TV_MENU)
    to_list()
    return
  end
  -- pokefirered/src/teachy_tv.c:1214 PlayNewMapMusic(MUS_FOLLOW_ME)
  song(MUS_FOLLOW_ME)
  Ui.state = "lesson"
  Ui._pages = nil
  Ui.step = (TeachyTv.RESUME_STEP[script] or 0) + 1
  Ui.frames = 0
  -- pokefirered/src/teachy_tv.c:505 TeachyTvSetupBg
  reset_bg3()
  -- pokefirered/src/teachy_tv.c:646 TeachyTvSetupPostBattleWindowAndObj
  host(T.DUDE_X_END, T.DUDE_Y, "down", false)
  if TeachyTv.endsInBattle(script) then
    -- pokefirered/src/teachy_tv.c:660 ChangeBgX(3, 0x3000, 1), ChangeBgY(3, 0x3000, 2)
    Ui.bg3X = Ui.bg3X + 48
    Ui.bg3Y = Ui.bg3Y - 48
    Ui.grassLo = Ui.grassLo + 3
    Ui.grassHi = Ui.grassHi - 3
  end
  Ui.grassDx = 0
  Ui.grassDy = 0
  grass_spawn(T.DUDE_X_END, T.DUDE_Y, true)
end

local NO_INPUT = {
  wasPressed = function() return false end,
  isDown = function() return false end,
}

local function press_input(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function() return false end,
  }
end

-- pokefirered/src/item_menu.c:2069 gBagMenuState.pocket / itemsAbove / cursorPos
local function snapshot_bag_positions(session, bag)
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local saved = { pos = {} }
  BagMenu.show(bag, { session = session })
  saved.pocket = BagMenu.pocketIdx
  for i = 1, #ItemsData.BAG_POCKET_ORDER do
    BagMenu.show(bag, { session = session, pocketIdx = i })
    saved.pos[i] = { cursor = BagMenu.cursor, scroll = BagMenu.scroll }
  end
  return saved
end

-- pokefirered/src/item_menu.c:2089 gBagMenuState.pocket = sBackupPlayerBag->pocket
local function apply_bag_positions(session, bag, saved)
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local last = (saved and tonumber(saved.pocket)) or 1
  local order = {}
  for i = 1, #ItemsData.BAG_POCKET_ORDER do
    if i ~= last then order[#order + 1] = i end
  end
  order[#order + 1] = last
  for _, i in ipairs(order) do
    local p = saved and saved.pos[i]
    BagMenu.show(bag, { session = session, pocketIdx = i })
    BagMenu.cursor = (p and p.cursor) or 1
    BagMenu.scroll = (p and p.scroll) or 0
    BagMenu.close()
  end
end

local BagDemo = {}
Ui.bagDemo = BagDemo

-- pokefirered/src/item_menu.c:2208 Task_Bag_TeachyTvRegister
function BagDemo.tick()
  local BagMenu = require("src.ui.game3.bag_menu")
  if BagDemo.finished or not BagMenu.isOpen() then return end
  BagDemo.frames = (BagDemo.frames or 0) + 1
  local entry = BagDemo.plan and BagDemo.plan[BagDemo.index]
  if entry and BagDemo.frames == entry.at then
    BagDemo.index = BagDemo.index + 1
    if entry.item then
      -- pokefirered/src/item_menu.c:2223 gSpecialVar_ItemId
      local ItemsData = require("src.core.game3.items_data")
      for i, row in ipairs(BagMenu.list and BagMenu.list() or {}) do
        if ItemsData.toNumericId(row.id) == entry.item then
          BagMenu.cursor = i
          break
        end
      end
    end
    if entry.exit then
      -- pokefirered/src/item_menu.c:2254 Bag_BeginCloseWin0Animation
      BagDemo.finished = true
      BagDemo.toTmCase = entry.tmCase and true or false
      BagMenu.close()
      return
    end
    BagMenu.handleInput(press_input(entry.key))
    return
  end
  BagMenu.handleInput(NO_INPUT)
end

function BagDemo.update(dt)
  BagDemo._acc = (BagDemo._acc or 0) + (tonumber(dt) or 0)
  local n = 0
  while BagDemo._acc >= FRAME and n < 8 do
    BagDemo._acc = BagDemo._acc - FRAME
    n = n + 1
    BagDemo.tick()
  end
  if BagDemo._acc > FRAME then BagDemo._acc = 0 end
end

-- pokefirered/src/item_menu.c:2192 Task_BButtonInterruptTeachyTv
function BagDemo.handleInput(input)
  if not input or BagDemo.finished then return end
  if input:wasPressed("b") then
    local BagMenu = require("src.ui.game3.bag_menu")
    BagDemo.interrupted = true
    BagDemo.finished = true
    se(SeIds.SE_SELECT)
    BagMenu.close()
  end
end

function BagDemo.draw()
end

local TmDemo = {}
Ui.tmDemo = TmDemo

-- pokefirered/src/data/text/teachy_tv.h:142 gPokedudeText_TMTypes
local TM_TEXT = {
  TM_TYPES = TeachyTv.TM_TYPES,
  TM_DESCRIPTION = TeachyTv.TM_DESCRIPTION,
}

local function tm_enter(index)
  local TmCase = require("src.ui.game3.tm_case")
  TmDemo.index = index
  TmDemo.frames = 0
  local entry = TmDemo.plan and TmDemo.plan[index]
  if not entry then return end
  if entry.exit then
    TmDemo.finished = true
    TmCase.close()
    return
  end
  if entry.text then
    -- pokefirered/src/tm_case.c:1420 PrintMessageWithFollowupTask
    TmDemo.pages = TeachyTv.pagesOf(TM_TEXT[entry.text])
    TmDemo.page = 1
    TmCase.mode = "message"
    TmCase.messageText = TmDemo.pages[1]
    return
  end
  if entry.key then TmCase.handleInput(press_input(entry.key)) end
end

-- pokefirered/src/tm_case.c:1353 Task_Pokedude_Run
function TmDemo.tick()
  local TmCase = require("src.ui.game3.tm_case")
  if TmDemo.finished or not TmCase.isOpen() then return end
  local entry = TmDemo.plan and TmDemo.plan[TmDemo.index]
  if not entry or entry.text then return end
  TmDemo.frames = TmDemo.frames + 1
  -- pokefirered/src/tm_case.c:1377 tPokedudeTimer > POKEDUDE_INPUT_DELAY
  if TmDemo.frames >= TeachyTv.POKEDUDE_INPUT_DELAY then
    tm_enter(TmDemo.index + 1)
  end
end

function TmDemo.update(dt)
  TmDemo._acc = (TmDemo._acc or 0) + (tonumber(dt) or 0)
  local n = 0
  while TmDemo._acc >= FRAME and n < 8 do
    TmDemo._acc = TmDemo._acc - FRAME
    n = n + 1
    TmDemo.tick()
  end
  if TmDemo._acc > FRAME then TmDemo._acc = 0 end
end

function TmDemo.handleInput(input)
  if not input or TmDemo.finished then return end
  local TmCase = require("src.ui.game3.tm_case")
  -- pokefirered/src/tm_case.c:1357 JOY_NEW(B_BUTTON), tPokedudeState = 21
  if input:wasPressed("b") then
    TmDemo.interrupted = true
    TmDemo.finished = true
    se(SeIds.SE_SELECT)
    TmCase.close()
    return
  end
  local entry = TmDemo.plan and TmDemo.plan[TmDemo.index]
  if entry and entry.text and input:wasPressed("a") then
    -- pokefirered/src/tm_case.c:1434 JOY_NEW(A_BUTTON | B_BUTTON)
    se(SeIds.SE_SELECT)
    if TmDemo.page < #(TmDemo.pages or {}) then
      TmDemo.page = TmDemo.page + 1
      TmCase.messageText = TmDemo.pages[TmDemo.page]
    else
      TmCase.mode = "list"
      TmCase.messageText = nil
      tm_enter(TmDemo.index + 1)
    end
  end
end

function TmDemo.draw()
end

-- pokefirered/src/tm_case.c:1322 Pokedude_InitTMCase
function Ui.openPokedudeTmCase()
  local TmCase = require("src.ui.game3.tm_case")
  local session = Ui._session
  TmDemo.plan = TeachyTv.TM_CASE_DEMO
  TmDemo.pages = nil
  TmDemo.page = 1
  TmDemo._acc = 0
  TmDemo.interrupted = false
  TmDemo.finished = false
  TeachyTv.initPokedudeTmCase(session)
  Ui.suspended = true
  -- pokefirered/src/tm_case.c:1338 InitTMCase(TMCASE_POKEDUDE, CB2_ReturnToTeachyTV, 0)
  TmCase.show(session, session and session.bag, {
    cursor = 1,
    scroll = 0,
    onClose = function() Ui.finishPokedudeTmCase() end,
  })
  Stack.push("teachy_pokedude_tm_case", TmDemo, { drawUnder = true, hideBelow = false })
  tm_enter(1)
end

-- pokefirered/src/tm_case.c:1446 tPokedudeState 21 restores the player's bag
function Ui.finishPokedudeTmCase()
  local session = Ui._session
  Stack.pop("teachy_pokedude_tm_case")
  TeachyTv.restorePokedudeTmCase(session)
  if TmDemo.interrupted then
    TeachyTv.setModeToResume(session)
  end
  Ui.returnFromDemo()
end

-- pokefirered/src/teachy_tv.c:1087 TeachyTvSetupBagItemsByOptionChosen
function Ui.openPokedudeBag(scriptId)
  local BagMenu = require("src.ui.game3.bag_menu")
  local session = Ui._session
  local bag = session and session.bag
  Ui._bagPos = snapshot_bag_positions(session, bag)
  BagDemo.script = scriptId
  BagDemo.location = TeachyTv.initPokedudeBag(session, scriptId)
  BagDemo.plan = TeachyTv.bagDemoPlan(scriptId)
  BagDemo.frames = 0
  BagDemo.index = 1
  BagDemo._acc = 0
  BagDemo.interrupted = false
  BagDemo.finished = false
  BagDemo.toTmCase = false
  Ui.suspended = true
  -- pokefirered/src/item_menu.c:2079 ResetBagCursorPositions
  apply_bag_positions(session, bag, nil)
  -- pokefirered/src/item_menu.c:2189 GoToBagMenu
  BagMenu.show(bag, {
    session = session,
    pocket = "ITEMS",
    onClose = function() Ui.finishPokedudeBag() end,
  })
  Stack.push("teachy_pokedude_bag", BagDemo, { drawUnder = true, hideBelow = false })
end

-- pokefirered/src/teachy_tv.c:437 CB2_ReturnToTeachyTV
function Ui.finishPokedudeBag()
  local session = Ui._session
  Stack.pop("teachy_pokedude_bag")
  TeachyTv.restorePlayerBag(session)
  apply_bag_positions(session, session and session.bag, Ui._bagPos)
  Ui._bagPos = nil
  -- pokefirered/src/item_menu.c:2385 exitCB = Pokedude_InitTMCase
  if BagDemo.toTmCase and not BagDemo.interrupted then
    BagDemo.toTmCase = false
    Ui.openPokedudeTmCase()
    return
  end
  if BagDemo.interrupted then
    TeachyTv.setModeToResume(session)
  end
  Ui.returnFromDemo()
end

-- pokefirered/src/teachy_tv.c:437 CB2_ReturnToTeachyTV
function Ui.returnFromDemo()
  local BagMenu = require("src.ui.game3.bag_menu")
  local session = Ui._session
  local res = TeachyTv.returnToTv(session)
  local script = TeachyTv.whichScript(session)
  if Ui._bagUnder then
    BagMenu.show(session and session.bag, { session = session })
  end
  Stack.push("teachy_tv", Ui, { hideBelow = true })
  Ui.open = true
  Ui.suspended = false
  if res and res.mode == TeachyTv.MODE.RESUME_SCRIPT then
    Ui.state = "lesson"
    Ui._pages = nil
    Ui.step = (TeachyTv.RESUME_STEP[script] or 0) + 1
    Ui.frames = 0
    song(MUS_FOLLOW_ME)
    -- pokefirered/src/teachy_tv.c:646 TeachyTvSetupPostBattleWindowAndObj
    host(T.DUDE_X_END, T.DUDE_Y, "down", false)
    return
  end
  -- pokefirered/src/teachy_tv.c:490 PlayNewMapMusic
  song(MUS_TEACHY_TV_MENU)
  to_list()
end

function Ui.handleInput(input)
  if not Ui.open or Ui.suspended or Ui.closing then return end

  -- pokefirered/src/teachy_tv.c:808 TeachyTvRenderMsgAndSwitchClusterFuncs
  if Ui.state == "lesson" then
    if input:wasPressed("b") then
      se(SeIds.SE_SELECT)
      abort_to_end()
    elseif input:wasPressed("a") then
      if Ui.printerActive() then
        se(SeIds.SE_SELECT)
        Ui.page = Ui.page + 1
      elseif Ui.stepName() == "erase_text_window_if_key_pressed" then
        se(SeIds.SE_SELECT)
        Ui._pages = nil
        step_advance()
      end
    end
    return
  end

  -- pokefirered/src/teachy_tv.c:719 !gPaletteFade.active
  if fade().isActive() then return end
  local rows = Ui.rows()
  if input:wasPressed("up") then
    if Ui.cursor > 1 then
      Ui.cursor = Ui.cursor - 1
      clamp_cursor()
      sync_resources()
      se(SeIds.SE_SELECT)
    end
  elseif input:wasPressed("down") then
    if Ui.cursor < #rows then
      Ui.cursor = Ui.cursor + 1
      clamp_cursor()
      sync_resources()
      se(SeIds.SE_SELECT)
    end
  elseif input:wasPressed("a") then
    se(SeIds.SE_SELECT)
    local row = rows[Ui.cursor]
    if not row or row.index == TeachyTv.CANCEL then
      Ui.close()
    else
      begin_lesson(row.index)
    end
  elseif input:wasPressed("b") then
    -- pokefirered/include/list_menu.h:8 LIST_CANCEL
    se(SeIds.SE_SELECT)
    Ui.close()
  elseif input:wasPressed("select") and not Ui._bagUnder then
    -- pokefirered/src/teachy_tv.c:723 sStaticResources.callback != CB2_BagMenuFromStartMenu
    se(SeIds.SE_SELECT)
    Ui.close()
  end
end

-- pokefirered/src/teachy_tv.c:526 TeachyTvLoadGraphic
function Ui.chrome()
  return art("screen")
end

-- pokefirered/src/teachy_tv.c:118 sBgTemplates[1] priority 0
function Ui.chromeCutOut()
  Ui.chrome()
  return Ui._chromeCutOut and true or false
end

-- pokefirered/src/teachy_tv.c:761 CopyToBgTilemapBufferRect_ChangePalette
function Ui.titleArt()
  return art("title")
end

-- pokefirered/src/teachy_tv.c:869 sBg1EndGraphic
function Ui.endArt()
  return art("end")
end

-- pokefirered/src/teachy_tv.c:1218 TeachyTvLoadBg3Map
function Ui.bg3Art()
  return art("bg3", BG3_W, BG3_H)
end

-- pokefirered/src/teachy_tv.c:637 tilemapBuffer[32 * i + j] = ((Random() & 3) << 10) + 0x301F
function Ui.staticArt()
  return art("static", 32, 8)
end

local function static_quads()
  if Ui._staticQuads == nil then
    if love and love.graphics and love.graphics.newQuad and Ui.staticArt() then
      local q = {}
      for i = 0, 3 do q[i] = love.graphics.newQuad(i * 8, 0, 8, 8, 32, 8) end
      Ui._staticQuads = q
    else
      Ui._staticQuads = false
    end
  end
  return Ui._staticQuads or nil
end

local OwSprites = nil
local function ow_sprites()
  if OwSprites == nil then
    local ok, mod = pcall(require, "src.core.game3.ow_sprites")
    OwSprites = (ok and type(mod) == "table" and mod.draw and mod) or false
  end
  return OwSprites or nil
end

-- pokefirered/src/teachy_tv.c:606 CreateObjectGraphicsSprite
local function draw_host()
  if not Ui.hostVisible then return end
  local sprites = ow_sprites()
  if not sprites then return end
  pcall(sprites.draw, TeachyTv.HOST_GFX,
    (Ui.hostX or T.DUDE_X_END) - 8, Ui.hostY or T.DUDE_Y, 0, 0,
    Ui.hostFacing or "down", Ui.hostWalk and 1 or 0, Ui.hostStep and true or false)
end

-- pokefirered/src/teachy_tv.c:526 TeachyTvLoadGraphic
local function draw_chrome()
  local bg = Ui.chrome()
  if not bg then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(bg, 0, 0)
end

-- pokefirered/src/teachy_tv.c:519 ChangeBgX(3, 0x1000, 2)
local function draw_bg3()
  local map = Ui.bg3Art()
  if not map then return end
  local ox = -(Ui.bg3X % BG3_W)
  local oy = -(Ui.bg3Y % BG3_H)
  love.graphics.setColor(1, 1, 1, 1)
  for dx = 0, 1 do
    for dy = 0, 1 do
      love.graphics.draw(map, ox + dx * BG3_W, oy + dy * BG3_H)
    end
  end
end

-- pokefirered/src/teachy_tv.c:632 TeachyTvBg2AnimController
local function draw_static()
  local grid = Ui.static
  local tile = grid and Ui.staticArt()
  local quads = tile and static_quads()
  if not quads then return end
  love.graphics.setColor(1, 1, 1, 1)
  for row = 0, STATIC_ROWS - 1 do
    for col = 0, STATIC_COLS - 1 do
      local pal = grid[row * STATIC_COLS + col + 1]
      if pal and quads[pal] then
        love.graphics.draw(tile, quads[pal], (STATIC_LEFT + col) * 8, (STATIC_TOP + row) * 8)
      end
    end
  end
end

-- pokefirered/src/teachy_tv.c:875 sSubspriteArray
local function grass_half_quad(sheet, frame, bottom)
  sheet.halves = sheet.halves or {}
  local key = frame * 2 + (bottom and 1 or 0)
  local q = sheet.halves[key]
  if not q then
    q = love.graphics.newQuad(0, frame * GRASS_H + (bottom and 8 or 0), GRASS_W, 8,
      GRASS_W, GRASS_H * GRASS_FRAMES)
    sheet.halves[key] = q
  end
  return q
end

-- pokefirered/src/teachy_tv.c:1132 TeachyTvGrassAnimationObjCallback
local function draw_grass(behindHost)
  if #Ui.grass == 0 then return end
  local sheet = grass_sheet()
  if not sheet then return end
  love.graphics.setColor(1, 1, 1, 1)
  for _, g in ipairs(Ui.grass) do
    local frame = Ui.grassFrame(g)
    if g.split and Ui.grassAnimCmd(g) == 0 then
      love.graphics.draw(sheet.image, grass_half_quad(sheet, frame, not behindHost),
        g.x - 8, g.y - 8 + (behindHost and 0 or 8))
    elseif not behindHost then
      love.graphics.draw(sheet.image, sheet.quads[frame + 1], g.x - 8, g.y - 8)
    end
  end
end

-- pokefirered/src/menu_indicators.c:289 gSineTable[tSinePos] * multiplier / 256
local function arrow_bob(freq)
  local Trig = require("src.core.game3.trig")
  local v = Trig.sin(((Ui._arrowK or 0) * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

-- pokefirered/src/teachy_tv.c:568 TeachyTvSetupScrollIndicatorArrowPair
local function draw_scroll_arrows(total, shown)
  if not TeachyTv.hasTmCase(Ui._session, Ui._bag) or total <= shown then return end
  local BagChrome = require("src.ui.game3.bag_chrome")
  if Ui.scroll > 0 then
    BagChrome.drawArrow("up", ARROW_X - 8, ARROW_UP_Y - 8 + arrow_bob(8))
  end
  if Ui.scroll < total - shown then
    BagChrome.drawArrow("down", ARROW_X - 8, ARROW_DOWN_Y - 8 + arrow_bob(-8))
  end
end

-- pokefirered/src/teachy_tv.c:936 TTVcmd_EraseTextWindowIfKeyPressed
function Ui.waitingForKey()
  if Ui.state ~= "lesson" then return false end
  if Ui.printerActive() then return true end
  return Ui.stepName() == "erase_text_window_if_key_pressed"
end

function Ui.draw()
  if not Ui.open then return end
  if not (love and love.graphics) then return end

  love.graphics.setColor(0.13, 0.16, 0.28, 1)
  love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  love.graphics.setColor(1, 1, 1, 1)
  draw_bg3()
  draw_static()

  local cutOut = Ui.chromeCutOut()
  if not cutOut then draw_chrome() end

  if Ui.state == "list" then
    -- pokefirered/src/teachy_tv.c:600 SetGpuReg(REG_OFFSET_BLDCNT, 0xCC)
    love.graphics.setColor(0, 0, 0, LIST_DARKEN)
    love.graphics.rectangle("fill", WIN0_X0, WIN0_Y0, WIN0_X1 - WIN0_X0, WIN0_Y1 - WIN0_Y0)
    love.graphics.setColor(1, 1, 1, 1)
    if cutOut then draw_chrome() end
    local rows = Ui.rows()
    local shown = maxShowed()
    -- pokefirered/src/teachy_tv.c:559 upText_Y
    local baseY = LIST_TPL.top * 8 + (TeachyTv.hasTmCase(Ui._session, Ui._bag) and 6 or 14)
    for i = 1, shown do
      local idx = Ui.scroll + i
      local row = rows[idx]
      if not row then break end
      local y = baseY + (i - 1) * ROW_PITCH
      if idx == Ui.cursor then
        -- pokefirered/src/teachy_tv.c:235 cursor_X
        Window.cursorPx(LIST_TPL.left * 8, y, LIST_CURSOR_OPTS)
      end
      -- pokefirered/src/teachy_tv.c:234 item_X
      FrlgFont.draw(tostring(row.label), LIST_TPL.left * 8 + 8, y, LIST_TEXT_OPTS)
    end
    draw_scroll_arrows(#rows, shown)
    return
  end

  if Ui.title then
    local title = Ui.titleArt()
    if title then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(title, 0, 0)
    end
  end

  draw_grass(true)
  draw_host()
  draw_grass(false)
  if cutOut then draw_chrome() end

  if Ui.endCard then
    local card = Ui.endArt()
    if card then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(card, 0, 0)
    end
  end

  local page = Ui.pages()[Ui.page]
  if not page then return end
  -- pokefirered/src/teachy_tv.c:676 TeachyTvInitTextPrinter
  local _, endX, endY = FrlgFont.draw(page, BODY_TPL.left * 8, BODY_TPL.top * 8 + 1, BODY_TEXT_OPTS)
  if Ui.waitingForKey() then
    -- pokefirered/src/text.c:471 TextPrinterDrawDownArrow
    local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
    local frame = PROMPT_BOUNCE[1 + (math.floor(t * 8) % #PROMPT_BOUNCE)] or 0
    local ax = (endX or (BODY_TPL.left * 8 + 16)) + 2
    local ay = endY or (BODY_TPL.top * 8 + 1)
    local limit = BODY_TPL.left * 8 + BODY_TPL.width * 8 - 10
    if ax > limit then ax = limit end
    Chrome.promptArrow(ax, ay, frame)
  end
end

return Ui
