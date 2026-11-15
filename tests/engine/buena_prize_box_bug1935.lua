-- Buena_PlacePrizeMenuBox (#1935): ../pokecrystal/home/scrolling_menu.asm:25-41,
-- ../pokecrystal/engine/events/buena.asm:219

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  encode = function(text) return { string.byte(tostring(text), 1) or 0 } end,
  advanceOf = function() return 8 end,
  width = function(text) return #tostring(text) * 8 end,
}
package.loaded["src.ui.gen2.Chrome"] = nil
package.loaded["src.ui.gen2.BuenaPassword"] = nil
local BuenaPassword = require("src.ui.gen2.BuenaPassword")

local function boxes()
  local found = {}
  for _, c in ipairs(calls) do
    if c[1] == "box" then found[#found + 1] = c end
  end
  return found
end

local function drew(text, x, y)
  for _, c in ipairs(calls) do
    if c[1] == "draw" and c[2] == text and c[3] == x and c[4] == y then
      return true
    end
  end
  return false
end

local prizes = {}
for i = 1, 6 do prizes[i] = { name = "PRIZE " .. i, cost = i } end

local screen = BuenaPassword.new({ data = {
  text = require("tests.fixture_data.gen2_rom_text_s7_f2").crystal,
} }, { mode = "prize", prizes = prizes, balance = 1 })
screen:draw()

local drawn = boxes()
eq(#drawn, 2, "prize mode draws the list frame and the Points box, nothing else")

local frame = drawn[1]
if check(frame ~= nil, "the scrolling list is framed") then
  eq(frame[2], 0, "InitScrollingMenu decrements the left coord to 0")
  eq(frame[3], 0, "and the top coord to 0")
  eq(frame[4], 18, "16 interior columns plus both borders")
  eq(frame[5], 11, "9 interior rows plus both borders")
end

local balance = drawn[2]
if check(balance ~= nil, "PrintBlueCardBalance keeps its own box") then
  eq(balance[2], 0, "BlueCardBalanceMenuHeader's menu_coords 0, 11, 11, 13")
  eq(balance[3], 11, "row 11")
  eq(balance[4], 12, "through column 11")
  eq(balance[5], 3, "through row 13")
end

check(drew("PRIZE 1", 16, 16), "the first prize name sits at (16, 16)")
check(drew("1", 120, 16), "with its cost digit in column 15")
check(drew("\xe2\x96\xbc", 128, 72),
  "the ▼ lands inside the frame at (128, 72), not on its border")
check(not drew("\xe2\x96\xb2", 128, 8),
  "the ▲ stays off until the list has scrolled")

T.finish("buena prize box bug 1935")
