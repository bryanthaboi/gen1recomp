-- Options: text speed, battle animation on/off, battle style SHIFT/SET
-- (engine/menus/main_menu.asm DisplayOptionMenu), the battle ruleset
-- (cycles the merged rulesets registry; gen1_faithful keeps the original
-- quirks), plus the port's audio rows and display rows: music/SFX
-- volume (0-7), music low-pass filter (OFF/1X/2X/3X), COLORS / TILT /
-- GBC FX / ZOOM / VOID FILL / VIDEO MODE, and the MODS row that opens
-- the mod manager.
-- Rows are descriptors fed through the ui.options.rows hook, so mods can
-- add their own; CANCEL is appended after the hook and stays fixed on the
-- bottom line like pokered's.

local PaletteFX = require("src.render.PaletteFX")
local Pipelines = require("src.render.Pipelines")
local Tilt = require("src.render.Tilt")
local GBCFX = require("src.render.GBCFX")
local Zoom = require("src.render.Zoom")
local TileRenderer = require("src.render.TileRenderer")
local GameSpeed = require("src.core.GameSpeed")
local VideoMode = require("src.core.VideoMode")
local FrameCap = require("src.core.FrameCap")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local OptionRows = require("src.ui.OptionRows")
local Renderer = require("src.render.Renderer")
local Strings = require("src.core.Strings")

local OptionsMenu = {}
OptionsMenu.__index = OptionsMenu
OptionsMenu.isOpaque = true

-- Opaque full-screen menu: own MEWMON so opening OPTION from the title
-- (or over the overworld) does not inherit TitleState's LOGO1 band -- that
-- zone covers UI rows 8-9, which is the third options box label line
-- (pink "MODS" strip when Blue's ROM LOGO1 white is {255,239,255}).
function OptionsMenu:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

-- TextSpeedOptionData frame delays with the original labels
local SPEEDS = { { 1, "FAST" }, { 3, "MEDIUM" }, { 5, "SLOW" } }
-- no-loader fallback for the ruleset row, same pair BattleState keeps
local Rulesets = {
  gen1_faithful = require("src.battle.rulesets.gen1_faithful"),
  modern_clean = require("src.battle.rulesets.modern_clean"),
}
local FILTERS = { "OFF", "1X", "2X", "3X" }

local function speedIndex(game)
  -- default matches InitOptions' TEXT_DELAY_MEDIUM in wOptions
  local cur = game.save.options.textSpeed or 3
  for i, s in ipairs(SPEEDS) do
    if s[1] == cur then return i end
  end
  return 2 -- MEDIUM
end

-- the ruleset row cycles the sorted non-hidden ids of the merged
-- registry (07-battle-extensibility.md 4.6), so mod-registered
-- rulesets are selectable; hidden marks a total conversion's exclusions
local function rulesetIds(game)
  local rulesets = game.data and game.data.rulesets or Rulesets
  local ids = {}
  for id, record in pairs(rulesets) do
    if not record.hidden then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

local function rulesetIndex(game, ids)
  local constants = game.data and game.data.constants
  local cur = game.save.options.ruleset
              or (constants and constants.defaultRuleset) or "gen1_faithful"
  for i, id in ipairs(ids) do
    if id == cur then return i end
  end
  return 1
end

local function rulesetName(game)
  local rulesets = game.data and game.data.rulesets or Rulesets
  local ids = rulesetIds(game)
  local id = ids[rulesetIndex(game, ids)] or game.save.options.ruleset
  local record = id and rulesets[id]
  return Strings(record and record.name or id or "----")
end

-- 0-7 volume level display (0 = OFF)
local function volLabel(v)
  v = v or 7
  return v == 0 and "OFF" or tostring(v)
end

-- volume rows clamp at the ends, like pokered's text-speed cursor
-- (.pressedLeftInTextSpeed stays at FAST rather than wrapping)
local function stepVolume(v, dir)
  return math.max(0, math.min(7, (v or 7) + dir))
end

local function colorIndex(opts)
  local cur = opts.colors or "gbc"
  for i, m in ipairs(PaletteFX.MODES) do
    if m == cur then return i end
  end
  return 1
end

local function wrapIndex(i, n)
  i = i % n
  if i < 0 then i = i + n end
  return i
end

local function sameRows(_, rows) return rows end

-- the vanilla rows as descriptors; each step body is the old per-index
-- ladder's, so the save.options mutations are unchanged
local function buildRows(game)
  local rows = {
    { id = "textSpeed", label = Strings("TEXT SPEED"),
      value = function(g) return Strings(SPEEDS[speedIndex(g)][2]) end,
      step = function(g)
        local i = speedIndex(g) % #SPEEDS + 1
        g.save.options.textSpeed = SPEEDS[i][1]
        return true
      end },
    { id = "animations", label = Strings("BATTLE ANIMATION"),
      value = function(g)
        return g.save.options.animations == false and Strings("OFF") or Strings("ON")
      end,
      step = function(g)
        local o = g.save.options
        o.animations = o.animations == false and true or false
        return true
      end },
    { id = "battleStyle", label = Strings("BATTLE STYLE"),
      value = function(g)
        return g.save.options.battleStyle == "set" and Strings("SET") or Strings("SHIFT")
      end,
      step = function(g)
        local o = g.save.options
        o.battleStyle = o.battleStyle == "set" and "shift" or "set"
        return true
      end },
    -- OG is the classic 160x144 battle screen; WIDE is the 304x144
    -- widescreen composition (src/battle/WideBattle.lua)
    { id = "battleLayout", label = Strings("BATTLE LAYOUT"),
      value = function(g)
        return g.save.options.battleLayout == "wide" and Strings("WIDE") or Strings("OG")
      end,
      step = function(g)
        local o = g.save.options
        o.battleLayout = o.battleLayout == "wide" and "og" or "wide"
        return true
      end },
    { id = "ruleset", label = Strings("RULESET"),
      value = function(g) return rulesetName(g) end,
      step = function(g, dir)
        local ids = rulesetIds(g)
        if #ids == 0 then return false end
        local i = rulesetIndex(g, ids)
        g.save.options.ruleset = ids[wrapIndex(i - 1 + dir, #ids) + 1]
        return true
      end },
    { id = "musicVol", label = Strings("MUSIC VOL"),
      value = function(g) return volLabel(g.save.options.musicVol) end,
      step = function(g, dir)
        local o = g.save.options
        o.musicVol = stepVolume(o.musicVol, dir)
        require("src.core.Music").setVolumeLevel(o.musicVol)
        return true
      end },
    { id = "sfxVol", label = Strings("SFX VOL"),
      value = function(g) return volLabel(g.save.options.sfxVol) end,
      step = function(g, dir)
        local o = g.save.options
        o.sfxVol = stepVolume(o.sfxVol, dir)
        require("src.core.Sound").setVolumeLevel(o.sfxVol)
        return true
      end },
    { id = "musicFilter", label = Strings("MUSIC FILTER"),
      value = function(g)
        return FILTERS[(g.save.options.musicFilter or 0) + 1]
      end,
      step = function(g, dir)
        local o = g.save.options
        o.musicFilter = ((o.musicFilter or 0) + dir) % #FILTERS
        require("src.core.Music").setFilterLevel(o.musicFilter)
        return true
      end },
    { id = "colors", label = Strings("COLORS"),
      value = function(g)
        return PaletteFX.modeLabel(g.save.options.colors or "gbc")
      end,
      step = function(g, dir)
        local o = g.save.options
        local i = colorIndex(o)
        i = wrapIndex(i - 1 + dir, #PaletteFX.MODES) + 1
        o.colors = PaletteFX.MODES[i]
        PaletteFX.setMode(o.colors)
        return true
      end },
    { id = "tilt", label = Strings("TILT"),
      value = function(g) return Tilt.levelLabel(g.save.options.tilt or 0) end,
      step = function(g, dir)
        local o = g.save.options
        o.tilt = wrapIndex((o.tilt or 0) + dir, 4)
        Tilt.setLevel(o.tilt)
        -- tilt and a mod's world pipeline are two answers to the same
        -- question; turning this on switches that off (Pipelines does the
        -- same in the other direction)
        if o.tilt > 0 then
          for _, entry in ipairs(Pipelines.list()) do
            if entry.def.drawWorld then Pipelines.setLevel(entry.id, 0) end
          end
          Pipelines.syncOptions(o)
        end
        return true
      end },
    { id = "gbcfx", label = Strings("GBC FX"),
      value = function(g)
        return GBCFX.levelLabel(g.save.options.gbcfx or 0)
      end,
      step = function(g, dir)
        local o = g.save.options
        o.gbcfx = wrapIndex((o.gbcfx or 0) + dir, 5)
        GBCFX.setLevel(o.gbcfx)
        return true
      end },
    { id = "zoom", label = Strings("ZOOM"),
      value = function(g)
        return Zoom.offsetLabel(g.save.options.zoom or 0)
      end,
      step = function(g, dir)
        local o = g.save.options
        local S = Renderer:fitScale()
        local lo, hi = Zoom.offsetRange(S)
        local off = (o.zoom or 0) + dir
        if off > hi then off = lo
        elseif off < lo then off = hi end
        o.zoom = off
        Zoom.offset = off
        return true
      end },
    { id = "voidFill", label = Strings("VOID FILL"),
      value = function(g)
        return TileRenderer.voidFillLabel(g.save.options.voidFill)
      end,
      step = function(g, dir)
        local o = g.save.options
        local modes = TileRenderer.VOID_FILLS
        local cur = o.voidFill or "trees"
        local i = 1
        for idx, m in ipairs(modes) do
          if m == cur then i = idx; break end
        end
        o.voidFill = modes[wrapIndex(i - 1 + dir, #modes) + 1]
        TileRenderer.setVoidFill(o.voidFill)
        return true
      end },
    { id = "videoMode", label = Strings("VIDEO MODE"),
      value = function(g)
        return VideoMode.modeLabel(g.save.options.videoMode)
      end,
      step = function(g, dir)
        local o = g.save.options
        o.videoMode = VideoMode.cycle(o.videoMode, dir)
        VideoMode.apply(o.videoMode)
        return true
      end },
    -- hard render cap (issue #88): bounds the present rate so a
    -- driver-forced vsync-off run cannot spin at thousands of FPS.  Logic
    -- is fixed-step off dt, so this touches presentation only.
    { id = "fpsCap", label = Strings("MAX FPS"),
      value = function(g)
        return FrameCap.label(g.save.options.fpsCap)
      end,
      step = function(g, dir)
        local o = g.save.options
        o.fpsCap = FrameCap.cycle(o.fpsCap, dir)
        FrameCap.apply(o.fpsCap)
        return true
      end },
    -- fast-forward the logic clock only; music and sfx keep their tempo
    -- (src/core/GameSpeed.lua), so this is safe to leave on
    { id = "speed", label = Strings("GAME SPEED"),
      value = function(g)
        return GameSpeed.levelLabel(g.save.options.speed)
      end,
      step = function(g, dir)
        local o = g.save.options
        o.speed = GameSpeed.cycle(o.speed, dir)
        return true
      end },
    -- the manager's discoverable home (18-mod-manager-ux); inert until
    -- opened, so the row costs a vanilla install nothing
    { id = "mods", label = Strings("MODS"),
      value = function(g)
        local status = g.modStatus or {}
        return Strings("%d INSTALLED", #(status.available or {}))
      end,
      activate = function(g)
        require("src.ui.Screens").push(g, "ManagerState")
      end },
    -- rebinding UI (gap C2, 12-ui-extensibility 4.4); captured inputs
    -- live in options.bindings, so the row costs a vanilla install nothing
    { id = "controls", label = Strings("CONTROLS"),
      activate = function(g)
        require("src.ui.Screens").push(g, "BindingsMenu")
      end },
  }
  -- issue #136: hide GBC FX on Android/iOS -- the present shader soft-bricks
  if not GBCFX.isSupported() then
    local filtered = {}
    for _, row in ipairs(rows) do
      if row.id ~= "gbcfx" then filtered[#filtered + 1] = row end
    end
    rows = filtered
  end
  -- A mod's render pipelines are display modes like TILT, so their rows sit
  -- with it rather than at the end of the list where a mod's own
  -- ui.options.rows additions land.  Nothing registered means nothing
  -- spliced, so a vanilla install sees the list it always had.
  local pipelineRows = Pipelines.rows(game)
  if pipelineRows[1] then
    local merged = {}
    for _, row in ipairs(rows) do
      merged[#merged + 1] = row
      if row.id == "tilt" then
        for _, extra in ipairs(pipelineRows) do merged[#merged + 1] = extra end
      end
    end
    -- no TILT row to anchor to (a future build could drop it): append
    -- rather than silently lose the modes
    if #merged == #rows then
      for _, extra in ipairs(pipelineRows) do merged[#merged + 1] = extra end
    end
    rows = merged
  end
  return rows
end

function OptionsMenu.new(game, opts)
  opts = opts or {}
  local rows = buildRows(game)
  local hooked = Runtime.call("ui.options.rows", sameRows, game, rows)
  if type(hooked) == "table" then
    rows = hooked
  else
    Logger.error("ui.options.rows returned %s; keeping the vanilla rows",
                 type(hooked))
  end
  return setmetatable({ game = game, rows = rows, index = 1, scroll = 0,
                        onCancel = opts.onCancel }, OptionsMenu)
end

function OptionsMenu:update(dt)
  local input = self.game.input
  local rows = self.rows
  -- CANCEL sits below the hook-built rows so a mod cannot orphan the exit
  local cancelRow = #rows + 1
  local changed = false
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or cancelRow
  elseif input:wasPressed("down") then
    self.index = self.index < cancelRow and self.index + 1 or 1
  elseif input:wasPressed("left") or input:wasPressed("right")
      or input:wasPressed("a") then
    local dir = input:wasPressed("left") and -1 or 1
    local row = rows[self.index]
    if row and row.activate then
      if input:wasPressed("a") then row.activate(self.game) end
    elseif row and row.step then
      changed = row.step(self.game, dir) and true or false
    elseif input:wasPressed("a") then -- CANCEL
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
  if changed and self.game.writeOptions then
    self.game:writeOptions()
  end
  self.scroll = OptionRows.clampScroll(self.index, self.scroll or 0,
                                       #rows, cancelRow)
end

function OptionsMenu:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll or 0,
                  "CANCEL", #self.rows + 1)
end

return OptionsMenu
