--   luajit tests/engine/gen2_ui_layout_option.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
require("src.core.Logger").warn = function() end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Save = require("src.core.gen2.Save")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Chrome = require("src.ui.gen2.Chrome")
local StartMenu = require("src.ui.gen2.StartMenu")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local Game2 = require("src.core.Game2")

local function newStack()
  return setmetatable({ states = {} }, { __index = StateStack })
end

eq(Save.DEFAULT_OPTIONS.uiLayout, "centered", "a Gen 2 save starts CENTERED")
eq(Save.defaultOptions().uiLayout, "centered", "and the loaded defaults carry it")

local row
for _, r in ipairs(OptionsMenu.ROWS) do
  if r.key == "uiLayout" then row = r end
end
check(row ~= nil, "Gen 2 OPTIONS has a UI LAYOUT row")
eq(row and row.label, "UI LAYOUT", "labelled as on Gen 1")
eq(row and table.concat(row.values, ","), "centered,dynamic", "CENTERED then DYNAMIC")
eq(row and row.port, true, "marked as a port option")

do
  local menuGame = { input = { wasPressed = function() return false end },
    save = Save.newGame(), stack = newStack() }
  local menu = OptionsMenu.new(menuGame, { options = Save.defaultOptions() })
  local page = menu:focusRow("uiLayout")
  eq(page and page:row().key, "uiLayout", "UI LAYOUT sits on a group page")
end

do
  local LauncherSettings = require("src.import.LauncherSettings")
  for _, version in ipairs({ "gold", "silver", "crystal" }) do
    local model = LauncherSettings.open({}, version)
    local found
    for _, section in ipairs(model.sections) do
      for _, r in ipairs(section.rows) do
        if r.label == "UI LAYOUT" then found = r end
      end
    end
    check(found ~= nil, version .. " launcher gear offers UI LAYOUT")
    if found then
      eq(found.value(), "CENTERED", version .. " UI LAYOUT reads CENTERED by default")
      found.step(1)
      eq(model.opts.gold.uiLayout, "dynamic", version .. " stepping it stores dynamic in the gold block")
      found.step(1)
      eq(model.opts.gold.uiLayout, "centered", version .. " and steps back")
    end
  end
end

local g = love.graphics
local dims, pdims = g.getDimensions, g.getPixelDimensions
local function window(w, h)
  g.getDimensions = function() return w, h end
  g.getPixelDimensions = function() return w, h end
end

local function fakeGame(layout, states)
  local stack = newStack()
  for _, s in ipairs(states or {}) do stack.states[#stack.states + 1] = s end
  return { options = { uiLayout = layout }, stack = stack }
end

local function whole(v) return v == math.floor(v) end

for _, win in ipairs({ { 1280, 720 }, { 1000, 700 }, { 960, 544 }, { 1366, 768 }, { 1100, 650 } }) do
  local w, h = win[1], win[2]
  window(w, h)
  local tag = ("%dx%d"):format(w, h)
  local s = Chrome.fitScale(w, h)
  local ox, oy = Chrome.fitOrigin(w, h, s)
  eq(Game2.uiDock(fakeGame("centered"), w, h, s, ox, oy), nil, tag .. ": CENTERED docks nothing")
  eq(Game2.uiDock(fakeGame(nil), w, h, s, ox, oy), nil, tag .. ": a missing option is CENTERED")
  local dock = Game2.uiDock(fakeGame("dynamic"), w, h, s, ox, oy)
  check(dock ~= nil, tag .. ": DYNAMIC docks")
  if dock then
    check(whole(dock.dx) and whole(dock.dy) and whole(dock.dt),
      tag .. ": every dock offset is whole GB pixels, so a shader grid keeps its phase")
    local right = ox + (dock.dx + 160) * s
    local bottom = oy + (dock.dy + 144) * s
    local top = oy + dock.dt * s
    check(right <= w and right > w - s, tag .. ": the right dock ends within one GB pixel of the window edge")
    check(bottom <= h and bottom > h - s, tag .. ": the bottom dock ends within one GB pixel of the window edge")
    check(top >= 0 and top < s, tag .. ": the right dock starts within one GB pixel of the top edge")
    eq(dock.clipRow, nil, tag .. ": nothing clips the START box with no text box up")
  end
end

do
  local save = Save.newGame()
  local dock = Game2.uiDock(fakeGame("dynamic", { {}, SaveMenu.new({ save = save },
    { save = save, existed = false }) }), 1280, 720, 5, 240, 0)
  eq(dock and dock.clipRow, 12, "the save screen clips the START box at row 12")
  local box = setmetatable({}, TextBox)
  dock = Game2.uiDock(fakeGame("dynamic", { {}, box }), 1280, 720, 5, 240, 0)
  eq(dock and dock.clipRow, 12, "a text box over the START menu clips it at row 12")
end

local tx, ty, stackT = 0, 0, {}
local realPush, realPop, realTranslate = g.push, g.pop, g.translate
g.push = function(...) stackT[#stackT + 1] = { tx, ty } return realPush(...) end
g.pop = function(...)
  local top = table.remove(stackT)
  tx, ty = top[1], top[2]
  return realPop(...)
end
g.translate = function(x, y) tx, ty = tx + x, ty + y end

local drawn
local realBox, realTextbox, realFill = Chrome.box, Chrome.textbox, Chrome.paletteFill
Chrome.box = function(x, y, bw, bh)
  drawn[#drawn + 1] = { kind = "box", x = x, y = y, w = bw, h = bh, dx = tx, dy = ty }
end
Chrome.textbox = function(x, y, bw, bh)
  drawn[#drawn + 1] = { kind = "textbox", x = x, y = y, w = bw, h = bh, dx = tx, dy = ty }
end
Chrome.paletteFill = function(x, y, bw, bh)
  drawn[#drawn + 1] = { kind = "fill", x = x, y = y, w = bw, h = bh, dx = tx, dy = ty }
end
local function find(kind, x, y)
  for _, d in ipairs(drawn) do
    if d.kind == kind and d.x == x and d.y == y then return d end
  end
end

local DOCK = { dx = 48, dy = 7, dt = -3, clipRow = nil }
local save = Save.newGame()
save.options = Save.defaultOptions()
local menuGame = { input = { wasPressed = function() return false end }, save = save }
local menu = StartMenu.new(menuGame, { save = save })

drawn, Chrome.dock = {}, nil
menu:draw()
local start = find("box", 10, 0)
check(start ~= nil and start.dx == 0 and start.dy == 0, "CENTERED: the START box stays in the letterbox")
local account = find("fill", 0, 13 * 8)
check(account ~= nil and account.dx == 0 and account.dy == 0,
  "CENTERED: the MENU ACCOUNT box stays in the letterbox")

drawn, Chrome.dock = {}, DOCK
menu:draw()
start = find("box", 10, 0)
check(start ~= nil and start.dx == DOCK.dx and start.dy == DOCK.dt,
  "DYNAMIC: the START box moves to the top right corner")
account = find("fill", 0, 13 * 8)
check(account ~= nil and account.dx == 0 and account.dy == DOCK.dy,
  "DYNAMIC: the MENU ACCOUNT box keeps the centred x on the bottom edge")

local panel = SaveMenu.new(menuGame, { save = save, existed = false })
drawn = {}
panel:draw()
local p = find("box", 4, 0)
check(p ~= nil and p.dx == DOCK.dx and p.dy == DOCK.dt, "DYNAMIC: the save panel moves to the top right corner")
local speech = find("textbox", 0, 12)
check(speech ~= nil and speech.dx == 0 and speech.dy == DOCK.dy,
  "DYNAMIC: the save text box keeps the centred x on the bottom edge")
panel.typedPhase, panel.pages, panel.page, panel.typer = panel.phase, { { "" } }, 1, nil
check(panel:yesNoVisible(), "the save YES/NO is up")
drawn = {}
panel:draw()
local yn = find("box", 0, 7)
check(yn ~= nil and yn.dx == 0 and yn.dy == DOCK.dy,
  "DYNAMIC: the save YES/NO rides the text box")

Chrome.dock = nil
drawn = {}
panel:draw()
p = find("box", 4, 0)
check(p ~= nil and p.dx == 0 and p.dy == 0, "CENTERED: the save panel stays in the letterbox")

do
  local game = fakeGame("dynamic")
  local bottomBox = setmetatable({ anchor = "bottom" }, ChoiceBox)
  local bareChoice = setmetatable({}, ChoiceBox)
  local seen = {}
  local function probe(name, mt)
    return setmetatable({ draw = function() seen[name] = { tx, ty } end }, mt)
  end
  local tb = setmetatable({ draw = function() seen.text = { tx, ty } end }, TextBox)
  bottomBox.draw = function() seen.yesno = { tx, ty } end
  bareChoice.draw = function() seen.bare = { tx, ty } end
  local windows = {
    "ScriptMenu", "MartMenu", "CenterPcMenu", "ItemPcMenu", "ElevatorMenu", "CallerBox",
    "MapRadio", "BankOfMom", "DayCareMenu", "MailboxMenu", "HeldItemMenu", "MoveDeleter",
    "TradeMenu", "DecorationMenu", "BuenaPassword", "BattleTowerMenu",
  }
  local states = { probe("start", StartMenu), probe("save", SaveMenu), tb, bottomBox, bareChoice }
  for _, name in ipairs(windows) do
    states[#states + 1] = probe(name, require("src.ui.gen2." .. name))
  end
  for _, s in ipairs(states) do
    game.stack.states[#game.stack.states + 1] = s
  end
  Chrome.dock = { dx = 48, dy = 7 }
  tx, ty = 0, 0
  Game2.drawDockedStack(game)
  Chrome.dock = nil
  check(seen.start and seen.start[1] == 0 and seen.start[2] == 0,
    "the START menu docks its own pieces")
  check(seen.save and seen.save[1] == 0 and seen.save[2] == 0, "so does the save panel")
  check(seen.text and seen.text[1] == 0 and seen.text[2] == 7, "the dialogue box docks to the bottom edge")
  check(seen.yesno and seen.yesno[1] == 0 and seen.yesno[2] == 7, "its YES/NO rides with it")
  check(seen.bare and seen.bare[1] == 0 and seen.bare[2] == 7,
    "a bare YES/NO keeps its cart rows over the docked text box")
  for _, name in ipairs(windows) do
    local at = seen[name]
    check(at and at[1] == 0 and at[2] == 7, name .. " shares the docked text box's rows")
  end
end

Chrome.box, Chrome.textbox, Chrome.paletteFill = realBox, realTextbox, realFill
g.push, g.pop, g.translate = realPush, realPop, realTranslate
g.getDimensions, g.getPixelDimensions = dims, pdims

T.finish("gen2 ui layout option")
