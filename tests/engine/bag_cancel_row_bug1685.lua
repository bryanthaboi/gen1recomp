-- The bag list ends on the terminator's CANCEL row (#1685).
--
-- pokered's item lists are $ff-terminated.  PrintListMenuEntries walks four
-- entries and, on the terminator, `jp z, .printCancelMenuItem` -- which is
-- `ld de, ListMenuCancelText / jp PlaceString`, a TAIL jump that RETURNS
-- from PrintListMenuEntries (home/list_menu.asm:371-372, 523-528).  The '▼'
-- at :518-522 is only reached by the fall-through, so any page showing
-- CANCEL shows no down arrow.  DisplayListMenuIDLoop compares the selection
-- against wListCount and takes ExitListMenu when it is the row past the last
-- item (:105-110), which is the same exit B takes.
--
-- The port emitted one row per bag entry and stopped, so the list had no
-- CANCEL to walk onto and printed an invented "Nothing here." when the bag
-- was empty.
--   luajit tests/engine/bag_cancel_row_bug1685.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Font wants a real atlas and this suite is about what lands on which row,
-- so it records the calls instead (the shape tests/engine/
-- bag_item_box_bug1521.lua uses).  ListMenu and Theme bind Font at require
-- time, and BagMenu binds ListMenu and TextBox at require time.
local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #tostring(text) * 8 end,
  -- Menu.new sizes its box off split(); reaching it at all is the failure
  -- this suite reports, so the stub answers instead of erroring
  split = function(text)
    local spans = {}
    for i = 1, #tostring(text) do spans[i] = { from = i, to = i, code = 0 } end
    return spans
  end,
}
package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = function() return nil end,
}
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
package.loaded["src.ui.BagMenu"] = nil
local ListMenu = require("src.ui.ListMenu")
local Theme = require("src.ui.Theme")
local BagMenu = require("src.ui.BagMenu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")

local CANCEL = Strings("CANCEL")

local Data = Fixtures.fresh()
for i = 1, 6 do
  local id = "FIXITEM_" .. i
  Data.items[id] = { id = id, index = 100 + i, name = "FIX ITEM " .. i,
                     price = 100, tossable = true }
end

local function freshGame(count)
  local game = {
    data = Data,
    save = {
      party = {},
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  -- one button edge per update, the way Input reports a fixed step
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  function game.input:isDown() return false end
  for i = 1, count do Bag.add(game.save, "FIXITEM_" .. i, i) end
  return game
end

local function openBag(game, opts)
  local list = BagMenu.new(game, opts)
  game.stack:push(list)
  return list
end

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local function drawnAt(text, x, y)
  return found("draw", function(c)
    return c[2] == text and c[3] == x and (y == nil or c[4] == y)
  end)
end

local function press(list, btn)
  list.game.input.pressed = btn
  list:update(1 / 60)
  list.game.input.pressed = nil
end

-- the row itself: one CANCEL after the last bag entry, carrying no id and no
-- quantity (home/list_menu.asm:523-528)
do
  local game = freshGame(6)
  local list = openBag(game)
  eq(#list.items, 7, "six bag entries plus the terminator's CANCEL row")
  local last = list.items[#list.items]
  eq(last.label, CANCEL, "the last row is CANCEL")
  eq(last.cancel, true, "flagged as the terminator row, not an item")
  eq(last.value, nil, "with no item id behind it")
  eq(last.right, nil, "and no 'xN' count (PrintListMenuEntries never gets "
                      .. "that far for the terminator)")
  eq(CANCEL, "CANCEL", "ListMenuCancelText reads CANCEL")
  for i = 1, 6 do
    eq(list.items[i].value, "FIXITEM_" .. i, "row " .. i .. " is still its item")
  end
end

-- page one of a long list: four real names, the '▼', no CANCEL yet
do
  local game = freshGame(6)
  local list = openBag(game)
  calls = {}
  list:draw()
  for row = 1, 4 do
    local y = 32 + (row - 1) * 16
    check(drawnAt("FIX ITEM " .. row, 48, y) ~= nil,
          "name " .. row .. " sits at (48, " .. y .. ")")
  end
  check(found("draw", function(c) return c[2] == CANCEL end) == nil,
        "CANCEL is below the fold on page one, not printed on it")
  check(found("code", function(c)
    return c[2] == Theme.moreArrow and c[3] == 144 and c[4] == 88
  end) ~= nil, "four real rows fill the page, so the '▼' prints (:518-522)")
end

-- walking down: the cursor reaches CANCEL and stops there, and the page it
-- lands on drops the '▼'
do
  local game = freshGame(6)
  local list = openBag(game)
  for _ = 1, 6 do press(list, "down") end
  eq(list.index, 7, "six downs put the cursor on the CANCEL row")
  eq(list.scroll, 4, "with the scroll capped at wListCount - 2")
  press(list, "down")
  eq(list.index, 7, "and a seventh down goes nowhere: CANCEL is the last row")
  eq(list.scroll, 4, "the list does not scroll past it either")

  calls = {}
  list:draw()
  -- rows 5, 6, CANCEL, then the terminator's return
  check(drawnAt("FIX ITEM 5", 48, 32) ~= nil, "FIX ITEM 5 leads the last page")
  check(drawnAt(CANCEL, 48, 64) ~= nil,
        "CANCEL sits one row below the last item, at the item names' x")
  check(found("code", function(c)
    return c[2] == Theme.cursor and c[3] == 40 and c[4] == 64
  end) ~= nil, "the cursor is on it, in wTopMenuItemX's column")
  check(found("code", function(c) return c[2] == Theme.moreArrow end) == nil,
        "and the '▼' is gone: .printCancelMenuItem returns before it")
end

-- the subtle one: three items plus CANCEL fills all four printed rows, so
-- `shown == rows` alone would still paint the arrow next to CANCEL
do
  local game = freshGame(3)
  local list = openBag(game)
  eq(#list.items, 4, "three items and CANCEL exactly fill the four rows")
  calls = {}
  list:draw()
  check(drawnAt(CANCEL, 48, 80) ~= nil, "CANCEL is the fourth printed row")
  check(found("code", function(c) return c[2] == Theme.moreArrow end) == nil,
        "a full page whose last row is CANCEL still prints no '▼' (:371-372)")
end

-- an empty bag is a box with CANCEL alone, which is what the cart shows
do
  local game = freshGame(0)
  local list = openBag(game)
  eq(#list.items, 1, "no items: the terminator is the whole list")
  eq(list.items[1] and list.items[1].cancel, true, "and that row is CANCEL")
  calls = {}
  list:draw()
  check(drawnAt(CANCEL, 48, 32) ~= nil, "printed on the first row")
  check(found("draw", function(c)
    return tostring(c[2]):find("Nothing here", 1, true) ~= nil
  end) == nil, "the port's invented \"Nothing here.\" line is gone")
  check(found("code", function(c) return c[2] == Theme.moreArrow end) == nil,
        "one row, no '▼'")
end

-- A on CANCEL is ExitListMenu: the same exit B takes (:105-110)
do
  local game = freshGame(6)
  local cancels = 0
  local list = openBag(game, { onCancel = function() cancels = cancels + 1 end })
  for _ = 1, 6 do press(list, "down") end
  eq(list.index, 7, "cursor on CANCEL")
  press(list, "a")
  check(game.stack:top() ~= list, "A on CANCEL leaves the item list")
  eq(#game.stack.states, 0, "with nothing pushed over it: no USE/TOSS box, "
                            .. "no message")
  eq(cancels, 1, "and the caller's onCancel ran, exactly as for B")
end

do
  local game = freshGame(6)
  local cancels = 0
  local list = openBag(game, { onCancel = function() cancels = cancels + 1 end })
  press(list, "b")
  check(game.stack:top() ~= list, "B still exits the list")
  eq(cancels, 1, "through the same callback")
end

-- SELECT swaps two bag entries; the terminator is not one
-- (engine/menus/swap_items.asm:19-22)
do
  local game = freshGame(6)
  local list = openBag(game)
  for _ = 1, 6 do press(list, "down") end
  press(list, "select")
  eq(list.swapIndex, nil, "SELECT on the CANCEL row starts no swap")
  press(list, "up")
  press(list, "select")
  eq(list.swapIndex, 6, "while SELECT on a real row still does")
end

package.loaded["src.render.Font"] = nil
package.loaded["src.core.Sound"] = nil
package.loaded["src.render.TextBox"] = nil
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
package.loaded["src.ui.BagMenu"] = nil
require("src.ui.Screens").invalidate()

T.finish()
