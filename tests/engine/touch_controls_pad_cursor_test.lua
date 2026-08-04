-- Touch-controls editor pad / Joy-Con cursor (same class as save-editor soft-lock).
-- Opening Touch Controls parked the launcher cursor and dropped all gamepad
-- input; touch still worked.  PadCursor + main.lua forwarding restore the
-- virtual pointer.
--   luajit tests/engine/touch_controls_pad_cursor_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PadCursor = require("src.ui.PadCursor")
local GamepadMap = require("src.core.GamepadMap")

PadCursor.reset()
PadCursor.gamepadaxis(nil, "leftx", 1)
PadCursor.update(0.05)
check(PadCursor.isActive(), "left stick activates pad cursor")
local x0 = select(1, PadCursor.pointer())
PadCursor.update(0.05)
check(select(1, PadCursor.pointer()) > x0, "left stick moves cursor right")

eq(PadCursor.gamepadpressed(nil, "a"), "a", "gamepad a → click")
eq(PadCursor.gamepadpressed(nil, "b"), "b", "gamepad b → close")
eq(PadCursor.gamepadpressed(nil, "leftshoulder"), "tab_prev", "L → size down")
eq(PadCursor.gamepadpressed(nil, "rightshoulder"), "tab_next", "R → size up")

GamepadMap._setForceNXForTests(true)
eq(PadCursor.gamepadpressed(nil, "a"), "b", "NX SDL a (south) → close (GB b)")
eq(PadCursor.gamepadpressed(nil, "b"), "a", "NX SDL b (east) → click (GB a)")
GamepadMap._setForceNXForTests(false)

PadCursor.yieldToPointer()
check(not PadCursor.isActive(), "yieldToPointer drops the virtual cursor")

-- Compat: tools/save-editor/PadInput.lua re-exports the shared module.
package.path = package.path .. ";./tools/save-editor/?.lua"
local PadInput = require("PadInput")
eq(PadInput, PadCursor, "PadInput shim is PadCursor")

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

local mainSrc = read("main.lua")
check(mainSrc:find("prepareOverlayHandoff", 1, true) ~= nil
      and mainSrc:find("openTouchControlsEditor", 1, true) ~= nil,
      "main.lua mentions prepareOverlayHandoff + touch editor")
-- prepare must run inside openTouchControlsEditor, not only openEditor
local touchOpen = mainSrc:match("local function openTouchControlsEditor%(%)(.-)\nend")
check(touchOpen ~= nil, "openTouchControlsEditor body found")
check(touchOpen:find("prepareOverlayHandoff", 1, true) ~= nil,
      "openTouchControlsEditor prepares overlay handoff like the save editor")
local touchClose = mainSrc:match("function closeTouchControlsEditor%(%)(.-)\nend")
check(touchClose ~= nil, "closeTouchControlsEditor body found")
check(touchClose:find("resumeAfterOverlay", 1, true) ~= nil,
      "closeTouchControlsEditor resumes the launcher pad cursor")
check(mainSrc:find("TouchEditor.gamepadpressed", 1, true) ~= nil,
      "main.lua forwards gamepadpressed to TouchEditor")
check(mainSrc:find("TouchEditor.gamepadaxis", 1, true) ~= nil,
      "main.lua forwards gamepadaxis to TouchEditor")

local edSrc = read("src/ui/TouchControlsEditor.lua")
check(edSrc:find('require("src.ui.PadCursor")', 1, true) ~= nil,
      "TouchControlsEditor loads PadCursor")
check(edSrc:find("function Editor.gamepadpressed", 1, true) ~= nil,
      "TouchControlsEditor exposes gamepadpressed")
check(edSrc:find("PadCursor.draw()", 1, true) ~= nil,
      "TouchControlsEditor draws the pad cursor")
check(edSrc:find("PadCursor.yieldToPointer()", 1, true) ~= nil,
      "touch/mouse yields the pad so taps use event coords")
check(edSrc:find('beginDrag("pad"', 1, true) ~= nil,
      "A begins a pad drag at the virtual cursor")
check(edSrc:find('endDrag("pad")', 1, true) ~= nil,
      "A release ends a pad drag")

local packSrc = read("scripts/pack_love.sh")
check(packSrc:find("tools/save-editor/PadInput.lua", 1, true) ~= nil,
      "pack still requires PadInput path (compat shim)")

T.finish("touch_controls_pad_cursor")
