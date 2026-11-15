package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Game2 = require("src.core.Game2")
local Screens = require("src.ui.Screens")
local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")

local data = {
  text = require("tests.fixture_data.gen2_rom_text_s7_g").text(),
  pokemon = {
    SUNKERN = {
      evolutions = {
        { method = "EVOLVE_ITEM", item = "SUN_STONE", into = "SUNFLORA" },
      },
    },
  },
}
local mon = { species = "SUNKERN", item = nil }

T.eq(ItemEffects.partyAction("SUN_STONE"), "stone",
  "SUN STONE opens the party target flow")
local result = ItemEffects.useOnMon("SUN_STONE", mon, data)
T.check(result.used, "SUN STONE succeeds on SUNKERN")
T.eq(result.evolution and result.evolution.into, "SUNFLORA",
  "SUN STONE selects SUNFLORA")

mon.item = "EVERSTONE"
result = ItemEffects.useOnMon("SUN_STONE", mon, data)
T.check(not result.used, "held EVERSTONE refuses the evolution")

local function startStone()
  local partyOptions, evolutionOptions
  local game = setmetatable({
    data = {
      pokemon = data.pokemon,
      screens = {
        Gen2PartyMenu = function(_, options)
          partyOptions = options
          return {}
        end,
        Gen2EvolutionAnim = function(_, options)
          evolutionOptions = options
          return {}
        end,
      },
    },
    save = {
      party = { { species = "SUNKERN", item = nil } },
      inventory = { SUN_STONE = 1 },
    },
    stack = { pop = function() end, push = function() end },
  }, Game2)
  Screens.invalidate()
  game:usePartyItem("SUN_STONE")
  partyOptions.onChoose(nil, game.save.party[1])
  return game, evolutionOptions
end

local game, evolution = startStone()
T.check(evolution.force, "SUN STONE evolution sets wForceEvolution")
T.eq(game.save.inventory.SUN_STONE, 1,
  "SUN STONE remains until evolution succeeds")

local animation = EvolutionAnim.new({ data = { pokemon = data.pokemon,
  text = require("tests.fixture_data.gen2_rom_text_s7_b").text() } }, {
  mon = game.save.party[1], entry = evolution and evolution.entry,
  force = evolution and evolution.force,
})
T.check(not animation:cancelPressed({ wasPressed = function(_, key)
  return key == "b"
end }), "B cannot cancel a forced stone evolution")

evolution.onDone({ canceled = true })
T.eq(game.save.inventory.SUN_STONE, 1,
  "a canceled evolution does not consume SUN STONE")

game, evolution = startStone()
evolution.onDone({ evolved = { species = "SUNFLORA" } })
T.eq(game.save.inventory.SUN_STONE, nil,
  "a completed evolution consumes SUN STONE")
Screens.invalidate()

T.finish("gen2 sun stone bug 1219")
