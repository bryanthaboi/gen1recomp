-- ConvertBerriesToBerryJuice (engine/events/pokerus/pokerus.asm:124), the
-- first thing GivePokerusAndConvertBerries does on a battle WIN: gated on
-- ENGINE_REACHED_GOLDENROD like the Pokerus roll beside it, one byte under
-- `1 out_of 16` (16/256), then a walk down the party for a SHUCKLE holding
-- a BERRY.  Only the FIRST match converts -- the routine returns the moment
-- it rewrites one item byte -- and nothing tells the player; the changed
-- held item is the whole event.
--
-- Shuckie (the Cianwood loaner) arrives holding a BERRY, which is the
-- intended payoff.  The Pokerus half lives in src/core/gen2/Pokerus.lua;
-- both are called from the same battle-exit arm in
-- src/ui/gen2/BattleState.lua, conversion first, the way the asm orders
-- them.

local EngineFlags = require("src.core.gen2.EngineFlags")

local BerryJuice = {}

-- `cp 1 out_of 16` with out_of = `* $100 /`: a byte under 16 converts.
BerryJuice.ROLL_LIMIT = 16

function BerryJuice.random()
  if love and love.math and love.math.random then
    return love.math.random(0, 255)
  end
  return math.random(0, 255)
end

-- The walk itself.  `opts.random` is a function of no arguments returning
-- 0..255 (the Pokerus convention), `opts.reachedGoldenrod` the engine flag.
-- Returns the party slot that converted, or nil.
function BerryJuice.convert(party, opts)
  opts = opts or {}
  if not opts.reachedGoldenrod then return nil end
  local roll = (opts.random or BerryJuice.random)()
  if roll >= BerryJuice.ROLL_LIMIT then return nil end
  for index, mon in ipairs(party or {}) do
    if mon.species == "SHUCKLE" and mon.item == "BERRY" then
      mon.item = "BERRY_JUICE"
      return index
    end
  end
  return nil
end

-- The save-facing wrapper, mirroring Pokerus.giveAfterBattle's shape so the
-- battle exit calls the two the same way.
function BerryJuice.convertAfterBattle(save, party, opts)
  if type(save) ~= "table" then return nil end
  opts = opts or {}
  local flags = save.engineFlags or {}
  return BerryJuice.convert(party or save.party or {}, {
    random = opts.random,
    reachedGoldenrod =
      flags[EngineFlags.id("ENGINE_REACHED_GOLDENROD")] == true,
  })
end

return BerryJuice
