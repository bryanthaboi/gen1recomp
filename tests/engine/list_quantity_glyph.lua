-- home/list_menu.asm:478-494
--   luajit tests/engine/list_quantity_glyph.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local realFont = package.loaded["src.render.Font"]
local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text)
    local n = 0
    for _ in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n * 8
  end,
}
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
local ListMenu = require("src.ui.ListMenu")

local TIMES = "\xc3\x97"

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local function rowDraws(y)
  local out = {}
  for _, c in ipairs(calls) do
    if c[1] == "draw" and c[4] == y then out[#out + 1] = c end
  end
  return out
end

do
  local list = ListMenu.new({}, "ITEMS", {
    { value = "POTION", label = "POTION", count = 6 },
    { value = "POKE_BALL", label = "POKé BALL", count = 12 },
    { value = "BICYCLE", label = "BICYCLE" },
    { cancel = true, label = "CANCEL" },
  }, { kind = "bag", itemBox = true })
  calls = {}
  list:draw()

  local glyph = found("draw", function(c) return c[3] == 112 and c[4] == 40 end)
  if check(glyph ~= nil, "something prints at the quantity column (14, row+1)") then
    eq(glyph[2], TIMES, "and it is the charmap '×' ($F1), not ASCII 'x' ($B7)")
  end
  check(found("draw", function(c) return c[2] == "6" and c[3] == 128 and c[4] == 40 end)
        ~= nil, "a one-digit count sits at column 16 (PrintNumber lb bc, 1, 2)")
  check(found("draw", function(c) return c[2] == "12" and c[3] == 120 and c[4] == 56 end)
        ~= nil, "a two-digit count fills columns 15-16")
  check(found("draw", function(c) return c[2] == TIMES and c[3] == 112 and c[4] == 56 end)
        ~= nil, "the second row's '×' is at the same column")
  check(found("draw", function(c) return c[2]:find("x", 1, true) ~= nil end) == nil,
        "no row prints a lowercase x anywhere")
  eq(#rowDraws(72), 0, "a key item (no count) prints nothing on its quantity row")
  eq(#rowDraws(88), 0, "nor does CANCEL")
end

do
  local list = ListMenu.new({}, "ITEMS", {
    { value = "A", label = "A", right = "ON" },
  }, { kind = "bag", itemBox = true })
  calls = {}
  list:draw()
  check(found("draw", function(c) return c[2] == "ON" and c[3] == 120 and c[4] == 40 end)
        ~= nil, "right text right-aligns to column 17 unchanged")
  check(found("draw", function(c) return c[2] == "O" end) == nil,
        "and is never byte-split")
end

package.loaded["src.render.Font"] = realFont
package.loaded["src.ui.ListMenu"] = nil
package.loaded["src.ui.Theme"] = nil
require("src.ui.Screens").invalidate()

T.finish()
