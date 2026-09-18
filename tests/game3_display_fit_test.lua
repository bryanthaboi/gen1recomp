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

local win = { w = 1024, h = 768, pw = 1024, ph = 768 }
local canvasCalls = {}

local fakeCanvas = {}
fakeCanvas.__index = fakeCanvas
function fakeCanvas:getWidth() return self.w end
function fakeCanvas:getHeight() return self.h end
function fakeCanvas:setFilter() end

_G.love = {
  graphics = {
    getDimensions = function() return win.w, win.h end,
    getPixelDimensions = function() return win.pw, win.ph end,
    getDPIScale = function() return win.ph / win.h end,
    newCanvas = function(w, h, settings)
      canvasCalls[#canvasCalls + 1] = { w = w, h = h, settings = settings }
      return setmetatable({ w = w, h = h }, fakeCanvas)
    end,
  },
}

package.loaded["src.core.SafeArea"] = {
  windowRect = function() return 0, 0, win.w, win.h end,
}

local Display = require("src.core.game3.display")

local function isWhole(v)
  return math.abs(v - math.floor(v + 0.5)) < 1e-6
end

local function case(w, h, dpi, expectK)
  win.w, win.h = w, h
  win.pw, win.ph = math.floor(w * dpi + 0.5), math.floor(h * dpi + 0.5)
  local scale, ox, oy, pw, ph, scaleY = Display.fit(w, h)
  scaleY = scaleY or scale
  local dx, dy = win.pw / w, win.ph / h
  local label = ("%dx%d dpi %g"):format(w, h, dpi)
  check(isWhole(scale * dx) and isWhole(scaleY * dy),
    label .. " whole physical pixels per texel (scale " .. tostring(scale) .. ")")
  check(math.abs(scale * dx - scaleY * dy) < 1e-6, label .. " square texels")
  check(isWhole(ox * dx) and isWhole(oy * dy),
    label .. " offsets on physical pixels (" .. tostring(ox) .. "," .. tostring(oy) .. ")")
  check(ox >= 0 and ox + pw <= w + 1e-6 and oy >= 0 and oy + ph <= h + 1e-6,
    label .. " frame inside window")
  if expectK then
    check(math.abs(scale * dx - expectK) < 1e-6,
      label .. " scale is " .. expectK .. "x (got " .. tostring(scale * dx) .. ")")
  end
end

case(1024, 768, 1, 4)
case(1360, 860, 1, 5)
case(1100, 1000, 1, 4)
case(900, 1100, 1, 3)
case(700, 1000, 1, 2)
case(1080, 1920, 1, 4)
case(390, 844, 3, 4)
case(392, 870, 2.755, 4)

win.w, win.h, win.pw, win.ph = 1360, 860, 1360, 860
local s, ox, oy = Display.fit(1360, 860)
check(s == 5 and ox == 80 and oy == 30, "desktop 1360x860 unchanged (5x at 80,30)")
win.w, win.h, win.pw, win.ph = 1100, 1000, 1100, 1000
s, ox, oy = Display.fit(1100, 1000)
check(s == 4 and ox == 70 and oy == 180, "desktop 1100x1000 unchanged (4x at 70,180)")

Display._canvas = nil
Display.ensureCanvas("main")
local last = canvasCalls[#canvasCalls]
check(last and last.w == 240 and last.h == 160, "canvas is 240x160")
check(last and last.settings and last.settings.dpiscale == 1, "canvas created at dpiscale 1")

print(("game3_display_fit_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
os.exit(failed == 0 and 0 or 1)
