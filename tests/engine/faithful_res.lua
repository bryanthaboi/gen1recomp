-- FAITHFUL RATIO: lock the window to an exact 160x144 multiple so the surface
-- is the Game Boy screen with no letterbox at all.
--
-- The interesting parts are the two things a naive setMode gets wrong: the
-- window minimum from conf.lua (480x360) sits ABOVE 1X and 2X, so the lock
-- has to lower it or LOVE clamps the window straight back up; and on a HiDPI
-- display a LOVE unit is more than a pixel, so asking for the pixel count
-- directly gives a window twice the size intended.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FaithfulRes = require("src.core.FaithfulRes")

-- ---------------------------------------------------------------- values

T.eq(FaithfulRes.normalize(nil), 0, "no setting is OFF")
T.eq(FaithfulRes.normalize("junk"), 0, "garbage degrades to OFF")
T.eq(FaithfulRes.normalize(-3), 0, "negatives clamp to OFF")
T.eq(FaithfulRes.normalize(9), 4, "above 4X clamps to 4X")
T.eq(FaithfulRes.normalize(2.7), 2, "fractions floor to a whole multiple")

T.eq(FaithfulRes.label(0), "OFF", "0 reads OFF")
T.eq(FaithfulRes.label(1), "1X", "1 reads 1X")
T.eq(FaithfulRes.label(4), "4X", "4 reads 4X")

-- the row cycles OFF -> 1X -> 2X -> 3X -> 4X -> OFF
local seen, v = {}, 0
for _ = 1, 5 do
  seen[#seen + 1] = FaithfulRes.label(v)
  v = FaithfulRes.cycle(v, 1)
end
T.eq(table.concat(seen, ","), "OFF,1X,2X,3X,4X", "the row cycles through OFF..4X")
T.eq(FaithfulRes.cycle(4, 1), 0, "and wraps back to OFF")
T.eq(FaithfulRes.cycle(0, -1), 4, "stepping back from OFF lands on 4X")

-- ---------------------------------------------------------------- sizing

local savedWindow = love.window
local savedSystem = love.system
local savedDims = love.graphics and love.graphics.getDimensions
local savedPixels = love.graphics and love.graphics.getPixelDimensions

-- `ratio` is PHYSICAL PIXELS PER UNIT, which is what the window reports and
-- what FaithfulRes measures -- not love.window.getDPIScale, which lies about
-- a window that is not high-DPI aware (that was the bug).
local function stubWindow(ratio)
  local calls = {}
  love.graphics = love.graphics or {}
  love.graphics.getDimensions = function() return 1024, 768 end
  love.graphics.getPixelDimensions = function()
    return 1024 * ratio, 768 * ratio
  end
  love.window = {
    -- deliberately WRONG, and deliberately present: nothing may read it
    getDPIScale = function() return 999 end,
    getMode = function()
      return 1024, 768, { fullscreen = true, resizable = true,
                          minwidth = 480, minheight = 360, vsync = 1 }
    end,
    setMode = function(w, h, flags)
      calls[#calls + 1] = { w = w, h = h, flags = flags }
    end,
  }
  return calls
end

-- A plain desktop window reports units == pixels, whatever the DISPLAY
-- scaling is.  Dividing by the display scale here is what made 2X render at
-- 1X and 4X at 3X, so the stub returns a nonsense getDPIScale to prove
-- nothing consults it.
stubWindow(1)
local w, h = FaithfulRes.size(2)
T.eq(w, 320, "2X is 320 units wide when a unit is a pixel")
T.eq(h, 288, "2X is 288 units tall when a unit is a pixel")
T.eq(FaithfulRes.size(0), nil, "OFF has no size")

local w4, h4 = FaithfulRes.size(4)
T.eq(w4, 640, "4X is 640 wide, not shrunk by the display scale")
T.eq(h4, 576, "4X is 576 tall")

-- a genuinely high-DPI window reports more pixels than units, so the unit
-- size halves to keep the PHYSICAL pixel count exact
stubWindow(2)
local w2, h2 = FaithfulRes.size(2)
T.eq(w2, 160, "2X asks for 160 units at 2 px/unit, which is 320 pixels")
T.eq(h2, 144, "and 144 units, which is 288 pixels")

-- ---------------------------------------------------------------- applying

FaithfulRes.locked = false
local calls = stubWindow(1)
love.system = { getOS = function() return "Windows" end }

-- OFF on boot must not touch a window the player sized themselves
T.eq(FaithfulRes.apply(0), false, "OFF reports unlocked")
T.eq(#calls, 0, "and does not resize an unlocked window on boot")

T.eq(FaithfulRes.apply(3), true, "3X reports locked")
T.eq(#calls, 1, "which took one setMode")
T.eq(calls[1].w, 480, "3X is 480 wide")
T.eq(calls[1].h, 432, "3X is 432 tall")
T.eq(calls[1].flags.fullscreen, false,
  "an exact size drops fullscreen -- the two cannot both hold")
T.eq(calls[1].flags.resizable, false,
  "and fixes the window, since a drag would silently break the lock")

-- 1X and 2X are below conf.lua's 480x360 floor; without lowering it LOVE
-- clamps the window back up and the lock silently does nothing
calls = stubWindow(1)
FaithfulRes.apply(1)
T.eq(calls[1].w, 160, "1X is 160 wide")
T.eq(calls[1].flags.minwidth, 160, "and lowers the window minimum to match")
T.eq(calls[1].flags.minheight, 144, "on both axes")

-- releasing the lock restores the resizable window and its original floor
calls = stubWindow(1)
T.eq(FaithfulRes.apply(0), false, "OFF reports unlocked")
T.eq(#calls, 1, "and this time it does resize, because we held the window")
T.eq(calls[1].flags.resizable, true, "handing resizing back to the player")
T.eq(calls[1].flags.minwidth, FaithfulRes.MIN_W, "with conf.lua's floor restored")
T.eq(calls[1].flags.minheight, FaithfulRes.MIN_H, "on both axes")
T.eq(FaithfulRes.locked, false, "and the module no longer claims the window")

-- Mobile has no resizable window to lock, so it locks the RENDER scale
-- instead and never calls setMode.  It used to report unlocked and do
-- nothing at all, which is why the OPTIONS row was inert on Android and iOS;
-- tests/engine/faithful_res_mobile.lua covers the scale side.
calls = stubWindow(1)
love.system = { getOS = function() return "Android" end }
T.eq(FaithfulRes.apply(4), true, "mobile locks, by capping the render scale")
-- the level asked for is irrelevant on mobile: ON is ON, and the scale is
-- read off the display so the picture is as big as exact pixels allow
T.eq(FaithfulRes.scaleCap(), FaithfulRes.deviceScale(),
     "and the scale comes from the display, not from the level")
T.eq(#calls, 0, "still without ever touching the window")
T.eq(FaithfulRes.apply(0), false, "OFF releases it")
T.eq(FaithfulRes.scaleCap(), nil, "and the cap goes away with it")
T.eq(#calls, 0, "the window is left alone either way")
FaithfulRes.mobileScale = 0

love.window, love.system = savedWindow, savedSystem
if love.graphics then
  love.graphics.getDimensions = savedDims
  love.graphics.getPixelDimensions = savedPixels
end
T.finish("faithful resolution")
