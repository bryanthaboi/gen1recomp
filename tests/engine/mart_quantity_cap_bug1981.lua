-- engine/events/pokemart.asm:151-155
-- home/print_bcd.asm:14-50

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local function glyphs(text)
  local n = 0
  for _ in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
  end
  return n
end

local realFont = package.loaded["src.render.Font"]
local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return glyphs(text) * 8 end,
  split = function(text)
    local out = {}
    for s in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      out[#out + 1] = s
    end
    return out
  end,
  spansFitting = function(spans, pixels) return math.min(#spans, math.floor(pixels / 8)) end,
  encode = function(text) return { text } end,
  advanceOf = function() return 8 end,
}

local RELOAD = {
  "src.ui.QuantityBox", "src.ui.ShopMenu", "src.ui.ListMenu",
  "src.ui.Menu", "src.ui.Theme",
}
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end

local QuantityBox = require("src.ui.QuantityBox")
local ShopMenu = require("src.ui.ShopMenu")

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local function presser(button)
  return { input = { wasPressed = function(_, b) return b == button end },
           stack = { pop = function() end } }
end

do
  local box = QuantityBox.new({}, { max = 99, unitPrice = 200 })
  eq(box.qty, 1, "the box opens on ×01 (InitialQuantityText)")
  box.game = presser("down")
  box:update(1 / 60)
  eq(box.qty, 99, "DOWN from 1 wraps to wMaxItemQuantity, not to a money cap")
  box.game = presser("up")
  box:update(1 / 60)
  eq(box.qty, 1, "UP from the max wraps back to 1")
end

do
  local box = QuantityBox.new({}, { max = 99, unitPrice = 200, start = 99 })
  eq(box.qty, 99, "start clamps inside 1..max")
  calls = {}
  box:draw()

  local frame = found("box", function() return true end)
  if check(frame ~= nil, "the priced box is drawn") then
    eq(frame[2], 7, "hlcoord 7, 9")
    eq(frame[3], 9, "row 9")
    eq(frame[4], 13, "c = 11 plus the border")
  end

  check(found("draw", function(c)
    return c[2] == "×99" and c[3] == 64 and c[4] == 80
  end) ~= nil, "the quantity prints at column 8 on row 10")

  local price = found("draw", function(c)
    return tostring(c[2]):find("¥") ~= nil
  end)
  if check(price ~= nil, "the total prints as its own field") then
    eq(price[2], "¥19800", "leading zeroes blank out, ¥ leads the digits")
    eq(price[3], 104, "right-aligned so the last digit lands in column 18")
    eq(price[4], 80, "on the same row as the quantity")
  end

  check(found("draw", function(c)
    return tostring(c[2]):find("×") and tostring(c[2]):find("¥")
  end) == nil, "quantity and price are separate fields, not one string")
end

do
  local box = QuantityBox.new({}, { max = 99, unitPrice = 200 })
  calls = {}
  box:draw()
  local price = found("draw", function(c)
    return tostring(c[2]):find("¥") ~= nil
  end)
  if check(price ~= nil, "×01 still prints a total") then
    eq(price[2], "¥200", "no zero padding ahead of the ¥")
    eq(price[3], 120, "still right-aligned to column 18")
  end
end

do
  local box = QuantityBox.new({}, { max = 5 })
  calls = {}
  box:draw()
  local frame = found("box", function() return true end)
  if check(frame ~= nil, "the plain box is drawn") then
    eq(frame[2], 15, "hlcoord 15, 9")
    eq(frame[4], 5, "c = 3 plus the border")
  end
  check(found("draw", function(c) return tostring(c[2]):find("¥") end) == nil,
        "no money field without a unitPrice")
end

do
  local pushed = {}
  local game = {
    data = {
      items = { POKE_BALL = { name = "POKe BALL", price = 200 } },
      text = {},
    },
    save = { money = 100, inventory = {}, bagOrder = {} },
    stack = { push = function(_, s) pushed[#pushed + 1] = s end,
              pop = function() end,
              top = function() return pushed[#pushed] end },
  }
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  menu.items[1].onSelect()
  pushed[1].stay.onShown()
  local list = pushed[2]
  if check(list ~= nil and list.onChoose ~= nil, "BUY pushes the item list") then
    local before = list.footer
    list.onChoose({ value = "POKE_BALL" })
    local qty = pushed[3]
    if check(qty ~= nil, "choosing an item opens the quantity menu") then
      eq(qty.max, 99, "wMaxItemQuantity is 99, not floor(money / price)")
      eq(qty.unitPrice, 200, "the unit price rides along for the total")
    end
    eq(list.footer, before,
       "no pre-confirm refusal: .isThereEnoughMoney runs after YES")
  end
end

package.loaded["src.render.Font"] = realFont
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end
require("src.ui.Screens").invalidate()

T.finish()
