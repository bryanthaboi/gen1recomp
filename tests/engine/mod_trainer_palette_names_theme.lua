-- Mod-API additions asked for in the hook thread: a trainer's own portrait
-- palette (trainers.palette, the per-record override pokemon already carry),
-- per-party trainer names (trainers.partyNames, Gen 2's [class] [name] split),
-- and a per-species wild battle theme (pokemon.battleTheme).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local love = _G.love or {}
_G.love = love
love.audio = love.audio or {}
love.audio.newSource = love.audio.newSource or function()
  return { play = function() end, stop = function() end,
           setLooping = function() end, setVolume = function() end,
           setFilter = function() end }
end

local Font = require("src.render.Font")
local TypeChart = require("src.battle.TypeChart")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")

local MOD = {
  ["mods/trainer_extras/manifest.json"] = [[{
    "id": "trainer_extras",
    "name": "Trainer Extras",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/trainer_extras/main.lua"] = [[
    local mod = ...
    mod.content.music:register("Music_ModWild", { file = "assets/wild.ogg" })
    mod.content.palettes:register("BELTPAL",
      { {255,255,255}, {200,120,60}, {90,60,30}, {0,0,0} })
    mod.content.trainers:patch("OPP_FIX_YOUNGSTER", {
      palette = "BELTPAL",
      partyNames = { [1] = "TAKESHI" },
    })
    mod.content.pokemon:patch("FIXMON_B", { battleTheme = "Music_ModWild" })
  ]],
}

local function newGame(data)
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.player.rival = "GARY"
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  return { data = data, save = save,
           stack = { top = function() return nil end,
                     push = function() end, pop = function() end } }
end

local Data = T.fixtures.fresh()
Font.load(Data)
TypeChart.load(Data)
Data.palettes = { pokemon = {}, palettes = {
  MEWMON = { {255,255,255}, {170,170,170}, {85,85,85}, {0,0,0} },
} }
Data.audio = { battle = { wild = "Music_DefaultWild",
                          trainer = "Music_DefaultTrainer" },
               songs = { Music_DefaultWild = { file = "assets/alt.ogg" },
                         Music_DefaultTrainer = { file = "assets/alt.ogg" } } }

local run = T.sdk.loadMods({ "mods/trainer_extras" },
                           { data = Data, fs = T.sdk.memfs(MOD) })
T.eq(#run.errors, 0, "the trainer-extras mod loads without validation errors")

-- ------------------------------------------------------- trainer palettes

local trainer = Data.trainers.OPP_FIX_YOUNGSTER
T.eq(trainer.palette, "BELTPAL", "the palette id lands on the trainer record")

local picked = BattleState.trainerPalette(Data, trainer)
T.check(picked ~= nil, "a trainer with a palette resolves one")
T.eq(picked.colors[2][1], 200, "the mod's own colors are the ones handed back")

local vanilla = BattleState.trainerPalette(Data, { id = "OPP_PLAIN" })
T.check(vanilla ~= nil, "a trainer without one still falls back")
T.eq(vanilla.colors[2][1], 170, "and the fallback is still MEWMON")

-- ------------------------------------------------------ per-party names

T.eq(trainer.partyNames[1], "TAKESHI", "the party name lands on the record")

local named = BattleState.newTrainer(newGame(Data), "OPP_FIX_YOUNGSTER", 1)
T.eq(named.trainer.name, "FIX YOUNGSTER TAKESHI",
     "the class name and the personal name are shown together")
T.eq(named.trainer.className, "FIX YOUNGSTER", "the class name stays reachable")
T.eq(named.trainer.personalName, "TAKESHI", "so does the personal name")
T.eq(named.introText, "FIX YOUNGSTER TAKESHI wants\nto fight!{PROMPT}",
     "the intro text uses the composed name")
T.eq(Data.trainers.OPP_FIX_YOUNGSTER.name, "FIX YOUNGSTER",
     "the shim never writes the composed name back onto the record")

trainer.partyNames = { [2] = "TAKESHI" }
local unnamed = BattleState.newTrainer(newGame(Data), "OPP_FIX_YOUNGSTER", 1)
T.eq(unnamed.trainer.name, "FIX YOUNGSTER",
     "a party with no name of its own keeps the class name alone")
trainer.partyNames = { [1] = "TAKESHI" }

-- --------------------------------------------------- species battle theme

T.eq(Data.pokemon.FIXMON_B.battleTheme, "Music_ModWild",
     "the species theme lands on the pokemon record")

local wild = BattleState.newWild(newGame(Data), "FIXMON_B", 5)
T.eq(wild:battleTheme(), "Music_ModWild",
     "a wild battle with that species plays the species theme")
T.eq(wild:computeMusicKind(), "wild", "and it is still a wild-kind battle")

local plain = BattleState.newWild(newGame(Data), "FIXMON_A", 5)
T.eq(plain:battleTheme(), nil,
     "a species without one leaves the kind default alone")

-- a trainer's own theme still wins over the lead mon's species theme
trainer.battleTheme = "Music_DefaultTrainer"
local both = BattleState.newTrainer(newGame(Data), "OPP_FIX_YOUNGSTER", 1)
T.eq(both:battleTheme(), "Music_DefaultTrainer",
     "the trainer theme wins over any species theme in the party")
trainer.battleTheme = nil

T.finish("mod trainer palette, party names and species theme")
