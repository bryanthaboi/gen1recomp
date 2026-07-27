-- Parity test: which evolutions honour a B press.
-- Self-contained: run via `luajit tests/parity_evolution_cancel.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- engine/movie/evolution.asm Evolution_CheckForCancel reads the joypad each
-- flash and, on B, checks wForceEvolution before honouring it:
--
--   .pressedB
--       ld a, [wForceEvolution]
--       and a
--       jr nz, .notAllowedToCancel
--
-- ItemUseEvoStone sets wForceEvolution before calling TryEvolvingMon, so a
-- stone evolution reads the press and throws it away (#290).  Trade
-- evolutions never reach the poll at all, since evos_moves.asm routes
-- LINK_STATE_TRADING past it (#213).  That leaves level-up and rare candy,
-- which run with wForceEvolution clear, as the only cancelable kinds.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity evolution cancel")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
Game.data = Data
Game.save = SaveData.newGame()
Game.stack = StateStack; StateStack:init()
require("src.render.Font").load(Data)

local EvolutionState = require("src.ui.EvolutionState")

-- `via` is the evolution method id out of Evolution.METHODS, which is also
-- what data/generated/pokemon.lua stores on each evolution record.
local function cancelable(via)
  local mon = { species = "PIKACHU", level = 20 }
  local state = EvolutionState.new(Game, mon, "RAICHU", function() end, via)
  return state.cancelable
end

eq(cancelable("LEVEL"), true, "level-up evolutions honour B")
eq(cancelable("ITEM"), false, "stone evolutions ignore B (#290)")
eq(cancelable("TRADE"), false, "trade evolutions ignore B (#213)")

-- rare candy walks the same level-up path, so it stays cancelable; an
-- unknown/mod method has no wForceEvolution equivalent and defaults to the
-- cancelable branch rather than silently locking the player in
eq(cancelable(nil), true, "an unspecified method stays cancelable")
eq(cancelable("MOD_CUSTOM"), true, "a mod method defaults to cancelable")

-- the stone methods really are the ITEM records, so the id above is the one
-- the data uses (this is what ties the assertion to real content)
do
  local stoneEvos, itemMethod = 0, false
  for _, def in pairs(Data.pokemon) do
    for _, evo in ipairs(def.evolutions or {}) do
      if evo.method == "ITEM" then
        stoneEvos = stoneEvos + 1
        if evo.item then itemMethod = true end
      end
    end
  end
  check(stoneEvos > 0, "the dex actually contains stone evolutions")
  check(itemMethod, "stone evolution records name the stone item")
end

S.finish()
