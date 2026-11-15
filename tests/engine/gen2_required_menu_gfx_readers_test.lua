package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local BattleState = require("src.ui.gen2.BattleState")
local BattleHud = require("src.ui.gen2.BattleHud")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")

local function errorsWith(fn, text)
  local ok, err = pcall(fn)
  return not ok and tostring(err):find(text, 1, true) ~= nil
end

-- ../pokecrystal/engine/gfx/load_pics.asm:309
T.check(errorsWith(function()
  BattleState.trainerArt({ gen2MenuGfx = { battleHud = {} } }, "FALKNER")
end, "trainerPics"), "a battleHud without trainerPics is an error")
T.eq(BattleState.trainerArt({ gen2MenuGfx = { battleHud = {
  trainerPics = { FALKNER = "assets/generated/battle/trainers/falkner.png" } } } },
  "FALKNER"), "assets/generated/battle/trainers/falkner.png",
  "the extracted class pic is the battle's")

-- ../pokecrystal/engine/sprite_anims/core.asm:547-557
T.check(errorsWith(function()
  BattleHud.new({ battleHud = {} }):drawExpBarEnd(0, 0)
end, "expBarEnd"), "a battleHud without expBarEnd is an error")

local function dexGame(menuGfx)
  return {
    data = { pokemon = {}, gen2MenuGfx = menuGfx },
    save = { pokedex = { seen = {}, caught = {} } },
  }
end

local noDex = PokedexMenu.new(dexGame(nil), {})
T.check(errorsWith(function() noDex:drawPanel() end, "pokedex"),
  "the dex without its sheet is an error, not the plain boxes")

-- ../pokecrystal/engine/pokegear/pokegear.asm:2346
local noNest = PokedexMenu.new(dexGame({ pokegear = { tiles = "x.png" } }), {})
T.check(errorsWith(function() noNest:drawNestIcon(0, 0) end, "nestIcon"),
  "the area page without PokedexNestIconGFX is an error, not a square")

-- ../pokecrystal/engine/pokedex/new_pokedex_entry.asm:1
local screen = setmetatable({
  game = { stack = {}, data = { gen2Pokedex = { entries = {} } } },
}, { __index = BattleState })
T.check(errorsWith(function() screen:openDexEntry("PIDGEY") end, "PIDGEY"),
  "a caught species with no dex entry is an error, not a skipped dex")

T.finish("Gen 2 menu_gfx readers require their ROM art")
