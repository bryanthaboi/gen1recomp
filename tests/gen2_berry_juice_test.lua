-- Shuckle's held BERRY fermenting into BERRY JUICE:
-- ConvertBerriesToBerryJuice (engine/events/pokerus/pokerus.asm:124).
--
--   luajit tests/gen2_berry_juice_test.lua
--
-- ROM-free.  A 16/256 roll after every battle WIN, gated on
-- ENGINE_REACHED_GOLDENROD like the Pokerus roll it precedes; the first
-- party SHUCKLE holding a BERRY has its item rewritten, silently.  Shuckie
-- (the Cianwood loaner) arrives holding one, which is the payoff.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 berry juice")
local check, eq = S.check, S.eq

local BerryJuice = require("src.battle.gen2.BerryJuice")

local function shuckle(item)
  return { species = "SHUCKLE", nickname = "SHUCKIE", item = item, hp = 20 }
end

-- ---- the roll and the walk ------------------------------------------------
do
  local party = { shuckle("BERRY") }
  eq(BerryJuice.convert(party, { reachedGoldenrod = true,
    random = function() return 15 end }), 1,
    "a roll under 16 converts")
  eq(party[1].item, "BERRY_JUICE", "the held BERRY became BERRY JUICE")

  party = { shuckle("BERRY") }
  eq(BerryJuice.convert(party, { reachedGoldenrod = true,
    random = function() return 16 end }), nil,
    "a roll at 16 does nothing")
  eq(party[1].item, "BERRY", "and the BERRY stays")

  party = { shuckle("BERRY") }
  eq(BerryJuice.convert(party, { reachedGoldenrod = false,
    random = function() return 0 end }), nil,
    "before Goldenrod the roll never runs")
end

-- ---- only the right mon, only the first -----------------------------------
do
  local party = {
    { species = "PIDGEY", item = "BERRY", hp = 20 },
    shuckle("GOLD_BERRY"),
    shuckle("BERRY"),
    shuckle("BERRY"),
  }
  eq(BerryJuice.convert(party, { reachedGoldenrod = true,
    random = function() return 0 end }), 3,
    "the walk finds the first SHUCKLE holding a plain BERRY")
  eq(party[1].item, "BERRY", "another species' BERRY is not touched")
  eq(party[2].item, "GOLD_BERRY", "a GOLD BERRY is not a BERRY")
  eq(party[3].item, "BERRY_JUICE", "the first match converts")
  eq(party[4].item, "BERRY",
    "and the routine returns there -- one conversion per win")
end

-- ---- the battle-exit call site --------------------------------------------
do
  local EngineFlagsFixture = require("tests.fixture_data.gen2_engine_flags")
  EngineFlagsFixture.bind("gold")
  local save = { engineFlags = { [21] = true },
    party = { shuckle("BERRY") } }
  eq(BerryJuice.convertAfterBattle(save, nil,
    { random = function() return 0 end }), 1,
    "the save-facing wrapper reads ENGINE_REACHED_GOLDENROD")
  eq(save.party[1].item, "BERRY_JUICE", "and converts the save's party")

  save = { engineFlags = {}, party = { shuckle("BERRY") } }
  eq(BerryJuice.convertAfterBattle(save, nil,
    { random = function() return 0 end }), nil,
    "no flag, no ferment")

  EngineFlagsFixture.bind("crystal")
  local crystal = { engineFlags = { [22] = true }, party = { shuckle("BERRY") } }
  eq(BerryJuice.convertAfterBattle(crystal, nil,
    { random = function() return 0 end }), 1,
    "Crystal's ENGINE_REACHED_GOLDENROD is flag 22")
  local goldId = { engineFlags = { [21] = true }, party = { shuckle("BERRY") } }
  eq(BerryJuice.convertAfterBattle(goldId, nil,
    { random = function() return 0 end }), nil,
    "and Gold's 21 is not it on Crystal")
  EngineFlagsFixture.bind("gold")

  -- The wire into the battle exit: GivePokerusAndConvertBerries runs the
  -- conversion FIRST, and BattleState:givePokerus is the port's copy of
  -- that arm.  A call site that is not spelled out in the file is not
  -- there at all (the same proof shape gen2_pokerus_test uses).
  local f = io.open("src/ui/gen2/BattleState.lua", "r")
  check(f ~= nil, "BattleState's source is readable")
  local body = f:read("*a")
  f:close()
  check(body:find("BerryJuice.convertAfterBattle(self.save, party)", 1, true)
    ~= nil, "givePokerus converts the berries")
  local convertAt = body:find("BerryJuice.convertAfterBattle(self.save, party)",
    1, true)
  local pokerusAt = body:find("Pokerus.giveAfterBattle(self.save, party)",
    1, true)
  check(convertAt and pokerusAt and convertAt < pokerusAt,
    "and does it before the Pokerus roll, the asm's own order")
end

S.finish()
