-- Chrome.printThrough (src/ui/gen2/Chrome.lua) used to run every string
-- through the GbcPalette shade-remap shader whenever a palette was given,
-- with no regard for whether the glyph it was about to draw came from a
-- tile page or from a TTF.  The shader recovers a shade by reading the
-- RED CHANNEL of an already-rasterized 2bpp tile pixel (SHADER_SOURCE in
-- src/render/GbcPalette.lua); a TTF glyph is LÖVE's own anti-aliased
-- coverage mask, drawn as plain white with the current tint carrying the
-- ink colour, which that same channel read always reports as shade 0 --
-- painting every character the SAME colour as the paper rect printThrough
-- had just drawn behind it, i.e. invisible.  Reported against a real Gold
-- build running a TTF translation mod: the naming screen's keyboard,
-- Diploma and Pokegear text all vanish, since all three draw through this
-- one routine (gen1recomp#1642).
--
-- The switch is per GLYPH, not per string: a TTF-mod build still keeps
-- multi-byte charmap sequences (the naming screen's own <PK>/<MN> cells,
-- the 'd/'l/'s ligatures) and anything a mod names in ttf.tiles on their ROM
-- tiles (src/render/Font.lua's Font.split), so one call can mix both kinds
-- of glyph and each must take its own path.
--
-- No real shader runs headless (love_stub does not stub newShader), so this
-- cannot check a rendered pixel.  Font.encode/drawCode/advanceOf/width are
-- replaced with fakes that hand printThrough a fixed list of glyph codes,
-- so what is checked is the two things that decide the outcome: which
-- glyphs skip the shader, and what colour is active when each one draws.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Font = require("src.render.Font")

-- Palette arrays are 1-indexed shade 0..3, same order GbcPalette.useRaw
-- reads (src/render/GbcPalette.lua channel()).
local PALETTE = { { 200, 220, 255 }, { 150, 170, 220 }, { 90, 100, 160 }, { 10, 10, 30 } }

local TILE_CODE = 0x80
local TTF_CODE = Font.TTF_BASE + 65 -- 'A', were it decoded

-- "text" is a plain list of glyph codes for this suite; Font.width/encode
-- pass it straight through, matching how a real caller's string would
-- decode to a list of codes.
Font.width = function(codes) return #codes * 8 end
Font.encode = function(codes) return codes end
Font.advanceOf = function(_code) return 8 end

local drawn
Font.drawCode = function(code, x, y)
  drawn[#drawn + 1] = { code = code, x = x, y = y, color = { love.graphics.getColor() } }
end

local useRawCalls
local realUseRaw = GbcPalette.useRaw
GbcPalette.useRaw = function(...)
  useRawCalls = useRawCalls + 1
  return realUseRaw(...)
end

GbcPalette.available = function() return true end

local function colorsEq(a, b)
  return math.abs(a[1] - b[1]) < 1e-9 and math.abs(a[2] - b[2]) < 1e-9
    and math.abs(a[3] - b[3]) < 1e-9
end

-- ------------------------------------------------------- all tile glyphs
do
  useRawCalls = 0
  drawn = {}
  Chrome.printThrough({ TILE_CODE, TILE_CODE }, 0, 0, PALETTE)
  T.eq(useRawCalls, 1, "one shaded run binds the shader once, not per glyph")
  T.eq(#drawn, 2, "both glyphs drew")
  for i, d in ipairs(drawn) do
    T.check(colorsEq(d.color, { 1, 1, 1, 1 }),
      ("tile glyph %d is tinted white, letting the shader pick the colour"):format(i))
  end
end

-- -------------------------------------------------------- all TTF glyphs
do
  useRawCalls = 0
  drawn = {}
  Chrome.printThrough({ TTF_CODE, TTF_CODE }, 0, 0, PALETTE)
  T.eq(useRawCalls, 0, "a TTF glyph never binds the shade-remap shader")
  T.eq(#drawn, 2, "both glyphs drew")
  local ink = Chrome.throughPalette(PALETTE, false)[4]
  for i, d in ipairs(drawn) do
    T.check(colorsEq(d.color, { ink[1] / 255, ink[2] / 255, ink[3] / 255, 1 }),
      ("TTF glyph %d is tinted with the palette's own ink colour"):format(i))
  end
end

-- --------------------------------------------- mixed: tile, TTF, then tile
do
  useRawCalls = 0
  drawn = {}
  Chrome.printThrough({ TILE_CODE, TTF_CODE, TILE_CODE }, 0, 0, PALETTE)
  T.eq(useRawCalls, 2,
    "the shader re-binds once per return to a tile glyph, not once for the whole string")
  T.eq(#drawn, 3, "all three glyphs drew")
  local ink = Chrome.throughPalette(PALETTE, false)[4]
  T.check(colorsEq(drawn[1].color, { 1, 1, 1, 1 }), "1st (tile) glyph: white/shaded")
  T.check(colorsEq(drawn[2].color, { ink[1] / 255, ink[2] / 255, ink[3] / 255, 1 }),
    "2nd (TTF) glyph, mid-string, still gets the ink tint")
  T.check(colorsEq(drawn[3].color, { 1, 1, 1, 1 }), "3rd (tile) glyph: shaded again")
end

-- ---------------------------------------------------- inverted TTF ink
do
  drawn = {}
  Chrome.printThrough({ TTF_CODE }, 0, 0, PALETTE, true)
  local ink = Chrome.throughPalette(PALETTE, true)[4]
  T.check(colorsEq(drawn[1].color, { ink[1] / 255, ink[2] / 255, ink[3] / 255, 1 }),
    "an inverted call tints TTF ink with the inverted palette's own shade-3 entry")
end

-- ---------------------------------------------- DMG mode's own TTF ink
do
  GbcPalette.setMode("dmg")
  drawn = {}
  Chrome.printThrough({ TTF_CODE }, 0, 0, PALETTE)
  local ink = Chrome.throughPalette(PALETTE, false)[4]
  T.check(colorsEq(drawn[1].color, { ink[1] / 255, ink[2] / 255, ink[3] / 255, 1 }),
    "DMG mode's own resolved palette (four grey hardware shades) still reaches the TTF ink")
  GbcPalette.setMode("gbc")
end

T.finish("gen2_chrome_print_through_ttf_test")
