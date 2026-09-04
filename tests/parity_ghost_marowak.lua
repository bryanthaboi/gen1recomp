-- Parity test: the Pokemon Tower 6F Marowak ghost scene.
--
-- InitWildBattle runs the battle transition before the disguise
-- (engine/battle/core.asm:6695-6702), _EnemyAppearedText carries no
-- article (data/text/text_2.asm:1251-1255), and the CUBONE's-mother text
-- ends in `done` so PlayCry lands on it (scripts/PokemonTower6F.asm:
-- 137-148, text/PokemonTower6F.asm:1-5).  See #1849.
--
-- Self-contained; run via `luajit tests/parity_ghost_marowak.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local S = require("tests.harness").suite("parity marowak scene")
local check, eq = S.check, S.eq

do
  local RealBattleState = require("src.battle.BattleState")
  local game = {
    data = Data,
    save = {
      party = { Pokemon.new(Data, "BULBASAUR", 30) },
      player = { name = "RED" },
      inventory = {},
      options = {},
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
  local b = RealBattleState.newWild(game, "MAROWAK", 30)
  b:makeGhost()
  eq(b.enemy.name, "GHOST", "the disguise renames the foe")
  eq(b.introText, "GHOST\nappeared!{PROMPT}",
    "_EnemyAppearedText has no article in front of the nick")
end

-- The script side: entry wipe and cry ordering.
local realTextBox = package.loaded["src.render.TextBox"]
local realBattleState = package.loaded["src.battle.BattleState"]

local pushed = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, cb)
    local box = { text = text, cb = cb }
    table.insert(pushed, box)
    return box
  end,
  substitute = function(_, text) return text end,
}
local battles = {}
local stubBattle = {}
stubBattle.__index = stubBattle
function stubBattle:makeGhost() self.ghost = true end
function stubBattle:makeUnveiledGhost() self.scopeReveal = true end
package.loaded["src.battle.BattleState"] = {
  newWild = function(_, species, level)
    local b = setmetatable({ species = species, level = level }, stubBattle)
    table.insert(battles, b)
    return b
  end,
}

local scripts = dofile("data/scripts/story3.lua")
local onStep = scripts.POKEMON_TOWER_6F.onStep
check(onStep ~= nil, "the tower 6F step trigger is registered")

local game = {
  data = { text = {} },
  save = { flags = {}, inventory = {} },
  stack = { push = function() end },
}
local rows
local pushedBattles, stackBattles = 0, 0
local ow = {
  pushBattle = function() pushedBattles = pushedBattles + 1 end,
  afterBattle = function() end,
  scriptMove = function() end,
  runner = { run = function(_, r) rows = r end },
}
game.stack.push = function(_, thing)
  if getmetatable(thing) == stubBattle then stackBattles = stackBattles + 1 end
end

eq(onStep(game, ow, 10, 16), true, "stepping on the trigger cell fires it")
eq(#pushed, 1, "the Be gone... line opens the scene")
pushed[1].cb()
eq(#battles, 1, "the ghost battle is built")
eq(pushedBattles, 1, "the battle goes through the entry wipe (pushBattle)")
eq(stackBattles, 0, "and is never pushed straight onto the stack")

battles[1].onFinish("win")
check(rows ~= nil, "victory queues the departed script")
eq(rows[1][1], "play_cry", "PlayCry is armed before the CUBONE's-mother box")
eq(rows[1][2], "MAROWAK", "and it is the RESTLESS SOUL's cry")
eq(rows[1][3], nil, "with no button wait -- that text ends in `done`")
eq(rows[2][1], "show_text", "the CUBONE's-mother line follows")
check(rows[2][2]:find("CUBONE") ~= nil, "and it is that line")
eq(rows[3][1], "wait", "then the DelayFrames 30 gap")
eq(rows[4][1], "show_text", "then the soul-was-calmed line")

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.battle.BattleState"] = realBattleState

S.finish()
