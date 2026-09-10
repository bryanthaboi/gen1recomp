-- pokecrystal/engine/gfx/cgb_layouts.asm:509-521
-- pokecrystal/home/text.asm:108

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq = T.eq
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local InitClock = require("src.ui.gen2.InitClock")

local function rgb(c) return table.concat(c, ",") end

do
  local pal = InitClock.PALETTE
  eq(rgb(pal[1]), "255,255,255", "PREDEFPAL_DIPLOMA colour 0 is white")
  eq(rgb(pal[2]), "247,181,140", "colour 1 is RGB 30,22,17")
  eq(rgb(pal[3]), "132,115,156", "colour 2 is RGB 16,14,19")
  eq(rgb(pal[4]), "0,0,0", "colour 3 is black")
end

do
  local clock = InitClock.new({ input = {} }, { mode = "clock", save = {} })
  eq(clock:palette(), InitClock.PALETTE, "the intro clock draws on SCGB_DIPLOMA")
  eq(rgb(clock:palette()[1]), "255,255,255", "so its boxes are white")

  local day = InitClock.new({ input = {} }, { mode = "day", save = {} })
  eq(day:palette(), Chrome.DEFAULT_BOX_PALETTE,
    "SetDayOfWeek's Textbox is the overworld PAL_BG_TEXT")
  eq(rgb(day:palette()[1]), "255,255,255", "so Mom's wheel is white too")
end
