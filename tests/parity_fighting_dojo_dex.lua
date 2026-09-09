-- Parity: the Fighting Dojo prize balls open the Pokédex entry before the
-- take-it prompt (#853).  FightingDojo.asm runs DisplayPokedex on the
-- ball's species (marking it seen) and only then prints the yes/no ask.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not Data.maps then Data:load() end

local S = require("tests.harness").suite("parity Fighting Dojo dex entry")
local check, eq = S.check, S.eq

local Font = require("src.render.Font")
Font.load(Data)

local TextBox = require("src.render.TextBox")
local DexEntryMenu = require("src.ui.DexEntryMenu")
local SaveData = require("src.core.SaveData")
local dojo = require("data.scripts.story4").FIGHTING_DOJO

local function fakeGame()
  local states = {}
  local save = SaveData.newGame()
  save.pokedex = { seen = {}, owned = {} }
  save.flags = { EVENT_BEAT_KARATE_MASTER = true }
  local game = {
    data = Data,
    save = save,
    pressed = false,
    stack = {
      states = states,
      push = function(_, s) states[#states + 1] = s end,
      pop = function(_) states[#states] = nil end,
      top = function(_) return states[#states] end,
    },
  }
  game.input = { wasPressed = function(_, btn)
    local p = game.pressed
    game.pressed = false
    return p and btn == "a"
  end }
  return game
end

local function pageText(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    out[#out + 1] = table.concat(page, "\n")
  end
  return table.concat(out, "\n")
end

-- each ball: dex entry first (seen, not owned), then the ask prompt
for _, c in ipairs({
  { textId = "TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL", species = "HITMONLEE" },
  { textId = "TEXT_FIGHTINGDOJO_HITMONCHAN_POKE_BALL", species = "HITMONCHAN" },
}) do
  local game = fakeGame()
  dojo.talk[c.textId](game, {}, nil, function() end)
  local top = game.stack:top()
  check(getmetatable(top) == DexEntryMenu,
        c.textId .. " opens the Pokédex entry first")
  eq(top and top.def and top.def.id, c.species,
     "the entry shows " .. c.species)
  check(game.save.pokedex.seen[c.species] == true,
        "the preview marks " .. c.species .. " seen")
  check(not game.save.pokedex.owned[c.species],
        "the preview does not mark " .. c.species .. " owned")
  -- engine/menus/pokedex.asm:500-506
  top.picDelay = 0
  game.pressed = true
  top:update(0)
  local ask = game.stack:top()
  check(getmetatable(ask) == TextBox,
        "closing the entry shows the take-it prompt")
  check(ask and pageText(ask):find(c.species, 1, true) ~= nil,
        "the prompt names " .. c.species)
end

-- before the Karate Master is beaten the ball still refuses, no dex entry
do
  local game = fakeGame()
  game.save.flags.EVENT_BEAT_KARATE_MASTER = nil
  dojo.talk.TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL(game, {}, nil,
    function() end)
  check(getmetatable(game.stack:top()) == TextBox,
        "an unbeaten master keeps the refusal text, not the dex entry")
  check(not game.save.pokedex.seen.HITMONLEE,
        "the refusal does not mark Hitmonlee seen")
end

S.finish()
