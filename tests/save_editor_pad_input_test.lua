-- Save editor pad / Joy-Con input (NX soft-lock fix).
-- PadInput mirrors the launcher cursor; main.lua must forward editorMode
-- gamepad/touch instead of discarding them.
--   luajit tests/save_editor_pad_input_test.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love or love_stub

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GamepadMap = require("src.core.GamepadMap")
local PadInput = require("PadInput")

PadInput.reset()

-- Stick deflection activates the cursor and moves it.
PadInput.gamepadaxis(nil, "leftx", 1)
PadInput.update(0.05)
check(PadInput.isActive(), "left stick activates pad cursor")
local x0 = select(1, PadInput.pointer())
PadInput.update(0.05)
local x1 = select(1, PadInput.pointer())
check(x1 > x0, "left stick moves cursor right")

-- A / B via GamepadMap (desktop labels = GB a/b).
eq(PadInput.gamepadpressed(nil, "a"), "a", "gamepad a → click action")
eq(PadInput.gamepadpressed(nil, "b"), "b", "gamepad b → close action")
eq(PadInput.gamepadpressed(nil, "leftshoulder"), "tab_prev", "L cycles tab prev")
eq(PadInput.gamepadpressed(nil, "rightshoulder"), "tab_next", "R cycles tab next")

-- NX face swap: SDL south "a" is Nintendo B → GB b (close).
GamepadMap._setForceNXForTests(true)
eq(PadInput.gamepadpressed(nil, "a"), "b", "NX SDL a (south) → close (GB b)")
eq(PadInput.gamepadpressed(nil, "b"), "a", "NX SDL b (east) → click (GB a)")
GamepadMap._setForceNXForTests(false)

-- Dual-path gate: gamepad sticks must not also fire from raw joystick (#620).
local gamepadJoy = {
  isGamepad = function() return true end,
}
eq(PadInput.joystickpressed(gamepadJoy, 1), nil,
   "ignoreRaw skips second fire on isGamepad sticks")

-- Raw (non-gamepad) stick still maps through GamepadMap.
local rawJoy = {
  isGamepad = function() return false end,
}
eq(PadInput.joystickpressed(rawJoy, 1), "a",
   "raw #1 clicks via shared map")

-- Right stick accumulates wheel notches.
PadInput.reset()
PadInput.gamepadaxis(nil, "righty", -1) -- stick up
PadInput.update(1.0)
local notches = PadInput.takeWheel()
check(notches >= 1, "right stick up yields positive wheel notches")

PadInput.reset()
check(not PadInput.isActive(), "reset clears active cursor")

-- Touch / mouse must yield the pad so a tap is not hit-tested at the Joy-Con
-- pointer (the NX "cursor shows but touch does nothing" bug).
PadInput.gamepadaxis(nil, "leftx", 1)
PadInput.update(0.05)
check(PadInput.isActive(), "stick activates before yield")
PadInput.yieldToPointer()
check(not PadInput.isActive(), "yieldToPointer drops the virtual cursor")

-- Source seams: main.lua must forward editorMode gamepad/touch; App must
-- own the pad handlers, prefer event click coords over the pad pointer, and
-- feed pad coords into Kit only when active and no pending click.
local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

local mainSrc = read("main.lua")
check(mainSrc:find("if editorMode then", 1, true) ~= nil
      and mainSrc:find("EditorApp.gamepadpressed", 1, true) ~= nil,
      "main.lua forwards gamepadpressed to EditorApp in editorMode")
check(mainSrc:find("EditorApp.mousepressed(x, y, 1)", 1, true) ~= nil,
      "main.lua touchpressed clicks the save editor (non-iOS)")
check(mainSrc:find('istouch and love.system.getOS() == "Android"', 1, true) ~= nil,
      "main.lua guards Android double-fire for editor mousepressed")

local appSrc = read("tools/save-editor/App.lua")
check(appSrc:find('require("PadInput")', 1, true) ~= nil,
      "App.lua loads PadInput")
check(appSrc:find("function App.gamepadpressed", 1, true) ~= nil,
      "App.lua exposes gamepadpressed")
check(appSrc:find("PadInput.reset()", 1, true) ~= nil,
      "App.unload resets PadInput")
check(appSrc:find("PadInput.pointer()", 1, true) ~= nil,
      "App.draw uses pad pointer when active")
check(appSrc:find("PadInput.yieldToPointer()", 1, true) ~= nil,
      "App.mousepressed yields the pad so touch uses event coords")
check(appSrc:find("mouseClicked and clickX", 1, true) ~= nil,
      "App.draw prefers click event coords over pad / mouse")

T.finish("save_editor_pad_input")
