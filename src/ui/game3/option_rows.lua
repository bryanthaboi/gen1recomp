-- pokefirered/src/option_menu.c

local Options = require("src.core.game3.options")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local Rows = {}

local function cart(ctx)
  return Options.block(ctx.options)
end

local function cartCycle(ctx, key, n, dir)
  local o = cart(ctx)
  local cur = tonumber(o[key]) or 0
  dir = (dir and dir < 0) and -1 or 1
  Options.set({ options = o }, key, ((cur + dir) % n + n) % n)
  return true
end

-- src/option_menu.c:478
local function cartLabel(ctx, key, tbl)
  local cur = tonumber(cart(ctx)[key]) or 0
  if cur < 0 or cur >= RomText.count(tbl) then return "?" end
  return RomText.at(tbl, cur)
end

-- src/option_menu.c:136
local function cartName(item)
  return RomText.at("sOptionMenuItemsNames", item)
end

local function volLabel(v)
  v = tonumber(v) or 7
  return v == 0 and Strings("OFF") or tostring(v)
end

local function stepVolume(v, dir)
  return math.max(0, math.min(7, (tonumber(v) or 7) + dir))
end

local FILTERS = { "OFF", "1X", "2X", "3X" }

local function gameSpeedLabel(v)
  local GameSpeed = require("src.core.GameSpeed")
  local speed = GameSpeed.clamp(v)
  if speed == 1 then return Strings("NORMAL") end
  return Strings("%dX", speed)
end

local function speedRow(id, label, key)
  return {
    id = id, label = Strings(label),
    value = function(ctx) return gameSpeedLabel(ctx.options[key]) end,
    step = function(ctx, dir)
      local GameSpeed = require("src.core.GameSpeed")
      ctx.options[key] = GameSpeed.cycle(ctx.options[key], dir)
      return true
    end,
  }
end

function Rows.build(ctx)
  local rows = {}
  local function add(row) rows[#rows + 1] = row end

  add({
    id = "textSpeed", label = cartName(0),
    value = function(c) return cartLabel(c, "textSpeed", "sTextSpeedOptions") end,
    step = function(c, dir) return cartCycle(c, "textSpeed", 3, dir) end,
  })
  add(speedRow("speedOverworld", "OVERWORLD SPEED", "speedOverworld"))
  add(speedRow("speedBattle", "BATTLE SPEED", "speedBattle"))
  add(speedRow("speedMenu", "MENU SPEED", "speedMenu"))

  add({
    id = "battleScene", label = cartName(1),
    value = function(c) return cartLabel(c, "battleScene", "sBattleSceneOptions") end,
    step = function(c, dir) return cartCycle(c, "battleScene", 2, dir) end,
  })
  add({
    id = "battleStyle", label = cartName(2),
    value = function(c) return cartLabel(c, "battleStyle", "sBattleStyleOptions") end,
    step = function(c, dir) return cartCycle(c, "battleStyle", 2, dir) end,
  })

  add({
    id = "sound", label = cartName(3),
    value = function(c) return cartLabel(c, "sound", "sSoundOptions") end,
    step = function(c, dir)
      cartCycle(c, "sound", 2, dir)
      local Audio = require("src.core.game3.audio")
      Audio.applyOptions({ options = cart(c) })
      return true
    end,
  })
  add({
    id = "musicVol", label = Strings("MUSIC VOL"),
    value = function(c) return volLabel(c.options.musicVol) end,
    step = function(c, dir)
      c.options.musicVol = stepVolume(c.options.musicVol, dir)
      require("src.core.game3.audio").applyEngineOptions(c.options)
      return true
    end,
  })
  add({
    id = "sfxVol", label = Strings("SFX VOL"),
    value = function(c) return volLabel(c.options.sfxVol) end,
    step = function(c, dir)
      c.options.sfxVol = stepVolume(c.options.sfxVol, dir)
      require("src.core.game3.audio").applyEngineOptions(c.options)
      return true
    end,
  })
  add({
    id = "musicFilter", label = Strings("MUSIC FILTER"),
    value = function(c)
      return Strings(FILTERS[(tonumber(c.options.musicFilter) or 0) + 1] or "OFF")
    end,
    step = function(c, dir)
      local v = (tonumber(c.options.musicFilter) or 0) + (dir < 0 and -1 or 1)
      c.options.musicFilter = (v % 4 + 4) % 4
      require("src.core.game3.audio").applyEngineOptions(c.options)
      return true
    end,
  })

  add({
    id = "buttonMode", label = cartName(4),
    value = function(c) return cartLabel(c, "buttonMode", "sButtonTypeOptions") end,
    step = function(c, dir) return cartCycle(c, "buttonMode", 3, dir) end,
  })
  add({
    id = "frameType", label = cartName(5),
    value = function(c)
      return RomText.plain("gText_FrameType") .. string.format("%2d", (tonumber(cart(c).frameType) or 0) + 1) -- src/option_menu.c:496
    end,
    step = function(c, dir)
      cartCycle(c, "frameType", 10, dir)
      local okC, Chrome = pcall(require, "src.ui.game3.chrome")
      if okC and Chrome and Chrome.setFrameType then
        Chrome.setFrameType(cart(c).frameType)
      end
      return true
    end,
  })

  add({
    id = "uiLayout", label = Strings("UI LAYOUT"),
    value = function(c)
      return Strings(c.options.uiLayout == "dynamic" and "DYNAMIC" or "CENTERED")
    end,
    step = function(c)
      c.options.uiLayout = (c.options.uiLayout == "dynamic") and "centered" or "dynamic"
      return true
    end,
  })
  add({
    id = "uiLetterbox", label = Strings("UI LETTERBOX"),
    value = function(c)
      local Letterbox = require("src.render.Letterbox")
      return Strings(Letterbox.label(c.options.uiLetterbox))
    end,
    step = function(c, dir)
      local Letterbox = require("src.render.Letterbox")
      c.options.uiLetterbox = Letterbox.cycle(c.options.uiLetterbox, dir)
      Letterbox.setMode(c.options.uiLetterbox)
      return true
    end,
  })
  add({
    id = "pixelFilter", label = Strings("PIXEL FILTER"),
    value = function(c)
      local Xbrz = require("src.render.Xbrz")
      return Strings(Xbrz.label(c.options.pixelFilter))
    end,
    step = function(c, dir)
      local Xbrz = require("src.render.Xbrz")
      c.options.pixelFilter = Xbrz.cycle(c.options.pixelFilter, dir)
      Xbrz.setMode(c.options.pixelFilter)
      return true
    end,
  })
  add({
    id = "videoMode", label = Strings("VIDEO MODE"),
    value = function(c)
      local VideoMode = require("src.core.VideoMode")
      return Strings(VideoMode.modeLabel(c.options.videoMode))
    end,
    step = function(c, dir)
      local VideoMode = require("src.core.VideoMode")
      c.options.videoMode = VideoMode.cycle(c.options.videoMode, dir)
      VideoMode.apply(c.options.videoMode)
      return true
    end,
  })
  add({
    id = "orientation", label = Strings("ORIENTATION"),
    value = function(c)
      local Orientation = require("src.core.Orientation")
      return Strings(Orientation.modeLabel(c.options.orientation))
    end,
    step = function(c, dir)
      local Orientation = require("src.core.Orientation")
      c.options.orientation = Orientation.cycle(c.options.orientation, dir)
      Orientation.apply(c.options.orientation)
      return true
    end,
  })
  add({
    id = "faithfulRes", label = Strings("FAITHFUL RATIO"),
    value = function(c)
      local FaithfulRes = require("src.core.FaithfulRes")
      return Strings(FaithfulRes.label(c.options.faithfulRes))
    end,
    step = function(c, dir)
      local FaithfulRes = require("src.core.FaithfulRes")
      c.options.faithfulRes = FaithfulRes.cycle(c.options.faithfulRes, dir)
      FaithfulRes.apply(c.options.faithfulRes)
      return true
    end,
  })
  add({
    id = "screenPos", label = Strings("SCREEN POS"),
    value = function(c)
      local ScreenPosition = require("src.core.ScreenPosition")
      return Strings(ScreenPosition.label(c.options.screenPos))
    end,
    step = function(c, dir)
      local ScreenPosition = require("src.core.ScreenPosition")
      local nextMode = ScreenPosition.cycle(c.options.screenPos, dir)
      if nextMode == c.options.screenPos then return false end
      c.options.screenPos = nextMode
      ScreenPosition.setMode(nextMode)
      return true
    end,
  })
  add({
    id = "fpsCap", label = Strings("MAX FPS"),
    value = function(c)
      local FrameCap = require("src.core.FrameCap")
      return Strings(FrameCap.label(c.options.fpsCap))
    end,
    step = function(c, dir)
      local FrameCap = require("src.core.FrameCap")
      c.options.fpsCap = FrameCap.cycle(c.options.fpsCap, dir)
      FrameCap.apply(c.options.fpsCap)
      return true
    end,
  })
  add({
    id = "vsync", label = Strings("VSYNC"),
    value = function(c)
      local VSync = require("src.core.VSync")
      return Strings(VSync.label(c.options.vsync))
    end,
    step = function(c, dir)
      local VSync = require("src.core.VSync")
      c.options.vsync = VSync.cycle(c.options.vsync, dir)
      VSync.apply(c.options.vsync)
      return true
    end,
  })
  add({
    id = "logicClock", label = Strings("LOGIC CLOCK"),
    value = function(c)
      local LogicClock = require("src.core.LogicClock")
      return Strings(LogicClock.label(c.options.logicClock))
    end,
    step = function(c, dir)
      local LogicClock = require("src.core.LogicClock")
      c.options.logicClock = LogicClock.cycle(c.options.logicClock, dir)
      LogicClock.apply(c.options.logicClock)
      return true
    end,
  })
  add({
    id = "performance", label = Strings("PERFORMANCE"),
    value = function(c)
      local Performance = require("src.core.Performance")
      return Strings(Performance.label(c.options.performance))
    end,
    step = function(c, dir)
      local Performance = require("src.core.Performance")
      c.options.performance = Performance.cycle(c.options.performance, dir)
      if c.game and c.game.applyOptions then c.game:applyOptions(c.options) end
      return true
    end,
  })

  add({
    id = "tilt", label = Strings("TILT"),
    value = function(c)
      local Tilt = require("src.render.Tilt")
      return Strings(Tilt.levelLabel(tonumber(c.options.tilt) or 0))
    end,
    step = function(c, dir)
      local Tilt = require("src.render.Tilt")
      local n = #Tilt.ANGLE_LABELS
      local v = ((tonumber(c.options.tilt) or 0) + (dir < 0 and -1 or 1)) % n
      c.options.tilt = (v + n) % n
      Tilt.setLevel(c.options.tilt)
      return true
    end,
  })
  add({
    id = "zoom", label = Strings("ZOOM"),
    value = function(c)
      local Zoom = require("src.render.Zoom")
      return Strings(Zoom.offsetLabel(tonumber(c.options.zoom) or 0))
    end,
    step = function(c, dir)
      local Zoom = require("src.render.Zoom")
      local Renderer = require("src.render.Renderer")
      Zoom.nudgeOptions(c.options, dir, Renderer:fitScale())
      return true
    end,
  })
  add({
    id = "voidFill", label = Strings("VOID FILL"),
    value = function(c)
      local VoidFill = require("src.core.game3.void_fill")
      return Strings(VoidFill.label(cart(c).voidFill))
    end,
    step = function(c, dir)
      local VoidFill = require("src.core.game3.void_fill")
      local o = cart(c)
      o.voidFill = VoidFill.cycle(o.voidFill, dir)
      VoidFill.setMode(o.voidFill)
      return true
    end,
  })

  add({
    id = "touchControls", label = Strings("TOUCH PAD"),
    value = function(c)
      local t = c.options.touchControls
      local on = not (type(t) == "table" and t.enabled == false)
      return Strings(on and "ON" or "OFF")
    end,
    step = function(c)
      local TouchControls = require("src.core.TouchControls")
      local t = c.options.touchControls
      if type(t) ~= "table" then t = { enabled = true } end
      t.enabled = not (t.enabled ~= false)
      c.options.touchControls = t
      TouchControls:applyOptions(c.options)
      return true
    end,
  })
  add({
    id = "haptics", label = Strings("VIBRATION"),
    value = function(c)
      local TouchControls = require("src.core.TouchControls")
      return Strings(TouchControls.hapticLabel(c.options.haptics))
    end,
    step = function(c, dir)
      local TouchControls = require("src.core.TouchControls")
      c.options.haptics = TouchControls.cycleHaptics(c.options.haptics, dir)
      TouchControls:applyOptions(c.options)
      TouchControls.buzz(c.options.haptics)
      return true
    end,
  })
  -- Manager discoverable home (18-mod-manager-ux), same contract as Gen 1
  -- OptionsMenu: always listed with an installed count, activate opens the
  -- manager. Inert until A; costs a vanilla install a single row.
  add({
    id = "mods", label = Strings("MODS"),
    value = function(c)
      local status = (c.game and c.game.modStatus) or {}
      return Strings("%d INSTALLED", #(status.available or {}))
    end,
    activate = function(c)
      local ModManager = require("src.ui.game3.mod_manager")
      ModManager.show({ game = c.game, session = c.session })
    end,
  })
  add({
    id = "hotbar", label = Strings("KEY BAR"),
    value = function(c) return Strings(c.options.hotbar == false and "OFF" or "ON") end,
    step = function(c)
      local TouchControls = require("src.core.TouchControls")
      c.options.hotbar = (c.options.hotbar == false)
      TouchControls:applyOptions(c.options)
      return true
    end,
  })

  local Orientation = require("src.core.Orientation")
  local VideoMode = require("src.core.VideoMode")
  local touchEnv = os.getenv("POKEPORT_TOUCH")
  local mobile = Orientation.isAndroid() or Orientation.isIOS()
  local showTouch = touchEnv == "1" or (mobile and touchEnv ~= "0")
  local keep = {}
  for _, row in ipairs(rows) do
    local drop = false
    if row.id == "orientation" and not mobile then drop = true end
    if row.id == "videoMode" and VideoMode.fixedDisplay and VideoMode.fixedDisplay() then
      drop = true
    end
    if (row.id == "touchControls" or row.id == "haptics" or row.id == "hotbar")
        and not showTouch then
      drop = true
    end
    if not drop then keep[#keep + 1] = row end
  end
  return keep
end

Rows.GROUPS = {
  { id = "group.speed", label = "SPEED",
    members = { "textSpeed", "speedOverworld", "speedBattle", "speedMenu" } },
  { id = "group.video", label = "VIDEO",
    members = { "uiLayout", "videoMode", "orientation", "faithfulRes",
                "screenPos", "fpsCap", "vsync", "logicClock" } },
  { id = "group.graphics", label = "GRAPHICS",
    members = { "uiLetterbox", "pixelFilter", "frameType" } },
  { id = "group.audio", label = "AUDIO",
    members = { "sound", "musicVol", "sfxVol", "musicFilter" } },
  { id = "group.battle", label = "BATTLE OPTIONS",
    members = { "battleScene", "battleStyle" } },
  { id = "group.extras", label = "EXTRAS",
    members = { "tilt", "zoom", "voidFill" } },
}

Rows.ORDER = {
  "group.speed", "group.video", "group.graphics", "group.audio",
  "performance", "group.battle", "group.extras", "buttonMode", "mods",
}

function Rows.group(rows, openPage)
  local owner, picked = {}, {}
  for _, g in ipairs(Rows.GROUPS) do
    for _, id in ipairs(g.members) do owner[id] = g end
    picked[g.id] = {}
  end
  for _, row in ipairs(rows) do
    local g = row.id and owner[row.id]
    if g then picked[g.id][#picked[g.id] + 1] = row end
  end
  local made = {}
  for _, g in ipairs(Rows.GROUPS) do
    local members = picked[g.id]
    if #members > 0 then
      made[g.id] = {
        id = g.id, label = Strings(g.label), group = true,
        value = function() return Strings("%d OPTIONS", #members) end,
        activate = function(ctx) openPage(Strings(g.label), members) end,
      }
    end
  end
  local byId, view, taken = {}, {}, {}
  for _, row in ipairs(rows) do
    if row.id and not owner[row.id] then byId[row.id] = row end
  end
  for _, id in ipairs(Rows.ORDER) do
    local row = made[id] or byId[id]
    if row then
      view[#view + 1] = row
      taken[id] = true
    end
  end
  for _, row in ipairs(rows) do
    local id = row.id
    if not (id and (owner[id] or taken[id])) then view[#view + 1] = row end
  end
  return view
end

return Rows
