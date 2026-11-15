-- ../pokecrystal/engine/movie/credits.asm:400-451
-- ../pokecrystal/data/credits_strings.asm:183-185

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Credits = require("src.ui.gen2.Credits")

local prior = GameVersion.get()

local function rgb(color, r, g, b, label)
  T.eq(("%d,%d,%d"):format(color[1], color[2], color[3]),
    ("%d,%d,%d"):format(r, g, b), label)
end


GameVersion.set("crystal")

local staff = Credits.STRINGS[Credits.STAFF]
T.eq(type(staff), "table", "the crystal STAFF heading is three lines")
T.eq(staff[2], "  CRYSTAL VERSION",
  "and names the edition the cart's own string does")

local crystal = Credits.layout()
T.eq(#crystal.bannerRows, 1, "ConstructCreditsTilemap calls .InitTopPortion once")
T.eq(crystal.bannerRows[1], 0, "so the banner is rows 0-3 only")
T.eq(crystal.borderRows[1], 4, "the first border strip is drawn at hlcoord 0, 4")
T.eq(crystal.borderRows[2], 17, "the second at hlcoord 0, 17, not Gold's 13")
T.eq(crystal.textRows, 12, "ParseCredits clears SCREEN_WIDTH * 12")
T.eq(crystal.theEndY, 9, "Credits_TheEnd is hlcoord 6, 9")
T.eq(crystal.lyStep, -2, "Credits_LYOverride is `dec a / dec a`")

local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end
local function pal555(...)
  local out, args = {}, { ... }
  for index = 1, 4 do
    local base = (index - 1) * 3
    out[index] = { scale5(args[base + 1]), scale5(args[base + 2]),
      scale5(args[base + 3]) }
  end
  return out
end
-- ../pokecrystal/gfx/credits/credits.pal:2
local CRYSTAL_GFX = { palettesPerScene = 3, palettes = {
  pal555(31, 00, 31, 31, 25, 00, 11, 14, 31, 07, 07, 07),
  pal555(31, 05, 05, 11, 14, 31, 11, 14, 31, 31, 31, 31),
  pal555(31, 05, 05, 00, 00, 00, 31, 31, 31, 31, 31, 31),
  pal555(31, 31, 31, 31, 27, 00, 26, 06, 31, 07, 07, 07),
  pal555(03, 13, 31, 20, 00, 24, 26, 06, 31, 31, 31, 31),
  pal555(03, 13, 31, 00, 00, 00, 31, 31, 31, 31, 31, 31),
  pal555(31, 31, 31, 23, 12, 28, 31, 22, 00, 07, 07, 07),
  pal555(03, 20, 00, 31, 22, 00, 31, 22, 00, 31, 31, 31),
  pal555(03, 20, 00, 00, 00, 00, 31, 31, 31, 31, 31, 31),
  pal555(31, 31, 31, 31, 10, 31, 31, 00, 09, 07, 07, 07),
  pal555(31, 14, 00, 31, 00, 09, 31, 00, 09, 31, 31, 31),
  pal555(31, 14, 00, 31, 31, 31, 31, 31, 31, 31, 31, 31),
} }
-- ../pokegold/gfx/credits/credits.pal:1
local GOLD_GFX = { palettesPerScene = 1, palettes = {
  pal555(31, 31, 31, 29, 08, 27, 15, 24, 12, 07, 07, 07),
  pal555(31, 31, 31, 30, 26, 11, 31, 11, 27, 07, 07, 07),
  pal555(31, 31, 31, 31, 31, 05, 17, 23, 31, 07, 07, 07),
  pal555(31, 31, 31, 22, 15, 10, 31, 19, 09, 07, 07, 07),
} }

local movie = Credits.new({ data = {} }, { gfx = CRYSTAL_GFX })
movie.scene = 0
local banner, strips, field = movie:palettes()
T.check(banner ~= strips and strips ~= field and banner ~= field,
  "GetCreditsPalette hands rows 0-3, the strips and the field three palettes")
rgb(banner[1], 255, 0, 255, "the banner keeps the block's first set")
rgb(field[1], 255, 41, 41, "the field's paper is RGB 31,05,05")
rgb(field[4], 255, 255, 255, "and its ink RGB 31,31,31, so the text is white")

movie.scene = 3
local _, _, last = movie:palettes()
rgb(last[1], 255, 115, 0, "scene 3 reads Igglybuff's third set")

movie.scene = 0
movie.borderFrame = 2
T.eq(movie:borderGraphic(), 3, ".Frames gives every crystal mon four graphics")

movie.lyOverride = 0
movie:advanceLY()
T.eq(movie.lyOverride, 254, "the override counts down two a pass")

local ending = Credits.new({ data = {} }, {
  script = { Credits.THEEND, Credits.WAIT, 1, Credits.END },
})
ending:parse()
T.eq(ending.shown[1].y, 9, "THE END lands on row 9")

local stale = Credits.new({ data = {} },
  { gfx = { palettes = GOLD_GFX.palettes } })
T.check(not pcall(stale.palettes, stale),
  "a credits.lua without palettesPerScene errors")

local fresh = { palettes = {} }
for index = 1, 12 do fresh.palettes[index] = { { index, 0, 0 } } end
fresh.palettesPerScene = 3
local imported = Credits.new({ data = {} }, { gfx = fresh })
imported.scene = 1
local a, b, c = imported:palettes()
T.eq(a[1][1], 4, "scene 1 starts at the fourth extracted set")
T.eq(b[1][1], 5, "its strips at the fifth")
T.eq(c[1][1], 6, "and its field at the sixth")


GameVersion.set("gold")

T.eq(Credits.STRINGS[Credits.STAFF][2], "    GOLD VERSION",
  "gold still reads GOLD VERSION")

local gs = Credits.layout()
T.eq(#gs.bannerRows, 2, "gold calls .InitTopPortion twice")
T.eq(gs.bannerRows[2], 14, "the second banner at hlcoord 0, 14")
T.eq(gs.borderRows[2], 13, "its lower strip on row 13")
T.eq(gs.textRows, 8, "and eight rows of text field")
T.eq(gs.theEndY, 8, "THE END on row 8")
T.eq(gs.lyStep, 2, "with the override counting up")

local gold = Credits.new({ data = {} }, { gfx = GOLD_GFX })
gold.scene = 0
local one, two, three = gold:palettes()
T.check(one == two and two == three,
  "gold copies one 8-byte set to every palette slot")
rgb(one[1], 255, 255, 255, "which is credits.pal's first set")

gold.borderFrame = 2
T.eq(gold:borderGraphic(), 1, "and Bellossom repeats its first graphic on frame 2")

GameVersion.set("silver")
T.eq(Credits.STRINGS[Credits.STAFF][2], "   SILVER VERSION",
  "silver keeps its own heading")

GameVersion.set(prior)

T.finish("crystal credits bug 1967")
