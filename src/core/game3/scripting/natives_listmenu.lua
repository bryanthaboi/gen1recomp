local Std = require("src.core.game3.scripting.stdscripts")

local ListMenu = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319

local SCR_MENU_CANCEL = 0x7F -- pokefirered/include/constants/menu.h:4
local SE_SELECT = 5 -- pokefirered/include/constants/songs.h:9

-- pokefirered/include/constants/menu.h:75
local LISTMENU_BADGES = 0
local LISTMENU_SILPHCO_FLOORS = 1
local LISTMENU_ROCKET_HIDEOUT_FLOORS = 2
local LISTMENU_DEPT_STORE_FLOORS = 3
local LISTMENU_WIRELESS_LECTURE_HEADERS = 4
local LISTMENU_BERRY_POWDER = 5
local LISTMENU_TRAINER_TOWER_FLOORS = 6

ListMenu.LISTMENU_BADGES = LISTMENU_BADGES
ListMenu.LISTMENU_SILPHCO_FLOORS = LISTMENU_SILPHCO_FLOORS
ListMenu.LISTMENU_BERRY_POWDER = LISTMENU_BERRY_POWDER

-- pokefirered/src/field_specials.c:1164
local LAYOUTS = {
  [LISTMENU_BADGES] = { maxShowed = 4, count = 9, left = 1, top = 1, height = 7, keepOpen = true },
  [LISTMENU_SILPHCO_FLOORS] = { maxShowed = 7, count = 12, left = 1, top = 1, height = 12, keepOpen = false },
  [LISTMENU_ROCKET_HIDEOUT_FLOORS] = { maxShowed = 4, count = 4, left = 1, top = 1, height = 8, keepOpen = false },
  [LISTMENU_DEPT_STORE_FLOORS] = { maxShowed = 4, count = 6, left = 1, top = 1, height = 8, keepOpen = false },
  [LISTMENU_WIRELESS_LECTURE_HEADERS] = { maxShowed = 4, count = 4, left = 1, top = 1, height = 8, keepOpen = true },
  [LISTMENU_BERRY_POWDER] = { maxShowed = 7, count = 12, left = 16, top = 1, height = 12, keepOpen = false },
  [LISTMENU_TRAINER_TOWER_FLOORS] = { maxShowed = 3, count = 3, left = 1, top = 1, height = 6, keepOpen = false },
}
ListMenu.LAYOUTS = LAYOUTS

-- pokefirered/src/field_specials.c:1257 sListMenuLabels
local EXT_CLEAR_TO = 0x13

local function clearToLabel(key)
  local RomText = require("src.core.game3.rom_text")
  local TextIR = require("src.core.game3.scripting.text_ir")
  local ir = RomText.translate(RomText.ir(key), {}, key)
  for i, seg in ipairs(ir) do
    if seg.t == "ext" and seg.cmd == EXT_CLEAR_TO then
      local head, tail = {}, {}
      for j = 1, i - 1 do head[#head + 1] = ir[j] end
      for j = i + 1, #ir do tail[#tail + 1] = ir[j] end
      return {
        text = TextIR.toPlain(head, {}),
        clearTo = seg.args[1],
        tail = TextIR.toPlain(tail, {}),
      }
    end
  end
  return RomText.plain(key)
end

local function labelsFor(kind)
  local count = LAYOUTS[kind] and LAYOUTS[kind].count
  if not count then return nil end
  local RomText = require("src.core.game3.rom_text")
  local labels = {}
  for i = 0, count - 1 do
    local key = RomText.key("sListMenuLabels", kind, i)
    if kind == LISTMENU_BERRY_POWDER then
      labels[i + 1] = clearToLabel(key)
    else
      labels[i + 1] = RomText.plain(key)
    end
  end
  return labels
end
ListMenu.labelsFor = labelsFor

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local rt = package.loaded["src.core.game3.runtime"]
  local session = rt and rt.getSession and rt.getSession()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(), ctx, VAR_RESULT, tonumber(value) or 0)
end

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local Menu = {}
ListMenu.Menu = Menu

Menu.open = false
Menu.labels = nil
Menu.scroll = 0
Menu.row = 1
Menu.maxShowed = 1
Menu.left = 1
Menu.top = 1
Menu._onPick = nil

local STACK_ID = "script_list_menu"

-- pokefirered/src/strings.c:585 {FONT_SMALL}
local SMALL_FONT = { small = true }

-- pokefirered/src/text.c:147
local LIST_ROW_H = 14

local _font = nil
local function frlgFont()
  if _font == nil then
    local okF, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
    _font = (okF and FrlgFont) or false
  end
  return _font or nil
end

local _window = nil
local function windowMod()
  if _window == nil then
    local okW, Window = pcall(require, "src.ui.game3.window")
    _window = (okW and Window) or false
  end
  return _window or nil
end

local function textWidth(text)
  local FrlgFont = frlgFont()
  if FrlgFont and FrlgFont.measure then
    local okM, w = pcall(FrlgFont.measure, text)
    if okM and tonumber(w) then return tonumber(w) end
  end
  return #tostring(text) * 6
end

-- pokefirered/src/strings.c:585
local function measure(label)
  if type(label) == "table" then
    -- pokefirered/src/daycare.c:1482
    if label.tailRight then return label.tailRight end
    return math.max(textWidth(label.text), (label.clearTo or 0) + textWidth(label.tail))
  end
  return textWidth(label)
end

-- pokefirered/src/field_specials.c:1355
local function windowWidth(labels)
  local mwidth = 0
  for _, label in ipairs(labels) do
    local w = measure(label)
    if w > mwidth then mwidth = w end
  end
  return math.floor((mwidth + 9) / 8) + 1
end

function Menu.isOpen()
  return Menu.open == true
end

function Menu.showItems(kind, labels, layout, scroll, cursor, onPick)
  if not (layout and labels) then return false end
  Menu.kind = kind
  Menu.labels = labels
  Menu.count = layout.count
  Menu.maxShowed = math.min(layout.maxShowed, layout.count)
  Menu.keepOpen = layout.keepOpen
  Menu.scroll = math.max(0, math.min(tonumber(scroll) or 0, layout.count - Menu.maxShowed))
  Menu.row = math.max(1, math.min((tonumber(cursor) or 0) + 1, Menu.maxShowed))
  Menu.width = layout.width or windowWidth(labels)
  Menu.left = layout.left
  -- pokefirered/src/field_specials.c:1356
  if Menu.left + Menu.width > 29 then Menu.left = 29 - Menu.width end
  Menu.top = layout.top
  Menu.height = layout.height
  Menu.arrowK = 0
  Menu._onPick = onPick
  Menu.open = true
  local okS, Stack = pcall(require, "src.ui.game3.stack")
  if not (okS and Stack) then
    Menu.open = false
    if onPick then onPick(SCR_MENU_CANCEL, false) end
    return true
  end
  Stack.push(STACK_ID, Menu, { hideBelow = false, drawUnder = true })
  return true
end

function Menu.show(kind, scroll, cursor, onPick)
  return Menu.showItems(kind, labelsFor(kind), LAYOUTS[kind], scroll, cursor, onPick)
end

function Menu.close()
  Menu.open = false
  Menu._onPick = nil
  local okS, Stack = pcall(require, "src.ui.game3.stack")
  if okS and Stack then Stack.pop(STACK_ID) end
end

function Menu.selection()
  return Menu.scroll + Menu.row - 1
end

function Menu.move(delta)
  if not Menu.open then return end
  if delta < 0 then
    if Menu.row > 1 then
      Menu.row = Menu.row - 1
      se(SE_SELECT)
    elseif Menu.scroll > 0 then
      Menu.scroll = Menu.scroll - 1
      se(SE_SELECT)
    end
  elseif delta > 0 then
    if Menu.row < Menu.maxShowed and Menu.selection() + 1 < Menu.count then
      Menu.row = Menu.row + 1
      se(SE_SELECT)
    elseif Menu.scroll + Menu.maxShowed < Menu.count then
      Menu.scroll = Menu.scroll + 1
      se(SE_SELECT)
    end
  end
end

-- pokefirered/src/field_specials.c:1407 Task_ListMenuHandleInput
function Menu.confirm()
  if not Menu.open then return end
  local index = Menu.selection()
  local keepOpen = Menu.keepOpen and index ~= (Menu.count - 1)
  local cb = Menu._onPick
  local scroll, row = Menu.scroll, Menu.row
  se(SE_SELECT)
  Menu.close()
  if keepOpen then
    Menu.scroll, Menu.row = scroll, row
  end
  if cb then cb(index, keepOpen) end
end

function Menu.cancel()
  if not Menu.open then return end
  local cb = Menu._onPick
  se(SE_SELECT)
  Menu.close()
  if cb then cb(SCR_MENU_CANCEL, false) end
end

function Menu.handleInput(input)
  if not (Menu.open and input) then return end
  if input:wasPressed("up") then Menu.move(-1)
  elseif input:wasPressed("down") then Menu.move(1)
  elseif input:wasPressed("a") then Menu.confirm()
  elseif input:wasPressed("b") then Menu.cancel()
  end
end

function Menu.update()
  if Menu.open then Menu.arrowK = (Menu.arrowK or 0) + 1 end
end

local function arrowBob(freq)
  local Trig = require("src.core.game3.trig")
  local v = Trig.sin(((Menu.arrowK or 0) * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

-- pokefirered/src/field_specials.c:1485 Task_CreateMenuRemoveScrollIndicatorArrowPair
local function drawScrollArrows()
  if Menu.maxShowed == Menu.count then return end
  local okB, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  if not (okB and BagChrome and BagChrome.drawArrow) then return end
  local x = 4 * Menu.width + 8 * Menu.left
  if Menu.scroll > 0 then
    BagChrome.drawArrow("up", x - 8, arrowBob(8))
  end
  if Menu.scroll < Menu.count - Menu.maxShowed then
    BagChrome.drawArrow("down", x - 8, 8 * Menu.height + 10 - 8 + arrowBob(-8))
  end
end

function Menu.draw()
  if not (Menu.open and Menu.labels) then return end
  local Window = windowMod()
  if not Window then return end
  local rows = Menu.maxShowed
  local th = Menu.height or math.max(2, math.ceil((rows * LIST_ROW_H) / 8))
  Window.stdFrame(Window.template(Menu.left, Menu.top, Menu.width, th))
  local leftPx = Menu.left * 8
  local topPx = Menu.top * 8
  for i = 1, rows do
    local label = Menu.labels[Menu.scroll + i]
    if label then
      local yPx = topPx + (i - 1) * LIST_ROW_H
      local textPx = leftPx + Window.CURSOR_WIDTH
      if i == Menu.row then Window.cursorPx(leftPx, yPx) end
      if type(label) == "table" and label.tailRight then
        -- pokefirered/src/daycare.c:1486
        Window.printPx(label.text, leftPx + (label.textX or 8), yPx)
        if label.tail and label.tail ~= "" then
          Window.printPx(label.tail,
            leftPx + label.tailRight - textWidth(label.tail), yPx)
        end
      elseif type(label) == "table" then
        Window.printPx(label.text, textPx, yPx)
        local FrlgFont = frlgFont()
        if FrlgFont and FrlgFont.draw then
          pcall(FrlgFont.draw, tostring(label.tail), textPx + (label.clearTo or 0), yPx,
            SMALL_FONT)
        end
      else
        Window.printPx(label, textPx, yPx)
      end
    end
  end
  drawScrollArrows()
end

ListMenu._suspended = nil

local function present(ctx, kind, scroll, cursor)
  local Natives = require("src.core.game3.scripting.natives")
  local done = false
  Natives.awaitState(ctx, function() return done end)
  local shown = Menu.show(kind, scroll, cursor, function(index, keepOpen)
    setResult(ctx, index)
    ListMenu._suspended = keepOpen and { kind = kind, scroll = Menu.scroll, row = Menu.row } or nil
    done = true
  end)
  if not shown then
    -- pokefirered/src/field_specials.c:1250
    setResult(ctx, SCR_MENU_CANCEL)
    done = true
  end
  return false
end

-- pokefirered/src/daycare.c:1531 ShowDaycareLevelMenu
function ListMenu.presentItems(ctx, key, labels, layout, onPick)
  local Natives = require("src.core.game3.scripting.natives")
  local done = false
  Natives.awaitState(ctx, function() return done end)
  local shown = Menu.showItems(key, labels, layout, 0, 0, function(index)
    if onPick then onPick(index) end
    done = true
  end)
  if not shown then
    if onPick then onPick(SCR_MENU_CANCEL) end
    done = true
  end
  return false
end

ListMenu.HANDLERS = {
  -- pokefirered/src/field_specials.c:1164
  [Std.SPECIAL.ListMenu] = function(ctx)
    local kind = varGet(ctx, VAR_0x8004)
    local scroll, cursor = 0, 0
    if kind == LISTMENU_SILPHCO_FLOORS then
      scroll = tonumber(ListMenu.elevatorScroll) or 0
      cursor = tonumber(ListMenu.elevatorCursorPos) or 0
    end
    ListMenu._suspended = nil
    return present(ctx, kind, scroll, cursor)
  end,
  -- pokefirered/src/field_specials.c:1469 ReturnToListMenu
  [Std.SPECIAL.ReturnToListMenu] = function(ctx)
    local state = ListMenu._suspended
    if not state then return false end
    return present(ctx, state.kind, state.scroll, state.row - 1)
  end,
}

return ListMenu
