-- Gen 2 screen geometry: the blit scale a widescreen screen paints its
-- 160x144 panel at, and the naming keyboard's cursor bracket.
--
-- Both are pure layout, so they are asserted as coordinates rather than as
-- pixels.  tests/drivers/gold_menu_shots.lua is what shows the result.

package.path = "./?.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or { random = function(a, b) return b and a or 0.5 end }
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
}
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local checks, failures = 0, 0
local function check(label, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(label, tostring(got),
      tostring(want)))
  end
end

-- ------------------------------------------------------- panel blit scale
--
-- A GB pixel has to cover a whole number of window pixels: a fractional blit
-- gives one row of an 8x8 tile two device pixels and its neighbour one, which
-- is what tore box borders and ate rows out of glyphs.
check("1024x768 fits five whole pixels", Chrome.fitScale(1024, 768), 5)
check("exactly 160x144 is 1:1", Chrome.fitScale(160, 144), 1)
check("640x576 is a clean four", Chrome.fitScale(640, 576), 4)
check("a window smaller than the screen still blits at 1",
  Chrome.fitScale(100, 90), 1)
check("height constrains a wide window", Chrome.fitScale(1920, 480), 3)
check("width constrains a tall window", Chrome.fitScale(480, 1920), 3)

local ox, oy = Chrome.fitOrigin(1024, 768)
check("panel centred horizontally", ox, math.floor((1024 - 160 * 5) / 2))
check("panel centred vertically", oy, math.floor((768 - 144 * 5) / 2))
check("origin is whole pixels", ox, math.floor(ox))

-- The scale and the origin have to agree, or a nested TextBox drawn by Game2
-- would land on a different grid than the panel under it.
for _, size in ipairs({ { 1024, 768 }, { 1280, 720 }, { 800, 600 },
    { 1366, 768 } }) do
  local s = Chrome.fitScale(size[1], size[2])
  local x, y = Chrome.fitOrigin(size[1], size[2], s)
  check(("%dx%d panel fits inside the window"):format(size[1], size[2]),
    (x >= 0 and y >= 0 and 160 * s + 2 * x <= size[1] + 1
      and 144 * s + 2 * y <= size[2] + 1), true)
end

-- ------------------------------------------------------- naming cursor
--
-- OAMData_TextEntryCursor is a box stamped AROUND the character cell out of
-- one corner tile; .LetterEntries steps its XOFFSET by $10 a column from an
-- XCOORD of 24 (OAM), i.e. screen tile 2 for column 0.  The old cursor sat a
-- tile to the left, between two letters.
local naming = NamingScreen.new({}, { type = "player" })

local KEYBOARD_TOP = 8
for col = 0, 8 do
  naming.col, naming.row = col, 0
  local tx, ty, wide = naming:cursorTile()
  check(("column %d brackets its own letter tile"):format(col), tx, 2 + col * 2)
  check(("column %d stays on the top keyboard row"):format(col), ty,
    KEYBOARD_TOP)
  check(("column %d bracket is one tile wide"):format(col), wide, 1)
end
for row = 0, 3 do
  naming.col, naming.row = 4, row
  local _, ty = naming:cursorTile()
  check(("row %d steps two tiles"):format(row), ty, KEYBOARD_TOP + row * 2)
end

-- The bottom row's three fat targets: .CaseDelEnd adds $00 / $30 / $60, so the
-- bracket lands on tiles 2 / 8 / 14 and is five tiles wide.
local BOTTOM_TX = { [0] = 2, [3] = 8, [6] = 14 }
for col, want in pairs(BOTTOM_TX) do
  naming.row = naming:bottomRow()
  naming.col = col
  local tx, ty, wide = naming:cursorTile()
  check(("bottom target at column %d"):format(col), tx, want)
  check(("bottom target row"):format(col), ty, KEYBOARD_TOP + 4 * 2)
  check(("bottom bracket is five tiles"):format(col), wide, 5)
end

-- Every letter row's bracket has to line up with the tile the letter is
-- printed on (drawPanel prints at 2 + col * 2, keyboardTop + row * 2).
naming.col, naming.row = 3, 2
local tx, ty = naming:cursorTile()
check("bracket x matches the printed letter", tx, 2 + 3 * 2)
check("bracket y matches the printed letter", ty, KEYBOARD_TOP + 2 * 2)

-- A box screen shifts the whole keyboard up two rows and gains a sixth row;
-- the bracket follows keyboardTop rather than a baked constant.
local box = NamingScreen.new({}, { type = "box" })
box.col, box.row = 0, 0
local btx, bty = box:cursorTile()
check("box keyboard bracket x", btx, 2)
check("box keyboard bracket y", bty, 6)
box.row = box:bottomRow()
local _, bby, bbw = box:cursorTile()
check("box bottom row", bby, 6 + 5 * 2)
check("box bottom bracket is five tiles", bbw, 5)

-- ------------------------------------------------------- OPTION rows
--
-- StringOptions is "TEXT SPEED<LF>        :<LF>...", so on the cart the value
-- sits on its OWN row under the label with the colon at column 10 and the
-- value at 11 (Options_TextSpeed prints at hlcoord 11, 3).  Pinned because it
-- reads like a layout bug and is not one.
local printed, cursorAt = {}, nil
local realPrint, realCursor = Chrome.print, Chrome.cursor
local realClear, realBox = Chrome.clear, Chrome.textbox
Chrome.print = function(text, tx, ty)
  printed[#printed + 1] = { text = text, x = tx, y = ty }
  return 0
end
Chrome.cursor = function(tx, ty) cursorAt = { x = tx, y = ty } end
Chrome.clear = function() end
Chrome.textbox = function() end

local options = OptionsMenu.new({}, { options = {} })
options:drawPanel()

Chrome.print, Chrome.cursor = realPrint, realCursor
Chrome.clear, Chrome.textbox = realClear, realBox

local function findPrint(text)
  for _, row in ipairs(printed) do
    if row.text == text then return row end
  end
end

local label = findPrint("TEXT SPEED")
check("TEXT SPEED sits at the PlaceString origin x", label and label.x, 2)
check("TEXT SPEED sits at the PlaceString origin y", label and label.y, 2)
local colon
for _, row in ipairs(printed) do
  if row.text == ":" and row.y == 3 then colon = row break end
end
check("its colon is on the next row at column 10", colon and colon.x, 10)
local value
for _, row in ipairs(printed) do
  if row.y == 3 and row.x == 11 then value = row break end
end
check("the value prints at hlcoord 11, 3", value ~= nil, true)
check("and it is the TEXT SPEED setting",
  value and (value.text == "FAST" or value.text == "MID "
    or value.text == "SLOW"), true)
check("the cursor is the column-1 arrow on the label row",
  cursorAt and cursorAt.x, 1)
check("the cursor starts on the first row", cursorAt and cursorAt.y, 2)
check("FRAME still prints its literal TYPE", findPrint(":TYPE") ~= nil, true)

-- ------------------------------------------------------- mart buy list
--
-- BuyMenu (engine/items/mart.asm) is FadeToMenu + BlankScreen, then
-- PlaceMoneyTopRight and ScrollingMenu_UpdateDisplay's ClearWholeMenuBox.
-- The list is not MenuBox'd; only the money box and UpdateItemDescription's
-- textbox are.  The top menu still overlays the mart, so it must not blank.
local MartMenu = require("src.ui.gen2.MartMenu")
local Save = require("src.core.gen2.Save")

local martBoxes, martClears = {}, 0
local martClear, martBox = Chrome.clear, Chrome.box
local martPrint, martCursor = Chrome.print, Chrome.cursor
Chrome.clear = function() martClears = martClears + 1 end
Chrome.box = function(x, y, w, h)
  martBoxes[#martBoxes + 1] = { x = x, y = y, w = w, h = h }
end
Chrome.print = function() end
Chrome.cursor = function() end

local function martHasBox(x, y, w, h)
  for _, b in ipairs(martBoxes) do
    if b.x == x and b.y == y and b.w == w and b.h == h then return true end
  end
  return false
end

local martSave = Save.newGame()
local martItems = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", price = 300,
    description = "Restores HP\nby 20." },
}
local mart = MartMenu.new({ save = martSave, data = { items = martItems } }, {
  save = martSave,
  items = martItems,
  marts = { lists = { { "POTION" } } },
})
mart:draw()
check("the top menu does not blank the tilemap", martClears, 0)
check("and frames BUY/SELL/QUIT", martHasBox(0, 0, 12, 9), true)
check("and the welcome speech box", martHasBox(0, 12, 20, 6), true)
check("the top menu is not opaque", mart.isOpaque, false)

martClears, martBoxes = 0, {}
mart:enterBuy()
mart:draw()
check("BUY blanks the screen (BlankScreen)", martClears > 0, true)
check("the money box is framed", martHasBox(11, 0, 9, 3), true)
check("the description box is framed", martHasBox(0, 12, 20, 6), true)
check("the item list is not (ClearWholeMenuBox, not MenuBox)",
  martHasBox(1, 3, 19, 9), false)
check("BlankScreen shadows isOpaque so the letterbox is not the mart",
  mart.isOpaque, true)

mart:leaveBuy()
check("leaving BUY unshadows isOpaque", mart.isOpaque, false)

Chrome.clear, Chrome.box = martClear, martBox
Chrome.print, Chrome.cursor = martPrint, martCursor

-- ------------------------------------------------------- one blit scale
--
-- Every Gold screen paints its 160x144 panel through the same helper.  A
-- screen that re-derives the scale gets math.min(winW / 160, winH / 144),
-- which is fractional on almost every window, and then its own tile rows tear
-- while the screen beside it is clean.  Source-level because a draw needs a
-- canvas and there is no canvas in this harness.
local listing = io.popen and io.popen("ls src/ui/gen2/*.lua 2>/dev/null")
local screens = {}
if listing then
  for path in listing:lines() do screens[#screens + 1] = path end
  listing:close()
end
check("the gen2 screen list was readable", #screens > 0, true)
for _, path in ipairs(screens) do
  local f = io.open(path, "r")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  check(path .. " does not re-derive the blit scale",
    src:find("math%.min%(win[WH] */ *[%dSCREN_WH]+", 1, false) == nil, true)
  if src:find("function [%w_]+:drawWidescreen") then
    check(path .. " blits through Chrome.fitScale",
      src:find("fitScale", 1, true) ~= nil, true)
  end
  -- An opaque screen is one nothing under it is drawn for: its cart routine
  -- ran ClearBGPalettes / ClearTilemap, so the map is gone and the screen owns
  -- the window edge to edge.  It therefore has to declare its own surround, or
  -- Game2:drawScene resolves the widescreen layer to something else (or to
  -- nothing) and the letterbox shows whatever was behind it.
  if src:find("isOpaque = true", 1, true) then
    check(path .. " is opaque, so it declares drawsWidescreen",
      src:find("function [%w_]+:drawsWidescreen") ~= nil, true)
  end
end

print(("gen2 screen layout: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
