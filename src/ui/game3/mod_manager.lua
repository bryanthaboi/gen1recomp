-- Gen 3 (FRLG) presentation for the shared mod manager.
-- Behavior lives in src/mods/ManagerState (list/detail/options/apply,
-- staged toggles, profiles). This module only maps that model onto the
-- game3 stack and FRLG chrome — it never draws with Gen 1 Font/Theme.
-- Layout follows src/ui/game3/option_menu.lua (help bar + user frame).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local ManagerState = require("src.mods.ManagerState")

local ModManager = {}

ModManager.open = false

-- Geometry is option_menu.lua's, verbatim: help bar 0..16, title
-- fixedStdFrame(2,3,26,2) with outer border at tiles 2..5 (y 16..48), content
-- userFrame(2,7,26,12) with outer at tiles 6..19 (y 48..160). Nine-slice
-- borders draw OUTSIDE the content rect, so a third stacked frame cannot fit
-- without overlapping — the tab line rides in the title instead.
local VISIBLE = 7
local WIN_X, WIN_Y, WIN_W, WIN_H = 16, 56, 208, 96
local ROW_Y0 = WIN_Y + 2
local ROW_STEP = 13
local LABEL_X = WIN_X + 16
local GLYPH_X = WIN_X + 8
local VALUE_X = WIN_X + 0x82
local HELP_BG = { 0 / 255, 123 / 255, 197 / 255, 1 }

local TAB_LABEL = {
  "[MODS] PROFILES ERRORS",
  "MODS [PROFILES] ERRORS",
  "MODS PROFILES [ERRORS]",
}

local TITLE = {
  list = "MOD MANAGER",
  detail = "MOD DETAIL",
  options = "MOD OPTIONS",
  permissions = "PERMISSIONS",
  errors = "ERRORS",
  apply = "PENDING CHANGES",
}

local function mgr()
  return ModManager._mgr
end

local function helpText()
  local m = mgr()
  if not m then return "" end
  if m.overlay then
    return m.overlay.kind == "confirm"
        and "{DPAD_UPDOWN}PICK {A_BUTTON}OK {B_BUTTON}BACK"
      or "{A_BUTTON}{B_BUTTON}OK"
  end
  if m.screen == "options" then
    return "{DPAD_UPDOWN}PICK {DPAD_LEFTRIGHT}SWITCH {B_BUTTON}DONE"
  end
  if m.screen == "list" then
    return "{DPAD_UPDOWN}PICK {DPAD_LEFTRIGHT}TAB {A_BUTTON}OPEN {START_BUTTON}APPLY"
  end
  return "{DPAD_UPDOWN}PICK {A_BUTTON}OK {B_BUTTON}BACK"
end

local function drawHelpBar()
  love.graphics.setColor(HELP_BG)
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.setColor(1, 1, 1, 1)
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  PokedexChrome.drawControlInfo(Strings(helpText()), 0xE4, 0)
end

local function truncate(text, cols)
  text = tostring(text or "")
  if #text > cols then return text:sub(1, cols) end
  return text
end

local function frameType()
  local m = mgr()
  local game = m and m.game
  local engine = (game and game.options) or (game and game.save and game.save.options) or {}
  local ok, Options = pcall(require, "src.core.game3.options")
  if ok and Options and Options.block then
    local cart = Options.block(engine)
    return tonumber(cart and cart.frameType) or 0
  end
  return 0
end

local function scrollArrow(dir, x, y)
  local ok, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if ok and BagChrome and BagChrome.drawArrow then
    local drew, res = pcall(BagChrome.drawArrow, dir, x, y)
    if drew and res then return end
  end
  FrlgFont.drawGlyph(dir == "up" and FrlgFont.CHAR_UP_ARROW or FrlgFont.CHAR_DOWN_ARROW,
    x + 4, y + 1, { colors = FrlgFont.COLOR.RED })
end

local function bob(k, freq)
  local Trig = require("src.core.game3.trig")
  local v = Trig.sin(((k or 0) * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

local function valueColors()
  return { fg = FrlgFont.STDPAL[5], shadow = FrlgFont.STDPAL[4], bg = FrlgFont.STDPAL[0] }
end

-- Windowed slice of rows. List/detail own a sticky 7/4-row view here:
-- ManagerState clamps its scroll to LIST_ROWS=11 (Gen 1 density), which is
-- taller than this frame — following m.scroll would park the cursor off
-- screen and then snap. Options trust ManagerState's 0-based scroll
-- (OptionRows.clampScroll, window 4).
local function visibleWindow(m, rows)
  local n = #rows
  if m.screen == "options" then
    local window = 4
    local first = (m.scroll or 0) + 1
    if first < 1 then first = 1 end
    local maxFirst = math.max(1, n - window + 1)
    if first > maxFirst then first = maxFirst end
    return first, math.min(n, first + window - 1), window
  end
  local window = (m.screen == "detail") and 4 or VISIBLE
  local key = tostring(m.screen) .. ":" .. tostring(m.tab)
  if ModManager._viewKey ~= key then
    ModManager._viewKey = key
    ModManager._viewFirst = 1
  end
  local first = ModManager._viewFirst or 1
  local cursor = m.cursor or 1
  if cursor < first then
    first = cursor
  elseif cursor > first + window - 1 then
    first = cursor - window + 1
  end
  local maxFirst = math.max(1, n - window + 1)
  if first > maxFirst then first = maxFirst end
  if first < 1 then first = 1 end
  ModManager._viewFirst = first
  return first, math.min(n, first + window - 1), window
end

-- ManagerState opens Gen 1 NamingScreen / QuantityBox via game.stack:push.
-- Bridge those two onto Gen 3 chrome instead of dropping them on the floor.
local function bridgePush(state)
  local NamingScreen = require("src.ui.NamingScreen")
  local QuantityBox = require("src.ui.QuantityBox")
  local mt = getmetatable(state)
  if mt == NamingScreen then
    local onDone = state.onDone
    local Naming = require("src.ui.game3.naming")
    Naming.open({
      title = state.title,
      maxLen = state.maxLen,
      seed = state.default,
      onDone = function(name)
        -- Naming blank-OK can deliver nil; ManagerState's onDone assumes a string.
        if name == nil then return end
        if onDone then onDone(name) end
      end,
    })
    return true
  end
  if mt == QuantityBox then
    ModManager._prompt = {
      kind = "qty",
      title = Strings("HOW MANY?"),
      value = state.qty or 1,
      max = state.max or 99,
      onDone = state.onDone,
    }
    return true
  end
  return false
end

function ModManager.show(opts)
  opts = opts or {}
  local game = opts.game
  if not game then return end
  if ModManager.open then return end

  local realGame = game
  local proxy = setmetatable({
    stack = {
      pop = function() ModManager.close() end,
      push = function(_, state)
        if bridgePush(state) then return end
        local ok, Logger = pcall(require, "src.core.Logger")
        if ok and Logger and Logger.error then
          Logger.error("mod_manager: unsupported nested screen %s dropped",
            tostring(state))
        end
        ModManager._mgr:notify("UNSUPPORTED SCREEN")
      end,
    },
    -- APPLY & RESTART: soft-return to the Gen 3 launcher rather than quitting
    -- the process (ManagerState:restartGame falls through to love.event.quit).
    -- Close first: Game3:returnToTitle Stack.clear()s without resetting this
    -- module's open flag, and show() no-ops while open stays true.
    restartWithMods = function()
      ModManager.close()
      if realGame.returnToTitle then
        realGame:returnToTitle()
      elseif love.event and love.event.quit then
        love.event.quit("restart")
      end
    end,
  }, { __index = game })

  local m = ManagerState.new(proxy)
  m:enter()
  ModManager._mgr = m
  ModManager._game = game
  ModManager._onClose = opts.onClose
  ModManager.open = true
  ModManager._arrowK = 0
  ModManager._prompt = nil
  ModManager._viewKey = nil
  ModManager._viewFirst = 1
  Stack.push("mod_manager", ModManager, { hideBelow = true, fullscreen = true })
end

function ModManager.close()
  if not ModManager.open then return end
  ModManager.open = false
  ModManager._mgr = nil
  Stack.pop("mod_manager")
  local cb = ModManager._onClose
  ModManager._onClose = nil
  if cb then cb() end
end

function ModManager.isOpen()
  return ModManager.open
end

function ModManager.handleInput(input)
  local m = mgr()
  if not m or not input then return end
  local prompt = ModManager._prompt
  if prompt and prompt.kind == "qty" then
    if input:wasPressed("up") then
      prompt.value = prompt.value + 1
      if prompt.value > prompt.max then prompt.value = 1 end
    elseif input:wasPressed("down") then
      prompt.value = prompt.value - 1
      if prompt.value < 1 then prompt.value = prompt.max end
    elseif input:wasPressed("a") then
      local onDone = prompt.onDone
      ModManager._prompt = nil
      if onDone then onDone(prompt.value) end
    elseif input:wasPressed("b") then
      local onDone = prompt.onDone
      ModManager._prompt = nil
      if onDone then onDone(nil) end
    end
    return
  end
  -- ManagerState:update reads game.input:wasPressed (same surface as game3)
  m.game.input = input
  m:update()
end

function ModManager.update()
  if ModManager.open then
    ModManager._arrowK = (ModManager._arrowK or 0) + 1
  end
end

local function drawRows(m, rows, y0, step, labelX, glyphX)
  local first, last = visibleWindow(m, rows)
  local y = y0
  local vcol = valueColors()
  for i = first, last do
    local row = rows[i]
    if row then
      if row.header then
        Window.printPx(truncate(row.label, 22), labelX, y,
          { colors = FrlgFont.COLOR.DARK_GRAY })
      else
        if glyphX and row.glyph and row.glyph ~= " " then
          Window.printPx(row.glyph, glyphX, y, { colors = FrlgFont.COLOR.RED })
        end
        Window.printPx(truncate(row.label, 18), labelX, y,
          { colors = FrlgFont.COLOR.NORMAL })
        if row.value and m.screen == "options" then
          local ok, text = pcall(row.value, m.game)
          Window.printPx(ok and truncate(tostring(text), 8) or "----",
            VALUE_X, y, { colors = vcol })
        end
        if i == m.cursor then
          Window.cursorPx(glyphX and (glyphX - 8) or (labelX - 8), y)
        end
      end
      y = y + step
    end
  end
  return first, last
end

local function drawDetailBody(m)
  local mod = m.currentMod
  if not mod then return end
  local lines = {}
  local function push(s) lines[#lines + 1] = truncate(s, 24) end
  push((mod.name or mod.id) .. " " .. (mod.version or ""))
  push((mod.enabled and "ENABLED" or "DISABLED")
    .. (m:isStaged(mod) and " (STAGED)" or ""))
  push((mod.category or "OTHER") .. "/" .. (mod.profile or "content"))
  local body = mod.error and ("FAILED: " .. mod.error)
    or mod.note and ("SKIPPED: " .. mod.note)
    or mod.description or ""
  for paragraph in tostring(body):gmatch("[^\n]+") do
    push(paragraph)
  end
  local rows = m:rowsForScreen()
  -- header block occupies the top of the content window
  local y = ROW_Y0
  for i = 1, math.min(3, #lines) do
    Window.printPx(lines[i], LABEL_X, y, { colors = FrlgFont.COLOR.DARK_GRAY })
    y = y + ROW_STEP
  end
  drawRows(m, rows, y + 2, ROW_STEP, LABEL_X, nil)
end

local function drawOverlay(m)
  local overlay = m.overlay
  if not overlay then return end
  local lines = overlay.lines or {}
  local h = 4 + #lines + (overlay.kind == "confirm" and 2 or 1)
  if h < 5 then h = 5 end
  local y = math.floor((160 - h * 8) / 2 / 8)
  Window.dialogueFrame()
  local ty = 2
  for i, line in ipairs(lines) do
    Window.printPx(truncate(line, 26), 2 * 8 + 4, (ty + i) * 8 - 6,
      { colors = FrlgFont.COLOR.NORMAL })
  end
  if overlay.kind == "confirm" then
    local yesY = (ty + #lines + 1) * 8 - 6
    Window.cursorPx(5 * 8, (overlay.index == 1 and yesY or yesY + 12))
    Window.printPx(Strings("YES"), 5 * 8 + 8, yesY, { colors = FrlgFont.COLOR.NORMAL })
    Window.printPx(Strings("NO"), 5 * 8 + 8, yesY + 12, { colors = FrlgFont.COLOR.NORMAL })
  else
    Window.printPx(Strings("A:OK"), 5 * 8, (ty + #lines + 1) * 8 - 6,
      { colors = FrlgFont.COLOR.NORMAL })
  end
end

local function drawQtyPrompt(p)
  Window.dialogueFrame()
  Window.printPx(truncate(p.title or "HOW MANY?", 24), 2 * 8 + 4, 16 * 8,
    { colors = FrlgFont.COLOR.NORMAL })
  Window.printPx(tostring(p.value), 12 * 8, 18 * 8, { colors = valueColors() })
  Window.cursorPx(10 * 8, 18 * 8)
  Window.printPx(Strings("{A_BUTTON}OK {B_BUTTON}CANCEL"), 2 * 8 + 4, 20 * 8,
    { colors = FrlgFont.COLOR.NORMAL })
end

function ModManager.draw()
  if not ModManager.open then return end
  local m = mgr()
  if not m then return end

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  drawHelpBar()

  local list = m.screen == "list"
  -- option_menu geometry: help bar 0..16, title content tiles (2,3,26,2)
  -- (outer border y 16..48), content tiles (2,7,26,12) (outer y 48..160).
  local title
  if list then
    -- Tab state lives on the title line; a third frame would overlap.
    title = m.banner or TAB_LABEL[m.tab] or TAB_LABEL[1]
  else
    title = m.banner or TITLE[m.screen] or Strings("MOD MANAGER")
  end
  Chrome.fixedStdFrame(2, 3, 26, 2)
  Window.printPx(truncate(title, 24), 16 + 8, 24 + 1,
    { colors = FrlgFont.COLOR.NORMAL })

  Window.userFrame(Window.template(2, 7, 26, 12), frameType())

  if m.screen == "detail" then
    drawDetailBody(m)
  elseif m.screen == "options" then
    local rows = m.optionRows or {}
    drawRows(m, rows, ROW_Y0, ROW_STEP, LABEL_X, nil)
  else
    local rows = m:rowsForScreen()
    drawRows(m, rows, ROW_Y0, ROW_STEP, LABEL_X, GLYPH_X)
  end

  local k = ModManager._arrowK or 0
  local rows = m.screen == "options" and (m.optionRows or {}) or m:rowsForScreen()
  local first, last = visibleWindow(m, rows)
  if first > 1 then
    scrollArrow("up", 208, WIN_Y + bob(k, 8))
  end
  if last < #rows then
    scrollArrow("down", 208, WIN_Y + WIN_H - 16 + bob(k, -8))
  end

  if m.notice then
    Window.printPx(truncate(m.notice, 26), 16, 148, { colors = FrlgFont.COLOR.RED })
  end
  drawOverlay(m)
  if ModManager._prompt and ModManager._prompt.kind == "qty" then
    drawQtyPrompt(ModManager._prompt)
  end
end

return ModManager
