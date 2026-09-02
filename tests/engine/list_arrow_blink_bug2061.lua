-- home/window.asm:5-13, 26-35, 217-263; home/list_menu.asm:518-524
--   luajit tests/engine/list_arrow_blink_bug2061.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

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

local held = nil
local input = {
  wasPressed = function(_, b) return held == b end,
  isDown = function() return false end,
}

local function newList(count)
  local items = {}
  for i = 1, count do
    items[i] = { value = "ITEM_" .. i, label = "ITEM " .. i, count = i }
  end
  local list = ListMenu.new({ input = input }, "ITEMS", items,
                            { kind = "bag", itemBox = true })
  list.game = { input = input }
  return list
end

local function arrowDrawn(list)
  calls = {}
  list:draw()
  for _, c in ipairs(calls) do
    if c[1] == "code" and c[2] == Theme.moreArrow
       and c[3] == 144 and c[4] == 88 then
      return true
    end
  end
  return false
end

local function idle(list, frames)
  held = nil
  for _ = 1, frames do list:update(1 / 60) end
end

do
  local list = newList(6)
  check(arrowDrawn(list), "the arrow starts visible, as HandleMenuInput_ seeds it")

  idle(list, 30)
  check(not arrowDrawn(list), "half a second of idling blanks it to ' '")

  idle(list, 30)
  check(arrowDrawn(list), "and it comes back: the toggle is periodic")

  idle(list, 30)
  check(not arrowDrawn(list), "and off again on the next phase")
end

-- home/window.asm:29-35; home/list_menu.asm:518-524
do
  local list = newList(6)
  idle(list, 30)
  check(not arrowDrawn(list), "off phase reached")

  held = "down"
  list:update(1 / 60)
  check(list.index == 2, "the press moved the cursor")
  check(arrowDrawn(list), "scrolling reprints the '▼' solid")

  idle(list, 30)
  check(not arrowDrawn(list), "then the idle blink resumes from that press")
end

-- home/list_menu.asm:371-372
do
  local list = newList(2)
  check(not arrowDrawn(list), "a short list has no '▼' at phase 0")
  idle(list, 30)
  check(not arrowDrawn(list), "nor at any other phase")
end

package.loaded["src.render.Font"] = realFont
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
require("src.ui.Screens").invalidate()

T.finish()
