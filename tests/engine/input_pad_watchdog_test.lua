package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Input = require("src.core.Input")
local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")

local realJoystick = love.joystick
local physical = {}
local pad = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, button) return physical[button] == true end,
  getGamepadAxis = function() return 0 end,
  getName = function() return "Xbox Controller" end,
  getGUID = function() return "030000005e040000" end,
  isConnected = function() return true end,
}
love.joystick = {
  getJoystickCount = function() return 1 end,
  getJoysticks = function() return { pad } end,
}

Input:init()
Input:applyBindings(nil)
Input:reset()
Input:step()

physical.a = true
Input:step()
check(Input:wasPressed("a"), "lost press event still yields one A edge")
check(Input:isDown("a"), "lost press event still holds A")
Input:step()
check(not Input:wasPressed("a"), "held A does not re-edge")
physical.a = false
Input:step()
check(not Input:isDown("a"), "lost release event still releases A")

physical.a = true
Input:gamepadpressed(pad, "a")
Input:step()
check(Input:wasPressed("a"), "event + poll agree on the press")
Input:step()
check(not Input:wasPressed("a"), "event + poll never double-edge")
physical.a = false
Input:gamepadreleased(pad, "a")
Input:step()
check(not Input:isDown("a"), "event release stays released")

physical.a = true
Input:gamepadpressed(pad, "a")
Input:step()
physical.a = false
Input:step()
check(not Input:isDown("a"), "stuck A clears when the pad reports it up")
Input:step()
physical.a = true
Input:step()
check(Input:wasPressed("a"), "next physical A press works without alt-tab")
physical.a = false
Input:step()

Input:armCapture()
physical.b = true
Input:step()
check(not Input:isDown("b"), "capture-armed press is not injected")
physical.b = false
Input:step()
Input:disarmCapture()

physical.back = true
Input:gamepadpressed(pad, "back")
Input:step()
physical.a = true
Input:step()
check(not Input:wasPressed("a"), "SELECT+A display chord is not injected as A")
physical.a = false
physical.back = false
Input:gamepadreleased(pad, "back")
Input:step()

Input:applyBindings({ speedUp = { pad = "start" } })
physical.start = true
Input:step()
check(not Input:isDown("start"), "a speed-bound button is not injected")
physical.start = false
Input:step()
Input:applyBindings(nil)

local function countEdges(btn, steps)
  local n = 0
  for _ = 1, steps do
    Input:step()
    if Input:wasPressed(btn) then n = n + 1 end
  end
  return n
end

physical.back = true
Input:padEventSeen("back")
Input:gamepadpressed(pad, "back")
Input:step()
physical.a = true
Input:padEventSeen("a")
Input:step()
physical.back = false
Input:gamepadreleased(pad, "back")
eq(countEdges("a", 10), 0, "SELECT+A chord, SELECT released first: no phantom A")
check(not Input:isDown("a"), "SELECT+A chord, SELECT released first: A not held")
physical.a = false
Input:step()
physical.a = true
Input:step()
check(Input:wasPressed("a"), "a fresh A after the chord still gets repaired")
physical.a = false
Input:step()

for _, b in ipairs({ "a", "b", "start", "back" }) do
  physical[b] = true
  Input:padEventSeen(b)
  Input:gamepadpressed(pad, b)
end
Input:step()
Input:reset()
local resetEdges = 0
for _ = 1, 10 do
  Input:step()
  for _, b in ipairs({ "a", "b", "start", "select" }) do
    if Input:wasPressed(b) then resetEdges = resetEdges + 1 end
  end
end
eq(resetEdges, 0, "soft reset with the chord held: no re-edge on the title")
physical.back = false
eq(countEdges("a", 5) + countEdges("b", 5), 0, "soft reset: A/B do not edge once SELECT lets go")
physical.a, physical.b, physical.start = false, false, false
Input:step()

physical.a = true
Input:padEventSeen("a")
Input:gamepadpressed(pad, "a")
Input:step()
Input:reset()
eq(countEdges("a", 10), 0, "focus reset with A held: no phantom A")
physical.a = false
Input:step()

local AutoInput = require("src.core.gen2.AutoInput")
physical.a = true
Input:padEventSeen("a")
Input:gamepadpressed(pad, "a")
Input:step()
local auto = AutoInput.new()
auto:start("CATCH_TUTORIAL", Input)
local autoEdges, autoHeld = 0, 0
for _ = 1, 30 do
  auto:step(Input)
  Input:step()
  if Input:wasPressed("a") then autoEdges = autoEdges + 1 end
  if Input:isDown("a") then autoHeld = autoHeld + 1 end
end
eq(autoEdges, 0, "AutoInput stream: a held pad A never presses A")
eq(autoHeld, 0, "AutoInput stream: a held pad A is never held")
auto:stop(Input)
physical.a = false
Input:gamepadreleased(pad, "a")
Input:step()
Input:step()

love.filesystem.remove("pad-reconcile.log")
SwitchDiagnostics._resetForTests()
love.filesystem.write("switch-debug.txt", "")
SwitchDiagnostics._resetForTests()
love.filesystem.write("switch-debug.txt", "")
SwitchDiagnostics.onJoystickEvent("gamepadpressed", pad, "a")
physical.a = true
Input:reset()
Input:reconcile()
local log = love.filesystem.read("pad-reconcile.log") or ""
check(log:find("=== reconcile", 1, true) ~= nil, "focus-in reconcile writes a trace block")
check(log:find("down=a", 1, true) ~= nil, "trace records what SDL reports held")
check(log:find("gamepadpressed", 1, true) ~= nil, "trace carries the recent event ring")
check((love.filesystem.read("switch.log") or ""):find("reconcile", 1, true) ~= nil,
  "switch.log is flushed on reconcile")
physical.a = false
love.filesystem.remove("switch-debug.txt")
love.filesystem.remove("pad-reconcile.log")
love.filesystem.remove("switch.log")
SwitchDiagnostics._resetForTests()

love.joystick = { getJoystickCount = function() return 0 end, getJoysticks = function() return {} end }
Input:reset()
Input:gamepadpressed(nil, "a")
Input:step()
check(Input:isDown("a"), "no pads connected leaves event state alone")
Input:gamepadreleased(nil, "a")
Input:step()

love.joystick = realJoystick
eq(type(Input.pollPads), "function", "pollPads exported")
T.finish()
