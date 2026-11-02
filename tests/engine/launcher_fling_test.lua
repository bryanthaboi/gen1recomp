package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Kit = require("src.ui.kit.Kit")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

check(type(Kit.flingSample) == "function" and type(Kit.flingRelease) == "function"
  and type(Kit.flingStep) == "function" and type(Kit.flingStop) == "function",
  "the kit carries the fling integrator")
if type(Kit.flingSample) ~= "function" then T.finish("launcher fling") end

local TAU = Kit.FLING_TAU
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

Kit.flingReset()
for _ = 1, 6 do Kit.flingSample(20, 1 / 60) end
local v = Kit.flingRelease(1)
check(near(v, 1200, 1), "six 20px frames at 60 Hz release at 1200 px/s (got " .. v .. ")")

Kit.flingReset()
for _ = 1, 6 do Kit.flingSample(20, 1 / 60) end
for _ = 1, 8 do Kit.flingSample(0, 1 / 60) end
eq(Kit.flingRelease(1), 0, "a finger held still before lifting does not glide")

Kit.flingReset()
for _ = 1, 12 do Kit.flingSample(1, 1 / 60) end
eq(Kit.flingRelease(1), 0, "a crawl under the start threshold does not glide")

Kit.flingReset()
for _ = 1, 6 do Kit.flingSample(-500, 1 / 60) end
eq(Kit.flingRelease(1), -Kit.FLING_MAX, "a violent flick clamps to the speed cap")
Kit.flingReset()
for _ = 1, 6 do Kit.flingSample(500, 1 / 60) end
eq(Kit.flingRelease(2), 2 * Kit.FLING_MAX, "the cap scales with the UI")

Kit.flingReset()
for _ = 1, 10 do Kit.flingSample(20, 1 / 120) end
Kit.flingSample(20, 0)
check(near(Kit.flingRelease(1), 2640, 1),
  "a move after the last frame folds into it, at 120 Hz too")

local function glide(dt, seconds)
  Kit.fling.v = 1500
  local total = 0
  for _ = 1, math.floor(seconds / dt + 0.5) do total = total + Kit.flingStep(dt, 1) end
  return total
end
local want = 1500 * TAU * (1 - math.exp(-1 / TAU))
local d30, d60, d120 = glide(1 / 30, 1), glide(1 / 60, 1), glide(1 / 120, 1)
check(near(d30, want) and near(d60, want) and near(d120, want),
  "one second of glide travels the same at 30, 60 and 120 Hz")

Kit.fling.v = 1500
local total, last, steps, shrinking = 0, math.huge, 0, true
while Kit.flinging() and steps < 1000 do
  local d = Kit.flingStep(1 / 60, 1)
  if math.abs(d) >= last then shrinking = false end
  last = math.abs(d)
  total = total + d
  steps = steps + 1
end
check(shrinking, "every glide step is shorter than the one before")
check(steps <= 240, "the glide comes to rest within four seconds")
check(total <= 1500 * TAU and total >= 1500 * TAU - Kit.FLING_REST * TAU - 1,
  "and the whole glide travels v * tau")
Kit.fling.v = 900
Kit.flingStop()
eq(Kit.flingStep(1 / 60, 1), 0, "a stopped glide does not move")

Kit.blockClicks = false
Kit._clipRect = nil
Kit.wheelY = 0
Kit.dragBegin(50, 50)
Kit.fling.v = 1200
local inner = 0
for _ = 1, 5 do
  Kit.dragAdd(Kit.flingStep(1 / 60, 1))
  inner = Kit.scrollInput(inner, 100, 0, 0, 100, 100)
end
check(inner > 0 and Kit.flinging(), "an inner list keeps taking the glide after release")
for _ = 1, 60 do
  Kit.dragAdd(Kit.flingStep(1 / 60, 1))
  inner = Kit.scrollInput(inner, 100, 0, 0, 100, 100)
end
eq(inner, 100, "it rests at its end")
eq(Kit.flinging(), false, "and its end stops the glide")
Kit.dragEnd()

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local mods = {}
for i = 1, 60 do
  mods[i] = {
    id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
    status = "ok", badge = "gameplay", description = "a mod",
    enabledByVersion = { red = true },
  }
end

local clock = 50
love.timer.getTime = function() return clock end
love.mouse.getPosition = function() return -100, -100 end
love.mouse.isDown = function() return false end

local function modsLauncher()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab = "mods"
  imp.mods = mods
  imp._ensureMods = function() return mods end
  LauncherView.draw(imp)
  LauncherView.draw(imp)
  return imp
end

local function frame(imp)
  clock = clock + 1 / 60
  LauncherView.update(imp, 1 / 60)
  LauncherView.draw(imp)
end

local function flick(imp, id, x, y, px)
  LauncherView.touchpressed(imp, id, x, y)
  for _ = 1, 6 do
    y = y - px
    LauncherView.touchmoved(imp, id, x, y)
    frame(imp)
  end
  LauncherView.touchreleased(imp, id, x, y)
  return y
end

window(360, 780)
local imp = modsLauncher()
local reg = imp._tabRegionRect
check((imp._tabScrollMax.mods or 0) > 600, "the mods list has room to glide")
local fx, fy = reg.x + 20, reg.y + reg.h - 40
flick(imp, 1, fx, fy, 30)
local released = imp._tabScroll.mods
eq(released, 180, "the finger moved the list by its own travel")
for _ = 1, 10 do frame(imp) end
check(imp._tabScroll.mods > released + 100,
  "the list keeps moving after the finger lifts (" .. released .. " -> "
    .. imp._tabScroll.mods .. ")")
check(imp._fling ~= nil, "and is still gliding")

local caughtAt = imp._tabScroll.mods
LauncherView.touchpressed(imp, 2, fx, reg.y + 60)
LauncherView.touchreleased(imp, 2, fx, reg.y + 60)
eq(imp._clickPt, nil, "a tap that catches the glide is not a tap")
frame(imp)
eq(imp._tabScroll.mods, caughtAt, "and the list stops where it was caught")
eq(Kit.flinging(), false, "with no glide left")
eq(imp._fling, nil, "and no glide state on the launcher")

LauncherView.touchpressed(imp, 3, fx, reg.y + 60)
LauncherView.touchreleased(imp, 3, fx, reg.y + 60)
check(imp._clickPt ~= nil, "the next tap on a resting list is a tap again")
imp._clickPt = nil
LauncherView.draw(imp)

local slow = modsLauncher()
local sAt0 = slow._tabScroll.mods or 0
LauncherView.touchpressed(slow, 4, fx, fy)
local sy = fy
for _ = 1, 30 do
  sy = sy - 1
  LauncherView.touchmoved(slow, 4, fx, sy)
  frame(slow)
end
LauncherView.touchreleased(slow, 4, fx, sy)
local slowAt = slow._tabScroll.mods
check(slowAt > sAt0, "a slow drag still scrolls")
for _ = 1, 10 do frame(slow) end
eq(slow._tabScroll.mods, slowAt, "but a slow drag does not glide")

local edge = modsLauncher()
local emax = edge._tabScrollMax.mods
edge._tabScroll.mods = emax - 200
LauncherView.draw(edge)
flick(edge, 5, fx, fy, 30)
for _ = 1, 10 do frame(edge) end
eq(edge._tabScroll.mods, emax, "a glide into the end of the list rests at the end")
eq(edge._fling, nil, "and the end stops the glide")
eq(Kit.flinging(), false, "with no velocity left")

local modal = modsLauncher()
flick(modal, 6, fx, fy, 30)
frame(modal)
check(modal._fling ~= nil, "the list is gliding")
modal._modActions = "mod1"
LauncherView.draw(modal)
local shieldedAt = modal._tabScroll.mods
frame(modal)
frame(modal)
eq(modal._tabScroll.mods, shieldedAt, "a modal opening over the list stops the glide")
eq(modal._fling, nil, "and clears it")
modal._modActions = nil

local wheel = modsLauncher()
flick(wheel, 7, fx, fy, 30)
frame(wheel)
LauncherView.wheelmoved(wheel, 0, -1)
eq(wheel._fling, nil, "a wheel notch stops a glide")

local mouse = modsLauncher()
local mdown, mx, my = false, fx, fy
love.mouse.isDown = function() return mdown end
love.mouse.getPosition = function() return mx, my end
mdown = true
frame(mouse)
for _ = 1, 6 do
  my = my - 30
  frame(mouse)
end
mdown = false
frame(mouse)
local mouseAt = mouse._tabScroll.mods
check(mouseAt > 0, "a mouse drag scrolls the list")
for _ = 1, 10 do frame(mouse) end
eq(mouse._tabScroll.mods, mouseAt, "and stays put when the button lets go")
eq(mouse._fling, nil, "a mouse drag never glides")
love.mouse.isDown = function() return false end
love.mouse.getPosition = function() return -100, -100 end

T.finish("launcher fling")
