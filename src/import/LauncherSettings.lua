-- Launcher settings rows: the gear menu's model layer.
--
-- The in-game OPTION menu (src/ui/OptionsMenu.lua) mutates game.save.options
-- and live-applies each change to the running engine.  The launcher has no
-- running engine, so this builds the same ladders against the persisted
-- options.lua table (src/core/SaveData.loadOptions/saveOptions) and lets the
-- next boot's applyOptions pick the values up.  Every ladder mirrors
-- OptionsMenu's semantics and stored values; when editing one, keep the two
-- in sync.  ZOOM uses the live window's integer fit (same 160×144 rule as
-- Renderer:fitScale) so the row can offer OUT/FIT/IN without a running game.
--
-- Rows are the same descriptor idiom OptionRows draws in game:
--   { label, value = fn() -> string, step = fn(dir) -> changed,
--     editText = { maxLen } }   -- editText marks a free-text row; the view
--                                  opens its prompt and commits via setText.
--
-- Mod rows come from each enabled mod's options_schema (the manager's auto-UI
-- contract, src/mods/ManagerState.lua buildOptionRows) and persist in
-- options.modOptions[modId][key], the exact table the loader reads on boot.

local Strings = require("src.core.Strings")
local SaveData = require("src.core.SaveData")

local LauncherSettings = {}

local function copyValue(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = copyValue(val) end
  return out
end

local function sameValue(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not sameValue(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function restoreInto(dst, key, value)
  local cur = dst[key]
  if type(cur) == "table" and type(value) == "table" then
    for k in pairs(cur) do cur[k] = nil end
    for k, v in pairs(value) do cur[k] = copyValue(v) end
  else
    dst[key] = copyValue(value)
  end
end

function LauncherSettings.persist(opts, base)
  local changed = {}
  for k, v in pairs(opts) do
    if not sameValue(v, base[k]) then changed[#changed + 1] = k end
  end
  for k in pairs(base) do
    if opts[k] == nil then changed[#changed + 1] = k end
  end
  if #changed == 0 then return true end
  SaveData.invalidateOptionsCache()
  local fresh = SaveData.loadOptions()
  for _, k in ipairs(changed) do fresh[k] = copyValue(opts[k]) end
  if SaveData.saveOptions(fresh) ~= nil then
    for _, k in ipairs(changed) do base[k] = copyValue(opts[k]) end
    return true
  end
  for _, k in ipairs(changed) do restoreInto(opts, k, base[k]) end
  return false
end

local function bgLocked(opts)
  return opts.battleLayout == "wide" and opts.battleFit == "fill"
     and opts.battleHud == "extended"
end

local function wrapIndex(i, n)
  i = i % n
  if i < 0 then i = i + n end
  return i
end

local function volLabel(v)
  v = v or 7
  return v == 0 and "OFF" or tostring(v)
end

local function stepVolume(v, dir)
  return math.max(0, math.min(7, (v or 7) + dir))
end

-- Cycle a stored value through an ordered list of {stored, label} pairs.
local function ladder(opts, key, pairsList, default)
  local function index()
    local cur = opts[key]
    if cur == nil then cur = default end
    for i, p in ipairs(pairsList) do
      if p[1] == cur then return i end
    end
    return 1
  end
  return function() return Strings(pairsList[index()][2]) end,
    function(dir)
      opts[key] = pairsList[wrapIndex(index() - 1 + (dir or 1), #pairsList) + 1][1]
      return true
    end
end

-- TextSpeedOptionData delays with the original labels (OptionsMenu SPEEDS).
local SPEEDS = { { 1, "FAST" }, { 3, "MEDIUM" }, { 5, "SLOW" } }
local FILTERS = { "OFF", "1X", "2X", "3X" }

-- The core rows.  Helper modules are required lazily under pcall: they are
-- pure label/cycle tables, but the launcher must never die because a render
-- module grew a dependency on live game data.
local function addTouchRows(rows, add, opts, hooks)
  -- TOUCH PAD only where the overlay can appear, mirroring OptionsMenu's
  -- gate (mobile, or desktop forced by POKEPORT_TOUCH=1).
  local env = os.getenv("POKEPORT_TOUCH")
  local osName = love.system and love.system.getOS and love.system.getOS()
  local show = env == "1"
    or (env ~= "0" and (osName == "Android" or osName == "iOS"))
  if show then
    add(Strings("TOUCH PAD"),
      function()
        local tc = opts.touchControls
        local on = not (type(tc) == "table" and tc.enabled == false)
        return on and Strings("ON") or Strings("OFF")
      end,
      function()
        local tc = type(opts.touchControls) == "table" and opts.touchControls or {}
        tc.enabled = tc.enabled == false
        opts.touchControls = tc
        return true
      end)
    -- VIBRATION sits with it (#806): same gate, same subsystem.  Stepping
    -- the row buzzes once at the level being selected.
    local okTC, TC = pcall(require, "src.core.TouchControls")
    if okTC then
      add(Strings("VIBRATION"),
        function() return Strings(TC.hapticLabel(opts.haptics)) end,
        function(dir)
          opts.haptics = TC.cycleHaptics(opts.haptics, dir)
          TC.buzz(opts.haptics)
          return true
        end)
    end
    add(Strings("KEY BAR"),
      function() return opts.hotbar == false and Strings("OFF") or Strings("ON") end,
      function()
        opts.hotbar = opts.hotbar == false
        return true
      end)
  end

  if hooks and hooks.editTouchControls then
    rows[#rows + 1] = {
      label = Strings("TOUCH CONTROLS"),
      actionLabel = Strings("Edit"),
      action = function()
        hooks.editTouchControls()
        -- The editor replaces the whole screen: nothing left to persist here
        -- beyond what the caller already saved on the way out.
        return false
      end,
    }
  end

  if hooks and hooks.openSkinStudio then
    rows[#rows + 1] = {
      label = Strings("SKIN STUDIO"),
      actionLabel = Strings("Open"),
      action = function()
        hooks.openSkinStudio()
        return false
      end,
    }
  end
end

local function addOrientationRow(add, opts)
  local okOr, Orientation = pcall(require, "src.core.Orientation")
  if okOr and (Orientation.isAndroid() or Orientation.isIOS()) then
    add(Strings("ORIENTATION"),
      function() return Strings(Orientation.modeLabel(opts.orientation)) end,
      function(dir)
        opts.orientation = Orientation.cycle(opts.orientation, dir)
        Orientation.apply(opts.orientation)
        return true
      end)
  end
end

local function clearTouchLayouts(tc)
  if type(tc) == "table" then
    tc.layouts, tc.positions, tc.scale = nil, nil, nil
  end
end

local function coreRows(opts, hooks, gen)
  local rows = {}
  local function add(label, value, step)
    rows[#rows + 1] = { label = label, value = value, step = step }
  end

  add(Strings("TEXT SPEED"), ladder(opts, "textSpeed", SPEEDS, 3))
  add(Strings("BATTLE ANIMATION"),
    ladder(opts, "animations",
      { { true, "ON" }, { false, "OFF" } }, true))
  add(Strings("BATTLE STYLE"),
    ladder(opts, "battleStyle",
      { { "shift", "SHIFT" }, { "set", "SET" } }, "shift"))
  add(Strings("BATTLE LAYOUT"),
    function()
      return opts.battleLayout == "wide" and Strings("WIDE") or Strings("OG")
    end,
    function()
      opts.battleLayout = opts.battleLayout == "wide" and "og" or "wide"
      if opts.battleLayout ~= "wide" then
        opts.battleHud = "standard"
      end
      return true
    end)
  add(Strings("BATTLE SIZE"),
    function()
      return opts.battleFit == "fill" and Strings("FILL") or Strings("FIXED")
    end,
    function()
      opts.battleFit = opts.battleFit == "fill" and "fixed" or "fill"
      return true
    end)
  add(Strings("BATTLE HUD"),
    function()
      return opts.battleLayout == "wide" and opts.battleHud == "extended"
             and Strings("EXTENDED")
             or Strings("STANDARD")
    end,
    function()
      if opts.battleLayout ~= "wide" then
        opts.battleHud = "standard"
        return false
      end
      opts.battleHud = opts.battleHud == "extended" and "standard" or "extended"
      return true
    end)
  add(Strings("BATTLE BG"),
    function()
      if bgLocked(opts) then return Strings("AUTO (FILL HUD)") end
      if opts.battleBg == "black" then return Strings("BLACK") end
      if opts.battleBg == "world" then return Strings("WORLD") end
      return Strings("WHITE")
    end,
    function(dir)
      if bgLocked(opts) then return false end
      local order = { "white", "black", "world" }
      local cur = 1
      for i, mode in ipairs(order) do
        if opts.battleBg == mode then cur = i break end
      end
      opts.battleBg = order[wrapIndex(cur - 1 + (dir or 1), #order) + 1]
      return true
    end)
  add(Strings("UI LAYOUT"),
    ladder(opts, "uiLayout",
      { { "centered", "CENTERED" }, { "dynamic", "DYNAMIC" } }, "centered"))

  add(Strings("MUSIC VOL"),
    function() return volLabel(opts.musicVol) end,
    function(dir) opts.musicVol = stepVolume(opts.musicVol, dir); return true end)
  add(Strings("SFX VOL"),
    function() return volLabel(opts.sfxVol) end,
    function(dir) opts.sfxVol = stepVolume(opts.sfxVol, dir); return true end)
  add(Strings("MUSIC FILTER"),
    function() return FILTERS[(opts.musicFilter or 0) + 1] end,
    function(dir)
      opts.musicFilter = ((opts.musicFilter or 0) + dir) % #FILTERS
      return true
    end)
  add(Strings("AUDIO MODE"),
    ladder(opts, "audioMode",
      { { "both", "BOTH" }, { "external_only", "EXT ONLY" }, { "game_only", "GAME ONLY" } }, "both"))

  local okPerf, Performance = pcall(require, "src.core.Performance")
  if okPerf then
    add(Strings("PERFORMANCE"),
      function() return Strings(Performance.label(opts.performance)) end,
      function(dir)
        opts.performance = Performance.cycle(opts.performance, dir)
        return true
      end)
  end

  local okPal, PaletteFX = pcall(require, "src.render.PaletteFX")
  if okPal then
    add(Strings("COLORS"),
      function() return PaletteFX.modeLabel(opts.colors or "gbc") end,
      function(dir)
        local cur, idx = opts.colors or "gbc", 1
        for i, m in ipairs(PaletteFX.MODES) do
          if m == cur then idx = i break end
        end
        opts.colors = PaletteFX.MODES[wrapIndex(idx - 1 + dir, #PaletteFX.MODES) + 1]
        return true
      end)
  end

  local okTilt, Tilt = pcall(require, "src.render.Tilt")
  if okTilt then
    add(Strings("TILT"),
      function() return Tilt.levelLabel(opts.tilt or 0) end,
      function(dir)
        opts.tilt = wrapIndex((opts.tilt or 0) + dir, 4)
        return true
      end)
  end

  local okZ, Zoom = pcall(require, "src.render.Zoom")
  if okZ then
    add(Strings("ZOOM"),
      function() return Zoom.offsetLabel(opts.zoom or 0) end,
      function(dir)
        Zoom.nudgeOptions(opts, dir, Zoom.windowFitScale())
        return true
      end)
  end

  local okTile, TileRenderer = pcall(require, "src.render.TileRenderer")
  if okTile and TileRenderer.VOID_FILLS then
    add(Strings("VOID FILL"),
      function() return TileRenderer.voidFillLabel(opts.voidFill) end,
      function(dir)
        local modes = TileRenderer.VOID_FILLS
        local cur, idx = opts.voidFill or "trees", 1
        for i, m in ipairs(modes) do
          if m == cur then idx = i break end
        end
        opts.voidFill = modes[wrapIndex(idx - 1 + dir, #modes) + 1]
        return true
      end)
  end

  local okVm, VideoMode = pcall(require, "src.core.VideoMode")
  if okVm then
    add(Strings("VIDEO MODE"),
      function() return VideoMode.modeLabel(opts.videoMode) end,
      function(dir)
        opts.videoMode = VideoMode.cycle(opts.videoMode, dir)
        return true
      end)
  end

  addOrientationRow(add, opts)

  local okFr, FaithfulRes = pcall(require, "src.core.FaithfulRes")
  if okFr then
    add(Strings("FAITHFUL RATIO"),
      function() return FaithfulRes.label(opts.faithfulRes) end,
      function(dir)
        opts.faithfulRes = FaithfulRes.cycle(opts.faithfulRes, dir)
        return true
      end)
  end

  local okSp, ScreenPos = pcall(require, "src.core.ScreenPosition")
  if okSp then
    add(Strings("SCREEN POS"),
      function() return Strings(ScreenPos.label(opts.screenPos)) end,
      function(dir)
        opts.screenPos = ScreenPos.cycle(opts.screenPos, dir)
        ScreenPos.setMode(opts.screenPos)
        return true
      end)
  end

  local okCap, FrameCap = pcall(require, "src.core.FrameCap")
  if okCap then
    add(Strings("MAX FPS"),
      function() return FrameCap.label(opts.fpsCap) end,
      function(dir)
        opts.fpsCap = FrameCap.cycle(opts.fpsCap, dir)
        return true
      end)
  end

  local okSpd, GameSpeed = pcall(require, "src.core.GameSpeed")
  if okSpd then
    add(Strings("OVERWORLD SPEED"),
      function() return GameSpeed.levelLabel(opts.speedOverworld) end,
      function(dir)
        opts.speedOverworld = GameSpeed.cycle(opts.speedOverworld, dir)
        return true
      end)
    add(Strings("BATTLE SPEED"),
      function() return GameSpeed.levelLabel(opts.speedBattle) end,
      function(dir)
        opts.speedBattle = GameSpeed.cycle(opts.speedBattle, dir)
        return true
      end)
    add(Strings("MENU SPEED"),
      function() return GameSpeed.levelLabel(opts.speedMenu) end,
      function(dir)
        opts.speedMenu = GameSpeed.cycle(opts.speedMenu, dir)
        return true
      end)
  end

  addTouchRows(rows, add, opts, hooks)

  -- RESET REBINDS, directly under the touch-pad row.  Rebinds are additive
  -- (src/core/Input.lua:applyBindings layers options.bindings over the
  -- defaults rather than replacing them), so a player who has bound
  -- themselves into a corner has no in-game way back -- there is no "unbind"
  -- gesture.  Clearing the table restores the stock keyboard and pad layout
  -- on the next Input:applyBindings, which the game does on its next start.
  -- The dragged touch-overlay layout goes with it: it is the same class of
  -- customisation and the same class of getting stuck.
  rows[#rows + 1] = {
    label = Strings("RESET REBINDS"),
    actionLabel = Strings("Reset"),
    danger = true,
    action = function()
      opts.bindings = nil
      if gen == 3 then
        if type(opts.game3) ~= "table" then opts.game3 = {} end
        opts.game3.touchControls = { layouts = {} }
      else
        clearTouchLayouts(opts.touchControls)
      end
      return true
    end,
  }

  return rows
end

-- ------- per-mod options (the manager's options_schema auto-UI contract)

local OPTION_TYPES = { toggle = true, choice = true, number = true, text = true }

-- Enabled mods with a loadable options_schema, discovered the same way
-- LauncherMods discovers manifests (mods/ one level deep; the launcher's
-- readiness check has already mounted a portable install's game folder).
local function discoverModSchemas(opts)
  local fs = love and love.filesystem
  local out = {}
  if not (fs and fs.getInfo and fs.getDirectoryItems) then return out end
  if not fs.getInfo("mods") then return out end
  local okJson, Json = pcall(require, "src.link.Json")
  local okMan, Manifest = pcall(require, "src.mods.Manifest")
  if not (okJson and okMan) then return out end
  local seen = {}
  for _, name in ipairs(fs.getDirectoryItems("mods")) do
    local path = "mods/" .. name
    local info = fs.getInfo(path)
    if info and (info.type == "directory" or info.type == "symlink") then
      local raw = fs.read(path .. "/manifest.json")
      local data = raw and select(1, Json.decode(raw))
      local okV, m = false, nil
      if data then okV, m = pcall(Manifest.validate, data, path) end
      if okV and m and not seen[m.id] and m.options_schema then
        seen[m.id] = true
        -- deriveList's enable resolution, through the one reader both mod
        -- surfaces use (SaveData.modEnabled): unanswered means enabled,
        -- except experimental mods, which stay off until opted in.
        local flag = require("src.core.SaveData").modEnabled(opts, m.id)
        local enabled = flag == true or (flag == nil and not m.experimental)
        if enabled and not SaveData.isSafeMode(opts) then
          local rel = path .. "/" .. m.options_schema
          local schema = require("src.mods.Sandbox").evalData(fs.read(rel), "@" .. rel)
          if schema then
            out[#out + 1] = { id = m.id, name = m.name or m.id, schema = schema }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Rows for one mod's schema against options.modOptions (ManagerState's
-- persistence shape, so the game sees launcher edits on its next boot).
local function modRows(opts, mod)
  local rows = {}
  local modId = mod.id
  local function stored()
    local t = opts.modOptions
    return t and t[modId] or nil
  end
  local function get(row)
    local s = stored()
    local v = s and s[row.key]
    if v == nil then v = row.default end
    return v
  end
  local function set(key, value)
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[modId] = opts.modOptions[modId] or {}
    opts.modOptions[modId][key] = value
  end

  for _, row in ipairs(mod.schema) do
    if type(row) ~= "table" or type(row.key) ~= "string" or row.key == ""
        or not OPTION_TYPES[row.type] then
      -- malformed rows are skipped silently here; the in-game manager is
      -- where schema errors are reported to the author
    elseif row.type == "toggle" then
      rows[#rows + 1] = { label = row.label or row.key,
        value = function() return get(row) and Strings("ON") or Strings("OFF") end,
        step = function()
          set(row.key, not get(row))
          return true
        end }
    elseif row.type == "choice" then
      rows[#rows + 1] = { label = row.label or row.key,
        value = function()
          local cur = get(row)
          for _, choice in ipairs(row.choices or {}) do
            if choice[2] == cur then return tostring(choice[1]) end
          end
          local first = (row.choices or {})[1]
          return first and tostring(first[1]) or "----"
        end,
        step = function(dir)
          local choices = row.choices or {}
          if #choices == 0 then return false end
          local cur, index = get(row), 1
          for i, choice in ipairs(choices) do
            if choice[2] == cur then index = i break end
          end
          set(row.key, choices[wrapIndex(index - 1 + dir, #choices) + 1][2])
          return true
        end }
    elseif row.type == "number" then
      rows[#rows + 1] = { label = row.label or row.key,
        value = function() return tostring(get(row) or 0) end,
        step = function(dir)
          local v = (tonumber(get(row)) or 0) + dir * (row.step or 1)
          if row.min then v = math.max(row.min, v) end
          if row.max then v = math.min(row.max, v) end
          set(row.key, v)
          return true
        end }
    elseif row.type == "text" then
      rows[#rows + 1] = { label = row.label or row.key,
        value = function() return tostring(get(row) or "") end,
        editText = { maxLen = row.maxLen or 7 },
        setText = function(text) set(row.key, text) end }
    end
  end
  if #rows > 0 then
    rows[#rows + 1] = { label = Strings("RESET DEFAULTS"),
      value = function() return "" end,
      step = function()
        for _, row in ipairs(mod.schema) do
          if type(row) == "table" and type(row.key) == "string"
              and OPTION_TYPES[row.type] then
            set(row.key, row.default)
          end
        end
        return true
      end }
  end
  for _, row in ipairs(rows) do
    row.safeModeBlocked = true
    if row.step then
      local step = row.step
      row.step = function(dir)
        if SaveData.isSafeMode(opts) then return false end
        return step(dir)
      end
    end
    if row.setText then
      local setText = row.setText
      row.setText = function(text)
        if SaveData.isSafeMode(opts) then return false end
        return setText(text)
      end
    end
  end
  return rows
end

-- ------- Gen 2 (Gold)
--
-- Gold reads NONE of the rows above.  Its OPTION screen writes a different
-- set of names, several of which collide with Gen 1's at a different TYPE
-- (battleStyle "SHIFT" vs "shift", textSpeed a label vs a frame delay), and
-- its renderer has no battle layout and no SGB palette packs -- so a gear
-- opened on the Gold tab used to offer a dozen controls that did nothing
-- and hide the seven that the cart itself has.
--
-- The block lives in options.lua under `gold` (the historical key; Gold and
-- Silver share it the way the Gen 1 games share the flat namespace), which is
-- exactly where src/core/gen2/Save.lua loadOptions reads it, so an edit here
-- is live on the next boot the same way a Gen 1 edit is.  Ladders mirror
-- src/ui/gen2/OptionsMenu.lua's ROWS; when editing one, keep the two in sync.
local GEN2_KEY = "gold"

local function gen2Rows(opts, hooks, shared)
  local rows = {}
  local function add(label, value, step)
    rows[#rows + 1] = { label = label, value = value, step = step }
  end

  -- The cart's own seven (engine/menus/options_menu.asm _Option).
  add(Strings("TEXT SPEED"), ladder(opts, "textSpeed",
    { { "FAST", "FAST" }, { "MID", "MID" }, { "SLOW", "SLOW" } }, "MID"))
  add(Strings("BATTLE SCENE"), ladder(opts, "battleScene",
    { { true, "ON" }, { false, "OFF" } }, true))
  add(Strings("BATTLE STYLE"), ladder(opts, "battleStyle",
    { { "SHIFT", "SHIFT" }, { "SET", "SET" } }, "SHIFT"))
  add(Strings("SOUND"), ladder(opts, "sound",
    { { "MONO", "MONO" }, { "STEREO", "STEREO" } }, "MONO"))
  add(Strings("PRINT"), ladder(opts, "print", {
    { "LIGHTEST", "LIGHTEST" }, { "LIGHTER", "LIGHTER" },
    { "NORMAL", "NORMAL" }, { "DARKER", "DARKER" }, { "DARKEST", "DARKEST" },
  }, "NORMAL"))
  add(Strings("MENU ACCOUNT"), ladder(opts, "menuAccount",
    { { false, "OFF" }, { true, "ON" } }, true))
  -- FRAME is the textbox border, 1-8, wrapping (UpdateFrame masks to 3 bits).
  add(Strings("FRAME"),
    function() return tostring(opts.frame or 1) end,
    function(dir)
      opts.frame = wrapIndex((opts.frame or 1) - 1 + (dir or 1), 8) + 1
      return true
    end)

  -- ...then the port's, the same shared modules the Gen 1 rows drive.
  add(Strings("MUSIC VOL"),
    function() return volLabel(opts.musicVol) end,
    function(dir) opts.musicVol = stepVolume(opts.musicVol, dir); return true end)
  add(Strings("SFX VOL"),
    function() return volLabel(opts.sfxVol) end,
    function(dir) opts.sfxVol = stepVolume(opts.sfxVol, dir); return true end)
  add(Strings("MUSIC FILTER"),
    function() return FILTERS[(opts.musicFilter or 0) + 1] end,
    function(dir)
      opts.musicFilter = ((opts.musicFilter or 0) + dir) % #FILTERS
      return true
    end)
  add(Strings("AUDIO MODE"),
    ladder(opts, "audioMode",
      { { "both", "BOTH" }, { "external_only", "EXT ONLY" }, { "game_only", "GAME ONLY" } }, "both"))

  local okPal, GbcPalette = pcall(require, "src.render.GbcPalette")
  if okPal then
    add(Strings("COLOR"),
      function() return GbcPalette.modeLabel(opts.color or "gbc") end,
      function(dir)
        local cur, idx = opts.color or "gbc", 1
        for i, mode in ipairs(GbcPalette.MODES) do
          if mode == cur then idx = i break end
        end
        opts.color =
          GbcPalette.MODES[wrapIndex(idx - 1 + dir, #GbcPalette.MODES) + 1]
        opts.palette = ""
        return true
      end)
  end

  local okSpd, GameSpeed = pcall(require, "src.core.GameSpeed")
  if okSpd then
    add(Strings("GAME SPEED"),
      function() return GameSpeed.levelLabel(opts.speed) end,
      function(dir)
        opts.speed = GameSpeed.cycle(opts.speed, dir)
        return true
      end)
  end

  local okTilt, Tilt = pcall(require, "src.render.Tilt")
  if okTilt then
    add(Strings("TILT"),
      function() return Tilt.levelLabel(opts.tilt or 0) end,
      function(dir)
        opts.tilt = wrapIndex((opts.tilt or 0) + dir, 4)
        return true
      end)
  end

  local okZ, Zoom = pcall(require, "src.render.Zoom")
  if okZ then
    add(Strings("ZOOM"),
      function() return Zoom.offsetLabel(opts.zoom or 0) end,
      function(dir)
        Zoom.nudgeOptions(opts, dir, Zoom.windowFitScale())
        return true
      end)
  end

  local okFill, BorderFill = pcall(require, "src.world.gen2.BorderFill")
  if okFill and BorderFill.VOID_FILLS then
    add(Strings("VOID FILL"),
      function() return BorderFill.voidFillLabel(opts.voidFill) end,
      function(dir)
        local modes = BorderFill.VOID_FILLS
        local cur, idx = opts.voidFill or "fade", 1
        for i, m in ipairs(modes) do
          if m == cur then idx = i break end
        end
        opts.voidFill = modes[wrapIndex(idx - 1 + dir, #modes) + 1]
        return true
      end)
  end

  local okVm, VideoMode = pcall(require, "src.core.VideoMode")
  if okVm then
    add(Strings("VIDEO MODE"),
      function() return VideoMode.modeLabel(shared.videoMode) end,
      function(dir)
        shared.videoMode = VideoMode.cycle(shared.videoMode, dir)
        return true
      end)
  end

  local okFr, FaithfulRes = pcall(require, "src.core.FaithfulRes")
  if okFr then
    add(Strings("FAITHFUL RATIO"),
      function() return FaithfulRes.label(shared.faithfulRes) end,
      function(dir)
        shared.faithfulRes = FaithfulRes.cycle(shared.faithfulRes, dir)
        return true
      end)
  end

  local okCap, FrameCap = pcall(require, "src.core.FrameCap")
  if okCap then
    add(Strings("MAX FPS"),
      function() return FrameCap.label(opts.fpsCap) end,
      function(dir)
        opts.fpsCap = FrameCap.cycle(opts.fpsCap, dir)
        return true
      end)
  end

  add(Strings("BATTLE LAYOUT"),
    function()
      return opts.battleLayout == "wide" and Strings("WIDE") or Strings("OG")
    end,
    function()
      opts.battleLayout = opts.battleLayout == "wide" and "og" or "wide"
      if opts.battleLayout ~= "wide" then
        opts.battleHud = "standard"
      end
      return true
    end)

  add(Strings("BATTLE HUD"),
    function()
      return opts.battleLayout == "wide" and opts.battleHud == "extended"
             and Strings("EXTENDED")
             or Strings("STANDARD")
    end,
    function()
      if opts.battleLayout ~= "wide" then
        opts.battleHud = "standard"
        return false
      end
      opts.battleHud = opts.battleHud == "extended" and "standard" or "extended"
      return true
    end)

  add(Strings("BATTLE SIZE"), ladder(opts, "battleFit",
    { { "fixed", "FIXED" }, { "fill", "FILL" } }, "fixed"))

  add(Strings("BATTLE BG"),
    function()
      if bgLocked(opts) then return Strings("AUTO (FILL HUD)") end
      if opts.battleBg == "black" then return Strings("BLACK") end
      if opts.battleBg == "world" then return Strings("WORLD") end
      return Strings("WHITE")
    end,
    function(dir)
      if bgLocked(opts) then return false end
      local order = { "white", "black", "world" }
      local cur = 1
      for i, mode in ipairs(order) do
        if opts.battleBg == mode then cur = i break end
      end
      opts.battleBg = order[wrapIndex(cur - 1 + (dir or 1), #order) + 1]
      return true
    end)

  addTouchRows(rows, add, shared, hooks)
  addOrientationRow(add, shared)

  rows[#rows + 1] = {
    label = Strings("RESET REBINDS"),
    actionLabel = Strings("Reset"),
    danger = true,
    action = function()
      opts.bindings = nil
      opts.touchControls = { layouts = {} }
      return true
    end,
  }

  return rows
end

-- Build the whole settings model: one options table (edited in place),
-- sections of rows, and a save() that persists it.  The caller keeps the
-- model for as long as the panel is open; nothing else in the launcher
-- writes options while a modal covers it, so the cached table stays true.
-- `hooks` carries the host actions a row cannot perform itself:
--   editTouchControls()  -- hand the screen to the touch-overlay editor
--   openSkinStudio()     -- hand the screen to the desktop skin studio
--
-- `version` is the game the gear was opened on.  It picks the row set, and
-- for Gold it also picks WHICH table the rows edit: the `gold` block inside
-- options.lua rather than the flat Gen 1 one.
function LauncherSettings.open(hooks, version)
  local opts = SaveData.loadOptions()
  local sections
  local GameVersion = require("src.core.GameVersion")
  local gen = GameVersion.VERSIONS[version] and GameVersion.generation(version)
  if gen == 2 then
    local block = opts[GEN2_KEY]
    if type(block) ~= "table" then
      block = {}
      opts[GEN2_KEY] = block
    end
    sections = {
      { title = Strings("Game Options"), rows = gen2Rows(block, hooks, opts) },
    }
  else
    sections = {
      { title = Strings("Game Options"), rows = coreRows(opts, hooks, gen) },
    }
  end
  local launcher = {
    title = Strings("Launcher Options"),
    rows = {
      {
        label = Strings("Reduce Motion"),
        value = function()
          return opts.reduceMotion == true and Strings("ON") or Strings("OFF")
        end,
        step = function()
          opts.reduceMotion = not (opts.reduceMotion == true)
          local okT, Transition = pcall(require, "src.ui.kit.Transition")
          if okT then Transition.reduceMotion = opts.reduceMotion end
          return true
        end,
      },
      {
        label = Strings("Splash Video"),
        value = function()
          return opts.splashVideo == false and Strings("OFF") or Strings("ON")
        end,
        step = function()
          opts.splashVideo = opts.splashVideo == false
          return true
        end,
      },
      {
        label = Strings("Theme Video BG"),
        value = function()
          return opts.themeVideoBg == false and Strings("OFF") or Strings("ON")
        end,
        step = function()
          opts.themeVideoBg = opts.themeVideoBg == false
          return true
        end,
      },
      {
        label = Strings("Splash Sound"),
        value = function()
          return opts.splashMute == true and Strings("OFF") or Strings("ON")
        end,
        step = function()
          opts.splashMute = not (opts.splashMute == true)
          return true
        end,
      },
      {
        label = Strings("Showcase Music"),
        value = function() return volLabel(opts.boxMusicVol) end,
        step = function(dir)
          opts.boxMusicVol = stepVolume(opts.boxMusicVol, dir or 1)
          require("src.box.Showcase").setVolume(opts.boxMusicVol)
          return true
        end,
      },
      {
        label = Strings("Showcase Cry"),
        value = function() return volLabel(opts.boxCryVol) end,
        step = function(dir) opts.boxCryVol = stepVolume(opts.boxCryVol, dir or 1); return true end,
      },
    },
  }
  local Window = require("src.import.LauncherWindow")
  if Window.supported() then
    table.insert(launcher.rows, 1, {
      label = Strings("Video Mode"),
      value = function() return Window.mode() == "fullscreen" and Strings("Fullscreen") or Strings("Windowed") end,
      step = function() return Window.toggle() end,
      choices = {{value="windowed", label=Strings("Windowed")},
        {value="fullscreen", label=Strings("Fullscreen")}},
      selected = Window.mode,
      select = function(value) Window.observe(0); return Window.apply(value) end,
    })
  end
  if hooks and hooks.openExtras then
    table.insert(launcher.rows, 1, {
      label = Strings("Extras"), actionLabel = Strings("Open"),
      action = function() hooks.openExtras(); return false end,
    })
  end
  local UnionSetting = require("src.online.union.Setting")
  launcher.rows[#launcher.rows + 1] = {
    label = Strings("Union Room"),
    note = Strings("Adds a Union Room upstairs in Gen 1 and Gen 2 Pokemon Centers. OFF restores the original Centers. Gen 3 Union Rooms always work."),
    value = function()
      return UnionSetting.enabledIn(opts) and Strings("ON") or Strings("OFF")
    end,
    step = function()
      opts[UnionSetting.KEY] = not UnionSetting.enabledIn(opts)
      return true
    end,
  }
  local RomSources = require("src.import.RomSources")
  launcher.rows[#launcher.rows + 1] = {
    label = Strings("Auto Re-import"),
    value = function()
      return opts.autoReimport == true and Strings("ON") or Strings("OFF")
    end,
    step = function()
      opts.autoReimport = not (opts.autoReimport == true)
      return true
    end,
  }
  launcher.rows[#launcher.rows + 1] = {
    label = Strings("Forget Saved ROMs"),
    actionLabel = Strings("Forget"),
    danger = true,
    confirm = {
      title = Strings("Forget saved ROMs?"),
      lines = {
        Strings("Kept ROM copies are deleted and the launcher stops offering to re-import from them."),
        Strings("Imported games stay playable."),
      },
    },
    doneText = Strings("Saved ROMs forgotten."),
    action = function()
      RomSources.forgetAll(opts)
      return true
    end,
  }
  table.insert(sections, 1, launcher)
  -- Mod options are generation-agnostic (the manager's options_schema
  -- contract), so they ride along either way.
  for _, mod in ipairs(discoverModSchemas(opts)) do
    local rows = modRows(opts, mod)
    if #rows > 0 then
      sections[#sections + 1] = { title = mod.name, rows = rows }
    end
  end
  local base = copyValue(opts)
  local model = {
    opts = opts,
    version = version,
    sections = sections,
  }
  model.save = function()
    if LauncherSettings.persist(opts, base) then
      model.saveError = nil
      return true
    end
    model.saveError = Strings("Settings could not be saved. Check the log.")
    model.flash = nil
    return false
  end
  return model
end

return LauncherSettings
