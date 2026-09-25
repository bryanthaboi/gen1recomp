package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PadHints = require("src.core.PadHints")

local function fakeFfi(opts)
  opts = opts or {}
  local calls = {}
  local ffi = {
    cdef = function() end,
    load = function(name)
      calls[#calls + 1] = { "load", name }
      if opts.loadThrows then error("no SDL2 here") end
      return {
        SDL_SetHint = function(name2, value)
          calls[#calls + 1] = { "hint", name2, value }
          return 1
        end,
      }
    end,
  }
  return ffi, calls
end

local function env(values)
  return function(k) return values[k] end
end

local ffi, calls = fakeFfi()
check(PadHints.apply("Windows", ffi, env({})), "Windows sets the hint")
eq(calls[1] and calls[1][2], "SDL2", "the hint goes through SDL2.dll")
eq(calls[2] and calls[2][2], "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "hint name")
eq(calls[2] and calls[2][3], "1", "hint value")

for _, name in ipairs({ "OS X", "Linux", "Android", "iOS", "NX" }) do
  local f, c = fakeFfi()
  check(not PadHints.apply(name, f, env({})), name .. " leaves the hint alone")
  eq(#c, 0, name .. " never touches SDL")
end

local f0, c0 = fakeFfi()
check(not PadHints.apply("Windows", f0, env({ POKEPORT_PAD_BACKGROUND = "0" })),
  "POKEPORT_PAD_BACKGROUND=0 opts out")
eq(#c0, 0, "and never loads SDL2")

local f1, c1 = fakeFfi()
check(PadHints.apply("Windows", f1, env({ POKEPORT_PAD_BACKGROUND = "1" })),
  "POKEPORT_PAD_BACKGROUND=1 still sets it")
eq(#c1, 2, "one load and one hint")

local fThrow = fakeFfi({ loadThrows = true })
local okThrow, result = pcall(PadHints.apply, "Windows", fThrow, env({}))
check(okThrow, "a throwing ffi.load is swallowed")
check(result == false, "and reports the hint as unset")

local savedWindow = love.window
local minimized, focused = false, true
love.window = {
  isMinimized = function() return minimized end,
  isVisible = function() return not minimized end,
  hasFocus = function() return focused end,
}
check(not PadHints.windowMinimized(), "a shown window is not minimized")
minimized = true
check(PadHints.windowMinimized(), "a minimized window is")
minimized = false
focused = false
check(not PadHints.windowMinimized(), "losing focus alone does not count as minimized")
love.window = { isVisible = function() return false end }
check(PadHints.windowMinimized(), "isVisible false is the fallback")
love.window = { isMinimized = function() error("boom") end }
check(not PadHints.windowMinimized(), "a throwing window query reads as shown")
love.window = nil
check(not PadHints.windowMinimized(), "no window module reads as shown")

local Input = require("src.core.Input")
local physical = {}
local pad = {
  isGamepad = function() return true end,
  isGamepadDown = function(_, button) return physical[button] == true end,
  getGamepadAxis = function() return 0 end,
  getName = function() return "Xbox Controller" end,
  getGUID = function() return "030000005e040000" end,
  isConnected = function() return true end,
}
local savedJoystick = love.joystick
love.joystick = {
  getJoystickCount = function() return 1 end,
  getJoysticks = function() return { pad } end,
}
minimized, focused = false, false
love.window = {
  isMinimized = function() return minimized end,
  isVisible = function() return not minimized end,
  hasFocus = function() return focused end,
}

Input:init()
Input:applyBindings(nil)
Input:reset()
Input:step()

physical.a = true
Input:step()
check(Input:wasPressed("a"), "unfocused but shown: the pad A press still lands")
physical.a = false
Input:step()
check(not Input:isDown("a"), "and releases")

minimized = true
physical.a = true
Input:step()
check(not Input:wasPressed("a"), "minimized: a pad press is dropped")
check(not Input:isDown("a"), "and never held")
physical.a = false
Input:step()
minimized = false
Input:step()
physical.a = true
Input:step()
check(Input:wasPressed("a"), "restored: the next press lands")
physical.a = false
Input:step()

local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")
local savedSystem = love.system
love.system = { getOS = function() return "OS X" end }
SwitchDiagnostics._resetForTests()
love.filesystem.write("switch-debug.txt", "")
focused = false
SwitchDiagnostics.onFocus(false)
SwitchDiagnostics.onJoystickEvent("gamepadpressed", pad, "a")
focused = true
SwitchDiagnostics.onFocus(true)
SwitchDiagnostics.maybeFlush(true, 100)
local log = love.filesystem.read("switch.log") or ""
check(log:find("focus f=false hasFocus=false visible=true", 1, true) ~= nil,
  "focus loss lands in the ring with hasFocus and visible")
check(log:find("focus f=true hasFocus=true visible=true", 1, true) ~= nil,
  "focus gain lands in the ring")
check(log:find("gamepadpressed button=a guid=030000005e040000 hf=false", 1, true) ~= nil,
  "joystick lines carry hf=")
check(not log:find("fg=", 1, true), "fg= is Windows only")

eq(PadHints.foreground("OS X"), nil, "foreground probe is Windows only")
PadHints._resetForTests()
local fgFfi = {
  cdef = function() end,
  C = {
    GetForegroundWindow = function() return {} end,
    GetWindowThreadProcessId = function(_, pid) pid[0] = 42 end,
    GetCurrentProcessId = function() return 42 end,
  },
  new = function() return {} end,
}
eq(PadHints.foreground("Windows", fgFfi), "ours", "our foreground window reads ours")
fgFfi.C.GetCurrentProcessId = function() return 7 end
eq(PadHints.foreground("Windows", fgFfi), "other", "another process reads other")
PadHints._resetForTests()
eq(PadHints.foreground("Windows", { cdef = function() end, C = {} }), nil,
  "a missing user32 export is swallowed")

love.filesystem.remove("switch-debug.txt")
love.filesystem.remove("switch.log")
SwitchDiagnostics._resetForTests()
PadHints._resetForTests()
love.window, love.joystick, love.system = savedWindow, savedJoystick, savedSystem

T.finish("pad hints bug 2452")
