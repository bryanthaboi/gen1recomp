-- ../pokered/scripts/FightingDojo.asm:238-252
-- ../pokered/engine/events/give_pokemon.asm:1-49
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not Data.maps then Data:load() end

local S = require("tests.harness").suite("parity Fighting Dojo gift")
local check, eq = S.check, S.eq

local Font = require("src.render.Font")
Font.load(Data)

local realTextBox = package.loaded["src.render.TextBox"]
local realDex = package.loaded["src.ui.DexEntryMenu"]
local soundOpts = require("src.render.TextBox").soundOpts
local shownTexts = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    shownTexts[#shownTexts + 1] = text
    if opts and opts.choice then
      opts.choice(true)
    elseif onDone then
      onDone()
    end
    return { text = text }
  end,
  soundOpts = soundOpts,
}
package.loaded["src.ui.DexEntryMenu"] = {
  new = function(_, _, onDone) if onDone then onDone() end return {} end,
}

local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local realCommands = package.loaded["src.script.Commands"]
package.loaded["src.script.Commands"] = nil
local ScriptCommands = require("src.script.Commands")
local dojo = require("data.scripts.story4").FIGHTING_DOJO

local captured
local function fakeRunner(game, ow)
  local runner = {}
  runner.resume = function() end
  runner.yield = function() end
  runner.isRunning = function() return false end
  function runner:run(script, extra)
    captured = script
    local ctx = { game = game, save = game.save, overworld = ow, runner = runner }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    local labels = {}
    for i, row in ipairs(script) do
      if row[1] == "label" then labels[row[2]] = i end
    end
    local pc = 1
    while pc <= #script do
      local row = script[pc]
      local fn = ScriptCommands[row[1]]
      local target = fn and fn(ctx, row[2], row[3], row[4], row[5])
      pc = target and (labels[target] or (#script + 1)) or (pc + 1)
    end
    if ctx.onDone then ctx.onDone() end
  end
  return runner
end

local function fakeGame()
  local save = SaveData.newGame()
  save.pokedex = { seen = {}, owned = {} }
  save.flags = { EVENT_BEAT_KARATE_MASTER = true }
  local states = {}
  return {
    data = Data, save = save,
    stack = {
      states = states,
      push = function(_, s) states[#states + 1] = s end,
      pop = function(_) states[#states] = nil end,
      top = function(_) return states[#states] end,
    },
  }
end

local function take(game)
  shownTexts, captured = {}, nil
  local doneCalled = false
  local ow = { map = { id = "FIGHTING_DOJO", def = { objects = {} } },
               npcs = {}, entities = {} }
  ow.runner = fakeRunner(game, ow)
  dojo.talk.TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL(game, ow, nil,
    function() doneCalled = true end)
  return doneCalled
end

local function saw(needle)
  for _, s in ipairs(shownTexts) do
    if s:find(needle, 1, true) then return true end
  end
  return false
end

do
  local game = fakeGame()
  check(take(game), "the take-it flow completes")
  check(captured ~= nil, "the gift runs on the script runner")
  if captured then
    eq(captured[1][1], "give_pokemon", "GivePokemon first (FightingDojo.asm:245)")
    eq(captured[1][2], "HITMONLEE", "for the ball's species")
    eq(captured[1][3], 30, "at level 30 (`ld c, 30`)")
    eq(captured[1][5], true, "with GotMonText (give_pokemon.asm:52-71)")
    eq(captured[2][1], "jump_if_false", "carry decides (`jr nc, .done`)")
  end
  eq(#game.save.party, 1, "HITMONLEE lands in the party")
  eq(game.save.party[1] and game.save.party[1].species, "HITMONLEE",
     "and it is the ball's species")
  check(saw("HITMONLEE"), "_GotMonText names it")
  check(saw("nickname"), "AddPartyMon asks for a nickname")
  check(game.save.flags.EVENT_GOT_HITMONLEE == true, "EVENT_GOT_HITMONLEE set")
  check(game.save.flags.EVENT_DEFEATED_FIGHTING_DOJO == true,
        "EVENT_DEFEATED_FIGHTING_DOJO set")
  local toggles = game.save.objectToggles and game.save.objectToggles.FIGHTING_DOJO
  eq(toggles and toggles.FIGHTINGDOJO_HITMONLEE_POKE_BALL, false, "and only that ball is hidden")
end

do
  local Boxes = require("src.pokemon.Boxes")
  local game = fakeGame()
  game.save.party = {}
  for i = 1, 6 do
    game.save.party[i] = Pokemon.new(Data, "RATTATA", 5)
  end
  Boxes.ensure(game.save)
  for _ = 1, Boxes.CAPACITY do
    table.insert(Boxes.active(game.save), Pokemon.new(Data, "RATTATA", 5))
  end
  check(take(game), "the refused take-it flow completes")
  eq(#game.save.party, 6, "the party is untouched")
  check(saw("BOX"), "_BoxIsFullText prints (give_pokemon.asm:40-42)")
  check(not game.save.flags.EVENT_GOT_HITMONLEE,
        "a refused gift sets no EVENT_GOT_HITMONLEE")
  check(not game.save.flags.EVENT_DEFEATED_FIGHTING_DOJO,
        "and no EVENT_DEFEATED_FIGHTING_DOJO")
  check(game.save.objectToggles == nil
        or game.save.objectToggles.FIGHTING_DOJO == nil,
        "and the ball stays on the mat")
end

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.DexEntryMenu"] = realDex
package.loaded["src.script.Commands"] = realCommands
S.finish()
