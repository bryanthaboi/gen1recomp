package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Input = require("src.core.Input")

local realJoystick = love.joystick

local function newPad(name)
  local p = { down = {}, axes = {} }
  p.isGamepad = function() return true end
  p.isGamepadDown = function(_, button) return p.down[button] == true end
  p.getGamepadAxis = function(_, axis) return p.axes[axis] or 0 end
  p.getName = function() return name end
  p.getGUID = function() return "030000005e040000" end
  p.isConnected = function() return true end
  return p
end

local padA, padB = newPad("Pad A"), newPad("Pad B")
love.joystick = {
  getJoystickCount = function() return 2 end,
  getJoysticks = function() return { padA, padB } end,
}

local function fresh()
  Input:init()
  Input:applyBindings(nil)
  Input:reset()
  padA.down, padA.axes, padB.down, padB.axes = {}, {}, {}, {}
  Input:step()
end

local function edges(btn, steps)
  local n = 0
  for _ = 1, steps or 1 do
    Input:step()
    if Input:wasPressed(btn) then n = n + 1 end
  end
  return n
end

fresh()
Input:keypressed("down")
eq(edges("down"), 1, "first source edges once")
padA.down.dpdown = true
Input:gamepadpressed(nil, "dpdown")
eq(edges("down"), 0, "a second source on a held button adds no edge")
Input:keyreleased("down")
eq(edges("down"), 0, "releasing one of two sources adds no edge")
check(Input:isDown("down"), "the remaining source keeps the hold")
padA.down.dpdown = false
Input:gamepadreleased(nil, "dpdown")
Input:step()
check(not Input:isDown("down"), "the hold ends with the last source")
padA.down.dpdown = true
Input:gamepadpressed(nil, "dpdown")
eq(edges("down"), 1, "a fresh press edges again")
padA.down.dpdown = false
Input:gamepadreleased(nil, "dpdown")

fresh()
padA.down.dpdown, padB.down.dpdown = true, true
Input:gamepadpressed(padA, "dpdown")
Input:gamepadpressed(padB, "dpdown")
eq(edges("down"), 1, "two pads mirroring one press edge once")
padA.down.dpdown = false
Input:gamepadreleased(padA, "dpdown")
eq(edges("down", 3), 0, "the first pad letting go does not re-press through the poll")
check(Input:isDown("down"), "the lagging pad keeps the hold")
padB.down.dpdown = false
Input:gamepadreleased(padB, "dpdown")
eq(edges("down", 2), 0, "the lagging release adds no edge")
check(not Input:isDown("down"), "both pads up releases the button")

fresh()
local function axis(pad, name, v)
  pad.axes[name] = v
  Input:gamepadaxis(pad, name, v)
end
axis(padA, "lefty", 0.6)
eq(edges("down"), 1, "stick push edges once")
axis(padB, "lefty", 0.1)
axis(padA, "lefty", 0.9)
eq(edges("down", 2), 0, "a lagging mirror pad cannot release and re-press the stick")
check(Input:isDown("down"), "the stick hold survives the mirror pad's stale value")
axis(padA, "lefty", 0)
Input:step()
check(not Input:isDown("down"), "the owning pad releases the stick")
axis(padB, "lefty", 0.8)
eq(edges("down"), 1, "the other pad can take the stick once it is free")
axis(padB, "lefty", 0)

love.joystick = realJoystick
T.finish()
