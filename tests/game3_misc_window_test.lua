#!/usr/bin/env luajit
-- pokefirered/src/new_menu_helpers.c:61

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function()
  return { setFilter = function() end, getDimensions = function() return 8, 8 end }
end
_G.love = { graphics = gfx }

local FrlgFont = require("src.ui.game3.frlg_font")
local Window = require("src.ui.game3.window")

local calls = {}
local realDraw = FrlgFont.draw
FrlgFont.draw = function(text, x, y, opts)
  opts = opts or {}
  local small = opts.small and true or false
  calls[#calls + 1] = {
    text = tostring(text), x = x, y = y, small = small,
    width = FrlgFont.measure(tostring(text), small and { small = true } or {}),
  }
  return realDraw(text, x, y, opts)
end

local function paint(fn)
  calls = {}
  fn()
  return calls
end

local function find(list, exact)
  for _, c in ipairs(list) do
    if c.text == exact then return c end
  end
  return nil
end

print("[test] 1. Window.printPx forwards opts.small into the font options")
local c = paint(function()
  Window.printPx("123456", 8, 20, { small = true })
  Window.printPx("123456", 8, 32)
end)
eq(#c, 2, "both calls reached FrlgFont.draw")
check(c[1] and c[1].small == true, "small = true survives the opts rebuild")
check(c[2] and c[2].small == false, "and a caller that asks for nothing still gets FONT_NORMAL")

print("[test] 2. the two fonts really do measure differently")
local smallW = FrlgFont.measure("123456", { small = true })
local normalW = FrlgFont.measure("123456", {})
check(smallW > 0 and normalW > 0, string.format("both metrics answer (%d / %d)", smallW, normalW))
check(smallW < normalW,
  string.format("FONT_SMALL is the narrower of the two (%d < %d)", smallW, normalW))

print("[test] 3. the mart money window right-aligns in FONT_SMALL (money.c:87)")
local ShopMenu = require("src.ui.game3.shop_menu")
local Strings = require("src.core.Strings")
local session = { money = 999999, bag = {}, name = "RED" }
ShopMenu.show({ session = session, items = { 4 } })
-- pokefirered/src/shop.c:1000
ShopMenu.mode = "buy"
local shop = paint(ShopMenu.draw)
local money = nil
for _, row in ipairs(shop) do
  if row.text:match("^¥%d") and row.y == 8 + 12 then money = row end
end
check(money ~= nil, "the money amount was drawn")
check(money and money.small == true, "the amount is FONT_SMALL")
local label = find(shop, Strings("MONEY"))
check(label ~= nil and label.small == false, "the MONEY label stays FONT_NORMAL (money.c:110)")
-- pokefirered/src/money.c:87
eq(money and (money.x + money.width), 8 + 64,
  "the amount ends exactly on the window's 64px right edge")
check(money and money.x >= 8, "and it starts inside the frame")
eq(money and money.y, 8 + 12, "at offset 0xC, as money.c:87 prints it")

print("[test] 4. IN BAG: is FONT_NORMAL, its count FONT_SMALL (strings.c:218)")
local Bag = require("src.core.game3.bag")
session.bag = Bag.new and Bag.new() or {}
ShopMenu._pending = { id = 4, price = 200 }
ShopMenu.mode = "buy_qty"
ShopMenu.qty = 1
local qty = paint(ShopMenu.draw)
local inBag = find(qty, Strings("IN BAG:"))
check(inBag ~= nil, "the in-bag label was drawn")
check(inBag and inBag.small == false, "IN BAG: prints before the {FONT_SMALL} code, so FONT_NORMAL")
local count = nil
for _, row in ipairs(qty) do
  if row.y == (inBag and inBag.y) and row ~= inBag then count = row end
end
check(count ~= nil, "the count shares the label's baseline")
check(count and count.small == true, "and the count is the FONT_SMALL half of the string")
-- pokefirered/src/shop.c:915
check(count and (count.x + count.width) <= 8 + 13 * 8,
  string.format("the count stays inside the frame (ends at %s, frame ends at %d)",
    tostring(count and (count.x + count.width)), 8 + 13 * 8))

local timesRow = nil
for _, row in ipairs(qty) do
  if row.text:match("^×") then timesRow = row end
end
check(timesRow ~= nil and timesRow.small == true,
  "the ×NN counter is FONT_SMALL (shop.c:868)")
-- pokefirered/src/shop.c:868
eq(timesRow and timesRow.x, 136 + 2, "the counter sits at window offset x=2")
eq(timesRow and timesRow.y, 72 + 10, "and y=0xA")

ShopMenu.close()
FrlgFont.draw = realDraw

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
