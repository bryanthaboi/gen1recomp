-- Parity test: the status screen's mon pic has to sit out the SGB recolor
-- when the sprite record is true-color (#430).  SetPal_StatusScreen puts a
-- monPal zone over the pic rect (status_screen.asm, mirrored by
-- SummaryMenu:sgbPalettes), so a full-color pic drawn there was run through
-- the 4-shade remap the way battle and the Pokedex entry page (#350) already
-- avoid.  Run with `luajit tests/parity_status_true_color.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity status true color")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
require("src.render.Font").load(Data)

local PaletteFX = require("src.render.PaletteFX")
local Sprites = require("src.pokemon.Sprites")
local Sound = require("src.core.Sound")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local SummaryMenu = require("src.ui.SummaryMenu")

local savedCry = Sound.playCry
Sound.playCry = function() end

-- the rects the frame reported on the UI canvas, the pass the status screen
-- draws into (Renderer appends them to that pass's zone list)
local function uiRects(draw)
  PaletteFX.clearTrueColor()
  PaletteFX.setPass("ui")
  draw()
  local rects = PaletteFX.trueColorRects("ui")
  PaletteFX.setPass(nil)
  return rects
end

local def = Data.pokemon.PIKACHU
local savedTrueColor = def.trueColor

local save = SaveData.newGame()
local mon = Pokemon.new(Data, "PIKACHU", 20)
local game = { data = Data, save = save, stack = { pop = function() end } }

-- the premise: this screen colorizes the pic through a species zone, so a
-- true-color pic needs an unshaded rect on top of it
do
  local pals = SummaryMenu.sgbPalettes({ mon = mon }, game)
  local monPal = PaletteFX.monPal(Data, "PIKACHU")
  local zone
  for _, z in ipairs(pals or {}) do
    if z.colors == monPal and z.w < 160 then zone = z end
  end
  check(zone ~= nil, "SetPal_StatusScreen's monPal zone covers the pic")
  if zone then
    eq(zone.x .. "," .. zone.y, "8,0", "and it starts at the pic's corner")
  end
end

def.trueColor = true

local _, pathTrueColor = Sprites.path(Data, "PIKACHU", "front",
  { mon = mon, kind = "summary" })
check(pathTrueColor == true,
      "Sprites.path reports trueColor for the summary pic")

local screen = SummaryMenu.new(game, mon)
check(screen.spriteTrueColor == true,
      "SummaryMenu keeps the sprite's trueColor flag (#430)")

local pw, ph = screen.sprite:getDimensions()
local py = math.max(0, 56 - ph)

-- LoadFlippedFrontSpriteByMonIndex: the draw is a negative x scale anchored
-- at 8 + pw, so the covered rect still starts at x = 8
local page1 = uiRects(function() screen:draw() end)
eq(#page1, 1, "page 1 reports one true-color rect")
if page1[1] then
  eq(("%d,%d,%d,%d"):format(page1[1].x, page1[1].y, page1[1].w, page1[1].h),
     ("%d,%d,%d,%d"):format(8, py, pw, ph),
     "and it is the mirrored draw's rect, not the unflipped one")
  check(page1[1].colors == false,
        "and it is an unshaded zone, not a palette")
end

screen.page = 2
local page2 = uiRects(function() screen:draw() end)
eq(#page2, 1, "page 2 (StatusScreen2 keeps the pic) reports it too")

-- vanilla records set no flag, so the zone list stays exactly what
-- sgbPalettes returned
def.trueColor = nil
local plain = SummaryMenu.new(game, mon)
check(plain.spriteTrueColor == false, "a plain pic reports no flag")
eq(#uiRects(function() plain:draw() end), 0,
   "and marks no rect, leaving the SGB pass untouched")

def.trueColor = savedTrueColor
Sound.playCry = savedCry
PaletteFX.clearTrueColor()
S.finish()
