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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local Gfx = require("src.core.game3.gfx")
local Window = require("src.ui.game3.window")
local ElevatorWindow = require("src.ui.game3.elevator_window")

local realStdFrame, realPrintPx = Window.stdFrame, Window.printPx
local frames, rows

local function composite()
  frames, rows = {}, {}
  Window.stdFrame = function(tpl) frames[#frames + 1] = tpl end
  Window.printPx = function(text, px, py) rows[#rows + 1] = { text = text, x = px, y = py } end
  Gfx.drawUi()
  Window.stdFrame, Window.printPx = realStdFrame, realPrintPx
end

-- pokefirered/src/field_specials.c:727
local function elevatorFrames()
  local n = 0
  for _, tpl in ipairs(frames) do
    if tpl and (tpl.tilemapLeft or tpl.left) == 22 and (tpl.tilemapTop or tpl.top) == 1
        and (tpl.width or tpl.w) == 7 and (tpl.height or tpl.h) == 4 then
      n = n + 1
    end
  end
  return n
end

local function rowWithText(text)
  for _, row in ipairs(rows) do
    if row.text == text then return row end
  end
  return nil
end

print("[test] 1. the field compositor paints nothing while the lift window is closed")
ElevatorWindow.hide()
composite()
eq(elevatorFrames(), 0, "Gfx.drawUi paints no elevator frame")
eq(rowWithText("Now on:"), nil, "and no gText_NowOn row")

print("[test] 2. DrawElevatorCurrentFloorWindow reaches the compositor")
-- pokefirered/src/field_specials.c:1094
local Adapters = require("src.core.game3.scripting.adapters")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")

local game = { session = {}, input = nil }
local host = Adapters.host(nil, game, nil)
local ctx = Ctx.new({})
ctx.mode = "bytecode"
ctx.status = "running"
-- pokefirered/src/field_specials.c:1106 indexes sFloorNamePointers with VAR_0x8005
Flags.setVar(nil, ctx, 0x8005, 0)
Natives.special(ctx, Std.SPECIAL.DrawElevatorCurrentFloorWindow, host)
eq(ElevatorWindow.isVisible(), true, "the special opened the window")
eq(ElevatorWindow.label(), "B4F", "sFloorNamePointers[0] is B4F")

composite()
eq(elevatorFrames(), 1, "Gfx.drawUi paints exactly one sElevatorCurrentFloorWindowTemplate frame")
-- pokefirered/src/field_specials.c:1105
local header = rowWithText("Now on:")
check(header ~= nil, "gText_NowOn is painted by the field compositor")
eq(header and header.x, 176, "at the window's left edge (22 * 8)")
eq(header and header.y, 10, "at y = 2 inside the window")
-- pokefirered/src/field_specials.c:1108
local label = rowWithText("B4F")
check(label ~= nil, "the floor label is painted by the field compositor")
eq(label and label.y, 24, "at y = 16 inside the window")
eq(label and label.x, ElevatorWindow.labelX(), "right aligned on pret's x = 56 edge")

print("[test] 3. it keeps painting every frame the lift window is up")
composite()
eq(elevatorFrames(), 1, "a second field frame paints it again")
check(rowWithText("B4F") ~= nil, "with the floor label still on it")

print("[test] 4. the window survives a floor change without a second frame")
Flags.setVar(nil, ctx, 0x8005, 8)
Natives.special(ctx, Std.SPECIAL.DrawElevatorCurrentFloorWindow, host)
composite()
eq(elevatorFrames(), 1, "still one frame")
check(rowWithText("5F") ~= nil, "now showing sFloorNamePointers[8]")
check(rowWithText("B4F") == nil, "and no longer the old floor")

print("[test] 5. CloseElevatorCurrentFloorWindow takes it off the field")
-- pokefirered/src/field_specials.c:1113
Natives.special(ctx, Std.SPECIAL.CloseElevatorCurrentFloorWindow, host)
eq(ElevatorWindow.isVisible(), false, "the special closed the window")
composite()
eq(elevatorFrames(), 0, "the compositor stops painting it")
eq(rowWithText("Now on:"), nil, "and the header is gone")

print("[test] 6. the draw is a pure paint")
for _, fn in ipairs({ "update", "keypressed", "handleInput", "onInput" }) do
  eq(ElevatorWindow[fn], nil, "ElevatorWindow has no " .. fn .. " hook to steal the floor list")
end
ElevatorWindow.show("2F")
local before = ElevatorWindow.label()
ElevatorWindow.draw()
ElevatorWindow.draw()
eq(ElevatorWindow.label(), before, "drawing does not mutate the window state")
eq(ElevatorWindow.isVisible(), true, "and does not close it")
ElevatorWindow.hide()

print("[test] 7. a soft reset takes the window down with the field script runtime")
-- pokefirered/src/field_specials.c:1113
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local okVm = pcall(Space.activate, nil, "FR_ROCKET_HIDEOUT_ELEVATOR", game, nil)
if okVm and Space.vm then
  Natives.special(ctx, Std.SPECIAL.DrawElevatorCurrentFloorWindow, host)
  eq(ElevatorWindow.isVisible(), true, "the lift window is up while the field script runs")
  composite()
  eq(elevatorFrames(), 1, "and the compositor paints it")
  pcall(Runtime.stop, nil, game)
  eq(Space.vm, nil, "Runtime.stop, what Game3:returnToTitle calls, ended that runtime")
  eq(ElevatorWindow.isVisible(), false, "the window went down with it")
  composite()
  eq(elevatorFrames(), 0, "and nothing paints it after the soft reset")
  local okVm2 = pcall(Space.activate, nil, "FR_PLAYERS_HOUSE_2F", game, nil)
  if okVm2 and Space.vm then
    composite()
    eq(elevatorFrames(), 0, "nor on the field of the session started after it")
    pcall(Runtime.stop, nil, game)
  end
else
  print("[skip] section 7 needs a script bundle: " .. tostring(Space.vm))
end

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL ELEVATOR HUD SEAM TESTS PASSED")
