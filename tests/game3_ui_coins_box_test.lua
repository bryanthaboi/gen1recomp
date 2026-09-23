#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_ui_coins_box_test")

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

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

local session = { coins = 0 }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
}

local CoinsBox = require("src.ui.game3.coins_box")

print("[test] 1. show / update / hide")
eq(CoinsBox.isVisible(), false, "hidden before showcoinsbox")
CoinsBox.show(1, 1, 50)
eq(CoinsBox.isVisible(), true, "showcoinsbox makes it visible")
eq(CoinsBox.amount(), 50, "showcoinsbox takes the explicit amount")
eq(CoinsBox.x, 1, "tile x kept from the script argument")
eq(CoinsBox.y, 1, "tile y kept from the script argument")
CoinsBox.update(75)
eq(CoinsBox.amount(), 75, "updatecoinsbox replaces the amount")
CoinsBox.hide()
eq(CoinsBox.isVisible(), false, "hidecoinsbox hides it")
CoinsBox.update(999)
eq(CoinsBox.amount(), 75, "updatecoinsbox on a hidden box is a no-op")

print("[test] 2. MAX_COINS clamp and zero floor")
-- pokefirered/include/constants/coins.h:4
eq(CoinsBox.MAX_COINS, 9999, "MAX_COINS is 9999")
CoinsBox.show(2, 3, 123456)
eq(CoinsBox.amount(), 9999, "an over-cap amount clamps to MAX_COINS")
CoinsBox.update(-5)
eq(CoinsBox.amount(), 0, "a negative amount floors at 0")

print("[test] 3. the amount falls back to the session when the script omits it")
session.coins = 420
CoinsBox.hide()
CoinsBox.show(19, 1)
eq(CoinsBox.amount(), 420, "showcoinsbox with no amount reads session.coins")
session.coins = 421
CoinsBox.update()
eq(CoinsBox.amount(), 421, "updatecoinsbox with no amount re-reads session.coins")

print("[test] 4. the count string matches PrintCoinsString")
-- pokefirered/src/coins.c:50
eq(CoinsBox.countText(7), "   7 COINS", "7 right-aligns into four columns")
eq(CoinsBox.countText(50), "  50 COINS", "50 right-aligns into four columns")
eq(CoinsBox.countText(9999), "9999 COINS", "9999 fills all four columns")

print("[test] 5. drawing is safe headless and only happens while visible")
local frames = 0
local Window = require("src.ui.game3.window")
local realStdFrame = Window.stdFrame
Window.stdFrame = function(tpl) frames = frames + 1; return realStdFrame(tpl) end
CoinsBox.hide()
CoinsBox.draw()
eq(frames, 0, "a hidden box draws no frame")
CoinsBox.show(4, 5, 12)
CoinsBox.draw()
eq(frames, 1, "a visible box draws one std frame")
Window.stdFrame = realStdFrame

print("[test] 6. the window template follows ShowCoinsWindow")
-- pokefirered/src/coins.c:79
local tpl = nil
Window.stdFrame = function(t) tpl = t end
CoinsBox.show(4, 5, 12)
CoinsBox.draw()
Window.stdFrame = realStdFrame
eq(tpl and tpl.tilemapLeft, 5, "tilemapLeft is x + 1")
eq(tpl and tpl.tilemapTop, 6, "tilemapTop is y + 1")
eq(tpl and tpl.width, 8, "width is 8 tiles")
eq(tpl and tpl.height, 3, "height is 3 tiles")

print("[test] 7. the ops-chain pcall seam")
for _, fn in ipairs({ "show", "update", "hide", "isVisible", "amount", "draw", "countText" }) do
  check(type(CoinsBox[fn]) == "function", "CoinsBox." .. fn .. " is callable")
end
check(pcall(CoinsBox.show, nil, nil, nil), "show tolerates nil arguments")
eq(CoinsBox.x, 1, "a nil tile x falls back to 1")
CoinsBox.hide()

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL COINS BOX TESTS PASSED")
