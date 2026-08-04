-- #595: the save editor's ADD ITEM list was reachable only by typing.
-- Kit.scroll is the shared wheel handler behind the fix; it takes a notch
-- only when the pointer is inside the list body, consumes it so two stacked
-- lists cannot both move, clamps to the last page, and honours the modal
-- shield.  Standalone like the other panel suites (see the header of
-- tests/run_save_editor_tests.lua):
--   luajit tests/save_editor_wheel_bug595_test.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love or love_stub

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Kit = require("Kit")

Kit.beginFrame(50, 50, false, -1)
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 3,
   "a wheel notch scrolls the list under the pointer")
eq(Kit.wheelY, 0, "and is consumed, so only one list moves")
Kit.endFrame()

Kit.beginFrame(50, 50, false, 1)
eq(Kit.scroll(0, 0, 100, 100, 3, 250, 10), 0, "wheel up scrolls back")
Kit.endFrame()

Kit.beginFrame(50, 50, false, -1)
eq(Kit.scroll(0, 0, 100, 100, 245, 250, 10), 240,
   "the last page is the floor of the list")
Kit.endFrame()

Kit.beginFrame(500, 500, false, -1)
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 0,
   "a list the pointer is not over ignores the wheel")
Kit.endFrame()

Kit.beginFrame(50, 50, false, -1)
eq(Kit.scroll(0, 0, 100, 100, 0, 8, 10), 0, "a list that fits cannot scroll")
Kit.endFrame()

Kit.beginFrame(50, 50, false, -1)
Kit.blockClicks = true
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 0,
   "the modal shield stops the wheel exactly as it stops a click")
Kit.blockClicks = false
Kit.endFrame()
eq(Kit.wheelY, 0, "an unclaimed notch retires with the frame")

-- #715: a phone has no wheel, so Kit.scroll also follows a held pointer
-- dragging vertically over the list body.  Kit.beginFrame polls
-- love.mouse.isDown for this (neither host routes mousereleased), so the
-- stub grows one here.
local held = false
love.mouse = love.mouse or {}
love.mouse.getPosition = love.mouse.getPosition or function() return 0, 0 end
love.mouse.isDown = function() return held end

held = true
Kit.beginFrame(50, 90, false, 0)
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 0,
   "the press frame starts a drag without moving the list")
Kit.endFrame()

Kit.beginFrame(50, 60, false, 0)  -- dragged 30px up, 10 rows / 100px = 3 rows
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 3,
   "dragging upward reveals lower rows")
Kit.endFrame()

Kit.beginFrame(50, -2910, false, 0)  -- a wild fling clamps like the wheel does
eq(Kit.scroll(0, 0, 100, 100, 3, 250, 10), 240,
   "a drag past the end clamps to the last page")
Kit.endFrame()

held = false
Kit.beginFrame(50, 60, false, 0)
eq(Kit.scroll(0, 0, 100, 100, 3, 250, 10), 3,
   "releasing the pointer ends the drag")
Kit.endFrame()

held = true
Kit.beginFrame(500, 500, false, 0)  -- press outside the list body
Kit.scroll(0, 0, 100, 100, 0, 250, 10)
Kit.endFrame()
Kit.beginFrame(500, 400, false, 0)
eq(Kit.scroll(0, 0, 100, 100, 0, 250, 10), 0,
   "a drag that never entered the list does not scroll it")
Kit.endFrame()
held = false
Kit.beginFrame(0, 0, false, 0)
Kit.endFrame()

-- The wheel has to reach the Items lists without touching the map camera,
-- which is the only thing App.wheelmoved used to drive (#595).  Loading the
-- whole editor needs data/generated/, so pin the routing at the source seam
-- instead: App.wheelmoved must queue notches for Kit on every non-map tab.
local f = assert(io.open("tools/save-editor/App.lua", "r"))
local src = f:read("*a")
f:close()
check(src:find("wheelY = wheelY + (y or 0)", 1, true) ~= nil,
      "App.wheelmoved queues notches for Kit on non-map tabs (#595)")
check(src:find("Kit.beginFrame(mx, my, mouseClicked, wheelY)", 1, true) ~= nil,
      "App.draw hands the queued notches to Kit.beginFrame (#595)")

T.finish("save_editor_wheel_bug595")
