-- Shared gamepad/raw map: launcher and gameplay use identical converters (SWNX-10/11).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")
local Input = require("src.core.Input")
local RomImporter = require("src.import.RomImporter")

-- Gamepad names map to GB actions.
eq(GamepadMap.mapGamepadButton("a"), "a", "gamepad A -> GB A")
eq(GamepadMap.mapGamepadButton("back"), "select", "gamepad back -> select")
eq(GamepadMap.mapGamepadButton("dpup"), "up", "gamepad d-pad up")

-- Generic raw indices (Linux handheld fallback).
eq(GamepadMap.mapRawButton(1), "a", "raw #1 -> A")
eq(GamepadMap.mapRawButton(8), "start", "raw #8 -> start")
eq(GamepadMap.mapRawToGamepadButton(2), "b", "raw #2 routes to gamepad b")

-- Input and RomImporter agree on the same GB action for a raw press.
Input:init()
Input:joystickpressed(nil, 1)
Input:step()
check(Input:isDown("a"), "Input raw #1 holds A")

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
  clickAt = function(_, x, y)
    clicked = (x == 0 and y == 0)
  end,
}
importer:joystickpressed(nil, 1)
package.loaded["src.import.LauncherView"] = prevView
check(clicked, "RomImporter raw #1 clicks via shared map (not hardcoded-only)")

importer:joystickpressed(nil, 2)
check(importer._padDir.dpright == nil,
  "raw #2 maps to B, not spurious d-pad")

T.finish()
