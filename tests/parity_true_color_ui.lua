-- True-color Pokemon art is drawn on the UI canvas in addition to battle.
-- The Pokedex, title screen, and Oak's intro need to report the exact
-- rectangle they draw so PaletteFX can put the unshaded copy over the SGB
-- palette pass.  Run with `luajit tests/parity_true_color_ui.lua`.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity true-color ui")
local check = S.check

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
require("src.render.Font").load(Data)

local PaletteFX = require("src.render.PaletteFX")
local Sound = require("src.core.Sound")
local DexEntryMenu = require("src.ui.DexEntryMenu")
local EvolutionState = require("src.ui.EvolutionState")
local TitleState = require("src.ui.TitleState")
local OakSpeech = require("src.ui.OakSpeech")
local TradeAnim = require("src.ui.TradeAnim")

local savedCry = Sound.playCry
Sound.playCry = function() end

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
local raichu = Data.pokemon.RAICHU
local savedRaichuTrueColor = raichu.trueColor
def.trueColor = true
raichu.trueColor = true

local game = {
  data = Data,
  save = { pokedex = { owned = { PIKACHU = true } } },
  stack = { pop = function() end },
}
local dex = DexEntryMenu.new(game, "PIKACHU")
check(dex.spriteTrueColor == true,
      "Pokedex keeps a Pokemon sprite's trueColor flag")
local dexRects = uiRects(function() dex:draw() end)
local dx, dy = 8, math.max(0, 60 - dex.sprite:getHeight())
check(#dexRects == 1 and dexRects[1].x == dx and dexRects[1].y == dy
      and dexRects[1].w == dex.sprite:getWidth()
      and dexRects[1].h == dex.sprite:getHeight(),
      "Pokedex reports the true-color sprite rectangle")

local evolving = EvolutionState.new(game, { species = "PIKACHU" }, "RAICHU")
check(evolving.oldSpriteTrueColor == true,
      "evolution keeps the current Pokemon sprite's trueColor flag")
check(evolving.newSpriteTrueColor == true,
      "evolution keeps the evolved Pokemon sprite's trueColor flag")
local evoRects = uiRects(function() evolving:draw() end)
local ex = math.floor((160 - evolving.oldSprite:getWidth()) / 2)
local ey = math.max(8, 64 - evolving.oldSprite:getHeight())
check(#evoRects == 1 and evoRects[1].x == ex and evoRects[1].y == ey
      and evoRects[1].w == evolving.oldSprite:getWidth()
      and evoRects[1].h == evolving.oldSprite:getHeight(),
      "evolution reports the true-color sprite rectangle")

local trade = TradeAnim.new(game, {
  sent = { species = "PIKACHU" }, received = { species = "RAICHU" },
})
check(trade.sentSpriteTrueColor == true,
      "trade keeps the sent Pokemon sprite's trueColor flag")
check(trade.recvSpriteTrueColor == true,
      "trade keeps the received Pokemon sprite's trueColor flag")
local tradeRects = uiRects(function() trade:draw() end)
check(#tradeRects == 1 and tradeRects[1].x == 56 and tradeRects[1].y == 16
      and tradeRects[1].w == trade.sentSprite:getWidth()
      and tradeRects[1].h == trade.sentSprite:getHeight(),
      "trade reports the sent true-color sprite rectangle")
trade.phase = "show_enemy"
local receivedRects = uiRects(function() trade:draw() end)
check(#receivedRects == 1 and receivedRects[1].x == 56
      and receivedRects[1].y == 16
      and receivedRects[1].w == trade.recvSprite:getWidth()
      and receivedRects[1].h == trade.recvSprite:getHeight(),
      "trade reports the received true-color sprite rectangle")

local titleGame = {
  data = { pokemon = Data.pokemon,
           field = { title = { cycleSpecies = { "PIKACHU" } } } },
}
local title = TitleState.new(titleGame, {})
title.phase, title.scy = "loop", 0
local titleSprite, titleTrueColor = title:currentSprite()
check(titleSprite and titleTrueColor,
      "title cache keeps a Pokemon sprite's trueColor flag")
local titleRects = uiRects(function() title:draw() end)
local tx = 40 + math.floor((56 - titleSprite:getWidth()) / 2)
check(#titleRects == 1 and titleRects[1].x == tx
      and titleRects[1].y == 136 - titleSprite:getHeight()
      and titleRects[1].w == 82 - tx
      and titleRects[1].h == titleSprite:getHeight(),
      "title reports the visible true-color sprite rectangle")

local oak = OakSpeech.new({
  data = { pokemon = Data.pokemon, trainers = {},
           field = { oakSpeech = { demoSpecies = "PIKACHU" } } },
}, nil)
oak.pic, oak.picFlip = oak.demoPic, true
oak.picTrueColor = oak.demoTrueColor
check(oak.demoTrueColor == true,
      "Oak intro keeps the demo Pokemon's trueColor flag")
local oakRects = uiRects(function() oak:draw() end)
local ow, oh = oak.demoPic:getDimensions()
local ox = 48 + math.floor((8 - ow / 8) / 2) * 8
local oy = 32 + (7 - oh / 8) * 8
check(#oakRects == 1 and oakRects[1].x == ox and oakRects[1].y == oy
      and oakRects[1].w == ow and oakRects[1].h == oh,
      "Oak intro reports the true-color sprite rectangle")

def.trueColor = savedTrueColor
raichu.trueColor = savedRaichuTrueColor
Sound.playCry = savedCry
PaletteFX.clearTrueColor()
S.finish()
