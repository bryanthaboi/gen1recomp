-- EndOfBattle evolves on the battle screen, before the map comes back
-- (engine/battle/end_of_battle.asm:42-45) (#1656)

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local S = require("tests.harness").suite("parity trainer evolution order")
local check = S.check

local Game = require("src.core.Game")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local ScriptRunner = require("src.script.ScriptRunner")
local OverworldState = require("src.world.OverworldController")
local Pokemon = require("src.pokemon.Pokemon")
require("src.render.Font").load(Data)

Game.data = Data
Game.save = SaveData.newGame()
Game.stack = StateStack; StateStack:init()
Game.renderer = { worldViewSize = function() return 160, 144 end }

local caterpie = Pokemon.new(Data, "CATERPIE", 7)
Game.save.party = { caterpie }

local fakeBattle
local originalBattleState = package.loaded["src.battle.BattleState"]
package.loaded["src.battle.BattleState"] = {
  newTrainer = function()
    fakeBattle = { leveledUp = { [caterpie] = true } }
    return fakeBattle
  end,
}

local overworld = setmetatable({}, { __index = OverworldState })
overworld:enter("ROUTE_1", 5, 5, "down")
local runner = ScriptRunner.new(Game, overworld)
runner:run({
  { "start_battle", "trainer", "OPP_YOUNGSTER", 1 },
  { "show_text", "THE TRAINER TALKS AFTER THE FIGHT" },
  { "show_text", "THE TRAINER HAS MORE TO SAY" },
})

check(fakeBattle ~= nil, "trainer battle starts and yields the script")
Game.stack:pop()
fakeBattle.onFinish("win")

package.loaded["src.battle.BattleState"] = originalBattleState

local function stateHas(state, text)
  for _, page in ipairs(state.pages or {}) do
    for _, line in ipairs(page) do
      if type(line) == "string" and line:find(text, 1, true) then return true end
    end
  end
  return false
end

local afterText = Game.stack:top()
check(stateHas(afterText, "THE TRAINER TALKS"),
  "the trainer's after-battle text is shown first")
check(#Game.stack.states == 1,
  "the evolution screen waits until trainer after-text closes")

Game.stack:pop()
afterText.onDone()

local moreText = Game.stack:top()
check(stateHas(moreText, "MORE TO SAY"),
  "all trainer after-text finishes before evolution")
check(#Game.stack.states == 1,
  "the evolution still waits for the last trainer text")

Game.stack:pop()
moreText.onDone()

-- The evolution belongs to the battle screen (BattleState:finish ->
-- Evolution.checkParty), so afterBattle leaves nothing behind the text.
check(#Game.stack.states == 0,
  "afterBattle pushes no evolution; the battle screen already ran it")

S.finish()
