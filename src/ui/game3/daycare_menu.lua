-- pokefirered/src/daycare.c:1531

local Strings = require("src.core.Strings")

local DaycareMenu = {}

local DAYCARE_MON_COUNT = 2 -- pokefirered/include/constants/global.h:34
local DAYCARE_LEVEL_MENU_EXIT = 5 -- pokefirered/include/constants/daycare.h:20
local SE_SELECT = 5 -- pokefirered/include/constants/songs.h:9
local STACK_ID = "daycare_level_menu"

-- pokefirered/src/daycare.c:86 sDaycareLevelMenuWindowTemplate
DaycareMenu.WINDOW = { left = 12, top = 1, width = 17, height = 5 }
-- pokefirered/src/new_menu_helpers.c:91 FONT_NORMAL_COPY_2 maxLetterHeight
DaycareMenu.ROW_PITCH = 14
-- pokefirered/src/daycare.c:113 .item_X
DaycareMenu.TEXT_X = 8
-- pokefirered/src/daycare.c:1482
DaycareMenu.LEVEL_RIGHT = 132
DaycareMenu.ROW_COUNT = 3
DaycareMenu.DAYCARE_LEVEL_MENU_EXIT = DAYCARE_LEVEL_MENU_EXIT

DaycareMenu.open = false
DaycareMenu.rowList = nil
DaycareMenu.cursor = 1
DaycareMenu._onPick = nil

local _stack = nil
local function stackMod()
  if _stack == nil then
    local ok, Stack = pcall(require, "src.ui.game3.stack")
    _stack = (ok and Stack) or false
  end
  return _stack or nil
end

local _window = nil
local function windowMod()
  if _window == nil then
    local ok, Window = pcall(require, "src.ui.game3.window")
    _window = (ok and Window) or false
  end
  return _window or nil
end

local _font = nil
local function frlgFont()
  if _font == nil then
    local ok, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    _font = (ok and FrlgFont) or false
  end
  return _font or nil
end

local function daycareMod()
  return package.loaded["src.core.game3.daycare"] or require("src.core.game3.daycare")
end

local function pokemonMod()
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon
end

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

function DaycareMenu.textWidth(text)
  local FrlgFont = frlgFont()
  if FrlgFont and FrlgFont.measure then
    local ok, w = pcall(FrlgFont.measure, text)
    if ok and tonumber(w) then return tonumber(w) end
  end
  return #tostring(text) * 6
end

-- pokefirered/src/daycare.c:1357 NameHasGenderSymbol
function DaycareMenu.nameHasGenderSymbol(name, gender)
  local males, females = 0, 0
  for _ in tostring(name or ""):gmatch("♂") do males = males + 1 end
  for _ in tostring(name or ""):gmatch("♀") do females = females + 1 end
  if gender == "M" then return males ~= 0 and females == 0 end
  if gender == "F" then return females ~= 0 and males == 0 end
  return false
end

-- pokefirered/src/daycare.c:1379 AppendGenderSymbol
function DaycareMenu.genderSymbol(name, gender)
  if gender == "M" then
    if not DaycareMenu.nameHasGenderSymbol(name, "M") then return "♂" end
  elseif gender == "F" then
    if not DaycareMenu.nameHasGenderSymbol(name, "F") then return "♀" end
  end
  -- pokefirered/src/trade.c:527 gText_GenderlessSymbol
  return ""
end

-- pokefirered/src/daycare.c:1486 DaycarePrintMonInfo
function DaycareMenu.rows(dc)
  local Daycare = daycareMod()
  local Pokemon = pokemonMod()
  local rows = {}
  for i = 1, DAYCARE_MON_COUNT do
    local mon = Daycare.mon(dc, i)
    local name = mon and Daycare.nickname(mon) or ""
    local species = tonumber(mon and (mon.species or mon.speciesId)) or 0
    local gender = mon and Pokemon.gender(species, mon.personality) or "U"
    local level = ""
    if mon then
      -- pokefirered/src/daycare.c:1479 GetLevelAfterDaycareSteps
      level = Strings("Lv%s",
        tostring(Daycare.levelAfterSteps(mon, dc and dc.steps and dc.steps[i])))
    end
    rows[i] = {
      value = i - 1,
      text = name,
      symbol = mon and DaycareMenu.genderSymbol(name, gender) or "",
      level = level,
    }
  end
  -- pokefirered/src/daycare.c:97 sLevelMenuItems
  rows[DaycareMenu.ROW_COUNT] = {
    value = DAYCARE_LEVEL_MENU_EXIT, text = Strings("EXIT"), symbol = "", level = "",
  }
  return rows
end

-- pokefirered/src/daycare.c:1464
function DaycareMenu.label(row)
  if not row then return "" end
  return tostring(row.text or "") .. tostring(row.symbol or "")
end

-- pokefirered/src/daycare.c:1482
function DaycareMenu.levelX(row)
  local text = row and row.level or ""
  if text == "" then return nil end
  return DaycareMenu.LEVEL_RIGHT - DaycareMenu.textWidth(text)
end

function DaycareMenu.isOpen()
  return DaycareMenu.open == true
end

function DaycareMenu.show(dc, onPick)
  local Stack = stackMod()
  if not Stack then return false end
  DaycareMenu.rowList = DaycareMenu.rows(dc)
  for _, row in ipairs(DaycareMenu.rowList) do
    row.labelText = DaycareMenu.label(row)
    row.levelXPx = DaycareMenu.levelX(row) or false
  end
  DaycareMenu.cursor = 1
  DaycareMenu._onPick = onPick
  DaycareMenu.open = true
  Stack.push(STACK_ID, DaycareMenu, { hideBelow = false, drawUnder = true })
  return true
end

function DaycareMenu.close()
  DaycareMenu.open = false
  DaycareMenu._onPick = nil
  local Stack = stackMod()
  if Stack then Stack.pop(STACK_ID) end
end

-- pokefirered/src/list_menu.c:620 ListMenuDefaultCursorMoveFunc
function DaycareMenu.move(delta)
  if not DaycareMenu.open then return end
  local want = DaycareMenu.cursor + delta
  if want < 1 or want > DaycareMenu.ROW_COUNT then return end
  DaycareMenu.cursor = want
  se(SE_SELECT)
end

-- pokefirered/src/daycare.c:1504
function DaycareMenu.confirm()
  if not DaycareMenu.open then return end
  local row = DaycareMenu.rowList and DaycareMenu.rowList[DaycareMenu.cursor]
  local cb = DaycareMenu._onPick
  local value = row and row.value
  DaycareMenu.close()
  if cb then cb(value) end
end

-- pokefirered/src/daycare.c:1521
function DaycareMenu.cancel()
  if not DaycareMenu.open then return end
  local cb = DaycareMenu._onPick
  DaycareMenu.close()
  if cb then cb(nil) end
end

-- pokefirered/src/daycare.c:1498 Task_HandleDaycareLevelMenuInput
function DaycareMenu.handleInput(input)
  if not (DaycareMenu.open and input) then return end
  if input:wasPressed("a") then DaycareMenu.confirm()
  elseif input:wasPressed("b") then DaycareMenu.cancel()
  elseif input:wasPressed("up") then DaycareMenu.move(-1)
  elseif input:wasPressed("down") then DaycareMenu.move(1)
  end
end

local _template = nil

function DaycareMenu.draw()
  if not (DaycareMenu.open and DaycareMenu.rowList) then return end
  local Window = windowMod()
  if not Window then return end
  local W = DaycareMenu.WINDOW
  if not _template then
    _template = Window.template(W.left, W.top, W.width, W.height)
  end
  -- pokefirered/src/daycare.c:1539 DrawStdWindowFrame
  Window.stdFrame(_template)
  local leftPx, topPx = W.left * 8, W.top * 8
  for i = 1, DaycareMenu.ROW_COUNT do
    local row = DaycareMenu.rowList[i]
    if row then
      local yPx = topPx + (i - 1) * DaycareMenu.ROW_PITCH
      -- pokefirered/src/daycare.c:114 .cursor_X
      if i == DaycareMenu.cursor then Window.cursorPx(leftPx, yPx) end
      Window.printPx(row.labelText or DaycareMenu.label(row), leftPx + DaycareMenu.TEXT_X, yPx)
      local levelX = row.levelXPx
      if levelX == nil then levelX = DaycareMenu.levelX(row) end
      if levelX then Window.printPx(row.level, leftPx + levelX, yPx) end
    end
  end
end

return DaycareMenu
