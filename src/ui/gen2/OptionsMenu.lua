-- Gold's OPTION screen (engine/menus/options_menu.asm _Option).
--
-- Layout is transcribed from the ASM: one full-screen textbox, StringOptions
-- placed at (2,2) as label / "        :" pairs, each option's value printed at
-- (11, labelRow + 1) -- except FRAME, whose number goes at (16,15) after the
-- literal "TYPE".  The cursor is a ▶ in column 1 at row 2 + index * 2.
--
-- Up/down move between rows, left/right change the value under the cursor, and
-- START or B leaves.  BACK is a row like any other that simply exits.
--
-- Values are stored on the save's options table by name (see
-- src/core/gen2/Save.lua DEFAULT_OPTIONS) rather than as the packed wOptions
-- byte, so a save stays readable and reordering an enum cannot silently
-- repoint a setting.
--
-- The row list a screen opens with runs through the ui.options.rows hook, the
-- same name and the same (game, rows) payload the Gen 1 screen uses
-- (src/ui/OptionsMenu.lua), so one mod source can add or drop a row on both
-- generations.

local Chrome = require("src.ui.gen2.Chrome")
local Logger = require("src.core.Logger")
local Marquee = require("src.ui.Marquee")
local Palette = require("src.render.Palette")
local Performance = require("src.core.Performance")
local Runtime = require("src.mods.Runtime")
local Save = require("src.core.gen2.Save")
local Strings = require("src.core.Strings")

local OptionsMenu = {}
OptionsMenu.__index = OptionsMenu
OptionsMenu.isOpaque = true

-- Music.setFilterLevel's ladder.
local FILTERS = {
  Strings.source("OFF"), Strings.source("1X"), Strings.source("2X"),
  Strings.source("3X"),
}

-- Values returned by shared helper modules are dynamic at this callsite, so
-- declare their finite labels explicitly for tools/modkit.py's catalog
-- harvester.  Player palette names and shader filenames are deliberately not
-- in this list: those are user content and stay verbatim.
local FINITE_VALUE_SOURCES = {
  Strings.source("AUTO"), Strings.source("HIGH"),
  Strings.source("BALANCED"), Strings.source("LOW"),
  Strings.source("NORMAL"), Strings.source("FIT"),
  Strings.source("OUT%d"), Strings.source("IN%d"),
  Strings.source("WATER"), Strings.source("TREES"), Strings.source("FADE "),
  Strings.source("GEN 2"), Strings.source("DMG"), Strings.source("CLASSIC"),
  Strings.source("GREEN"), Strings.source("LIME"), Strings.source("OLIVE"),
  Strings.source("AMBER"), Strings.source("ORANGE"), Strings.source("RED"),
  Strings.source("ROSE"), Strings.source("MAGENTA"),
  Strings.source("PURPLE"), Strings.source("INDIGO"), Strings.source("BLUE"),
  Strings.source("CYAN"), Strings.source("TEAL"), Strings.source("MINT"),
  Strings.source("SAND"), Strings.source("BROWN"), Strings.source("SILVER"),
  Strings.source("MONO"),
  Strings.source("PALETTE"), Strings.source("FULL"),
  Strings.source("WINDOWED"), Strings.source("CENTER"),
  Strings.source("UPPER"), Strings.source("TOP"), Strings.source("SKIN"),
  Strings.source("LIGHT"), Strings.source("STRONG"),
  Strings.source("ADAPTIVE"), Strings.source("UNAVAILABLE"),
  Strings.source("DISPLAY"), Strings.source("DISPLAY (%dHZ)"),
}

local function volLabel(v)
  v = v or 7
  return v == 0 and Strings("OFF") or tostring(v)
end

local function stepVolume(v, delta)
  return math.max(0, math.min(7, (v or 7) + delta))
end

local function dropClassic(options)
  local GbcPalette = require("src.render.GbcPalette")
  if GbcPalette.mode ~= "classic" then return end
  local target = (options.palette and options.palette ~= "")
    and GbcPalette.CUSTOM_MODE or "gbc"
  options.color = target
  GbcPalette.setMode(target)
end

local function colorPickerOpts(game)
  local GbcPalette = require("src.render.GbcPalette")
  local options = game.options
  dropClassic(options)
  local labels = GbcPalette.MODE_LABELS or {}
  local modes = {}
  for i, id in ipairs(GbcPalette.MODES) do
    modes[i] = { labels[id] or id:upper(), id }
  end
  return {
    palette = Palette,
    get = function() return options.palette or "" end,
    set = function(v)
      options.palette = v
      local target = (v ~= "") and GbcPalette.CUSTOM_MODE or "gbc"
      options.color = target
      GbcPalette.setMode(target)
      GbcPalette.setCustomRamp(v ~= "" and Palette.ramp(v) or nil)
      if game.persistOptions then pcall(game.persistOptions, game) end
    end,
    modes = modes,
    getMode = function() return options.color or "gbc" end,
    setMode = function(v)
      options.color = v
      GbcPalette.setMode(v)
      if game.persistOptions then pcall(game.persistOptions, game) end
    end,
  }
end

-- Each row: the label, the option key it edits, and the cycle of values with
-- the exact strings the cart prints (trailing spaces included -- they are what
-- blank the longer previous value, e.g. "MID " over "SLOW").
-- Labels and cart-original display strings are wrapped in Strings.source so
-- the catalog generator harvests them even though this table is built once
-- at require time, before any mod's Strings.load has a catalog to answer
-- from (src/core/Strings.lua's own note on this).  The lookup itself happens
-- live, in drawPanel, through plain Strings(...) calls.
local ROWS = {
  {
    label = Strings.source("TEXT SPEED"), key = "textSpeed",
    values = { "FAST", "MID", "SLOW" },
    display = {
      FAST = Strings.source("FAST"), MID = Strings.source("MID "),
      SLOW = Strings.source("SLOW"),
    },
  },
  {
    label = Strings.source("BATTLE SCENE"), key = "battleScene",
    values = { true, false },
    display = {
      [true] = Strings.source("ON "), [false] = Strings.source("OFF"),
    },
  },
  {
    label = Strings.source("BATTLE STYLE"), key = "battleStyle",
    values = { "SHIFT", "SET" },
    display = {
      SHIFT = Strings.source("SHIFT"), SET = Strings.source("SET  "),
    },
  },
  {
    label = Strings.source("SOUND"), key = "sound",
    values = { "MONO", "STEREO" },
    display = {
      MONO = Strings.source("MONO  "), STEREO = Strings.source("STEREO"),
    },
  },
  {
    label = Strings.source("PRINT"), key = "print",
    values = { "LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST" },
    display = {
      LIGHTEST = Strings.source("LIGHTEST"), LIGHTER = Strings.source("LIGHTER "),
      NORMAL = Strings.source("NORMAL  "), DARKER = Strings.source("DARKER  "),
      DARKEST = Strings.source("DARKEST "),
    },
  },
  {
    label = Strings.source("MENU ACCOUNT"), key = "menuAccount",
    values = { false, true },
    display = {
      [false] = Strings.source("OFF"), [true] = Strings.source("ON "),
    },
  },
  -- FRAME is the textbox border style, 1-8, and prints its number after the
  -- word TYPE rather than in the shared value column.
  { label = Strings.source("FRAME"), key = "frame", frame = true },
  -- Everything from here down is the port's, not the cart's.  They are the
  -- same settings the Gen 1 OPTION screen carries and they drive the same
  -- shared modules, so a player who learns them in Red knows them here.  The
  -- cart's screen has no room for them, which is why this one scrolls.
  --
  -- The two volume rows clamp at the ends rather than wrapping, the way
  -- pokered's text-speed cursor does, so holding left reaches OFF and stays.
  { id = "controls", label = Strings.source("CONTROLS"), port = true,
    activate = function(game)
      require("src.ui.Screens").push(game, "BindingsMenu")
    end },
  { label = Strings.source("MUSIC VOL"), key = "musicVol", port = true,
    cycle = function(options, delta)
      options.musicVol = stepVolume(options.musicVol, delta)
      require("src.core.Music").setVolumeLevel(options.musicVol)
    end,
    text = function(options) return volLabel(options.musicVol) end },
  { label = Strings.source("SFX VOL"), key = "sfxVol", port = true,
    cycle = function(options, delta)
      options.sfxVol = stepVolume(options.sfxVol, delta)
      require("src.core.Sound").setVolumeLevel(options.sfxVol)
    end,
    text = function(options) return volLabel(options.sfxVol) end },
  -- Each filter step keeps 40% of the previous step's treble, so 2X and 3X
  -- are the 1X low-pass applied twice and three times over.
  { label = Strings.source("MUSIC FILTER"), key = "musicFilter", port = true,
    cycle = function(options, delta)
      options.musicFilter = ((options.musicFilter or 0) + delta) % #FILTERS
      require("src.core.Music").setFilterLevel(options.musicFilter)
    end,
    text = function(options)
      return Strings(FILTERS[(options.musicFilter or 0) + 1])
    end },
  -- Heads the port's display group, same spot src/ui/OptionsMenu.lua's own
  -- PERFORMANCE row occupies relative to ZOOM/VOID FILL/TILT/SHADER FX below
  -- (the extras this tier scales).  Gen 1 row shape (`value`/`step`, not this
  -- file's own `text`/`cycle`) works here unmodified: OptionsMenu:cycle
  -- answers `row.step` first, and drawPanel already reads a function
  -- `row.value` -- both written for exactly this kind of shared mod row.
  { id = "performance", label = Strings.source("PERFORMANCE"), port = true,
    value = function(g)
      return Strings(Performance.label(g.options and g.options.performance))
    end,
    step = function(g, dir)
      local o = g.options
      o.performance = Performance.cycle(o.performance, dir)
      g:applyOptions()
      return true
    end },
  { label = Strings.source("GAME SPEED"), key = "speed", port = true,
    cycle = function(options, delta)
      local GameSpeed = require("src.core.GameSpeed")
      options.speed = GameSpeed.cycle(options.speed, delta)
    end,
    text = function(options)
      local speed = tonumber(options.speed) or 1
      if speed == 1 then return Strings("NORMAL") end
      return Strings("%dX", speed)
    end },
  { label = Strings.source("ZOOM"), key = "zoom", port = true,
    cycle = function(options, delta, game)
      local Zoom = require("src.render.Zoom")
      local scale = Zoom.windowFitScale()
      if game and game.world and game.world.fitScale then
        scale = game.world:fitScale()
      end
      Zoom.nudgeOptions(options, delta, scale)
    end,
    text = function(options)
      local offset = math.floor(tonumber(options.zoom) or 0)
      if offset == 0 then return Strings("FIT") end
      return offset < 0 and Strings("OUT%d", -offset)
        or Strings("IN%d", offset)
    end },
  -- VOID FILL: FADE is each map's own border block with the dissolve across
  -- a boundary; WATER / TREES force one outdoor block; BLACK is a flat void.
  -- #1418.  Same key the Gen 1 OPTION screen uses, different ladder (FADE
  -- is Gold's default because that is already what the maps call for).
  { label = Strings.source("VOID FILL"), key = "voidFill", port = true,
    cycle = function(options, delta)
      local BorderFill = require("src.world.gen2.BorderFill")
      BorderFill.setVoidFill(options.voidFill or "fade")
      options.voidFill = BorderFill.cycle(delta)
    end,
    text = function(options)
      return Strings(require("src.world.gen2.BorderFill").voidFillLabel(options.voidFill))
    end },
  { label = Strings.source("TILT"), key = "tilt", port = true,
    cycle = function(options, delta)
      local Tilt = require("src.render.Tilt")
      -- Four levels (OFF, 15, 35, 50); left steps back through them.
      local level = ((options.tilt or 0) + delta) % 4
      options.tilt = level
      Tilt.setLevel(level)
    end,
    text = function(options)
      return Strings(require("src.render.Tilt").levelLabel(options.tilt or 0))
    end },
  { label = Strings.source("COLOR"), key = "color", port = true,
    text = function(options)
      local palette = options.palette
      local name = Palette.label(palette)
      if name then
        -- m: is the engine's finite monochrome ladder; p: is a named user
        -- palette pack and its filename is user content.
        return type(palette) == "string" and palette:sub(1, 2) == "m:"
          and Strings(name) or name
      end
      return Strings(require("src.render.GbcPalette").modeLabel(options.color or "gbc"))
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "PaletteScreen", colorPickerOpts(game))
    end },
  -- SHADER FX reaches Gen 2 too, not just Gen 1. Same "activate" shape as
  -- CONTROLS/TOUCH LAYOUT below (a pushed screen, not a `cycle` ladder) --
  -- ShaderFXScreen is the shared list screen both generations push, `id`
  -- matching the Gen 1 row's so a mod filtering "shaderfx" on Red also
  -- reaches Gold.
  { id = "uiLetterbox", label = Strings.source("UI LETTERBOX"), port = true,
    cycle = function(options, delta)
      local Letterbox = require("src.render.Letterbox")
      options.uiLetterbox = Letterbox.cycle(options.uiLetterbox, delta)
      Letterbox.setMode(options.uiLetterbox)
    end,
    text = function(options)
      local Letterbox = require("src.render.Letterbox")
      return Strings(Letterbox.label(options.uiLetterbox))
    end },
  { id = "shaderfx", label = Strings.source("SHADER FX"), port = true,
    text = function(options)
      local ShaderFX = require("src.render.ShaderFX")
      local entry = ShaderFX.activeEntry("main")
      if not entry then return Strings("OFF") end
      return (entry.name:gsub("%.slangp$", "")):upper()
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "ShaderFXScreen", "main")
    end },
  -- Dual-shader secondary slot, same shared ShaderFXScreen as the row
  -- above, opened on "secondary" instead -- see src/ui/OptionsMenu.lua's
  -- mirror of this row for the full rationale.
  { id = "shaderfx2", label = Strings.source("SHADER FX 2"), port = true,
    text = function(options)
      local ShaderFX = require("src.render.ShaderFX")
      local entry = ShaderFX.activeEntry("secondary")
      if not entry then return Strings("OFF") end
      return (entry.name:gsub("%.slangp$", "")):upper()
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "ShaderFXScreen", "secondary")
    end },
  { label = Strings.source("VIDEO MODE"), key = "videoMode", port = true,
    cycle = function(options, delta)
      local VideoMode = require("src.core.VideoMode")
      options.videoMode = VideoMode.cycle(options.videoMode, delta)
      VideoMode.apply(options.videoMode)
    end,
    text = function(options)
      local VideoMode = require("src.core.VideoMode")
      return VideoMode.normalize(options.videoMode) == "borderless"
        and Strings("FULL") or Strings("WINDOWED")
    end },
  { label = Strings.source("SCREEN POS"), key = "screenPos", port = true,
    cycle = function(options, delta)
      local ScreenPosition = require("src.core.ScreenPosition")
      options.screenPos = ScreenPosition.cycle(options.screenPos, delta)
      ScreenPosition.setMode(options.screenPos)
    end,
    text = function(options)
      return Strings(require("src.core.ScreenPosition").label(options.screenPos))
    end },
  { id = "touchControls", label = Strings.source("TOUCH PAD"), port = true,
    text = function(options)
      local tc = options.touchControls
      local on = not (type(tc) == "table" and tc.enabled == false)
      return on and Strings("ON") or Strings("OFF")
    end,
    cycle = function(options, _delta, game)
      local tc = type(options.touchControls) == "table" and options.touchControls or {}
      tc.enabled = tc.enabled == false
      options.touchControls = tc
      require("src.core.TouchControls"):applyOptions(options)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { id = "touchLayout", label = Strings.source("TOUCH LAYOUT"), port = true,
    activate = function(game)
      game.stack:push(require("src.ui.TouchControlsEditor").new(game))
    end },
  { id = "haptics", label = Strings.source("VIBRATION"), port = true,
    text = function(options)
      return Strings(require("src.core.TouchControls").hapticLabel(options.haptics))
    end,
    cycle = function(options, delta, game)
      local TC = require("src.core.TouchControls")
      options.haptics = TC.cycleHaptics(options.haptics, delta)
      TC:applyOptions(options)
      TC.buzz(options.haptics)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { id = "hotbar", label = Strings.source("KEY BAR"), port = true,
    text = function(options)
      return options.hotbar == false and Strings("OFF") or Strings("ON")
    end,
    cycle = function(options, _delta, game)
      options.hotbar = options.hotbar == false
      require("src.core.TouchControls"):applyOptions(options)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { label = Strings.source("MAX FPS"), key = "fpsCap", port = true,
    cycle = function(options, delta)
      local FrameCap = require("src.core.FrameCap")
      options.fpsCap = FrameCap.cycle(options.fpsCap, delta)
      FrameCap.apply(options.fpsCap)
    end,
    text = function(options)
      local FrameCap = require("src.core.FrameCap")
      local value = FrameCap.normalize(options.fpsCap)
      if value == FrameCap.DISPLAY then
        local label = FrameCap.label(value)
        local hz = tonumber(label:match("^DISPLAY %((%d+)HZ%)$"))
        return hz and Strings("DISPLAY (%dHZ)", hz) or Strings("DISPLAY")
      end
      return FrameCap.label(value)
    end },
  { label = Strings.source("VSYNC"), key = "vsync", port = true,
    cycle = function(options, delta)
      local ok, PS = pcall(require, "src.core.PresentSync")
      if ok and PS.vsyncStepAllowed
         and not PS.vsyncStepAllowed(options.vsync, delta) then
        return
      end
      local VSync = require("src.core.VSync")
      options.vsync = VSync.cycle(options.vsync, delta)
      VSync.apply(options.vsync)
    end,
    text = function(options)
      local ok, PS = pcall(require, "src.core.PresentSync")
      if ok and PS.vsyncEnableBlocked and PS.vsyncEnableBlocked() then
        return Strings("UNAVAILABLE")
      end
      return Strings(require("src.core.VSync").label(options.vsync))
    end },
  { label = Strings.source("LOGIC CLOCK"), key = "logicClock", port = true,
    cycle = function(options, delta)
      local LogicClock = require("src.core.LogicClock")
      options.logicClock = LogicClock.cycle(options.logicClock, delta)
      LogicClock.apply(options.logicClock)
    end,
    text = function(options)
      return Strings(require("src.core.LogicClock").label(options.logicClock))
    end },
  { label = Strings.source("BATTLE LAYOUT"), key = "battleLayout", port = true,
    values = { "og", "wide" },
    display = {
      og = Strings.source("OG  "), wide = Strings.source("WIDE"),
    } },
  { label = Strings.source("BATTLE SIZE"), key = "battleFit", port = true,
    values = { "fixed", "fill" },
    display = {
      fixed = Strings.source("FIXED"), fill = Strings.source("FILL "),
    } },
  -- BATTLE BG (#1709): the void around the battle screen.
  { label = Strings.source("BATTLE BG"), key = "battleBg", port = true,
    values = { "white", "black", "world" },
    display = {
      white = Strings.source("WHITE"), black = Strings.source("BLACK"),
      world = Strings.source("WORLD"),
    } },
  { label = Strings.source("BACK"), cancel = true },
}

-- The cart's screen is one full-height textbox with every row on it.  This one
-- carries four more, so it shows a window of rows and scrolls: labels start at
-- (2,2) and step two rows, exactly as _Option lays them, and the window moves
-- only when the cursor would leave it.
local VISIBLE_ROWS = 7

-- The same grouping the Gen 1 screen uses (src/ui/OptionsMenu.lua GROUPS),
-- with Gold's own rows in it: FRAME is a graphics setting here and SOUND is
-- an audio one.  Runs after the ui.options.rows hook and only builds
-- self.view, so self.rows stays the flat list a mod reads and edits.
local GROUPS = {
  { id = "group.speed", label = Strings.source("SPEED"),
    members = { "textSpeed", "speed" } },
  { id = "group.video", label = Strings.source("VIDEO"),
    members = { "videoMode", "screenPos", "fpsCap", "vsync", "logicClock" } },
  { id = "group.graphics", label = Strings.source("GRAPHICS"),
    members = { "color", "uiLetterbox", "shaderfx", "shaderfx2", "frame" } },
  { id = "group.audio", label = Strings.source("AUDIO"),
    members = { "sound", "musicVol", "sfxVol", "musicFilter" } },
  { id = "group.battle", label = Strings.source("BATTLE OPTIONS"),
    members = { "battleScene", "battleStyle", "battleLayout", "battleFit",
      "battleBg" } },
  { id = "group.extras", label = Strings.source("EXTRAS"),
    members = { "zoom", "voidFill", "tilt" } },
}

local ORDER = {
  "group.speed", "group.video", "group.graphics", "group.audio",
  "performance", "group.battle", "group.extras",
}

-- A group's page is this same screen driving the rows it was handed, with
-- its own BACK on the bottom.
local function groupView(rows, open)
  local owner, picked = {}, {}
  for _, group in ipairs(GROUPS) do
    for _, id in ipairs(group.members) do owner[id] = group end
    picked[group.id] = {}
  end
  for _, row in ipairs(rows) do
    if row.id and owner[row.id] then
      local into = picked[owner[row.id].id]
      into[#into + 1] = row
    end
  end
  local made, byId = {}, {}
  for _, group in ipairs(GROUPS) do
    local members = picked[group.id]
    if #members > 0 then
      -- No value line: the value column is eight characters wide here, and a
      -- group has no setting of its own to show in it anyway.
      made[group.id] = { id = group.id, label = group.label, group = true,
                         activate = function(game) open(game, members) end }
    end
  end
  for _, row in ipairs(rows) do
    if row.id and not owner[row.id] then byId[row.id] = row end
  end
  local view, taken = {}, {}
  for _, id in ipairs(ORDER) do
    local row = made[id] or byId[id]
    if row then view[#view + 1] = row; taken[id] = true end
  end
  for _, row in ipairs(rows) do
    local id = row.id
    if not (id and (owner[id] or taken[id])) then view[#view + 1] = row end
  end
  return view
end

-- ui.options.rows identity: an unhooked build hands its own rows back.
local function sameRows(_, rows) return rows end

-- The descriptors one opening of the screen works from.  They are shallow
-- copies of ROWS, so a mod that edits a row inside the hook cannot leak that
-- edit into the next opening -- the Gen 1 site rebuilds its descriptors for the
-- same reason (src/ui/OptionsMenu.lua buildRows).
--
-- `id` is the key a Gen 1 mod filters a row on ("shaderfx", "speed", "musicVol")
-- and is added ALONGSIDE this file's own `key`, never in place of it: a mod
-- written against Red's OPTION screen finds the shared rows where it expects
-- them, and the rows Gold has that Red does not (PRINT, MENU ACCOUNT, FRAME,
-- COLOR) simply appear in the list the hook receives.
local function buildRows()
  local rows = {}
  local env = os.getenv("POKEPORT_TOUCH")
  local osName = love.system and love.system.getOS and love.system.getOS()
  local showTouch = env == "1"
    or (env ~= "0" and (osName == "Android" or osName == "iOS"))
  local isNX = require("src.core.Platform").isNX()
  for i, row in ipairs(ROWS) do
    -- PRINT is wGBPrinterBrightness, how dark the Game Boy Printer prints
    -- (GBPRINTER_LIGHTEST..DARKEST, constants/ram_constants.asm:67-70).
    -- There is no printer here (src/script/gen2/Specials.lua answers the
    -- print specials with "no Game Boy Printer"), so nothing reads the
    -- value and the row is hidden rather than offering a dead setting.
    -- The descriptor and the save key stay, so a build that grows a printer
    -- only has to drop this test.
    local hidden = row.key == "print"
      or (isNX and row.key == "videoMode")
      or (not showTouch and (row.id == "touchControls"
          or row.id == "touchLayout" or row.id == "haptics"
          or row.id == "hotbar"))
    if not hidden then
      local copy = {}
      for key, value in pairs(row) do copy[key] = value end
      copy.id = copy.id or copy.key or (copy.cancel and "cancel") or nil
      rows[#rows + 1] = copy
    end
  end
  return rows
end

function OptionsMenu:wantsFillScale() return true end
function OptionsMenu:drawsWidescreen() return true end

-- opts: options (the table to edit in place), onDone(options)
-- The page edits the SAME options table the parent screen does, so a value
-- changed on it lands where the caller's onDone will read it.
local function pushGroup(parent, members)
  local page = setmetatable({}, OptionsMenu)
  page.game = parent.game
  page.rows = members
  page.options = parent.options
  page.index, page.scroll, page.sub = 1, 0, true
  page.view = {}
  for i, row in ipairs(members) do page.view[i] = row end
  page.view[#page.view + 1] = { label = Strings.source("BACK"), cancel = true,
                                id = "cancel" }
  parent.game.stack:push(page)
  return page
end

function OptionsMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, OptionsMenu)
  self.game = game
  -- Unguarded, like the Gen 1 site: the screen is built once per opening.  A
  -- hook that answers with anything but a table is degraded to the vanilla
  -- rows rather than leaving the player with an empty OPTION screen.
  local rows = buildRows()
  local hooked = Runtime.call("ui.options.rows", sameRows, game, rows)
  if type(hooked) == "table" then
    rows = hooked
  else
    Logger.error("ui.options.rows returned %s; keeping the vanilla rows",
                 type(hooked))
  end
  self.rows = rows
  self.options = opts.options or Save.defaultOptions()
  -- Fill in anything missing so a row can never read nil and lose the
  -- player's other settings when it writes back.
  for key, value in pairs(Save.DEFAULT_OPTIONS) do
    if self.options[key] == nil then self.options[key] = value end
  end
  self.onDone = opts.onDone
  self.index = 1
  self.scroll = 0
  self.view = groupView(rows, function(_, members)
    return pushGroup(self, members)
  end)
  return self
end

function OptionsMenu:visible()
  return self.view or self.rows
end

function OptionsMenu:ensureVisible()
  local rows = self:visible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0,
    math.min(self.scroll, math.max(0, #rows - VISIBLE_ROWS)))
end

function OptionsMenu:row()
  return self:visible()[self.index]
end

-- Cursor onto a row by id, opening its group page first if it lives in one.
-- Returns the screen the row ended up on, so a caller can keep driving it.
function OptionsMenu:focusRow(id)
  local rows = self:visible()
  for i, row in ipairs(rows) do
    if row.id == id then
      self.index = i
      self:ensureVisible()
      return self
    end
  end
  for i, row in ipairs(rows) do
    if row.group and row.activate then
      local group
      for _, g in ipairs(GROUPS) do if g.id == row.id then group = g end end
      for _, member in ipairs(group and group.members or {}) do
        if member == id then
          self.index = i
          row.activate(self.game)
          local page = self.game.stack:top()
          return page.focusRow and page:focusRow(id) or page
        end
      end
    end
  end
  return nil
end

function OptionsMenu:cycle(row, delta)
  -- The Gen 1 row vocabulary (src/ui/OptionRows.lua:3-7), answered first so a
  -- mod's row written against Red's OPTION screen steps here too.  `step` takes
  -- the game, not the options table, because that is the handle it is given on
  -- the other generation.
  if row.step then
    row.step(self.game, delta)
    return
  end
  -- A port row owns its own ladder (and its own live module), so it steps
  -- itself rather than walking a `values` list.
  if row.cycle then
    row.cycle(self.options, delta, self.game)
    return
  end
  if row.frame then
    -- Eight frames, wrapping (UpdateFrame masks to 3 bits).
    local frame = ((self.options.frame or 1) - 1 + delta) % 8 + 1
    self.options.frame = frame
    -- options_menu.asm:475 UpdateFrame reloads the tiles as the value changes,
    -- so this screen's own border restyles under the cursor.
    require("src.render.Font").setFrame(frame)
    return
  end
  if not row.values then return end
  local current = self.options[row.key]
  local at = 1
  for i, value in ipairs(row.values) do
    if value == current then at = i break end
  end
  local next_ = at + delta
  -- Left at the first entry wraps to the last and vice versa, matching
  -- Options_TextSpeed's .LeftPressed / .Increase clamps.
  if next_ < 1 then next_ = #row.values end
  if next_ > #row.values then next_ = 1 end
  self.options[row.key] = row.values[next_]
  -- MUSIC VOL applies itself as it steps; SOUND has to as well, or the
  -- pan sits on the current song until the next map change (#1471)
  if row.key == "sound" then
    require("src.core.Music").applyOptions(self.options)
  end
end

function OptionsMenu:leave_()
  if self.onDone then self.onDone(self.options) end
  if self.game and self.game.stack and self.game.stack:top() == self then
    self.game.stack:pop()
  end
end

function OptionsMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("start") or input:wasPressed("b") then
    self:leave_()
    return
  end
  local rows = self:visible()
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #rows
    self:ensureVisible()
    return
  elseif input:wasPressed("down") then
    self.index = self.index < #rows and self.index + 1 or 1
    self:ensureVisible()
    return
  end
  local row = self:row()
  if not row then return end
  if input:wasPressed("a") then
    if row.cancel then
      self:leave_()
    elseif row.activate then
      -- the A-press action for a row that opens something instead of cycling
      -- a value (src/ui/OptionsMenu.lua:556)
      row.activate(self.game)
    else
      -- A on a value row advances it, which is what the ASM's shared
      -- right-press path does when A is held on a non-CANCEL row.
      self:cycle(row, 1)
    end
    return
  end
  if input:wasPressed("left") then
    self:cycle(row, -1)
  elseif input:wasPressed("right") then
    self:cycle(row, 1)
  end
end

function OptionsMenu:drawPanel()
  Chrome.clear()
  -- hlcoord 0,0 with b = SCREEN_HEIGHT - 2, c = SCREEN_WIDTH - 2.
  Chrome.textbox(0, 0, Chrome.SCREEN_W - 2, Chrome.SCREEN_H - 2)
  -- The textbox spends column 19 on its frame, so a line drawn past column
  -- 18 prints over the border: 17 characters from the label's column 2,
  -- 8 from the value's column 11.  Anything longer scrolls under the cursor.
  local rows = self:visible()
  for slot = 1, math.min(VISIBLE_ROWS, #rows) do
    local i = slot + self.scroll
    local row = rows[i]
    if row then
      local labelY = 2 + (slot - 1) * 2
      local hot = i == self.index
      local key = tostring(row.id or row.label)
      local function fit(text, col)
        local room = 19 - col
        if hot then return Marquee.scroll(text, room, key) end
        return Marquee.clip(text, room)
      end
      Chrome.print(fit(Strings(row.label), 2), 2, labelY)
      if row.frame then
        Chrome.print(Strings(":TYPE"), 10, labelY + 1)
        Chrome.print(tostring(self.options.frame or 1), 16, labelY + 1)
      elseif row.text then
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(fit(row.text(self.options), 11), 11, labelY + 1)
      elseif row.values then
        Chrome.print(":", 10, labelY + 1)
        local value = self.options[row.key]
        local text = row.display and Strings(row.display[value]) or tostring(value)
        Chrome.print(fit(text, 11), 11, labelY + 1)
      elseif type(row.value) == "function" then
        -- the Gen 1 row's value reader (src/ui/OptionRows.lua:4), so a mod row
        -- shows its setting here instead of drawing a bare label
        local ok, text = pcall(row.value, self.game)
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(fit(ok and tostring(text) or "?", 11), 11, labelY + 1)
      end
    end
  end
  Chrome.cursor(1, 2 + (self.index - self.scroll - 1) * 2)
  -- The ▼ hint every scrolling Gen 2 list shows when there is more below.
  if self.scroll + VISIBLE_ROWS < #rows then
    local Font = require("src.render.Font")
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(Chrome.DOWN_ARROW, 1 * 8, (2 + VISIBLE_ROWS * 2 - 1) * 8)
  end
end

function OptionsMenu:draw()
  self:drawPanel()
end

function OptionsMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

OptionsMenu.ROWS = ROWS

return OptionsMenu
