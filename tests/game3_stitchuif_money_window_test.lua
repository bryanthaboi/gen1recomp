#!/usr/bin/env luajit

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

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

local session = { coins = 0, money = 0 }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
}

local FrlgFont = require("src.ui.game3.frlg_font")
local CoinsBox = require("src.ui.game3.coins_box")
local MoneyBox = require("src.ui.game3.money_box")

local calls = {}
local realDraw = FrlgFont.draw
FrlgFont.draw = function(text, x, y, opts)
  opts = opts or {}
  local small = opts.small and true or false
  local w = FrlgFont.measure(text, small and { small = true } or {})
  calls[#calls + 1] = {
    text = text, x = x, y = y, small = small, width = w, right = x + w,
  }
  return realDraw(text, x, y, opts)
end

local function paint(box)
  calls = {}
  box.draw()
  return calls
end

local function find(list, exact)
  for _, c in ipairs(list) do
    if c.text == exact then return c end
  end
  return nil
end

-- pokefirered/src/coins.c:79, pokefirered/src/money.c:123
local function contentRight(tileX) return (tileX + 1 + 8) * 8 end
local function contentLeft(tileX) return (tileX + 1) * 8 end

print("[test] 1. the coins count prints in FONT_SMALL (coins.c:76)")
CoinsBox.show(0, 5, 1000)
local c = paint(CoinsBox)
local count = find(c, CoinsBox.countText(1000))
local label = nil
for _, row in ipairs(c) do
  if row.text == "COINS" then label = row end
end
check(count ~= nil, "the count string was drawn")
check(count and count.text == "1000 COINS",
  "the count reads PrintCoinsString, got " .. tostring(count and count.text))
check(count and count.small == true, "the count uses FONT_SMALL")
check(label ~= nil and label.small == false,
  "the COINS label stays FONT_NORMAL (coins.c:89)")

print("[test] 2. the count stays inside the eight-tile window (coins.c:76)")
check(count and count.right <= contentRight(0),
  string.format("the count ends at %s, window content ends at %d",
    tostring(count and count.right), contentRight(0)))
check(count and count.x >= contentLeft(0),
  string.format("the count starts at %s, window content starts at %d",
    tostring(count and count.x), contentLeft(0)))
check(count and count.right == contentRight(0),
  "the count is right-aligned flush with 64 px inside the window")
check(count and count.y == (5 + 1) * 8 + 12, "the count sits on row 0xC of the window")

print("[test] 3. the widest coin count still fits")
CoinsBox.update(9999)
count = find(paint(CoinsBox), CoinsBox.countText(9999))
check(count and count.text == "9999 COINS", "MAX_COINS fills all four columns")
check(count and count.small == true, "the 9999 count uses FONT_SMALL")
check(count and count.right <= contentRight(0),
  string.format("9999 COINS ends at %s, window content ends at %d",
    tostring(count and count.right), contentRight(0)))

print("[test] 4. a shifted window moves the right edge with it")
CoinsBox.hide()
CoinsBox.show(12, 1, 7)
count = find(paint(CoinsBox), CoinsBox.countText(7))
check(count and count.right == contentRight(12),
  string.format("the count right-aligns to %d, got %s",
    contentRight(12), tostring(count and count.right)))
CoinsBox.hide()

print("[test] 5. the money box prints its amount in FONT_SMALL (money.c:87)")
MoneyBox.show(0, 0, 30000)
local m = paint(MoneyBox)
local amount = find(m, "¥30000")
local moneyLabel = nil
for _, row in ipairs(m) do
  if row.text == "MONEY" then moneyLabel = row end
end
check(amount ~= nil, "the money amount was drawn")
check(amount and amount.small == true, "the money amount uses FONT_SMALL")
check(moneyLabel ~= nil and moneyLabel.small == false,
  "the MONEY label stays FONT_NORMAL (money.c:110)")
check(amount and amount.right == contentRight(0),
  string.format("the money right-aligns to %d, got %s",
    contentRight(0), tostring(amount and amount.right)))
check(amount and amount.y == 8 + 12, "the money sits on row 0xC of the window")

print("[test] 6. MAX_MONEY fits the money window too")
MoneyBox.update(999999)
amount = find(paint(MoneyBox), "¥999999")
check(amount and amount.small == true, "the six-digit amount uses FONT_SMALL")
check(amount and amount.right <= contentRight(0),
  string.format("999999 ends at %s, window content ends at %d",
    tostring(amount and amount.right), contentRight(0)))
check(amount and amount.x >= contentLeft(0),
  "the six-digit amount starts inside the window")
MoneyBox.hide()

FrlgFont.draw = realDraw

if failed > 0 then
  print(string.format("\n[test] FAILED %d", failed))
  os.exit(1)
end
print("\n[test] all passed")
