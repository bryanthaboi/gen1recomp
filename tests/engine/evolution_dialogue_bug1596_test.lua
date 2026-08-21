-- The evolution dialogue is the cart's, in the cart's order (#1596):
-- engine/pokemon/evos_moves.asm:120-134 (the clear is rows 0-11 only),
-- :136-150, :151-153

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, id) played[#played + 1] = id end,
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

local EVO_LEVEL = 16

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

-- The box that goes up before the movie, and the frames it holds for.
do
  local game, mon = newGame()
  Evolution.evolve(game, mon, "FIXMON_B", nil, "LEVEL")
  local intro = game.stack:top()
  if check(getmetatable(intro) == TextBox,
           "_IsEvolvingText goes up in a real bordered text box first") then
    check(textOf(intro):find("is evolving"),
          "and it is the cart's line: " .. textOf(intro))
    check(intro.stay ~= nil and not intro.stay.prompt,
          "which waits for no button (IsEvolvingText ends in `done`) "
          .. "and stays up under whatever follows")
  end
  -- it hands off to the movie on its own, with no input at all
  local top
  for _ = 1, 900 do
    top = game.stack:top()
    if getmetatable(top) == EvolutionState then break end
    step(game)
  end
  check(getmetatable(top) == EvolutionState,
        "the flash movie opens once the DelayFrames 50 hold has passed")
  local underneath = false
  for _, s in ipairs(game.stack.states or {}) do
    if s == intro then underneath = true end
  end
  check(underneath, "the 'is evolving!' box is still on the stack under the "
        .. "flash (ClearScreenArea wipes rows 0-11 only, evos_moves.asm:126-128)")
  check(not EvolutionState.isOpaque,
        "and the flash screen is not opaque, so the box beneath draws")
  eq(mon.species, "FIXMON_A",
     "and nothing has evolved yet while the box was up")
end

-- What closes the movie: EvolvedText + IntoText, and the jingle.
do
  local game, mon = newGame()
  Evolution.evolve(game, mon, "FIXMON_B", nil, "LEVEL")
  local evo
  for _ = 1, 900 do
    evo = game.stack:top()
    if getmetatable(evo) == EvolutionState then break end
    step(game)
  end
  assert(getmetatable(evo) == EvolutionState, "the movie never opened")
  played = {}
  for _ = 1, 600 do
    if evo.done then break end
    step(game)
  end
  eq(mon.species, "FIXMON_B", "the mon evolved")
  local box = game.stack:top()
  if check(getmetatable(box) == TextBox, "and the result text is a text box") then
    local said = textOf(box)
    check(said:find("evolved") and said:find("into"),
          "_EvolvedText + _IntoText print together: " .. said)
    check(not said:find("Congratulations"),
          "no fabricated \"Congratulations!\" line (it is in no ROM)")
    check(box.auto ~= nil and box.auto.sound ~= nil,
          "and the box carries a jingle the way sound_get_item_1 boxes do")
    -- type it out; auto.sound fires once the last page has landed
    for _ = 1, 900 do
      if box.autoStarted then break end
      step(game)
    end
    local heard = false
    for _, id in ipairs(played) do
      if id == "Get_Item2" then heard = true end
    end
    check(heard, "SFX_GET_ITEM_2 plays on that box (evos_moves.asm:151)")
  end
end

T.finish()
