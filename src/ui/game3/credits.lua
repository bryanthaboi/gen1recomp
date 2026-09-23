-- pokefirered/src/credits.c:711 DoCredits

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Extract = require("src.import.gba.extract_island1")

local Credits = {}

Credits.ID = "credits"
Credits.open = false

-- pokefirered/src/credits.c:25
local SCENE = {
  INIT_WIN0 = 0, SETUP_DARKEN_EFFECT = 1, OPEN_WIN0 = 2, LOAD_PLAYER_SPRITE_AT_INDIGO = 3,
  PRINT_TITLE_STAFF = 4, WAIT_TITLE_STAFF = 5, EXEC_CMD = 6, PRINT_ADDPRINTER1 = 7,
  PRINT_ADDPRINTER2 = 8, PRINT_DELAY = 9, MAPNEXT_DESTROYWINDOW = 10, MAPNEXT_LOADMAP = 11,
  MAP_LOADMAP_CREATESPRITES = 12, MON_DESTROY_ASSETS = 13, MON_SHOW = 14,
  THEEND_DESTROY_ASSETS = 15, THEEND_SHOW = 16, WAITBUTTON = 17, TERMINATE = 18,
}
Credits.SCENE = SCENE

-- pokefirered/src/credits.c:48
local CMD_PRINT, CMD_MAPNEXT, CMD_MAP, CMD_MON, CMD_THEENDGFX, CMD_WAITBUTTON = 0, 1, 2, 3, 4, 5
Credits.CMD = {
  PRINT = CMD_PRINT, MAPNEXT = CMD_MAPNEXT, MAP = CMD_MAP, MON = CMD_MON,
  THEENDGFX = CMD_THEENDGFX, WAITBUTTON = CMD_WAITBUTTON,
}

-- pokefirered/include/constants/flags.h:1530
local FLAG_DONT_SHOW_MAP_NAME_POPUP = 0x4000
-- pokefirered/src/credits.c:456
local WIN_X, WIN_Y = 0, 32
-- pokefirered/src/credits.c:453
local HEADER_FG, HEADER_SHADOW = 5, 2
local REGULAR_FG, REGULAR_SHADOW = 1, 2
-- pokefirered/src/new_menu_helpers.c:74
local LINE_HEIGHT = 14
local BLACK, WHITE = { 0, 0, 0 }, { 1, 1, 1 }

-- pokefirered/src/palette.c:151
local ALL = { world = true, text = true, sprite = true, screen = true }
local TEXT_PAL = { text = true }
local FIELD_PALS = { world = true, text = true, screen = true }

local M
local images = {}

local function root()
  return (Extract.CACHE_ROOT or "data/generated/gba") .. "/credits/"
end

local function read(rel)
  return require("src.core.game3.dataset").cache():read(root() .. rel)
end

local function load_table(rel)
  local src = read(rel)
  if not src then return nil end
  local chunk = load(src, "@credits/" .. rel, "t", {})
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  if ok and type(v) == "table" then return v end
  return nil
end

local function image(name, w, h)
  local key = name
  if images[key] ~= nil then return images[key] or nil end
  local bytes = read(name .. ".rgba")
  local entry = false
  if bytes and #bytes == w * h * 4 then
    local data = love.image.newImageData(w, h, "rgba8", bytes)
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    entry = { image = img, data = data, w = w, h = h }
  end
  images[key] = entry
  return entry or nil
end

local function quad_cache(entry, fw, fh, frame)
  entry.quads = entry.quads or {}
  local q = entry.quads[frame]
  if not q then
    q = love.graphics.newQuad(0, frame * fh, fw, fh, entry.w, entry.h)
    entry.quads[frame] = q
  end
  return q
end

local function flags()
  return require("src.core.game3.scripting.flags")
end

local function store()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.store
end

local function session()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession()
end

local function game()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt._game
end

-- pokefirered/src/palette.c:151 BeginNormalPaletteFade
local function begin_fade(groups, delay, startY, targetY, color)
  local f = M.fade
  if f and f.active then return false end
  M.fade = {
    groups = groups, delay = delay, counter = delay, y = startY, target = targetY,
    color = color or BLACK, toggle = false, finishing = false, fcount = 0, active = true,
  }
  Credits.updateFade()
  return true
end

local function fade_active()
  return M.fade ~= nil and M.fade.active
end

-- pokefirered/src/palette.c:393 UpdateNormalPaletteFade
function Credits.updateFade()
  local f = M.fade
  if not (f and f.active) then return end
  if f.finishing then
    -- pokefirered/src/palette.c:757
    if f.fcount == 4 then
      f.active = false
      f.finishing = false
      f.fcount = 0
    else
      f.fcount = f.fcount + 1
    end
    return
  end
  if not f.toggle then
    if f.counter < f.delay then
      f.counter = f.counter + 1
      return
    end
    f.counter = 0
  end
  for g in pairs(f.groups) do
    M.level[g] = { y = f.y, color = f.color }
  end
  f.toggle = not f.toggle
  if not f.toggle then
    if f.y == f.target then
      f.finishing = true
    elseif f.y < f.target then
      f.y = math.min(f.target, f.y + 2)
    else
      f.y = math.max(f.target, f.y - 2)
    end
  end
end

local function set_level(g, y, color)
  M.level[g] = { y = y, color = color or BLACK }
end

-- pokefirered/src/credits.c:769
local function create_window()
  M.text = nil
  M.windowActive = true
  -- pokefirered/src/credits.c:830
  set_level("text", M.level.world.y, M.level.world.color)
end

-- pokefirered/src/credits.c:778
local function destroy_window()
  if M.windowActive then
    M.text = nil
    M.windowActive = false
  end
end

-- pokefirered/src/credits.c:1336 LoadPlayerOrRivalSprite
local function load_player_or_rival(whichScene)
  if M.task then return end
  local p = M.pack.spriteParams[whichScene]
  if not p then return end
  local x, y
  if p.motion == 1 then
    x, y = 240 + 32, 80
  elseif p.motion == 2 then
    x, y = 240 - 32, 160
  else
    x, y = 240 - 32, 80
  end
  local s = session() or {}
  local g = s.gender or s.playerGender
  local female = g == 1 or g == "female" or g == "F"
  local sheet = p.character == 1 and "rival" or (female and "player_female" or "player_male")
  local ground = ({ [0] = "ground_grass", [1] = "ground_grass", [2] = "ground_dirt", [3] = "ground_city" })[p.ground]
  M.task = {
    motion = p.motion,
    sheet = sheet,
    ground = ground,
    groundRunning = p.ground ~= 1,
    x = x, y = y, gx = x, gy = y + 38,
    frame = 0, frameTimer = 0, gframe = 0, gframeTimer = 0,
  }
  set_level("sprite", 0)
end

-- pokefirered/src/credits.c:1322 DestroyPlayerOrRivalSprite
local function destroy_player_or_rival()
  M.task = nil
end

-- pokefirered/src/credits.c:1280 Task_MovePlayerAndGroundSprites
local function run_tasks()
  local t = M.task
  if not t then return end
  if t.motion == 1 then
    if t.x ~= 0xD0 then
      t.x, t.gx = t.x - 1, t.gx - 1
    else
      t.motion = 0
    end
  elseif t.motion == 2 then
    if M.parity % 2 == 1 then
      if t.y ~= 0x50 then
        t.y, t.gy = t.y - 1, t.gy - 1
      else
        t.motion = 0
      end
    end
  elseif t.motion == 3 then
    if M.mainseq == SCENE.THEEND_DESTROY_ASSETS then
      t.x, t.gx = t.x - 1, t.gx - 1
    end
  end
end

-- pokefirered/src/credits.c:499
local function animate_sprites()
  local t = M.task
  if not t then return end
  t.frameTimer = t.frameTimer + 1
  if t.frameTimer >= 8 then
    t.frameTimer = 0
    t.frame = (t.frame + 1) % 6
  end
  if t.groundRunning then
    t.gframeTimer = t.gframeTimer + 1
    if t.gframeTimer >= 8 then
      t.gframeTimer = 0
      t.gframe = (t.gframe + 1) % 8
    end
  end
end

-- pokefirered/src/overworld.c:2490 CameraCB_CreditsPan
local function camera_update()
  local c = M.cam
  if not c then return end
  if c.len == 0 then
    c.idx = c.idx + 1
    local cmd = c.cmds[c.idx]
    if not cmd then
      c.sx, c.sy = 0, 0
      M.cam = nil
      return
    end
    c.len = cmd.length
    c.sx, c.sy = cmd.xspeed, cmd.yspeed
  end
  c.len = c.len - 1
  c.px = c.px + c.sx
  c.py = c.py + c.sy
  local FieldView = require("src.core.game3.field_view")
  FieldView.setCameraPanning(c.px, c.py)
end

local function overworld_main_cb()
  camera_update()
  local okA, TilesetAnim = pcall(require, "src.core.game3.tileset_anim")
  if okA and TilesetAnim and TilesetAnim.step then TilesetAnim.step() end
end

-- pokefirered/src/overworld.c:2384 SetUpScrollSceneForCredits
local function load_scene_map(which)
  local scene = M.pack.scenes[which]
  local load = scene and scene[1]
  if not (load and load.op == "loadmap") then return end
  local MapCatalog = require("src.import.gba.map_catalog")
  local mapId = MapCatalog.mapIdFor(load.mapGroup, load.mapNum)
  local cmds = {}
  for i = 2, #scene do
    if scene[i].op == "scroll" then cmds[#cmds + 1] = scene[i] end
  end
  local FieldView = require("src.core.game3.field_view")
  FieldView.setCameraPanning(0, 0)
  M.cam = { cmds = cmds, idx = 0, len = load.delay, sx = 0, sy = 0, px = 0, py = 0 }
  local g = game()
  if g and mapId then
    require("src.core.game3.map").load(nil, g, mapId, { x = load.x, y = load.y, facing = "down" })
  end
  set_level("world", 16)
  set_level("text", 16)
end

local function scroll_scene_ready()
  -- pokefirered/src/credits.c:803
  create_window()
  M.win0 = { top = 36, bottom = 160 - 36 }
  M.darken = true
end

-- pokefirered/src/credits.c:788 DoOverworldMapScrollScene
local function do_overworld_map_scroll_scene()
  if M.subseq == 0 then
    flags().setFlag(store(), nil, FLAG_DONT_SHOW_MAP_NAME_POPUP, true)
    local Map = require("src.core.game3.map")
    Map.disableMusicChange = Map.MUSIC_DISABLE_KEEP
    M.ovwld = 0
    M.subseq = 1
  end
  -- pokefirered/src/overworld.c:2384
  M.ovwld = M.ovwld + 1
  if M.ovwld == 3 then
    load_scene_map(M.whichMon)
  elseif M.ovwld == 11 then
    -- pokefirered/src/overworld.c:2481
    begin_fade(FIELD_PALS, 0, 16, 0, BLACK)
  elseif M.ovwld == 13 then
    M.ovwld = 0
    scroll_scene_ready()
    return true
  end
  return false
end

-- pokefirered/src/credits.c:1101 DoCreditsMonScene
local function do_credits_mon_scene()
  local mon = M.mon
  local s = M.subseq
  if s == 0 then
    M.fade = nil
    destroy_player_or_rival()
    M.win0 = nil
    M.darken = false
    local def = M.pack.mons[M.whichMon]
    local size = M.manifest.mons[M.whichMon]
    M.mon = {
      def = def,
      timer = 0,
      shown = 0,
      circleScale = 0,
      showCircle = false,
      showWindows = false,
      showBall = false,
      ball = image("pokeball_" .. M.whichMon, 240, 160),
      frames = {
        image("mon_" .. M.whichMon .. "_1", size.frame1.w, size.frame1.h),
        image("mon_" .. M.whichMon .. "_2", size.frame2.w, size.frame2.h),
      },
    }
    set_level("screen", 16)
    M.subseq = 1
  elseif s == 1 then
    mon.shown = 0
    M.subseq = 2
  elseif s == 2 then
    mon.showCircle = true
    mon.showWindows = true
    begin_fade(ALL, 0, 16, 0, BLACK)
    mon.timer = 40
    M.subseq = 3
  elseif s == 3 then
    if mon.timer ~= 0 then
      mon.timer = mon.timer - 1
    else
      M.subseq = 4
    end
  elseif s == 4 then
    if not fade_active() then
      mon.timer = 8
      mon.next = 1
      M.subseq = 5
    end
  elseif s == 5 then
    if mon.timer ~= 0 then
      mon.timer = mon.timer - 1
    elseif mon.next < 3 then
      mon.shown = mon.next
      mon.timer = 4
      mon.next = mon.next + 1
    else
      M.subseq = 6
    end
  elseif s == 6 then
    if mon.timer < 256 then
      mon.timer = mon.timer + 16
      mon.circleScale = mon.timer
    else
      mon.circleScale = 0x100
      mon.timer = 32
      M.subseq = 7
    end
  elseif s == 7 then
    if mon.timer ~= 0 then
      mon.timer = mon.timer - 1
    else
      mon.showCircle = false
      mon.showBall = true
      pcall(function() require("src.core.game3.audio").playCry(mon.def.species) end)
      mon.timer = 128
      M.subseq = 8
    end
  elseif s == 8 then
    if mon.timer ~= 0 then
      mon.timer = mon.timer - 1
    else
      begin_fade(ALL, 0, 0, 16, BLACK)
      M.subseq = 9
    end
  elseif s == 9 then
    if not fade_active() then
      M.subseq = 0
      M.mon = nil
      return true
    end
  end
  return false
end

-- pokefirered/src/credits.c:1230 DoCopyrightOrTheEndGfxScene
local function do_copyright_or_the_end_gfx_scene()
  local s = M.subseq
  if s == 0 then
    M.fade = nil
    destroy_player_or_rival()
    M.win0 = nil
    M.darken = false
    M.world = false
    M.closing = { img = image(M.whichMon == 0 and "copyright" or "the_end", 240, 160), shown = false }
    M.subseq = 1
  elseif s == 1 then
    M.subseq = 2
  elseif s == 2 then
    M.closing.shown = true
    if M.whichMon ~= 0 then
      begin_fade(ALL, 0, 0, 0, BLACK)
    else
      begin_fade(ALL, 0, 16, 0, BLACK)
    end
    M.subseq = 3
  elseif s == 3 then
    if not fade_active() then
      M.subseq = 0
      return true
    end
  end
  return false
end

local function cmd_at(i)
  return M.pack.script[i]
end

-- pokefirered/src/credits.c:815 RollCredits
local function roll_credits()
  local seq = M.mainseq
  if seq == SCENE.INIT_WIN0 then
    M.win0 = { top = 80 - 1, bottom = 80 + 1 }
    M.mainseq = SCENE.SETUP_DARKEN_EFFECT
    return 0
  elseif seq == SCENE.SETUP_DARKEN_EFFECT then
    M.darken = true
    create_window()
    M.mainseq = SCENE.OPEN_WIN0
    return 0
  elseif seq == SCENE.OPEN_WIN0 then
    if M.win0.top == 0x24 then
      M.timer = 0
      M.mainseq = SCENE.LOAD_PLAYER_SPRITE_AT_INDIGO
    else
      M.win0.top = M.win0.top - 1
      M.win0.bottom = M.win0.bottom + 1
    end
    return 0
  elseif seq == SCENE.LOAD_PLAYER_SPRITE_AT_INDIGO then
    if M.timer ~= 0 then
      M.timer = M.timer - 1
      return 0
    end
    load_player_or_rival(0)
    M.timer = 100
    M.mainseq = SCENE.PRINT_TITLE_STAFF
    return 0
  elseif seq == SCENE.PRINT_TITLE_STAFF then
    if M.timer ~= 0 then
      M.timer = M.timer - 1
      return 0
    end
    M.timer = 360
    -- pokefirered/src/credits.c:868
    M.text = { staff = true, title = M.pack.title }
    M.mainseq = SCENE.WAIT_TITLE_STAFF
    return 0
  elseif seq == SCENE.WAIT_TITLE_STAFF then
    if M.timer ~= 0 then
      M.timer = M.timer - 1
      return 0
    end
    destroy_window()
    M.mainseq = SCENE.EXEC_CMD
    M.timer = 0
    M.scrcmdidx = 1
    return 0
  elseif seq == SCENE.EXEC_CMD then
    if M.timer ~= 0 then
      M.timer = M.timer - 1
      return M.canSpeedThrough
    end
    local c = cmd_at(M.scrcmdidx)
    if not c then
      M.mainseq = SCENE.TERMINATE
      return 0
    end
    if c.cmd == CMD_PRINT then
      begin_fade(TEXT_PAL, 0, 0, 16, BLACK)
      M.mainseq = SCENE.PRINT_ADDPRINTER1
      M.text = nil
      return M.canSpeedThrough
    elseif c.cmd == CMD_MAPNEXT then
      M.mainseq = SCENE.MAPNEXT_DESTROYWINDOW
      M.whichMon = c.param
      -- pokefirered/src/credits.c:898
      begin_fade(FIELD_PALS, 0, 0, 16, BLACK)
    elseif c.cmd == CMD_MAP then
      M.mainseq = SCENE.MAP_LOADMAP_CREATESPRITES
      M.whichMon = c.param
    elseif c.cmd == CMD_MON then
      M.mainseq = SCENE.MON_DESTROY_ASSETS
      M.whichMon = c.param
      -- pokefirered/src/credits.c:907
      begin_fade(ALL, 0, 0, 16, BLACK)
    elseif c.cmd == CMD_THEENDGFX then
      M.mainseq = SCENE.THEEND_DESTROY_ASSETS
      M.whichMon = c.param
      begin_fade(ALL, 4, 0, 16, BLACK)
    elseif c.cmd == CMD_WAITBUTTON then
      M.mainseq = SCENE.WAITBUTTON
    end
    M.timer = c.duration
    M.scrcmdidx = M.scrcmdidx + 1
    return 0
  elseif seq == SCENE.PRINT_ADDPRINTER1 then
    if fade_active() then return M.canSpeedThrough end
    local c = cmd_at(M.scrcmdidx)
    local t = M.pack.texts[c.param] or {}
    M.text = { title = t.title or "" }
    M.mainseq = SCENE.PRINT_ADDPRINTER2
    return M.canSpeedThrough
  elseif seq == SCENE.PRINT_ADDPRINTER2 then
    local c = cmd_at(M.scrcmdidx)
    local t = M.pack.texts[c.param] or {}
    M.text.names = t.names or ""
    M.mainseq = SCENE.PRINT_DELAY
    return M.canSpeedThrough
  elseif seq == SCENE.PRINT_DELAY then
    local c = cmd_at(M.scrcmdidx)
    M.timer = c.duration
    M.scrcmdidx = M.scrcmdidx + 1
    begin_fade(TEXT_PAL, 0, 16, 0, BLACK)
    M.mainseq = SCENE.EXEC_CMD
    return M.canSpeedThrough
  elseif seq == SCENE.MAPNEXT_DESTROYWINDOW then
    if not fade_active() then
      destroy_window()
      M.subseq = 0
      M.mainseq = SCENE.MAPNEXT_LOADMAP
    end
    return 0
  elseif seq == SCENE.MAPNEXT_LOADMAP then
    if do_overworld_map_scroll_scene() then
      M.canSpeedThrough = 1
      M.mainseq = SCENE.EXEC_CMD
    end
    return 0
  elseif seq == SCENE.MAP_LOADMAP_CREATESPRITES then
    if not fade_active() then
      destroy_window()
      M.subseq = 0
      M.world = true
      set_level("screen", 0)
      while not do_overworld_map_scroll_scene() do end
      -- pokefirered/src/credits.c:966
      local scene = ({ [3] = 1, [6] = 2, [9] = 3, [12] = 4 })[M.whichMon] or 1
      load_player_or_rival(scene)
      M.canSpeedThrough = 1
      M.mainseq = SCENE.EXEC_CMD
    end
    return 0
  elseif seq == SCENE.MON_DESTROY_ASSETS then
    if not fade_active() then
      destroy_player_or_rival()
      destroy_window()
      M.subseq = 0
      M.canSpeedThrough = 0
      M.world = false
      M.mainseq = SCENE.MON_SHOW
    end
    return 0
  elseif seq == SCENE.MON_SHOW then
    if do_credits_mon_scene() then
      M.mainseq = SCENE.EXEC_CMD
    end
    return 0
  elseif seq == SCENE.THEEND_DESTROY_ASSETS then
    if not fade_active() then
      destroy_window()
      M.subseq = 0
      M.canSpeedThrough = 0
      M.mainseq = SCENE.THEEND_SHOW
    end
    return 0
  elseif seq == SCENE.THEEND_SHOW then
    if do_copyright_or_the_end_gfx_scene() then
      M.mainseq = SCENE.EXEC_CMD
    end
    return 0
  elseif seq == SCENE.WAITBUTTON then
    if M.aPressed then
      begin_fade(ALL, 0, 0, 16, WHITE)
      M.mainseq = SCENE.TERMINATE
      return 0
    end
    if M.timer ~= 0 then
      M.timer = M.timer - 1
    else
      M.mainseq = SCENE.TERMINATE
      begin_fade(ALL, 0, 0, 16, WHITE)
    end
    return 0
  elseif seq == SCENE.TERMINATE then
    if not fade_active() then destroy_window() end
  end
  return 2
end

function Credits.isOpen()
  return Credits.open
end

function Credits.state()
  if not M then return nil end
  local c = M.pack and M.pack.script[M.scrcmdidx - 1]
  return {
    mainseq = M.mainseq,
    subseq = M.subseq,
    scrcmdidx = M.scrcmdidx,
    lastCmd = c and c.cmd,
    whichMon = M.whichMon,
    text = M.text,
    textLevel = M.level.text.y,
    task = M.task,
    mon = M.mon,
    closing = M.closing,
    frames = M.frames,
    world = M.world,
  }
end

function Credits.start(opts)
  opts = opts or {}
  local pack = load_table("pack.lua")
  local manifest = load_table("manifest.lua")
  if not (pack and manifest) then return false end
  images = {}
  M = {
    pack = pack,
    manifest = manifest,
    mainseq = SCENE.INIT_WIN0,
    subseq = 0,
    timer = 0,
    scrcmdidx = 1,
    canSpeedThrough = 0,
    whichMon = 0,
    windowActive = false,
    parity = 0,
    frames = 0,
    world = true,
    darken = false,
    level = {
      world = { y = 0, color = BLACK }, text = { y = 0, color = BLACK },
      sprite = { y = 0, color = BLACK }, screen = { y = 0, color = BLACK },
    },
  }
  local FieldView = require("src.core.game3.field_view")
  FieldView.hideActors = true
  FieldView.setCameraPanning(0, 0)
  Credits.open = true
  Stack.push(Credits.ID, Credits, { hideBelow = true })
  return true
end

-- pokefirered/src/credits.c:746
local function terminate()
  Credits.open = false
  Stack.pop(Credits.ID)
  flags().setFlag(store(), nil, FLAG_DONT_SHOW_MAP_NAME_POPUP, false)
  local Map = require("src.core.game3.map")
  Map.disableMusicChange = Map.MUSIC_DISABLE_OFF
  local FieldView = require("src.core.game3.field_view")
  FieldView.hideActors = false
  FieldView.setCameraPanning(0, 0)
  M.done = true
  local g = game()
  if g then g.softResetRequested = true end
end

function Credits.reset()
  Credits.open = false
  M = nil
  local Map = require("src.core.game3.map")
  Map.disableMusicChange = Map.MUSIC_DISABLE_OFF
  local FieldView = require("src.core.game3.field_view")
  FieldView.hideActors = false
  FieldView.setCameraPanning(0, 0)
end

function Credits.update(_dt)
  if not (Credits.open and M) then return end
  M.frames = M.frames + 1
  local r = roll_credits()
  M.aPressed = false
  if r == 2 then
    terminate()
    return
  end
  run_tasks()
  animate_sprites()
  if r == 1 and M.parity % 2 == 1 then overworld_main_cb() end
  Credits.updateFade()
  if r == 1 then M.parity = M.parity + 1 end
end

-- pokefirered/src/credits.c:1015
function Credits.handleInput(input)
  if not (Credits.open and M and input) then return end
  if M.mainseq == SCENE.WAITBUTTON and input:wasPressed("a") then
    M.aPressed = true
  end
end

local function lerp_color(c, level)
  local a = (level.y or 0) / 16
  local t = level.color or BLACK
  return { c[1] + (t[1] - c[1]) * a, c[2] + (t[2] - c[2]) * a, c[3] + (t[3] - c[3]) * a, 1 }
end

local function print_block(text, x, y, fg, shadow, pitch)
  local colors = {
    fg = lerp_color(FrlgFont.STDPAL[fg], M.level.text),
    shadow = lerp_color(FrlgFont.STDPAL[shadow], M.level.text),
    bg = FrlgFont.STDPAL[0],
  }
  local line = 0
  for raw in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local lx, body = x, raw
    local clear, rest = raw:match("^{CLEAR_TO (%d+)}(.*)$")
    if clear then
      lx = x + tonumber(clear)
      body = rest
    end
    if body ~= "" then
      FrlgFont.draw(body, WIN_X + lx, WIN_Y + y + line * pitch, { colors = colors })
    end
    line = line + 1
  end
end

local function with_band(fn)
  local w = M.win0
  if not w then return end
  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.intersectScissor(0, w.top, 240, math.max(0, w.bottom - w.top))
  fn()
  if sx then love.graphics.setScissor(sx, sy, sw, sh) else love.graphics.setScissor() end
end

local function draw_sprite(entry, fw, fh, frame, cx, cy, level)
  if not entry then return end
  local k = 1 - level.y / 16
  love.graphics.setColor(k, k, k, 1)
  love.graphics.draw(entry.image, quad_cache(entry, fw, fh, frame), cx - fw / 2, cy - fh / 2)
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_field_layer()
  local Renderer = package.loaded["src.render.Renderer"]
  local wl = M.level.world
  if Renderer then
    Renderer.worldFadeAlpha = wl.y / 16
    Renderer.worldFadeColor = wl.color
  end
  -- pokefirered/src/credits.c:762 InitBgDarkenEffect
  if M.darken and M.win0 then
    love.graphics.setColor(0, 0, 0, 10 / 16)
    love.graphics.rectangle("fill", 0, M.win0.top, 240, M.win0.bottom - M.win0.top)
    love.graphics.setColor(1, 1, 1, 1)
  end
  with_band(function()
    local t = M.text
    if t and M.windowActive then
      if t.staff then
        print_block(t.title, 8, 0x29, HEADER_FG, HEADER_SHADOW, LINE_HEIGHT + 2)
      else
        print_block(t.title or "", 2, 6, HEADER_FG, HEADER_SHADOW, LINE_HEIGHT)
        if t.names then print_block(t.names, 8, 6, REGULAR_FG, REGULAR_SHADOW, LINE_HEIGHT) end
      end
    end
    local task = M.task
    if task then
      local sl = M.level.sprite
      local ground = image(task.ground, 64, 32 * 8)
      draw_sprite(ground, 64, 32, task.groundRunning and task.gframe or 0, task.gx, task.gy, sl)
      draw_sprite(image(task.sheet, 64, 64 * 6), 64, 64, task.frame, task.x, task.y, sl)
    end
  end)
end

local function screen_overlay()
  local l = M.level.screen
  if l.y > 0 then
    love.graphics.setColor(l.color[1], l.color[2], l.color[3], l.y / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

local function draw_mon_scene()
  local mon = M.mon
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  if not mon then return end
  if mon.showBall and mon.ball then
    love.graphics.draw(mon.ball.image, 0, 0)
  end
  if mon.showCircle then
    local circle = image("circle", M.manifest.circle.w, M.manifest.circle.h)
    if circle then
      -- pokefirered/src/credits.c:1126
      local s = mon.circleScale
      if s <= 0 then
        local r, g, b, a = circle.data:getPixel(circle.w / 2, circle.h / 2)
        love.graphics.setColor(r, g, b, a)
        love.graphics.rectangle("fill", 0, 0, 240, 160)
        love.graphics.setColor(1, 1, 1, 1)
      else
        local k = 256 / s
        love.graphics.draw(circle.image, 0x78, 0x50, 0, k, k, circle.w / 2, circle.h / 2)
      end
    end
  end
  if mon.showWindows then
    local wins = mon.def.windows
    if mon.shown == 0 then
      local Pokemon = require("src.core.game3.pokemon")
      local pic = Pokemon.frontPic(mon.def.species)
      if pic and pic.image then
        love.graphics.draw(pic.image, wins[1].left * 8, wins[1].top * 8)
      end
    else
      local f = mon.frames[mon.shown]
      local w = wins[mon.shown + 1]
      if f and w then love.graphics.draw(f.image, w.left * 8, w.top * 8) end
    end
  end
  screen_overlay()
end

function Credits.draw()
  if not (Credits.open and M) then return end
  if M.mainseq == SCENE.MON_SHOW then
    local Renderer = package.loaded["src.render.Renderer"]
    if Renderer then Renderer.worldFadeAlpha = 1 Renderer.worldFadeColor = BLACK end
    draw_mon_scene()
    return
  end
  if M.closing then
    local Renderer = package.loaded["src.render.Renderer"]
    if Renderer then Renderer.worldFadeAlpha = 1 Renderer.worldFadeColor = BLACK end
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
    if M.closing.shown and M.closing.img then love.graphics.draw(M.closing.img.image, 0, 0) end
    screen_overlay()
    return
  end
  draw_field_layer()
end

return Credits
