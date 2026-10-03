-- Focus-ring navigation between and within layers (found driving the
-- launcher with a pad only, on PS4; the same ring runs on Xbox and on
-- desktop arrow keys).
-- Self-contained: luajit tests/engine/launcher_pad_nav_layers_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local Kit = require("src.ui.kit.Kit")

-- One frame of focusables: the header cluster, a cart with its action
-- button straight below, and a footer card.
local function frame()
  Kit.beginFrame(0, 0, false, 0)
  Kit.focusable("tab-sync", 520, 10, 30, 30)
  Kit.focusable("gear", 560, 10, 30, 30)
  Kit.focusable("tab-red", 20, 60, 40, 24)
  Kit.focusable("play-red", 20, 120, 120, 150)
  Kit.focusable("rom-red", 20, 290, 120, 30)
  Kit.focusable("footer-promo", 20, 400, 200, 40)
  Kit.endFrame()
end

local function step(from, dir)
  Kit.scale = 1
  Kit.blockClicks = false
  Kit.focusId = from
  frame()
  Kit.focusId = from
  Kit.navigate(dir)
  frame()
  return Kit.focusId
end

-- Save Sync sits in the top bar beside the gear, not in the tab row.
eq(step("tab-sync", "right"), "gear", "Right from Save Sync reaches the gear")
eq(step("gear", "left"), "tab-sync", "Left from the gear reaches Save Sync")

-- Down inside the content layer before leaving it.
eq(step("play-red", "down"), "rom-red",
  "Down from the cart reaches the button under it, not the footer")
eq(step("rom-red", "up"), "play-red", "Up from that button returns to the cart")
eq(step("rom-red", "down"), "footer-promo",
  "with nothing further down in the layer, Down still reaches the footer")

T.finish()
