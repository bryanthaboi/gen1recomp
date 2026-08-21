-- A level-up evolution survives the B held from the level-up box (#968, #1031); a fresh press still cancels (#290, #213).
-- pokered engine/movie/evolution.asm EvolveMon, Evolution_CheckForCancel.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- TextBox and EvolutionState both require Sound inside update, so seeding
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
}

local Fixtures = require("tests.modkit.fixtures")
local Evolution = require("src.pokemon.Evolution")
local EvolutionState = require("src.ui.EvolutionState")
local Input = require("src.core.Input")
local Pokemon = require("src.pokemon.Pokemon")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")

local Data = Fixtures.fresh()
require("src.render.Font").load(Data)

-- FIXMON_A evolves into FIXMON_B at 16 (tests/fixture_data/pokemon.lua)
local EVO_LEVEL = 16
-- x is the default keyboard B (src/core/Input.lua DEFAULT_BINDINGS)
local B_KEY = "x"

local function newGame()
  local game = { data = Data }
  local mon = Pokemon.new(Data, "FIXMON_A", EVO_LEVEL)
  game.save = {
    party = { mon },
    player = { name = "RED", id = 1 },
    options = { textSpeed = 5 },
    flags = {},
    pokedex = { seen = {}, owned = {} },
  }
  game.stack = setmetatable({}, { __index = StateStack })
  game.stack:init()
  game.input = Input
  Input:init()
  return game, mon
end

-- one fixed step, in Game:step's order: promote the queued edges, then
local function step(game)
  game.input:step()
  game.stack:update(1 / 60)
end

local function textOf(box)
  local out = {}
  for _, page in ipairs(box.pages) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, " ")
end

-- the post-battle sequence: grew-to-level box, then Evolution.checkParty
local function levelUpBox(game, mon)
  game.stack:push(TextBox.new(game, "FIXMON A grew\nto level 16!",
    function() Evolution.checkParty(game, nil, { [mon] = true }) end))
end

-- one B edge on the box, still held when the movie takes over: the bug's handoff
local function dismissWithB(game, mon)
  levelUpBox(game, mon)
  local box = game.stack:top()
  for _ = 1, 900 do
    if box.done then break end
    step(game)
  end
  if not box.done then return nil, "the level-up text never finished typing" end
  Input:keypressed(B_KEY)
  step(game)
  -- IsEvolvingText holds its own box for DelayFrames 50 before EvolveMon
  -- runs (engine/pokemon/evos_moves.asm:120-134)
  local intro = game.stack:top()
  if getmetatable(intro) ~= TextBox then
    return nil, "the \"is evolving!\" box never opened"
  end
  if not textOf(intro):find("is evolving") then
    return nil, "the box before the movie is not _IsEvolvingText"
  end
  local top
  for _ = 1, 900 do
    top = game.stack:top()
    if getmetatable(top) == EvolutionState then break end
    step(game)
  end
  if getmetatable(top) ~= EvolutionState then
    return nil, "the evolution screen never opened"
  end
  return top
end

-- B held out of the text box: the movie must run to the end and evolve.
do
  local game, mon = newGame()
  local evo, why = dismissWithB(game, mon)
  if check(evo ~= nil, "the level-up box handed off to the movie: " .. tostring(why)) then
    check(Input:isDown("b"),
          "B is still physically down as the movie starts, which is what "
          .. "the old isDown poll cancelled on")
    eq(evo.cancelable, true,
       "and this is a cancelable level-up evolution, so the movie really "
       .. "is reading the button (#290)")
    -- never released: no second edge ever reaches the movie
    for _ = 1, 400 do
      if evo.done then break end
      step(game)
    end
    check(Input:isDown("b"), "B was held for the whole movie")
    eq(evo.canceled, false, "the held B did not cancel the evolution")
    eq(mon.species, "FIXMON_B", "the mon actually evolved")
    eq(mon.stats.hp, require("src.pokemon.Stats")
         .calc(Data.pokemon.FIXMON_B, EVO_LEVEL, mon.dvs, mon.statExp).hp,
       "and Evolution.apply recalculated its stats on the new species")
    local top = game.stack:top()
    check(getmetatable(top) == TextBox and textOf(top):find("evolved into"),
          "the congratulations text is what closes the movie")
  end
end

-- A deliberate fresh press after the 80-frame delay still cancels.
do
  local game, mon = newGame()
  local evo = assert(dismissWithB(game, mon))
  Input:keyreleased(B_KEY)
  for _ = 1, 400 do
    if evo.t > 80 then break end
    step(game)
  end
  check(evo.t > 80 and not evo.done,
        "the movie is past the DelayFrames window and still running")
  Input:keypressed(B_KEY)
  step(game)
  eq(evo.canceled, true, "a fresh B press cancels the evolution (#213)")
  eq(mon.species, "FIXMON_A", "and the mon keeps its species")
  local top = game.stack:top()
  check(getmetatable(top) == TextBox and textOf(top):find("stopped evolving"),
        "_StoppedEvolvingText prints instead of the congratulations")
end

-- A press inside the 80 frames is not polled at all, so the mon still
do
  local game, mon = newGame()
  local evo = assert(dismissWithB(game, mon))
  Input:keyreleased(B_KEY)
  for _ = 1, 10 do step(game) end
  Input:keypressed(B_KEY)
  step(game)
  Input:keyreleased(B_KEY)
  check(evo.t <= 80, "the press landed inside the delay window")
  eq(evo.canceled, false, "a B press during the delay is never polled")
  for _ = 1, 400 do
    if evo.done then break end
    step(game)
  end
  eq(mon.species, "FIXMON_B", "so the evolution still completes")
end

T.finish()
