-- engine/pokemon/bills_pc.asm:176
-- :118 PokeballTileGraphics; data/text/text_3.asm:30
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local Menu = require("src.ui.Menu")
local Theme = require("src.ui.Theme")
local BoxMenu = require("src.ui.BoxMenu")
local Boxes = require("src.pokemon.Boxes")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function stubGame()
  local game = { data = Data, save = SaveData.newGame() }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    wasPressed = function() return false end,
    isDown = function() return false end,
  }
  return game
end

-- home/window.asm:198
local cursors
local realDrawCode = Font.drawCode
Font.drawCode = function(code, x, y)
  cursors[#cursors + 1] = { code = code, x = x, y = y }
end

local function cursorCodes(menu)
  cursors = {}
  menu:draw()
  local out = {}
  for _, g in ipairs(cursors) do
    if g.code == Theme.cursor or g.code == Theme.cursorHollow then
      out[#out + 1] = g.code
    end
  end
  return out
end

do
  local menu = Menu.new(stubGame(), {
    { label = "ONE" }, { label = "TWO" },
  })
  menu.index = 2
  eq(cursorCodes(menu)[1], Theme.cursor, "a plain Menu draws the filled arrow")
  menu.hollowIndex = 1
  eq(cursorCodes(menu)[1], Theme.cursor,
    "a hollow mark on another row leaves the cursor filled")
  menu.hollowIndex = 2
  eq(cursorCodes(menu)[1], Theme.cursorHollow,
    "hollowIndex on the cursor row draws the unfilled arrow")
end

-- bills_pc.asm:176
do
  local game = stubGame()
  local menu = BoxMenu.new(game)
  game.stack:push(menu)
  local changeBox
  for i, item in ipairs(menu.items) do
    if item.keepOpen then changeBox = changeBox or i end
  end
  check(changeBox, "the PC menu has keepOpen items")
  menu.index = changeBox
  menu.items[changeBox].onSelect()
  eq(menu.hollowIndex, changeBox,
    "picking a keepOpen item marks the parent cursor hollow")
  eq(cursorCodes(menu)[1], Theme.cursorHollow, "and it draws hollow")
  while game.stack:top() ~= menu do game.stack:pop() end
  menu:update(1 / 60)
  eq(menu.hollowIndex, nil, "back on top, the filled arrow returns")
  eq(cursorCodes(menu)[1], Theme.cursor, "and it draws filled")
end

Font.drawCode = realDrawCode

-- engine/menus/save.asm:437
local function upvalue(fn, name)
  for i = 1, 60 do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
  end
end

do
  local changeBoxMenu = upvalue(upvalue(BoxMenu.new, "changeBox"), "changeBoxMenu")
  check(type(changeBoxMenu) == "function", "found changeBoxMenu")

  local game = stubGame()
  Boxes.ensure(game.save)
  game.save.boxes[2] = { Pokemon.new(Data, "FIXMON_A", 5) }
  changeBoxMenu(game)
  local menu = game.stack:top()
  check(menu, "the CHANGE BOX menu went up")

  local lines, circles, images = {}, 0, {}
  local realDraw, realCircle = Font.draw, love.graphics.circle
  local realImageDraw = love.graphics.draw
  Font.draw = function(s) lines[#lines + 1] = s end
  love.graphics.circle = function() circles = circles + 1 end
  love.graphics.draw = function(img, _, x, y)
    images[#images + 1] = { path = type(img) == "table" and img.path, x = x, y = y }
  end
  menu:draw()
  Font.draw, love.graphics.circle, love.graphics.draw =
    realDraw, realCircle, realImageDraw

  local joined = table.concat(lines, "|")
  check(joined:find("<PK><MN> BOX.", 1, true),
    "the ROM-free prompt is the two-tile ligature, not POKeMON")
  check(not joined:find("POKéMON BOX.", 1, true), "and never the ASCII word")
  check(not joined:find("{DONE}", 1, true), "with no terminator marker")

  eq(circles, 0, "the box marker is no longer a vector pokeball")
  local balls = 0
  for _, img in ipairs(images) do
    if img.path == "assets/generated/battle/balls.png" then
      balls = balls + 1
      -- engine/menus/save.asm:488
      eq(img.x, 144, "the ball sits on tile column 18")
      eq(img.y, 16, "on box 2's row")
    end
  end
  eq(balls, 1, "one balls.2bpp tile 0, for the one stocked box")
end

do
  local strip = function(s)
    return (s:gsub("{DONE}%s*$", ""):gsub("{PROMPT}%s*$", ""))
  end
  eq(strip("Choose a\n<PK><MN> BOX.{DONE}"), "Choose a\n<PK><MN> BOX.",
    "the draw strips the terminator the extractor now writes")
end

T.finish("bills pc change box bug2124")
