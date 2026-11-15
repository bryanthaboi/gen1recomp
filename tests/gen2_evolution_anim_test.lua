-- The evolution screen survives being pushed onto a stack.
--
--   luajit tests/gen2_evolution_anim_test.lua
--
-- `enter` is the stack's lifecycle hook: StateStack:push calls `state:enter(...)`
-- (src/core/StateStack.lua:18), and Gold runs that same stack
-- (src/core/Game2.lua:makeStack).  EvolutionAnim used to define `enter(phase)`
-- as its own phase-transition method, so pushing it called that method with
-- no argument, set phase to nil,
-- and left update() falling through every branch -- decrementing its timer
-- forever while World:busy() stayed true.  A post-battle evolution became an
-- unrecoverable hang; the Gold route bot found it the first time its starter
-- reached level 14, roughly two hours into a run.
--
-- The regression this pins is not the rename but the PROPERTY: after a push,
-- the screen still runs to completion.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 evolution anim")
local check, eq = S.check, S.eq

local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")

-- No screen may use the stack's hook name for its own purposes.
check(rawget(EvolutionAnim, "enter") == nil,
      "EvolutionAnim does not define `enter` (the stack lifecycle hook)")
check(type(rawget(EvolutionAnim, "setPhase")) == "function",
      "its phase transition has a name of its own")

do
  local S7B = require("tests.fixture_data.gen2_rom_text_s7_b")
  local mon = { species = "OLD", nickname = "SURNOM", moves = {} }
  local anim = EvolutionAnim.new({ data = { audio = {}, text = S7B.text() } }, {
    mon = mon, entry = { into = "NEW" }, party = { mon },
  })
  eq(anim.lines[1], "What? SURNOM", "_EvolvingText comes from the cache")
  eq(anim.lines[2], "is evolving!", "split on the cart's own line break")
  anim = EvolutionAnim.new({ data = { audio = {},
    text = S7B.text({ _EvolvingText = "Quoi ? {STRBUF}\nevolue !{DONE}" }) } }, {
    mon = mon, entry = { into = "NEW" }, party = { mon },
  })
  eq(anim.lines[1], "Quoi ? SURNOM", "a translated cache line replaces the English")
  eq(anim.lines[2], "evolue !", "and is split the same way")
  check(not pcall(EvolutionAnim.new, { data = { audio = {}, text = S7B.without("_EvolvingText") } },
    { mon = mon, entry = { into = "NEW" }, party = { mon } }),
    "a cache without _EvolvingText is an error")
end

local cache = os.getenv("GOLD_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local function loadGen(name)
  local path = cache .. "/data/generated/" .. name
  local fh = io.open(path, "r")
  if not fh then return nil end
  fh:close()
  return assert(loadfile(path))()
end

local pokemon = loadGen("pokemon.lua")
if not pokemon then
  check(true, "gold cache absent : name check only (SKIP the run-through)")
  S.finish()
  return
end

local Evolution = require("src.core.gen2.Evolution")
local data = { pokemon = pokemon, moves = loadGen("moves.lua"), audio = {},
               gen2Palettes = loadGen("palettes.lua"), text = loadGen("rom_text.lua") }

-- CYNDAQUIL -> QUILAVA at 14, the exact evolution the bot wedged on.
local mon = { species = "CYNDAQUIL", level = 14, hp = 20, maxHp = 20,
              moves = { { id = "EMBER", pp = 10, maxPp = 25 } } }
local save = { party = { mon }, pokedex = { seen = {}, caught = {} } }
local game = { data = data, save = save }

local plan = Evolution.plan(data, { mon }, { [1] = true }, { timeOfDay = 1 })
eq(#plan, 1, "CYNDAQUIL at 14 has an evolution to play")

local done = false
local anim = EvolutionAnim.new(game, {
  mon = plan[1].mon, entry = plan[1].entry, index = plan[1].index,
  party = save.party, save = save,
  onDone = function() done = true end,
})

-- The push, exactly as Screens.push does it: no extra arguments.  This is the
-- line that used to kill the screen.
-- StateStack is used as a singleton (Game calls StateStack:init()), so the
-- test drives it directly rather than inventing an instance it does not have.
local StateStack = require("src.core.StateStack")
StateStack:init()
StateStack:push(anim)

eq(anim.phase, "evolving", "being pushed does not clear the phase")

-- Mashing A is what a bot (or an impatient player) does; it must not stall it.
game.input = { wasPressed = function(_, b) return b == "a" end }
local frames = 0
for _ = 1, 5000 do
  if done then break end
  frames = frames + 1
  check(anim.phase ~= nil, "phase stays set while the animation runs")
  if anim.phase == nil then break end
  anim:update(1 / 60)
end

check(done, "the evolution runs to completion and calls onDone")
check(frames < 2000, "and finishes promptly (" .. frames .. " frames)")
eq(save.party[1].species, "QUILAVA", "the party record is written back")

S.finish()
