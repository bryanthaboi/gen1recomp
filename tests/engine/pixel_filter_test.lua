-- PIXEL FILTER (save.options.pixelFilter): xBRZ over the finished frame.
-- OFF is the default, so an old save presents exactly as it did.
--   luajit tests/engine/pixel_filter_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Xbrz = require("src.render.Xbrz")
local Performance = require("src.core.Performance")

T.eq(require("src.core.SaveData").newGame().options.pixelFilter, "off",
  "Gen 1 starts OFF")
T.eq(require("src.core.gen2.Save").DEFAULT_OPTIONS.pixelFilter, "off",
  "and so does Gen 2")

-- ------------------------------------------------------------ the ladder

T.eq(Xbrz.normalize(nil), "off", "no stored value is OFF")
T.eq(Xbrz.normalize("nonsense"), "off", "and so is a value we cannot read")
T.eq(Xbrz.cycle("off", 1), "xbrz", "right steps onto XBRZ")
T.eq(Xbrz.cycle("xbrz", 1), "off", "and wraps at the end")
T.eq(Xbrz.cycle("off", -1), "xbrz", "left wraps back")
for _, id in ipairs(Xbrz.MODES) do
  T.check(Xbrz.label(id) ~= nil, id .. " has a label")
end

Xbrz.applyOptions({ pixelFilter = "xbrz" })
T.eq(Xbrz.mode, "xbrz", "applyOptions installs the saved mode")
Xbrz.applyOptions({})
T.eq(Xbrz.mode, "off", "and an options table without one is OFF")

-- ------------------------------------------------------------ gating

T.check(not Xbrz.active(), "OFF is never active")
T.eq(Performance.CAPS.high.xbrz, true, "HIGH allows it")
T.eq(Performance.CAPS.balanced.xbrz, true, "so does BALANCED")
T.eq(Performance.CAPS.low.xbrz, false, "LOW holds it off")

-- A stand-in newShader, so active() can get past the shader build headless.
local realLove = _G.love
_G.love = { graphics = { newShader = function() return {} end } }
package.loaded["src.render.Xbrz"] = nil
Xbrz = require("src.render.Xbrz")
local tier = Performance.tier
Xbrz.setMode("xbrz")
Performance.tier = "high"
T.check(Xbrz.active(), "XBRZ on a HIGH tier is active")
Performance.tier = "low"
T.check(not Xbrz.active(), "LOW clamps it without touching the choice")
T.eq(Xbrz.mode, "xbrz", "the stored choice survives the clamp")
Performance.tier = tier
Xbrz.setMode("off")

-- A driver that refuses the shader degrades to the plain blit, once.
_G.love = { graphics = { newShader = function() error("no glsl") end } }
package.loaded["src.render.Xbrz"] = nil
Xbrz = require("src.render.Xbrz")
Xbrz.setMode("xbrz")
T.check(not Xbrz.active(), "a shader the driver rejects reports inactive")
Xbrz.setMode("off")
_G.love = realLove
package.loaded["src.render.Xbrz"] = nil
Xbrz = require("src.render.Xbrz")

-- ------------------------------------------------------------ the grid

-- 160 source pixels at 7x from x = 100: exactly the span, no overhang.
local gx, n = Xbrz._gridSpan(100, 1120, 100, 7)
T.eq(gx, 100, "an aligned rect starts on its own origin")
T.eq(n, 160, "and covers exactly its pixels")

-- The whole 1920 window around that letterbox: the grid reaches back past 0
-- and on past the right edge, a whole pixel at a time.
gx, n = Xbrz._gridSpan(0, 1920, 100, 7)
T.eq(gx, 100 - 15 * 7, "the window's grid starts a whole pixel left of 0")
T.check(gx <= 0 and gx > -7, "and within one pixel of it")
T.check(gx + n * 7 >= 1920, "the grid reaches the right edge")
T.check(gx + (n - 1) * 7 < 1920, "without a spare column")

-- BATTLE SIZE "fill" scales fractionally; the grid still lands on it.
gx, n = Xbrz._gridSpan(0, 1000, 12.5, 6.25)
T.eq(gx, 12.5 - 2 * 6.25, "a fractional scale steps whole source pixels")
T.check(gx + n * 6.25 >= 1000, "and still covers the window")

T.finish("pixel filter")
