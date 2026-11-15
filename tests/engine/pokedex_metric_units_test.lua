#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

T.suite("pokedex metric units")

local Font = require("src.render.Font")
local drawn
local fontDraw = Font.draw
Font.draw = function(text) drawn[#drawn + 1] = tostring(text) end
local function has(text)
  for _, value in ipairs(drawn) do if value == text then return true end end
  return false
end

local DexEntryMenu = require("src.ui.DexEntryMenu")
local game = { save = { pokedex = { owned = {} } }, data = { text = {}, constants = {} } }
local metric = { id = "BULBASAUR", name = "BULBASAUR", dex = 1,
  dexEntry = { kind = "SEED", heightFt = 2, heightIn = 4, weight = 152, heightM = 0.7, weightKg = 6.9 } }
local imperial = { id = "BULBASAUR", name = "BULBASAUR", dex = 1,
  dexEntry = { kind = "SEED", heightFt = 2, heightIn = 4, weight = 152 } }

drawn = {}
DexEntryMenu.render(game, metric, nil, true)
check(has("GR. 0,7m") and has("GEW. 6,9kg"), "a caught Gen 1 entry prints its metric height and weight")
drawn = {}
DexEntryMenu.render(game, metric, nil, false)
check(has("GR. ???m") and has("GEW. ???kg"), "a seen Gen 1 entry prints the metric unknown masks")
check(not has("lb") and not has("???"), "a metric Gen 1 entry prints no imperial field")
drawn = {}
DexEntryMenu.render(game, metric, nil, false, nil, 1, { metricMasks = { "TAI ???m", "PDS ???kg" } })
check(has("TAI ???m") and has("PDS ???kg"), "the entry page prints the masks it resolved when it opened")
drawn = {}
DexEntryMenu.render(game, imperial, nil, false)
check(has("???") and has("lb") and not has("GR. ???m"), "an entry without metric values keeps the US fields")

Font.draw = fontDraw

local PokedexText = require("src.core.gen2.PokedexText")
local data = {
  gen2Pokedex = { entries = { CHIKORITA = { dex = 152, kind = "LEAF", height = 211, weight = 141 } } },
  pokemon = { CHIKORITA = { dexEntry = { heightM = 0.9, weightKg = 6.4 } } },
}
PokedexText.apply(data)
local entry = data.gen2Pokedex.entries.CHIKORITA
check(entry.heightM == 0.9 and entry.weightKg == 6.4 and entry.height == 211,
  "a mod's metric values reach the #DEX entry beside the US cart's")

local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local texts, tiles
local S7E = require("tests.fixture_data.gen2_rom_text_s7_e")
local menu = setmetatable({ page = 1, metricLabels = { "m", "kg" }, data = { text = S7E } },
  { __index = PokedexMenu })
function menu:text(str, tx, ty) texts[#texts + 1] = { tostring(str), tx, ty } end
function menu:tile(id, tx, ty) tiles[#tiles + 1] = { id, tx, ty } end
for _, name in ipairs({ "fill", "border", "blank", "drawPic", "drawFootprint" }) do menu[name] = function() end end
function menu:cursorVisible() return false end
function menu:monName() return "CHIKORITA" end
local function at(str, tx, ty)
  for _, t in ipairs(texts) do if t[1] == str and t[2] == tx and t[3] == ty then return true end end
  return false
end
texts, tiles = {}, {}
menu:drawEntryBody({ species = "CHIKORITA", caught = true }, entry)
check(at("0,9", 14, 7) and at("m", 17, 7) and at("6,4", 14, 9) and at("kg", 17, 9),
  "a caught Gen 2 entry prints its metric height and weight right-aligned before the unit")
local footTile = false
for _, t in ipairs(tiles) do if t[2] == 14 and t[3] == 7 then footTile = true end end
check(not footTile and not at("lb", 17, 9), "a metric Gen 2 entry prints neither the foot mark nor the pound label")
texts, tiles = {}, {}
menu:drawEntryBody({ species = "CHIKORITA", caught = false }, entry)
check(at("???", 14, 7) and at("???", 14, 9), "a seen Gen 2 entry prints the metric unknown masks")
texts, tiles = {}, {}
menu:drawEntryBody({ species = "CHIKORITA", caught = true },
  { dex = 152, kind = "LEAF", height = 211, weight = 141 })
check(at(S7E["Pokedex_DrawDexEntryScreenBG.Weight"], 9, 9) and not at("m", 17, 7),
  "an entry without metric values keeps the US fields")

T.finish("pokedex metric units")
