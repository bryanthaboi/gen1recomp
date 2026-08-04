-- Same-frame press→release and multi-source hold regressions for Input.lua.
-- Self-contained: `luajit tests/input_hold_test.lua`; also dofile'd by
-- tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("input hold")
local check = S.check
local Input = require("src.core.Input")

Input:init()

-- Quick tap before the next FixedStep must edge-fire without leaving isDown.
Input:keypressed("up")
Input:keyreleased("up")
Input:step()
check(Input:wasPressed("up"), "same-frame tap still edges wasPressed")
check(not Input:isDown("up"), "same-frame tap does not stick isDown")

Input:reset()
Input:keypressed("up")
Input:step()
check(Input:wasPressed("up"), "held press edges wasPressed")
check(Input:isDown("up"), "held press keeps isDown across step")
Input:step()
check(not Input:wasPressed("up"), "hold does not re-edge next step")
check(Input:isDown("up"), "hold stays down next step")
Input:keyreleased("up")
check(not Input:isDown("up"), "release clears isDown")

-- W and Up both map to up; releasing one must not drop the other.
Input:reset()
Input:keypressed("w")
Input:keypressed("up")
Input:step()
Input:keyreleased("w")
check(Input:isDown("up"), "second source keeps up held after first release")
Input:keyreleased("up")
check(not Input:isDown("up"), "last source release clears up")

-- Stick flick on→off before step must not stick.
Input:reset()
Input:gamepadaxis(nil, "leftx", -0.9)
Input:gamepadaxis(nil, "leftx", 0)
Input:step()
check(Input:wasPressed("left"), "stick flick edges wasPressed")
check(not Input:isDown("left"), "stick flick does not stick isDown")

-- Linux handhelds without an SDL game-controller mapping send raw joystick
-- axes and D-pad hats instead of gamepad events.
Input:reset()
Input:joystickaxis(nil, 1, -0.9)
Input:step()
check(Input:isDown("left"), "raw joystick left axis holds left")
Input:joystickaxis(nil, 1, 0)
check(not Input:isDown("left"), "raw joystick axis release clears left")

Input:reset()
Input:joystickhat(nil, 1, "u")
Input:step()
check(Input:isDown("up"), "raw joystick hat holds up")
Input:joystickhat(nil, 1, "c")
check(not Input:isDown("up"), "raw joystick hat release clears up")

Input:reset()
Input:joystickpressed(nil, 1)
Input:step()
check(Input:isDown("a"), "raw joystick primary button presses A")

-- A pad SDL already maps sends both event pairs for one physical button,
-- and its raw indices are per-driver (iOS puts the D-pad on 7..10), so the
-- raw fallback must stand down for it (#620).
local mapped = { isGamepad = function() return true end }
Input:reset()
Input:joystickpressed(mapped, 9)
Input:joystickhat(mapped, 1, "l")
Input:joystickaxis(mapped, 1, -0.9)
Input:step()
check(not Input:isDown("select"), "mapped pad ignores raw button indices")
check(not Input:isDown("left"), "mapped pad ignores raw hat and axis")
Input:gamepadpressed(mapped, "dpleft")
Input:step()
check(Input:isDown("left"), "mapped pad still routes through gamepad events")

-- The launcher has a separate virtual cursor, so prove generic joystick
-- events reach its left-stick and D-pad state too.
local RomImporter = require("src.import.RomImporter")
local importer = setmetatable({
  _padCursor = { x = 0, y = 0 }, _padCursorActive = false,
  _padAxis = { leftx = 0, lefty = 0, righty = 0 },
  _padDir = {}, _rawHatDirs = {}, _padInited = true,
  -- FlexLove view marker: without it the pad A path is a no-op (headless).
  _flex = true,
}, RomImporter)
local clicked = false
local prevView = package.loaded["src.import.LauncherView"]
package.loaded["src.import.LauncherView"] = {
  clickAt = function() clicked = true end,
}
importer:joystickaxis(nil, 1, -0.8)
check(importer._padAxis.leftx == -0.8,
  "raw joystick left axis reaches the launcher cursor")
importer:joystickhat(nil, 1, "r")
check(importer._padDir.dpright,
  "raw joystick hat reaches the launcher cursor")
importer:joystickhat(nil, 1, "c")
check(not importer._padDir.dpright,
  "raw joystick hat release clears the launcher cursor")
importer:joystickpressed(nil, 1)
check(clicked, "raw joystick primary button clicks the launcher cursor")
clicked = false
importer:joystickpressed(mapped, 1)
check(not clicked, "mapped pad does not double-click the launcher cursor")
package.loaded["src.import.LauncherView"] = prevView

-- Drivers that only inject pressQueue still get a one-step hold.
Input:reset()
table.insert(Input.pressQueue, "down")
Input:step()
check(Input:wasPressed("down"), "synthetic pressQueue edges wasPressed")
check(Input:isDown("down"), "synthetic pressQueue sets isDown")

S.finish()
