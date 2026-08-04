-- FAITHFUL RATIO on Android / iOS.
--
-- On mobile the setting is ON or OFF, and ON means one thing: lock the
-- viewport to the Game Boy's 10:9 at the largest WHOLE multiple this screen
-- can hold, centred, black around it -- the way an emulator opens a Game Boy
-- game on a phone.
--
-- Three things had to be true and none of them were:
--
--   * it had to apply at all.  FaithfulRes.apply returned false on its first
--     line for mobile, so the OPTIONS row did nothing on Android and iOS.
--     A phone has no window to resize, so the lock caps the RENDER scale.
--
--   * it had to be sized for the device.  The first cut kept the desktop's
--     absolute 1X-4X ladder, which names a window size you can see on a
--     desktop and means a different fraction of every phone: 4X was a quarter
--     of a 1080p display and 5X/6X were not on the list at all.  The scale is
--     read off the display now, not chosen by the player.
--
--   * it had to work in the OVERWORLD.  The world pass deliberately expands
--     to cover the whole display so letterbox voids become more map.  So the
--     lock shrank the UI blit while the map kept filling the screen -- and
--     showed MORE map, since a smaller scale fits more world pixels in.
--
-- Pixel perfect throughout: whole multiples only.  The leftover is bars, and
-- on a 9:20 phone there is a lot of it vertically.  That is what a 10:9
-- screen looks like on a tall display; stretching to reach the edges would
-- resample every pixel, which is the one thing this setting exists to refuse.
--   luajit tests/engine/faithful_res_mobile.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FaithfulRes = require("src.core.FaithfulRes")
local Renderer = require("src.render.Renderer")
local Zoom = require("src.render.Zoom")

local g = love.graphics
local realDims, realPixelDims = g.getDimensions, g.getPixelDimensions
local realOS = love.system and love.system.getOS
local savedOffset = Zoom.offset
love.system = love.system or {}

local function pose(w, h, osName)
  love.system.getOS = function() return osName or "Android" end
  g.getDimensions = function() return w, h end
  g.getPixelDimensions = function() return w, h end
end

Renderer.uiWidth, Renderer.uiHeight = Renderer.WIDTH, Renderer.HEIGHT
Zoom.offset = 0

-- ------------------------------------------------------- it applies at all

pose(1080, 2400) -- a Pixel 7, portrait
T.eq(FaithfulRes.isMobile(), true, "the fixture reads as a phone")
T.eq(FaithfulRes.apply(1), true, "FAITHFUL RATIO applies on mobile at all now")
T.eq(FaithfulRes.locked, true, "and reports itself locked")

-- ------------------------------------------------- one ON, sized by the device

T.eq(FaithfulRes.maxLevel(), 1, "mobile offers ON, not a ladder of multiples")
T.eq(#FaithfulRes.levels(), 2, "so the row is exactly OFF and ON")
T.eq(FaithfulRes.label(1), "ON", "and ON is spelled ON, not 1X")
T.eq(FaithfulRes.label(0), "OFF", "with OFF unchanged")

-- 1080/160 = 6.75 and 2400/144 = 16.6, so the largest WHOLE multiple is 6
T.eq(FaithfulRes.deviceScale(), 6, "the scale comes off the display: 6x here")
T.eq(FaithfulRes.scaleCap(), 6, "and that is what the renderer is told to lock")
T.eq(Renderer:fitScale(), 6, "so a GB pixel is exactly 6 screen pixels")

-- the player never picks a smaller one, which is how the first cut managed to
-- draw a postage stamp on a 1080p phone
T.eq(FaithfulRes.normalize(3), 1, "any ON value is just ON")
FaithfulRes.apply(1)
T.eq(Renderer:fitScale(), 6, "and always lands on the device maximum")

-- --------------------------------------------------------- the overworld

FaithfulRes.apply(0)
local unlockedW = Renderer:worldViewSize()
T.check(unlockedW > 160, "unlocked, the overworld view covers the whole display")

FaithfulRes.apply(1)
local lockedW, lockedH = Renderer:worldViewSize()
T.eq(lockedW, 160, "locked, the overworld shows exactly a GB screen wide")
T.eq(lockedH, 144, "and exactly a GB screen tall")
T.check(lockedW < unlockedW,
  "so the lock SHRINKS the map area instead of growing it")

-- ------------------------------------------------------ pixel perfect

-- 6 x 160 = 960 of 1080 wide.  Reaching the edges would need 6.75, which
-- resamples every pixel; the bars are the honest answer.
local cap = FaithfulRes.scaleCap()
T.eq(cap, math.floor(cap), "the locked scale is a whole number, never fractional")
T.eq(160 * cap, 960, "which puts the GB screen at 960 of 1080 pixels wide")

-- ------------------------------------------------------- rotation is free

-- fitScale reads the live drawable size every frame, so a rotate re-derives
-- the scale with nothing to re-apply
pose(1080, 2400); FaithfulRes.apply(1)
T.eq(Renderer:fitScale(), 6, "portrait locks at 6x")
pose(2400, 1080); FaithfulRes.apply(1)
T.eq(Renderer:fitScale(), 7, "landscape re-derives to 7x (1080/144), still whole")
T.eq(Renderer:worldViewSize(), 160, "and the overworld stays locked through it")

-- ---------------------------------------------------------- OFF is OFF

-- Nothing about OFF changed: it is the behaviour the game already had.
pose(1080, 2400)
FaithfulRes.apply(0)
T.eq(FaithfulRes.locked, false, "OFF releases the lock")
T.eq(FaithfulRes.scaleCap(), nil, "with no cap on the renderer")
T.eq(Renderer:fitScale(), 6, "the UI fits exactly as it did before")
T.check(Renderer:worldViewSize() > 160, "and the overworld fills the screen again")

-- ------------------------------------------------- desktop is untouched

pose(1280, 800, "Windows")
T.eq(FaithfulRes.isMobile(), false, "the fixture reads as desktop")
T.eq(FaithfulRes.maxLevel(), 4, "desktop keeps its 1X-4X ladder")
T.eq(FaithfulRes.label(2), "2X", "and its labels")
T.eq(FaithfulRes.scaleCap(), nil, "no cap: the window itself is the lock there")
T.eq(Renderer:fitScale(), 5, "so fitScale is untouched (800/144 = 5)")

g.getDimensions, g.getPixelDimensions = realDims, realPixelDims
if realOS then love.system.getOS = realOS end
Zoom.offset = savedOffset
FaithfulRes.locked = false
FaithfulRes.mobileScale = 0

T.finish("faithful ratio mobile")
