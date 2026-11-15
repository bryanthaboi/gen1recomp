package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 party facade bottomMessage")
local eq = S.eq

local Gen2Compat = require("src.mods.Gen2Compat")

local game = {
  save = { party = {} },
  stack = { top = function() return nil end, pop = function() end },
  data = {
    pokemon = { PIDGEY = { name = "PIDGEY" } },
    text = {
      ChooseAMonString = "Choose a POKeMON.",
      MoveToWhereString = "Move to where?",
    },
  },
}
Gen2Compat.bind(function() return game end)

local PM = Gen2Compat.resolve("src.ui.PartyMenu", "fixture")
local pidgey = { species = "PIDGEY" }

local menu = PM.new(game, { party = { pidgey } })
eq(menu:bottomMessage(), "Choose a POKeMON.",
  "the default prompt is ChooseAMonString's text, not its label")

menu.switchFrom = 1
eq(menu:bottomMessage(), "Move to where?", "a switch in progress prints MoveToWhereString")
menu.switchFrom = nil

menu.prompt, menu.promptIsBuiltin = "Pick one.", false
eq(menu:bottomMessage(), "Pick one.", "a prompt that is not a built-in label comes back as given")

S.finish()
