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
-- row, the pager and "+ New save slot" drawn-but-inert.  The fix makes the
-- threshold column-aware, so those windows scroll instead of clipping.
--
-- The seam is LauncherView.draw itself: it publishes the page-scroll extent
-- on the importer (imp._pageScroll / imp._pageScrollMax, the values the
-- touch-drag and wheel paths feed), so a headless draw shows whether the
-- scroll engaged without reading any file-local constant.
--
-- What is asserted here is REACHABILITY, not scrolling: "+ New save slot" is
-- the control that sits at the very bottom of the one-column pile, and the
-- bug was that it drew where no tap could land.  Either it fits in the
-- window outright, or the page scrolls far enough to bring it in -- both are
-- correct, and which one a given window gets depends on how tall the panel's
-- content happens to be.  Asserting "this window scrolls" instead pinned the
-- test to the size of the stack: when the pinned Touch-Controls /
-- Reset-rebinds pair moved behind the gear and the save-file buttons moved
-- into the slot card, 480x900 started fitting outright and a scroll
-- assertion failed on a window that had just got BETTER.
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
local Kit = require("src.ui.kit.Kit")
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

-- Draw a frame with the layout audit on and report where "+ New save slot"
-- landed.  Kit records the rect every clickable control occupies plus the
-- clip that bounds its hit test, so this sees exactly what a tap would.
local function newSlotRect(imp)
  Kit.audit = {}
  LauncherView.draw(imp)
  local found
  for _, r in ipairs(Kit.audit) do
    if r.class == "control" and tostring(r.label):find("New save slot", 1, true) then
      found = r
    end
  end
  Kit.audit = nil
  return found
end

-- The control is reachable when its rect, intersected with whatever clip
-- bounds it, still has real area inside the window -- either straight away or
-- after the page is scrolled to the bottom.
local function reachable(imp, H)
  local function visible()
    local r = newSlotRect(imp)
    if not r then return false end
    local y1, y2 = r.y, r.y + r.h
    if r.clip then
      y1 = math.max(y1, r.clip.y)
      y2 = math.min(y2, r.clip.y + r.clip.h)
    end
    y1, y2 = math.max(y1, 0), math.min(y2, H)
    return (y2 - y1) > 1
  end
  if visible() then return true end
  imp._pageScroll = 1e6          -- clamps to the extent inside draw()
  return visible()
end

-- ------------------------------------------------ #852: the bottom is reachable
-- 480x900 one column: enough room for the old flat 460*s threshold, not for
-- the one-column stack.  Before the fix draw() left _pageScrollMax at 0 here
-- and the slot card sat clipped inert against the pinned buttons.
window(480, 900)
local m = Layout.metrics(1200)
eq(m.twoCol, false, "480-wide window lays out one column")
local imp = freshLauncher()
LauncherView.draw(imp)
check(reachable(imp, 900),
  "one-column window can reach the bottom of the slot card")
imp = freshLauncher()
LauncherView.draw(imp)
eq(imp._pageScroll, 0, "a fresh page starts at the top")

-- A short portrait phone still engages page scroll after removing the gaps
-- beside the header/footer dividers; 360x780 now fits without page overflow.
window(360, 740)
local pm = Layout.metrics(1200)
local phone = freshLauncher()
LauncherView.draw(phone)
check((phone._pageScrollMax or 0) > 0,
  "portrait-phone one-column window engages the page scroll")
eq(phone._pageScroll, 0, "a fresh page starts at the top")

-- The wheel moves the page (the same offset the touch drag feeds), and the
-- offset clamps to the extent, so the whole stack down to "+ New save slot"
-- and the footer is reachable rather than clipped away.
local extent = phone._pageScrollMax
phone._wheelY = -1
LauncherView.draw(phone)
eq(phone._pageScroll, math.min(math.floor(48 * pm.s), extent),
  "one wheel notch scrolls the page down by its step")
phone._pageScroll = 1e6
LauncherView.draw(phone)
eq(phone._pageScroll, phone._pageScrollMax,
  "an offset past the end clamps to the extent, so the bottom is reachable")
check(reachable(phone, 740),
  "the scrolled portrait phone reaches the bottom of the slot card")

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
