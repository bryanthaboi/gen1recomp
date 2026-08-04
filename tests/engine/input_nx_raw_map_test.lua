-- NX raw fallback + Nintendo face remap (SWNX-11).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")

GamepadMap._setForceNXForTests(true)

eq(GamepadMap.mapGamepadButton("b"), "a", "NX physical A (SDL b) -> GB A")
eq(GamepadMap.mapGamepadButton("a"), "b", "NX physical B (SDL a) -> GB B")
eq(GamepadMap.mapRawButton(1), "b", "NX raw #1 Nintendo B -> GB B")
eq(GamepadMap.mapRawButton(2), "a", "NX raw #2 Nintendo A -> GB A")
eq(GamepadMap.mapRawToGamepadButton(1), "a", "NX raw #1 routes as SDL south name")
eq(GamepadMap.mapRawToGamepadButton(2), "b", "NX raw #2 routes as SDL east name")
eq(GamepadMap.mapRawButton(9), "select", "NX minus (#9) -> select")
eq(GamepadMap.mapRawButton(10), "start", "NX plus (#10) -> start")

GamepadMap._setForceNXForTests(false)

T.finish()
