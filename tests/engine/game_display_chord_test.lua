-- Select+face chords fire Game:keypressed digits (NXMOD-06..10).
-- Spec: Select held + A/B/Y/X/L → keys 2/3/5/6/7; without Select, face stays GB.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local GamepadMap = require("src.core.GamepadMap")

local joy = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, button) return false end,
}

local digits = {}
local padForwarded = {}
local wroteOptions = false

local origKeypressed = Game.keypressed
local origPad = Input.gamepadpressed
local origWrite = Game.writeOptions

function Game:keypressed(key)
  digits[#digits + 1] = key
  -- Mimic digit persistence side-effect for keys that write options.
  if key == "2" or key == "3" or key == "5" or key == "6" or key == "7" then
    wroteOptions = true
  end
end

function Input:gamepadpressed(joystick, button)
  padForwarded[#padForwarded + 1] = button
  return origPad(self, joystick, button)
end

local function resetSpies()
  digits = {}
  padForwarded = {}
  wroteOptions = false
end

local function holdSelect()
  Input:init()
  -- Press Select (SDL back) into Input so isDown("select") is true.
  origPad(Input, joy, "back")
  Input:step()
  check(Input:isDown("select"), "Select held via Input")
end

-- --- Without Select: face buttons keep normal GB path (NXMOD-09) ---
GamepadMap._setForceNXForTests(false)
Input:init()
resetSpies()
Game:gamepadpressed(joy, "a")
eq(#digits, 0, "no digit without Select")
eq(#padForwarded, 1, "face reaches Input without Select")
eq(padForwarded[1], "a", "Input receives face a")
check(not wroteOptions, "no options write without Select chord")

-- --- Select + face → same digit path as PC keys (NXMOD-06..08, NXMOD-10) ---
local chordCases = {
  { button = "a", digit = "2", label = "Select+A -> 2" },
  { button = "b", digit = "3", label = "Select+B -> 3" },
  { button = "y", digit = "5", label = "Select+Y -> 5" },
  { button = "x", digit = "6", label = "Select+X -> 6" },
  { button = "leftshoulder", digit = "7", label = "Select+L -> 7" },
}

for _, case in ipairs(chordCases) do
  holdSelect()
  resetSpies()
  Game:gamepadpressed(joy, case.button)
  eq(#digits, 1, case.label .. " fires keypressed once")
  eq(digits[1], case.digit, case.label)
  eq(#padForwarded, 0, case.label .. " does not forward face to Input")
  check(wroteOptions, case.label .. " uses digit options path")
end

-- --- NX Nintendo UX: physical A (SDL b) → 2, physical B (SDL a) → 3 ---
GamepadMap._setForceNXForTests(true)
holdSelect()
resetSpies()
Game:gamepadpressed(joy, "b") -- physical Nintendo A
eq(digits[1], "2", "NX Select+physical A (SDL b) -> key 2")
eq(#padForwarded, 0, "NX chord A does not forward face")
check(wroteOptions, "NX chord A options path")

holdSelect()
resetSpies()
Game:gamepadpressed(joy, "a") -- physical Nintendo B
eq(digits[1], "3", "NX Select+physical B (SDL a) -> key 3")
eq(#padForwarded, 0, "NX chord B does not forward face")

-- Without Select on NX, face still goes to Input (no accidental cycle).
Input:init()
resetSpies()
Game:gamepadpressed(joy, "b")
eq(#digits, 0, "NX no digit without Select")
eq(#padForwarded, 1, "NX face reaches Input without Select")

-- Dual-path Select: joystick isGamepadDown("back") also counts as held.
GamepadMap._setForceNXForTests(false)
Input:init()
resetSpies()
local joySelectDown = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, button) return button == "back" end,
}
Game:gamepadpressed(joySelectDown, "y")
eq(digits[1], "5", "Select via isGamepadDown(back) + Y -> 5")
eq(#padForwarded, 0, "isGamepadDown Select chord does not forward face")

-- Edge: face chords without Select must not cycle digits (NXMOD-09).
-- leftshoulder without Select is the GAME SPEED hotkey (upstream), so it
-- does not reach Input — only face buttons do.
GamepadMap._setForceNXForTests(false)
for _, btn in ipairs({ "a", "b", "y", "x" }) do
  Input:init()
  resetSpies()
  Game:gamepadpressed(joy, btn)
  eq(#digits, 0, "edge: no cycle without Select for " .. btn)
  eq(#padForwarded, 1, "edge: " .. btn .. " still reaches Input without Select")
  check(not wroteOptions, "edge: no options write without Select for " .. btn)
end

-- leftshoulder alone cycles speed (does not forward / does not digit).
do
  local sped = 0
  local origCycle = Game._cycleSpeed
  function Game:_cycleSpeed(dir) sped = sped + (dir or 0) end
  Input:init()
  resetSpies()
  Game:gamepadpressed(joy, "leftshoulder")
  eq(#digits, 0, "edge: L alone does not fire display digit")
  eq(#padForwarded, 0, "edge: L alone does not forward to Input (speed hotkey)")
  eq(sped, -1, "edge: L alone cycles GAME SPEED down")
  Game._cycleSpeed = origCycle
end

-- Select+L still wins over the speed hotkey.
holdSelect()
resetSpies()
do
  local sped = 0
  local origCycle = Game._cycleSpeed
  function Game:_cycleSpeed(dir) sped = sped + (dir or 0) end
  Game:gamepadpressed(joy, "leftshoulder")
  eq(digits[1], "7", "Select+L still fires display digit 7")
  eq(sped, 0, "Select+L does not cycle GAME SPEED")
  eq(#padForwarded, 0, "Select+L does not forward L to Input")
  Game._cycleSpeed = origCycle
end

-- Edge: Select alone (no face) does not synthesize a digit
holdSelect()
resetSpies()
-- pressing back again while held is not a display chord partner
Game:gamepadpressed(joy, "back")
eq(#digits, 0, "edge: Select alone does not fire a display digit")
eq(#padForwarded, 1, "edge: Select alone still forwards to Input")

GamepadMap._setForceNXForTests(false)
Game.keypressed = origKeypressed
Input.gamepadpressed = origPad
Game.writeOptions = origWrite

T.finish()
