#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_ui_elevator_window_test", "scripts/text.lua")

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

local ElevatorWindow = require("src.ui.game3.elevator_window")

print("[test] 1. show / hide follow the two specials")
-- pokefirered/src/field_specials.c:1094, :1113
eq(ElevatorWindow.isVisible(), false, "hidden before DrawElevatorCurrentFloorWindow")
ElevatorWindow.show("1F")
eq(ElevatorWindow.isVisible(), true, "the special makes it visible")
eq(ElevatorWindow.label(), "1F", "it keeps the floor label it was handed")
ElevatorWindow.show("B4F")
eq(ElevatorWindow.label(), "B4F", "a second draw replaces the label")
ElevatorWindow.hide()
eq(ElevatorWindow.isVisible(), false, "CloseElevatorCurrentFloorWindow hides it")
eq(ElevatorWindow.label(), nil, "and drops the label")

print("[test] 2. the window template is sElevatorCurrentFloorWindowTemplate")
-- pokefirered/src/field_specials.c:727
local Window = require("src.ui.game3.window")
local realStdFrame = Window.stdFrame
local tpl, frames = nil, 0
Window.stdFrame = function(t) tpl = t; frames = frames + 1 end
ElevatorWindow.draw()
eq(frames, 0, "a hidden window draws nothing")
ElevatorWindow.show("5F")
ElevatorWindow.draw()
Window.stdFrame = realStdFrame
eq(frames, 1, "a visible window draws one std frame")
eq(tpl and tpl.tilemapLeft, 22, "tilemapLeft is 22")
eq(tpl and tpl.tilemapTop, 1, "tilemapTop is 1")
eq(tpl and tpl.width, 7, "width is 7 tiles")
eq(tpl and tpl.height, 4, "height is 4 tiles")

print("[test] 3. the two printed rows match DrawElevatorCurrentFloorWindow")
-- pokefirered/src/field_specials.c:1105, :1108
local realPrintPx = Window.printPx
local rows = {}
Window.printPx = function(text, px, py) rows[#rows + 1] = { text = text, x = px, y = py } end
ElevatorWindow.draw()
Window.printPx = realPrintPx
eq(#rows, 2, "two text rows")
eq(rows[1] and rows[1].text, "Now on:", "gText_NowOn on the first row")
eq(rows[1] and rows[1].x, 176, "printed at the window's left edge (22 * 8)")
eq(rows[1] and rows[1].y, 10, "at y = 2 inside the window")
eq(rows[2] and rows[2].text, "5F", "the floor label on the second row")
eq(rows[2] and rows[2].y, 24, "at y = 16 inside the window")
check(rows[2] and rows[2].x > (rows[1] and rows[1].x or 0),
  "the floor label is right aligned, not flush left")
eq(rows[2] and rows[2].x, ElevatorWindow.labelX(), "labelX drives the right alignment")
check(ElevatorWindow.labelX() <= 22 * 8 + 56, "it never crosses pret's x = 56 right edge")

print("[test] 4. a label-less draw still shows the frame and the header")
ElevatorWindow.show(nil)
rows = {}
Window.printPx = function(text, px, py) rows[#rows + 1] = { text = text, x = px, y = py } end
ElevatorWindow.draw()
Window.printPx = realPrintPx
eq(#rows, 1, "only the header prints when the floor is unknown")
ElevatorWindow.hide()

print("[test] 5. the specials chain reaches this screen through the host adapters")
local Adapters = require("src.core.game3.scripting.adapters")
local game = { session = {}, input = nil }
local host = Adapters.host(nil, game, nil)
check(type(host.elevatorWindow) == "function", "the host adapter carries elevatorWindow")
host.elevatorWindow("B2F")
eq(ElevatorWindow.isVisible(), true, "adapters.elevatorWindow opened this window")
eq(ElevatorWindow.label(), "B2F", "with the label the special passed")
host.elevatorWindowClose()
eq(ElevatorWindow.isVisible(), false, "adapters.elevatorWindowClose closed it")

print("[test] 6. the special itself drives the window")
-- pokefirered/src/field_specials.c:1094
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local ctx = Ctx.new({})
ctx.mode = "bytecode"
ctx.status = "running"
-- pokefirered/src/field_specials.c:1106 indexes sFloorNamePointers with VAR_0x8005
Flags.setVar(nil, ctx, 0x8005, 4)
Natives.special(ctx, Std.SPECIAL.DrawElevatorCurrentFloorWindow, host)
eq(ElevatorWindow.isVisible(), true, "DrawElevatorCurrentFloorWindow opened the window")
eq(ElevatorWindow.label(), "1F", "sFloorNamePointers[4] is 1F")
Natives.special(ctx, Std.SPECIAL.CloseElevatorCurrentFloorWindow, host)
eq(ElevatorWindow.isVisible(), false, "CloseElevatorCurrentFloorWindow closed it")

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL ELEVATOR WINDOW TESTS PASSED")
