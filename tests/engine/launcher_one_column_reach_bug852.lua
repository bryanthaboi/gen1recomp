-- One-column launcher reach (#852) and the safe-area launcher anchor (#810).
-- No pokered cite: the launcher is port-only chrome.
--
-- #852: minPanelHeight in src/import/LauncherView.lua was a flat 460*s tuned
-- for the two-column layout.  A one-column window (portrait phone, squat 4:3
-- device) stacks title + actions card + slot card + the pinned
-- Play/Reset-rebinds/Touch-Controls block, which needs more room; the flat
-- threshold read "tall enough", so the short-window page scroll never
-- engaged, buildSlotCard was cut by Kit.pushClip against the pinned block,
-- and Kit's clip-bounded hit-testing (src/ui/kit/Kit.lua) left every slot
-- row, the pager and "+ New save slot" drawn-but-inert.  The fix made the
-- threshold column-aware (LauncherView's PANEL_MIN_TWO/ONE).  That minimum
-- now doubles as the FIT-SCALE target: Layout.metrics shrinks the whole UI
-- until the stack plus chrome fits the window, so those windows show
-- everything on screen; only below the fit floor does the page scroll.
--
-- The seam is LauncherView.draw itself: it publishes the page-scroll extent
-- on the importer (imp._pageScroll / imp._pageScrollMax, the values the
-- touch-drag and wheel paths feed), so a headless draw shows whether the
-- scroll engaged without reading any file-local constant.  The 480x900
-- window below is the discriminator: its natural panel space satisfies the
-- old flat threshold (inert, slot card clipped) but not the one-column one.
--
-- #810 gets its unit-conversion pin in tests/engine/safe_area_units_test.lua;
-- here the complementary end-to-end anchor: Layout.metrics must place the
-- launcher at the corrected safe-area origin, not a DPI-inflated band down
-- the screen.
--   luajit tests/engine/launcher_one_column_reach_bug852.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- The launcher touches two graphics calls the shared stub does not carry
-- (focus-ring joins, the footer's BCG invert shader); both are draw-only, so
-- inert fills are enough for the layout arithmetic under test.
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Layout = require("src.ui.kit.Layout")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

-- A fresh launcher on the Red tab; no cache exists headless, so every
-- version sits in its "ROM required" state, which still lays out the full
-- one-column pile (title, actions card, slot card, pinned block).
local function freshLauncher()
  return RomImporter.new(function() end, { launcher = true })
end

-- ------------------------------------------ #852: the stack stays reachable
-- 480x900 one column.  Before the #852 fix the flat 460*s threshold read
-- "tall enough", so the page-scroll never engaged and the slot card sat
-- clipped inert against the pinned buttons.  Now the one-column minimum is
-- also the FIT-SCALE target: Layout.metrics shrinks the whole UI until that
-- minimum plus the header/footer chrome fits the window height, so the
-- entire stack -- title, actions card, slot card, pinned block, footer --
-- lands on screen and there is nothing to scroll.
--
-- The draw's own metrics use the launcher's fit hint ({ two = 460, one =
-- 660 }), so the test passes the same hint to keep m.s in agreement.
window(480, 900)
local m = Layout.metrics(1200, { two = 460, one = 660 })
eq(m.twoCol, false, "480-wide window lays out one column")
local imp = freshLauncher()
LauncherView.draw(imp)
eq(imp._pageScrollMax or 0, 0,
  "fit-scale puts the whole one-column stack on screen")
eq(imp._pageScroll, 0, "a fresh page starts at the top")

-- The reporter's portrait phone (360x780 units) also fits after fit-scaling;
-- before the fix its slot list was unreachable.
window(360, 780)
local phone = freshLauncher()
LauncherView.draw(phone)
eq(phone._pageScrollMax or 0, 0,
  "portrait-phone one-column window fits after fit-scaling")

-- Below the fit floor a very short window still engages the page scroll, and
-- the wheel clamps to the extent so the bottom of the stack -- down to
-- "+ New save slot" and the footer -- stays reachable rather than clipped.
window(480, 360)
local short = freshLauncher()
LauncherView.draw(short)
check((short._pageScrollMax or 0) > 0,
  "a very short one-column window below the fit floor scrolls")
local shortM = Layout.metrics(1200, { two = 460, one = 660 })
local extent = short._pageScrollMax
short._wheelY = -1
LauncherView.draw(short)
eq(short._pageScroll, math.min(math.floor(48 * shortM.s), extent),
  "one wheel notch scrolls the page down by its step")
short._pageScroll = 1e6
LauncherView.draw(short)
eq(short._pageScroll, short._pageScrollMax,
  "an offset past the end clamps to the extent, so the bottom is reachable")

-- A one-column window tall enough for the whole stack stays inert: the
-- column-aware minimum is a floor, not a permanent scroll.
window(480, 1200)
local tall = freshLauncher()
LauncherView.draw(tall)
eq(tall._pageScrollMax, 0,
  "a tall one-column window does not scroll for nothing")

-- --------------------------------------- #810: launcher anchored in units
-- Layout.metrics anchors the launcher at SafeArea.rect's origin.  Feed it
-- the iOS 16 portrait frame that reported the safe rect in framebuffer
-- pixels (3x DPI): the launcher must start at the 44-unit notch inset, not
-- 132 units down with the top of the window black (the #810 report).  The
-- rescale itself is pinned in tests/engine/safe_area_units_test.lua.
love.graphics.getDimensions = function() return 375, 812 end
love.graphics.getPixelDimensions = function() return 1125, 2436 end
local oldSafe = love.window.getSafeArea
love.window.getSafeArea = function() return 0, 132, 1125, 2232 end
local ios = Layout.metrics(1200)
eq(ios.top, 44, "launcher anchors at the unit-space notch inset")
eq(ios.h, 744, "launcher gets the full unit-space safe height")
love.window.getSafeArea = oldSafe

T.finish("launcher one-column reach")
