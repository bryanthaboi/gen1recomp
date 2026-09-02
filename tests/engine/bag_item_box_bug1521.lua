-- The bag's item list is LIST_MENU_BOX (#1521): home/list_menu.asm:29-31,
-- :51-52, :364-365, :471-479, :518-521, data/text_boxes.asm:13

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Font wants a real atlas; the geometry is what this suite is about, so it
-- records the calls instead.  ListMenu and Theme bind Font at require time.
local realFont = package.loaded["src.render.Font"]
local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #tostring(text) * 8 end,
}
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
local ListMenu = require("src.ui.ListMenu")
local Theme = require("src.ui.Theme")

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local function newList(count)
  local items = {}
  for i = 1, count do
    items[i] = { value = "ITEM_" .. i, label = "ITEM " .. i, count = i }
  end
  return ListMenu.new({}, "ITEMS", items, { kind = "bag", itemBox = true })
end

do
  local list = newList(6)
  eq(list.rows, 4, "PrintListMenuEntries prints 4 names, not 7")
  eq(list.isOpaque, false,
     "the box is partial, so the map keeps drawing behind it")

  calls = {}
  list:draw()

  local box = found("box", function(c) return true end)
  if check(box ~= nil, "the list draws LIST_MENU_BOX") then
    eq(box[2], 4, "upper-left X 4")
    eq(box[3], 2, "upper-left Y 2")
    eq(box[4], 16, "through lower-right X 19")
    eq(box[5], 11, "through lower-right Y 12")
  end

  -- names at hlcoord 6, 4 and every two rows after it
  for row = 1, 4 do
    local y = 32 + (row - 1) * 16
    check(found("draw", function(c)
      return c[2] == "ITEM " .. row and c[3] == 48 and c[4] == y
    end) ~= nil, "name " .. row .. " sits at (48, " .. y .. ")")
  end
  check(found("draw", function(c) return c[2] == "ITEM 5" end) == nil,
        "the fifth name is scrolled out, not printed below the box")

  -- the quantity: '×' at column 14, the count right-aligned after it
  check(found("draw", function(c)
    return c[2] == "\xc3\x97" and c[3] == 112 and c[4] == 40
  end) ~= nil, "the first quantity's '×' is a row down at column 14")
  check(found("draw", function(c)
    return c[2] == "1" and c[3] == 128 and c[4] == 40
  end) ~= nil, "with the count right-aligned in the two columns after it")

  check(found("code", function(c)
    return c[2] == Theme.cursor and c[3] == 40 and c[4] == 32
  end) ~= nil, "the cursor is in column 5 (wTopMenuItemX)")
  check(found("code", function(c)
    return c[2] == Theme.moreArrow and c[3] == 144 and c[4] == 88
  end) ~= nil, "a full page ends with the '▼'")

  -- nothing else: no title, no money footer (wPrintItemPrices = 0)
  check(found("draw", function(c) return tostring(c[2]):find("¥") end) == nil,
        "the everyday bag has no money box (that is the mart's screen)")
  check(found("draw", function(c) return c[2] == "ITEMS" end) == nil,
        "and no title row: the box carries no header text")
end

-- the box keeps the palette beneath and caps the cursor at wMaxMenuItem
do
  local list = newList(6)
  eq(list.sgbPalettes, false,
     "no SET_PAL_GENERIC: ItemMenuLoop keeps RunDefaultPaletteCommand's "
     .. "palette (start_sub_menus.asm:300)")
  eq(list.cursorRows, 3,
     "wMaxMenuItem 2: three cursor rows (home/list_menu.asm:46-48)")
  list.game = { input = { wasPressed = function(_, b) return b == "down" end,
                          isDown = function() return false end } }
  for _ = 1, 3 do list:update(1 / 60) end
  eq(list.index, 4, "three downs reach the fourth item")
  eq(list.index - list.scroll, 3,
     "scrolling instead of dropping the cursor onto the look-ahead row")
end

-- a short list stops at its last name, and the terminator's CANCEL row is
-- what would follow -- never the '▼'
do
  local list = newList(2)
  calls = {}
  list:draw()
  check(found("code", function(c) return c[2] == Theme.moreArrow end) == nil,
        "a page that runs out of names prints no '▼' (:372)")
end

package.loaded["src.render.Font"] = realFont
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
require("src.ui.Screens").invalidate()

T.finish()
