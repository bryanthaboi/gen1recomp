-- PIXEL FILTER (save.options.pixelFilter): xBRZ over the finished frame.
-- OFF is the default, so an old save presents exactly as it did.
--   luajit tests/engine/pixel_filter_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local PixelFilter = require("src.render.PixelFilter")
local Performance = require("src.core.Performance")

T.eq(require("src.core.SaveData").newGame().options.pixelFilter, "off",
  "Gen 1 starts OFF")
T.eq(require("src.core.gen2.Save").DEFAULT_OPTIONS.pixelFilter, "off",
  "and so does Gen 2")

-- ------------------------------------------------------------ the ladder

T.eq(PixelFilter.normalize(nil), "off", "no stored value is OFF")
T.eq(PixelFilter.normalize("nonsense"), "off", "and so is a value we cannot read")
T.eq(table.concat(PixelFilter.MODES, ","), "off,sharp,xbrz,scalefx,omniscale",
  "OFF, then sharpest to smoothest")
T.eq(PixelFilter.cycle("off", 1), "sharp", "right steps onto SHARP")
T.eq(PixelFilter.cycle("sharp", 1), "xbrz", "then XBRZ")
T.eq(PixelFilter.cycle("omniscale", 1), "off", "and wraps at the end")
T.eq(PixelFilter.cycle("off", -1), "omniscale", "left wraps back")
for _, id in ipairs(PixelFilter.MODES) do
  T.check(PixelFilter.label(id) ~= nil, id .. " has a label")
end

-- Every registered filter keeps the pass contract src/render/PixelFilter.lua
-- documents: named source passes, then exactly one output pass, last.
for i = 2, #PixelFilter.MODES do
  local id = PixelFilter.MODES[i]
  local def = require("src.render.pixel_filters." .. id)
  T.eq(def.id, id, id .. " is registered under its own id")
  local passes = def.passes or {}
  T.check(#passes > 0 and passes[#passes].scope == "output",
    id .. " ends on its output pass")
  for p = 1, #passes - 1 do
    T.check(passes[p].scope == "source" and type(passes[p].name) == "string",
      id .. " pass " .. p .. " is a named source pass")
  end
  for p = 1, #passes do
    T.check(type(passes[p].source) == "string", id .. " pass " .. p .. " has GLSL")
  end
end

PixelFilter.applyOptions({ pixelFilter = "xbrz" })
T.eq(PixelFilter.mode, "xbrz", "applyOptions installs the saved mode")
PixelFilter.applyOptions({})
T.eq(PixelFilter.mode, "off", "and an options table without one is OFF")

-- ------------------------------------------------------------ gating

T.check(not PixelFilter.active(), "OFF is never active")
T.eq(Performance.CAPS.high.pixelFilter, true, "HIGH allows it")
T.eq(Performance.CAPS.balanced.pixelFilter, true, "so does BALANCED")
T.eq(Performance.CAPS.low.pixelFilter, false, "LOW holds it off")

-- A stand-in newShader, so active() can get past the shader build headless.
local realLove = _G.love
_G.love = { graphics = { newShader = function() return {} end } }
package.loaded["src.render.PixelFilter"] = nil
PixelFilter = require("src.render.PixelFilter")
local tier = Performance.tier
PixelFilter.setMode("xbrz")
Performance.tier = "high"
T.check(PixelFilter.active(), "XBRZ on a HIGH tier is active")
Performance.tier = "low"
T.check(not PixelFilter.active(), "LOW clamps it without touching the choice")
T.eq(PixelFilter.mode, "xbrz", "the stored choice survives the clamp")
PixelFilter.setMode("sharp")
T.check(PixelFilter.active(), "SHARP is cheap enough to stay on at LOW")
Performance.tier = tier
PixelFilter.setMode("off")

-- ScaleFX keeps its metric in float canvases; a driver without them turns
-- that filter off rather than running it on quantized data.
_G.love = { graphics = { newShader = function() return {} end,
  getCanvasFormats = function() return { rgba8 = true } end } }
package.loaded["src.render.PixelFilter"] = nil
PixelFilter = require("src.render.PixelFilter")
Performance.tier = "high"
PixelFilter.setMode("scalefx")
T.check(not PixelFilter.active(), "SCALEFX without rgba16f reports inactive")
PixelFilter.setMode("xbrz")
T.check(PixelFilter.active(), "while an rgba8-only filter still runs")
Performance.tier = tier
PixelFilter.setMode("off")

-- A driver that refuses the shader degrades to the plain blit, once.
_G.love = { graphics = { newShader = function() error("no glsl") end } }
package.loaded["src.render.PixelFilter"] = nil
PixelFilter = require("src.render.PixelFilter")
PixelFilter.setMode("xbrz")
T.check(not PixelFilter.active(), "a shader the driver rejects reports inactive")
PixelFilter.setMode("off")
_G.love = realLove
package.loaded["src.render.PixelFilter"] = nil
PixelFilter = require("src.render.PixelFilter")

-- ------------------------------------------------------------ the grid

-- 160 source pixels at 7x from x = 100: exactly the span, no overhang.
local gx, n = PixelFilter._gridSpan(100, 1120, 100, 7)
T.eq(gx, 100, "an aligned rect starts on its own origin")
T.eq(n, 160, "and covers exactly its pixels")

-- The whole 1920 window around that letterbox: the grid reaches back past 0
-- and on past the right edge, a whole pixel at a time.
gx, n = PixelFilter._gridSpan(0, 1920, 100, 7)
T.eq(gx, 100 - 15 * 7, "the window's grid starts a whole pixel left of 0")
T.check(gx <= 0 and gx > -7, "and within one pixel of it")
T.check(gx + n * 7 >= 1920, "the grid reaches the right edge")
T.check(gx + (n - 1) * 7 < 1920, "without a spare column")

-- BATTLE SIZE "fill" scales fractionally; the grid still lands on it.
gx, n = PixelFilter._gridSpan(0, 1000, 12.5, 6.25)
T.eq(gx, 12.5 - 2 * 6.25, "a fractional scale steps whole source pixels")
T.check(gx + n * 6.25 >= 1000, "and still covers the window")

T.finish("pixel filter")
