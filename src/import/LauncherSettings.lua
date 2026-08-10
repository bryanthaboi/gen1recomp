-- Launcher settings rows: the gear menu's model layer.
--
-- The in-game OPTION menu (src/ui/OptionsMenu.lua) mutates game.save.options
-- and live-applies each change to the running engine.  The launcher has no
-- running engine, so this builds the same ladders against the persisted
-- options.lua table (src/core/SaveData.loadOptions/saveOptions) and lets the
-- next boot's applyOptions pick the values up.  Every ladder mirrors
-- OptionsMenu's semantics and stored values; when editing one, keep the two
-- in sync.  ZOOM is deliberately absent: its range depends on the live
-- renderer's fit scale (Renderer:fitScale), which does not exist here.
--
-- Rows are the same descriptor idiom OptionRows draws in game:
--   { label, value = fn() -> string, step = fn(dir) -> changed,
--     editText = { maxLen } }   -- editText marks a free-text row; the view
--                                  opens its prompt and commits via setText.
--
-- Mod rows come from each enabled mod's options_schema (the manager's auto-UI
-- contract, src/mods/ManagerState.lua buildOptionRows) and persist in
-- options.modOptions[modId][key], the exact table the loader reads on boot.

local AppLocale = require("src.core.AppLocale")
local SaveData = require("src.core.SaveData")

local LauncherSettings = {}

local settingValues = {
  [AppLocale.source("ADVANCED")] = true,
  [AppLocale.source("AUTO")] = true,
  [AppLocale.source("BALANCED")] = true,
  [AppLocale.source("BLACK")] = true,
  [AppLocale.source("BORDERLESS")] = true,
  [AppLocale.source("CENTERED")] = true,
  [AppLocale.source("CLASSIC")] = true,
  [AppLocale.source("DYNAMIC")] = true,
  [AppLocale.source("FAST")] = true,
  [AppLocale.source("FILL")] = true,
  [AppLocale.source("FIXED")] = true,
  [AppLocale.source("HEAVY")] = true,
  [AppLocale.source("HIGH")] = true,
  [AppLocale.source("LANDSCAPE")] = true,
  [AppLocale.source("LIGHT")] = true,
  [AppLocale.source("LOW")] = true,
  [AppLocale.source("MEDIUM")] = true,
  [AppLocale.source("NORMAL")] = true,
  [AppLocale.source("OFF")] = true,
  [AppLocale.source("OG")] = true,
  [AppLocale.source("OG BLUE")] = true,
  [AppLocale.source("OG INV")] = true,
  [AppLocale.source("OG RED")] = true,
  [AppLocale.source("OG YELLOW")] = true,
  [AppLocale.source("ON")] = true,
  [AppLocale.source("PORTRAIT")] = true,
  [AppLocale.source("REVERSE LANDSCAPE")] = true,
  [AppLocale.source("SET")] = true,
  [AppLocale.source("SGB INV")] = true,
  [AppLocale.source("SHIFT")] = true,
  [AppLocale.source("SLOW")] = true,
  [AppLocale.source("TREES")] = true,
  [AppLocale.source("WATER")] = true,
  [AppLocale.source("WHITE")] = true,
  [AppLocale.source("WIDE")] = true,
  [AppLocale.source("WINDOWED")] = true,
  [AppLocale.source("WORLD")] = true,
}

local function settingValue(source)
  source = tostring(source)
  return settingValues[source] and AppLocale(source) or source
end

local function wrapIndex(i, n)
  i = i % n
  if i < 0 then i = i + n end
  return i
end

local function volLabel(v)
  v = v or 7
  return v == 0 and settingValue("OFF") or tostring(v)
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
  return function() return settingValue(pairsList[index()][2]) end,
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
local function coreRows(opts, hooks)
  local rows = {}
  local function add(label, value, step)
    rows[#rows + 1] = { label = label, value = value, step = step }
  end

  -- Interface Language is an application preference, not a Pokemon/gameplay
  -- option.  Keep it in the launcher's global settings model because those
  -- settings already persist in options.lua across Red/Blue/Yellow.  The view
  -- observes AppLocale.generation() and rebuilds this model on the next frame.
  local localeRow = {}
  localeRow.label = AppLocale("Interface Language")
  localeRow.value = function()
    return AppLocale.displayName(opts.interfaceLocale or AppLocale.get())
  end
  localeRow.step = function(dir)
    opts.interfaceLocale = AppLocale.cycle(opts.interfaceLocale or AppLocale.get(), dir)
    AppLocale.set(opts.interfaceLocale)
    return true
  end
  rows[#rows + 1] = localeRow

  add(AppLocale("TEXT SPEED"), ladder(opts, "textSpeed", SPEEDS, 3))
  add(AppLocale("BATTLE ANIMATION"),
    ladder(opts, "animations",
      { { true, "ON" }, { false, "OFF" } }, true))
  add(AppLocale("BATTLE STYLE"),
    ladder(opts, "battleStyle",
      { { "shift", "SHIFT" }, { "set", "SET" } }, "shift"))
  add(AppLocale("BATTLE LAYOUT"),
    ladder(opts, "battleLayout",
      { { "og", "OG" }, { "wide", "WIDE" } }, "og"))
  add(AppLocale("BATTLE SIZE"),
    ladder(opts, "battleFit",
      { { "fixed", "FIXED" }, { "fill", "FILL" } }, "fixed"))
  add(AppLocale("BATTLE BG"),
    ladder(opts, "battleBg",
      { { "white", "WHITE" }, { "black", "BLACK" }, { "world", "WORLD" } },
      "white"))
  add(AppLocale("UI LAYOUT"),
    ladder(opts, "uiLayout",
      { { "centered", "CENTERED" }, { "dynamic", "DYNAMIC" } }, "centered"))

  add(AppLocale("MUSIC VOL"),
    function() return volLabel(opts.musicVol) end,
    function(dir) opts.musicVol = stepVolume(opts.musicVol, dir); return true end)
  add(AppLocale("SFX VOL"),
    function() return volLabel(opts.sfxVol) end,
    function(dir) opts.sfxVol = stepVolume(opts.sfxVol, dir); return true end)
  add(AppLocale("MUSIC FILTER"),
    function() return settingValue(FILTERS[(opts.musicFilter or 0) + 1]) end,
    function(dir)
      opts.musicFilter = ((opts.musicFilter or 0) + dir) % #FILTERS
      return true
    end)

  local okPerf, Performance = pcall(require, "src.core.Performance")
  if okPerf then
    add(AppLocale("PERFORMANCE"),
      function() return settingValue(Performance.label(opts.performance)) end,
      function(dir)
        opts.performance = Performance.cycle(opts.performance, dir)
        return true
      end)
  end

  local okPal, PaletteFX = pcall(require, "src.render.PaletteFX")
  if okPal then
    add(AppLocale("COLORS"),
      function() return settingValue(PaletteFX.modeLabel(opts.colors or "gbc")) end,
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
    add(AppLocale("TILT"),
      function() return settingValue(Tilt.levelLabel(opts.tilt or 0)) end,
      function(dir)
        opts.tilt = wrapIndex((opts.tilt or 0) + dir, 4)
        return true
      end)
  end

  -- issue #136: GBC FX soft-bricks the mobile present shader; same gate as
  -- the in-game row.
  local okFx, GBCFX = pcall(require, "src.render.GBCFX")
  if okFx and GBCFX.isSupported() then
    add(AppLocale("GBC FX"),
      function() return settingValue(GBCFX.levelLabel(opts.gbcfx or 0)) end,
      function(dir)
        opts.gbcfx = wrapIndex((opts.gbcfx or 0) + dir, 5)
        return true
      end)
  end

  local okTile, TileRenderer = pcall(require, "src.render.TileRenderer")
  if okTile and TileRenderer.VOID_FILLS then
    add(AppLocale("VOID FILL"),
      function() return settingValue(TileRenderer.voidFillLabel(opts.voidFill)) end,
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
    add(AppLocale("VIDEO MODE"),
      function() return settingValue(VideoMode.modeLabel(opts.videoMode)) end,
      function(dir)
        opts.videoMode = VideoMode.cycle(opts.videoMode, dir)
        return true
      end)
  end

  -- ORIENTATION (#592): Android only -- the lock rides SDL's orientation
  -- hint, which iOS reads only at startup (the Info.plist governs there) and
  -- desktop ignores.  Unlike the other launcher rows this one live-applies:
  -- the window exists here too, and rotating under the player's finger is
  -- the only feedback that reads.
  do
    local osName = love.system and love.system.getOS and love.system.getOS()
    local okOr, Orientation = pcall(require, "src.core.Orientation")
    if okOr and osName == "Android" then
      add(AppLocale("ORIENTATION"),
        function() return settingValue(Orientation.modeLabel(opts.orientation)) end,
        function(dir)
          opts.orientation = Orientation.cycle(opts.orientation, dir)
          Orientation.apply(opts.orientation)
          return true
        end)
    end
  end

  local okFr, FaithfulRes = pcall(require, "src.core.FaithfulRes")
  if okFr then
    add(AppLocale("FAITHFUL RATIO"),
      function() return settingValue(FaithfulRes.label(opts.faithfulRes)) end,
      function(dir)
        opts.faithfulRes = FaithfulRes.cycle(opts.faithfulRes, dir)
        return true
      end)
  end

  local okCap, FrameCap = pcall(require, "src.core.FrameCap")
  if okCap then
    add(AppLocale("MAX FPS"),
      function() return settingValue(FrameCap.label(opts.fpsCap)) end,
      function(dir)
        opts.fpsCap = FrameCap.cycle(opts.fpsCap, dir)
        return true
      end)
  end

  local okSpd, GameSpeed = pcall(require, "src.core.GameSpeed")
  if okSpd then
    -- Per-category (RFC 0007): overworld/battle/menu each cycle their own
    -- multiplier, mirroring OptionsMenu.lua's three rows.
    add(AppLocale("OVERWORLD SPEED"),
      function() return settingValue(GameSpeed.levelLabel(opts.speedOverworld)) end,
      function(dir)
        opts.speedOverworld = GameSpeed.cycle(opts.speedOverworld, dir)
        return true
      end)
    add(AppLocale("BATTLE SPEED"),
      function() return settingValue(GameSpeed.levelLabel(opts.speedBattle)) end,
      function(dir)
        opts.speedBattle = GameSpeed.cycle(opts.speedBattle, dir)
        return true
      end)
    add(AppLocale("MENU SPEED"),
      function() return settingValue(GameSpeed.levelLabel(opts.speedMenu)) end,
      function(dir)
        opts.speedMenu = GameSpeed.cycle(opts.speedMenu, dir)
        return true
      end)
  end

  -- TOUCH PAD only where the overlay can appear, mirroring OptionsMenu's
  -- gate (mobile, or desktop forced by POKEPORT_TOUCH=1).
  do
    local env = os.getenv("POKEPORT_TOUCH")
    local osName = love.system and love.system.getOS and love.system.getOS()
    local show = env == "1"
      or (env ~= "0" and (osName == "Android" or osName == "iOS"))
    if show then
      add(AppLocale("TOUCH PAD"),
        function()
          local tc = opts.touchControls
          local on = not (type(tc) == "table" and tc.enabled == false)
          return settingValue(on and "ON" or "OFF")
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
        add(AppLocale("VIBRATION"),
          function() return settingValue(TC.hapticLabel(opts.haptics)) end,
          function(dir)
            opts.haptics = TC.cycleHaptics(opts.haptics, dir)
            TC.buzz(opts.haptics)
            return true
          end)
      end
    end
  end

  -- TOUCH CONTROLS, the on-screen pad's layout editor.  It used to be a
  -- button on the game panel, once per game -- but the overlay layout is
  -- global (options.touchControls.layouts), so three tabs offered three
  -- buttons that edited the same thing while crowding the column that has to
  -- hold Play.  It belongs with the other control rows, behind the gear.
  -- The host owns the editor screen, so the row only fires when a hook was
  -- supplied (the standalone save editor opens this model with none).
  if hooks and hooks.editTouchControls then
    rows[#rows + 1] = {
      label = AppLocale("TOUCH CONTROLS"),
      actionLabel = AppLocale("Edit"),
      action = function()
        hooks.editTouchControls()
        -- The editor replaces the whole screen: nothing left to persist here
        -- beyond what the caller already saved on the way out.
        return false
      end,
    }
  end

  -- RESET REBINDS, directly under the touch-pad row.  Rebinds are additive
  -- (src/core/Input.lua:applyBindings layers options.bindings over the
  -- defaults rather than replacing them), so a player who has bound
  -- themselves into a corner has no in-game way back -- there is no "unbind"
  -- gesture.  Clearing the table restores the stock keyboard and pad layout
  -- on the next Input:applyBindings, which the game does on its next start.
  -- The dragged touch-overlay layout goes with it: it is the same class of
  -- customisation and the same class of getting stuck.
  rows[#rows + 1] = {
    label = AppLocale("RESET REBINDS"),
    actionLabel = AppLocale("Reset"),
    danger = true,
    action = function()
      opts.bindings = nil
      local tc = opts.touchControls
      if type(tc) == "table" then tc.layouts = nil end
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
  local enabledFlags = opts.mods or {}
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
        -- deriveList's enable resolution: a missing entry means enabled,
        -- except experimental mods, which stay off until opted in.
        local flag = enabledFlags[m.id]
        local enabled = flag == true or (flag == nil and not m.experimental)
        if enabled then
          local chunk = fs.load(path .. "/" .. m.options_schema)
          if chunk then
            local okR, schema = pcall(chunk)
            if okR and type(schema) == "table" then
              out[#out + 1] = { id = m.id, name = m.name or m.id, schema = schema }
            end
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
        value = function() return settingValue(get(row) and "ON" or "OFF") end,
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
    rows[#rows + 1] = { label = AppLocale("RESET DEFAULTS"),
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
  return rows
end

-- Build the whole settings model: one options table (edited in place),
-- sections of rows, and a save() that persists it.  The caller keeps the
-- model for as long as the panel is open; nothing else in the launcher
-- writes options while a modal covers it, so the cached table stays true.
-- `hooks` carries the host actions a row cannot perform itself:
--   editTouchControls()  -- hand the screen to the touch-overlay editor
function LauncherSettings.open(hooks)
  local opts = SaveData.loadOptions()
  -- Normalize the persisted value without re-applying the already active
  -- bootstrap locale every time this panel opens.
  opts.interfaceLocale = AppLocale.normalize(opts.interfaceLocale)
  local sections = {
    { title = AppLocale("OPTIONS"), rows = coreRows(opts, hooks) },
  }
  for _, mod in ipairs(discoverModSchemas(opts)) do
    local rows = modRows(opts, mod)
    if #rows > 0 then
      sections[#sections + 1] = { title = mod.name, rows = rows }
    end
  end
  return {
    opts = opts,
    sections = sections,
    localeGeneration = AppLocale.generation(),
    save = function() SaveData.saveOptions(opts) end,
  }
end

return LauncherSettings
