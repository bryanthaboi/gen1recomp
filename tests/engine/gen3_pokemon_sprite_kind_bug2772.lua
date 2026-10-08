package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

package.loaded["src.core.game3.runtime"] = { getSession = function() return nil end }

local Pokemon = require("src.core.game3.pokemon")
local vanillaFront = { image = "vanilla-front", w = 64, h = 64 }
local vanillaBack = { image = "vanilla-back", w = 64, h = 64 }
Pokemon.frontPic = function() return vanillaFront end
Pokemon.frontSprite = Pokemon.frontPic
Pokemon.backPic = function() return vanillaBack end
Pokemon.icon = function() return nil end
Pokemon.name = function() return "PIKACHU" end
Pokemon.speciesFromName = function() return nil end

local Gen3Compat = require("src.mods.Gen3Compat")
local game = { phase = "field", data = {}, mods = { content = {} } }
Gen3Compat.bind(function() return game end)

Runtime.hooks = Hooks.new()
Gen3Compat.applyMerged(game)

local seen = {}
Runtime.hooks:wrap("pokemon.sprite", function(next, path, ctx)
  seen[#seen + 1] = { kind = ctx.kind, side = ctx.side }
  return next(path, ctx)
end)

local function lastKind() return seen[#seen] and seen[#seen].kind end

T.eq(Pokemon.frontPic(25), vanillaFront, "a passed-through hook keeps the vanilla pic")
T.eq(lastKind(), "battle", "frontPic with no kind is battle")
Pokemon.backPic(25)
T.eq(lastKind(), "battle", "backPic with no kind is battle")

Pokemon.frontPic(25, nil, false, 0, "summary")
T.eq(lastKind(), "summary", "frontPic hands its kind to the hook")
Pokemon.backPic(25, nil, false, "hof")
T.eq(lastKind(), "hof", "backPic hands its kind to the hook")

local mon = { species = 25, personality = 0, otId = 1, otSecretId = 0 }
Pokemon.monFrontPic(mon, nil, "trade")
T.eq(lastKind(), "trade", "monFrontPic hands its kind through")
Pokemon.monBackPic(mon, nil, "hof")
T.eq(lastKind(), "hof", "monBackPic hands its kind through")
Pokemon.monFrontPic(mon)
T.eq(lastKind(), "battle", "monFrontPic with no kind is battle")

Pokemon.dexFrontPic(25, 0)
T.eq(lastKind(), "dex", "dexFrontPic is a dex pic")
Pokemon.dexFrontPic(25, 0, "credits")
T.eq(lastKind(), "credits", "dexFrontPic takes a kind override")

Pokemon.frontPic(25, nil, false, 0, "evolution")
Pokemon.frontPic(25)
T.eq(lastKind(), "battle", "the kind is not carried over from an earlier call")

local function read(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local sites = {
  { "src/ui/game3/summary_menu.lua", 'monFrontPic(mon, nil, "summary")' },
  { "src/ui/game3/summary_menu.lua", 'frontPic(species, nil, nil, nil, "summary")' },
  { "src/ui/game3/evolution_scene.lua", 'mon and mon.personality, "evolution")' },
  { "src/ui/game3/egg_hatch.lua", 'mon and mon.personality, "hatch")' },
  { "src/ui/game3/egg_hatch.lua", 'frontPic(Pokemon.SPECIES_EGG, nil, nil, nil, "hatch")' },
  { "src/ui/game3/credits.lua", 'frontPic(mon.def.species, nil, nil, nil, "credits")' },
  { "src/ui/game3/rse/credits.lua", 'species), "credits")' },
  { "src/ui/game3/mon_pic.lua", '0x8000, "overworld")' },
  { "src/ui/game3/hall_of_fame.lua", 'monFrontPic(s.mon, nil, "hof")' },
  { "src/ui/game3/hall_of_fame_pc.lua", 'monFrontPic(mon, nil, "hof")' },
  { "src/ui/game3/trade_scene.lua", 'monFrontPic(s.offer, nil, "trade")' },
  { "src/ui/game3/trade_scene.lua", 'monFrontPic(s.received, nil, "trade")' },
  { "src/ui/game3/pc_chrome.lua", 'monFrontPic(hoveredMon, nil, "box")' },
  { "src/ui/game3/rse/pokedex.lua", 'personality, "dex")' },
}
for _, site in ipairs(sites) do
  T.check(read(site[1]):find(site[2], 1, true) ~= nil, site[1] .. " passes " .. site[2])
end

T.finish("gen3 pokemon.sprite ctx.kind bug 2772")
