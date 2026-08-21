-- Gold's OPTION screen (engine/menus/options_menu.asm _Option).
--
-- Layout is transcribed from the ASM: one full-screen textbox, StringOptions
-- placed at (2,2) as label / "        :" pairs, each option's value printed at
-- (11, labelRow + 1) -- except FRAME, whose number goes at (16,15) after the
-- literal "TYPE".  The cursor is a ▶ in column 1 at row 2 + index * 2.
--
-- Up/down move between rows, left/right change the value under the cursor, and
-- START or B leaves.  CANCEL is a row like any other that simply exits.
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
local Runtime = require("src.mods.Runtime")
local Save = require("src.core.gen2.Save")

local OptionsMenu = {}
OptionsMenu.__index = OptionsMenu
OptionsMenu.isOpaque = true

-- Music.setFilterLevel's ladder.
local FILTERS = { "OFF", "1X", "2X", "3X" }

local function volLabel(v)
  v = v or 7
  return v == 0 and "OFF" or tostring(v)
end

local function stepVolume(v, delta)
  return math.max(0, math.min(7, (v or 7) + delta))
end

-- Each row: the label, the option key it edits, and the cycle of values with
-- the exact strings the cart prints (trailing spaces included -- they are what
-- blank the longer previous value, e.g. "MID " over "SLOW").
local ROWS = {
  {
    label = "TEXT SPEED", key = "textSpeed",
    values = { "FAST", "MID", "SLOW" },
    display = { FAST = "FAST", MID = "MID ", SLOW = "SLOW" },
  },
  {
    label = "BATTLE SCENE", key = "battleScene",
    values = { true, false },
    display = { [true] = "ON ", [false] = "OFF" },
  },
  {
    label = "BATTLE STYLE", key = "battleStyle",
    values = { "SHIFT", "SET" },
    display = { SHIFT = "SHIFT", SET = "SET  " },
  },
  {
    label = "SOUND", key = "sound",
    values = { "MONO", "STEREO" },
    display = { MONO = "MONO  ", STEREO = "STEREO" },
  },
  {
    label = "PRINT", key = "print",
    values = { "LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST" },
    display = {
      LIGHTEST = "LIGHTEST", LIGHTER = "LIGHTER ", NORMAL = "NORMAL  ",
      DARKER = "DARKER  ", DARKEST = "DARKEST ",
    },
  },
  {
    label = "MENU ACCOUNT", key = "menuAccount",
    values = { false, true },
    display = { [false] = "OFF", [true] = "ON " },
  },
  -- FRAME is the textbox border style, 1-8, and prints its number after the
  -- word TYPE rather than in the shared value column.
  { label = "FRAME", key = "frame", frame = true },
  -- Everything from here down is the port's, not the cart's.  They are the
  -- same settings the Gen 1 OPTION screen carries and they drive the same
  -- shared modules, so a player who learns them in Red knows them here.  The
  -- cart's screen has no room for them, which is why this one scrolls.
  --
  -- The two volume rows clamp at the ends rather than wrapping, the way
  -- pokered's text-speed cursor does, so holding left reaches OFF and stays.
  { id = "controls", label = "CONTROLS", port = true,
    activate = function(game)
      require("src.ui.Screens").push(game, "BindingsMenu")
    end },
  { label = "MUSIC VOL", key = "musicVol", port = true,
    cycle = function(options, delta)
      options.musicVol = stepVolume(options.musicVol, delta)
      require("src.core.Music").setVolumeLevel(options.musicVol)
    end,
    text = function(options) return volLabel(options.musicVol) end },
  { label = "SFX VOL", key = "sfxVol", port = true,
    cycle = function(options, delta)
      options.sfxVol = stepVolume(options.sfxVol, delta)
      require("src.core.Sound").setVolumeLevel(options.sfxVol)
    end,
    text = function(options) return volLabel(options.sfxVol) end },
  -- Each filter step keeps 40% of the previous step's treble, so 2X and 3X
  -- are the 1X low-pass applied twice and three times over.
  { label = "MUSIC FILTER", key = "musicFilter", port = true,
    cycle = function(options, delta)
      options.musicFilter = ((options.musicFilter or 0) + delta) % #FILTERS
      require("src.core.Music").setFilterLevel(options.musicFilter)
    end,
    text = function(options)
      return FILTERS[(options.musicFilter or 0) + 1]
    end },
  { label = "GAME SPEED", key = "speed", port = true,
    cycle = function(options, delta)
      local GameSpeed = require("src.core.GameSpeed")
      options.speed = GameSpeed.cycle(options.speed, delta)
    end,
    text = function(options)
      return require("src.core.GameSpeed").levelLabel(options.speed)
    end },
  { label = "ZOOM", key = "zoom", port = true,
    cycle = function(options, delta, game)
      local Zoom = require("src.render.Zoom")
      local scale = (game and game.world and game.world.fitScale
        and game.world:fitScale()) or 1
      local lo, hi = Zoom.offsetRange(scale)
      local offset = (options.zoom or 0) + delta
      if offset > hi then offset = lo elseif offset < lo then offset = hi end
      options.zoom = offset
      Zoom.offset = offset
    end,
    text = function(options)
      return require("src.render.Zoom").offsetLabel(options.zoom or 0)
    end },
  -- VOID FILL: FADE is each map's own border block with the dissolve across
  -- a boundary; WATER / TREES force one outdoor block; BLACK is a flat void.
  -- #1418.  Same key the Gen 1 OPTION screen uses, different ladder (FADE
  -- is Gold's default because that is already what the maps call for).
  { label = "VOID FILL", key = "voidFill", port = true,
    cycle = function(options, delta)
      local BorderFill = require("src.world.gen2.BorderFill")
      BorderFill.setVoidFill(options.voidFill or "fade")
      options.voidFill = BorderFill.cycle(delta)
    end,
    text = function(options)
      return require("src.world.gen2.BorderFill").voidFillLabel(options.voidFill)
    end },
  { label = "TILT", key = "tilt", port = true,
    cycle = function(options, delta)
      local Tilt = require("src.render.Tilt")
      -- Four levels (OFF, 15, 35, 50); left steps back through them.
      local level = ((options.tilt or 0) + delta) % 4
      options.tilt = level
      Tilt.setLevel(level)
    end,
    text = function(options)
      return require("src.render.Tilt").levelLabel(options.tilt or 0)
    end },
  -- COLOR is the Gen 2 answer to the Gen 1 screen's COLORS row.  Gold is a
  -- CGB game whose colour comes from its own palettes, so there are no packs
  -- to swap -- what there is instead is the choice to turn that colour OFF,
  -- down to the grey Game Boy or the green one.  GBC is the default.
  { label = "COLOR", key = "color", port = true,
    cycle = function(options, delta)
      local GbcPalette = require("src.render.GbcPalette")
      GbcPalette.setMode(options.color or "gbc")
      options.color = GbcPalette.cycle(delta)
    end,
    text = function(options)
      return require("src.render.GbcPalette").modeLabel(options.color or "gbc")
    end },
  { label = "GBC FX", key = "gbcfx", port = true,
    cycle = function(options, delta)
      local GBCFX = require("src.render.GBCFX")
      if not GBCFX.isSupported() then
        options.gbcfx = 0
        return
      end
      local level = ((options.gbcfx or 0) + delta) % 5
      options.gbcfx = level
      GBCFX.setLevel(level)
    end,
    text = function(options)
      return require("src.render.GBCFX").levelLabel(options.gbcfx or 0)
    end },
  { label = "VIDEO MODE", key = "videoMode", port = true,
    cycle = function(options, delta)
      local VideoMode = require("src.core.VideoMode")
      options.videoMode = VideoMode.cycle(options.videoMode, delta)
      VideoMode.apply(options.videoMode)
    end,
    text = function(options)
      local VideoMode = require("src.core.VideoMode")
      return VideoMode.normalize(options.videoMode) == "borderless"
        and "FULL" or "WINDOWED"
    end },
  { label = "SCREEN POS", key = "screenPos", port = true,
    cycle = function(options, delta)
      local ScreenPosition = require("src.core.ScreenPosition")
      options.screenPos = ScreenPosition.cycle(options.screenPos, delta)
      ScreenPosition.setMode(options.screenPos)
    end,
    text = function(options)
      return require("src.core.ScreenPosition").label(options.screenPos)
    end },
  { id = "touchControls", label = "TOUCH PAD", port = true,
    text = function(options)
      local tc = options.touchControls
      local on = not (type(tc) == "table" and tc.enabled == false)
      return on and "ON" or "OFF"
    end,
    cycle = function(options, _delta, game)
      local tc = type(options.touchControls) == "table" and options.touchControls or {}
      tc.enabled = tc.enabled == false
      options.touchControls = tc
      require("src.core.TouchControls"):applyOptions(options)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { id = "touchLayout", label = "TOUCH LAYOUT", port = true,
    activate = function(game)
      game.stack:push(require("src.ui.TouchControlsEditor").new(game))
    end },
  { id = "haptics", label = "VIBRATION", port = true,
    text = function(options)
      return require("src.core.TouchControls").hapticLabel(options.haptics)
    end,
    cycle = function(options, delta, game)
      local TC = require("src.core.TouchControls")
      options.haptics = TC.cycleHaptics(options.haptics, delta)
      TC:applyOptions(options)
      TC.buzz(options.haptics)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { label = "MAX FPS", key = "fpsCap", port = true,
    cycle = function(options, delta)
      local FrameCap = require("src.core.FrameCap")
      options.fpsCap = FrameCap.cycle(options.fpsCap, delta)
      FrameCap.apply(options.fpsCap)
    end,
    text = function(options)
      return require("src.core.FrameCap").label(options.fpsCap)
    end },
  { label = "CANCEL", cancel = true },
}

-- The cart's screen is one full-height textbox with every row on it.  This one
-- carries four more, so it shows a window of rows and scrolls: labels start at
-- (2,2) and step two rows, exactly as _Option lays them, and the window moves
-- only when the cursor would leave it.
local VISIBLE_ROWS = 7

-- ui.options.rows identity: an unhooked build hands its own rows back.
local function sameRows(_, rows) return rows end

-- The descriptors one opening of the screen works from.  They are shallow
-- copies of ROWS, so a mod that edits a row inside the hook cannot leak that
-- edit into the next opening -- the Gen 1 site rebuilds its descriptors for the
-- same reason (src/ui/OptionsMenu.lua buildRows).
--
-- `id` is the key a Gen 1 mod filters a row on ("gbcfx", "speed", "musicVol")
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
  for i, row in ipairs(ROWS) do
    if showTouch or (row.id ~= "touchControls" and row.id ~= "touchLayout"
        and row.id ~= "haptics") then
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
  return self
end

function OptionsMenu:ensureVisible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0,
    math.min(self.scroll, math.max(0, #self.rows - VISIBLE_ROWS)))
end

function OptionsMenu:row()
  return self.rows[self.index]
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
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.rows
    self:ensureVisible()
    return
  elseif input:wasPressed("down") then
    self.index = self.index < #self.rows and self.index + 1 or 1
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
  for slot = 1, math.min(VISIBLE_ROWS, #self.rows) do
    local i = slot + self.scroll
    local row = self.rows[i]
    if row then
      local labelY = 2 + (slot - 1) * 2
      Chrome.print(row.label, 2, labelY)
      if row.frame then
        Chrome.print(":TYPE", 10, labelY + 1)
        Chrome.print(tostring(self.options.frame or 1), 16, labelY + 1)
      elseif row.text then
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(row.text(self.options), 11, labelY + 1)
      elseif row.values then
        Chrome.print(":", 10, labelY + 1)
        local value = self.options[row.key]
        local text = row.display and row.display[value] or tostring(value)
        Chrome.print(text, 11, labelY + 1)
      elseif type(row.value) == "function" then
        -- the Gen 1 row's value reader (src/ui/OptionRows.lua:4), so a mod row
        -- shows its setting here instead of drawing a bare label
        local ok, text = pcall(row.value, self.game)
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(ok and tostring(text) or "?", 11, labelY + 1)
      end
    end
  end
  Chrome.cursor(1, 2 + (self.index - self.scroll - 1) * 2)
  -- The ▼ hint every scrolling Gen 2 list shows when there is more below.
  if self.scroll + VISIBLE_ROWS < #self.rows then
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
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

OptionsMenu.ROWS = ROWS

return OptionsMenu
