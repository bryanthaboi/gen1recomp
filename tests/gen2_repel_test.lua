-- CheckRepelEffect, the last gate in TryWildEncounter.
--
--   luajit tests/gen2_repel_test.lua
--
-- The port had the whole REPEL step chain -- World:useRepel arming
-- save.repelSteps, StepEvents.repelStep ticking it down and printing the
-- wear-off -- and nothing in the encounter path ever READ it, so a Max Repel
-- was consumed, messaged and counted while changing nothing at all.
--
-- CheckRepelEffect (engine/overworld/wildmons.asm) runs AFTER
-- ChooseWildEncounter has already picked the mon, which is the fact that
-- decides every case below: the filter is on the LEVEL that was rolled, and
-- the mon it is measured against is the first party member that is not
-- fainted.  `ld a, [wCurPartyLevel] / cp [hl] / jr nc, .encounter` takes the
-- encounter on greater-or-equal, so a lead standing at the wilds' own level
-- repels nothing.
--
-- CheckEncounterRoamMon writes wCurPartyLevel too, so a beast goes through the
-- same filter; SweetScentEncounter never reaches the routine at all.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 repel")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Roamers = require("src.core.gen2.Roamers")

local COLL_TALL_GRASS = 0x18

local DATA = {
  items = {
    REPEL = { id = "REPEL", name = "REPEL", pocket = "ITEM", index = 0x14 },
    MAX_REPEL = { id = "MAX_REPEL", name = "MAX REPEL", pocket = "ITEM",
      index = 0x2b },
  },
  moves = { TACKLE = { name = "TACKLE", pp = 35 } },
  pokemon = {
    HOOTHOOT = { name = "HOOTHOOT", index = 163, types = { "NORMAL", "FLYING" },
      baseStats = { hp = 60, attack = 30, defense = 30, speed = 50,
        specialAttack = 36, specialDefense = 56 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
    RAIKOU = { name = "RAIKOU", index = 243, types = { "ELECTRIC", "ELECTRIC" },
      baseStats = { hp = 90, attack = 85, defense = 75, speed = 115,
        specialAttack = 115, specialDefense = 100 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
    QUAGSIRE = { name = "QUAGSIRE", index = 195, types = { "WATER", "GROUND" },
      baseStats = { hp = 95, attack = 85, defense = 85, speed = 35,
        specialAttack = 65, specialDefense = 65 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
  },
}

-- An always-passing rate and all seven slots filled with the same row, so
-- nothing below is about a roll: every step that is not repelled starts a
-- battle with a level 15 HOOTHOOT.
local function sevenSlots()
  local list = {}
  for i = 1, 7 do list[i] = { species = "HOOTHOOT", level = 15 } end
  return list
end

local ENCOUNTERS = {
  grass = {
    ROUTE_42 = {
      map = "ROUTE_42",
      rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = { MORN = sevenSlots(), DAY = sevenSlots(), NITE = sevenSlots() },
    },
  },
}
for key, value in pairs(require("tests.fixtures.gen2_roamers").encounters("gold")) do
  ENCOUNTERS[key] = value
end

local function repelWorld(party)
  local game = {
    data = DATA,
    save = { player = { name = "GOLD", badges = {} },
      party = party or {}, inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.maps = { ROUTE_42 = { id = "ROUTE_42", group = 3, map = 1,
    width = 2, height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {} } }
  world.map = {
    id = "ROUTE_42", def = world.maps.ROUTE_42, width = 2, height = 2,
    cellCollision = function() return COLL_TALL_GRASS end,
  }
  world.map.def.environment = "ROUTE"
  world.encounters = ENCOUNTERS
  world.player = { cellX = 0, cellY = 0 }
  world.daytime = "DAY"
  world.started = nil
  world.startBattle = function(self, opts) self.started = opts return true end
  return world, game
end

local function mon(species, level)
  return { species = species, level = level, hp = 20, maxHp = 20 }
end

-- ---- the plain grass filter ------------------------------------------------
do
  local world, game = repelWorld({ mon("QUAGSIRE", 40) })
  check(world:tryWildEncounter(), "with no REPEL the level 15 wild fires")
  eq(world.started.wild.species, "HOOTHOOT", "and it is the map's own slot")

  world.started = nil
  game.save.pokedex = { seen = {}, caught = {} }
  game.save.repelSteps = 250
  check(not world:tryWildEncounter(),
    "a ticking REPEL drops a wild BELOW the lead's level")
  check(world.started == nil, "so no battle starts")
  eq(game.save.repelSteps, 250,
    "and the filter never touches the counter -- DoRepelStep owns it")
  check(not game.save.pokedex.seen.HOOTHOOT,
    "a repelled encounter is not even SEEN")
end

-- `jr nc, .encounter`: equal levels still fight.  This is the difference
-- between "repels weaker mons" and "repels everything", and it is one branch.
do
  local world, game = repelWorld({ mon("QUAGSIRE", 15) })
  game.save.repelSteps = 250
  check(world:tryWildEncounter(),
    "a wild at exactly the lead's level is NOT repelled")
  eq(world.started.wild.level, 15, "and fights at its own level")
end

do
  local world, game = repelWorld({ mon("QUAGSIRE", 16) })
  game.save.repelSteps = 100
  check(not world:tryWildEncounter(), "one level under the lead is repelled")
end

-- The walk starts at wPartyMon1HP and skips every slot whose HP is zero, so
-- the mon a repel measures against is the first LIVE one -- and an egg (HP
-- zeroed by DayCare_GiveEgg) is never it.
do
  local world, game = repelWorld({
    { species = "EGG", isEgg = true, hp = 0, maxHp = 0, level = 40 },
    { species = "QUAGSIRE", level = 5, hp = 0, maxHp = 20 },
    mon("QUAGSIRE", 40),
  })
  game.save.repelSteps = 250
  check(not world:tryWildEncounter(),
    "the egg and the fainted mon are skipped; the level 40 lead repels")

  world.started = nil
  game.save.party = { { species = "QUAGSIRE", level = 5, hp = 12, maxHp = 20 },
    mon("QUAGSIRE", 40) }
  check(world:tryWildEncounter(),
    "a live level 5 in front of it lets the level 15 wild through")
end

-- No repel armed at all is the routine's own first line: `and a / jr z`.
do
  local world, game = repelWorld({ mon("QUAGSIRE", 40) })
  game.save.repelSteps = 0
  check(world:tryWildEncounter(), "a spent REPEL suppresses nothing")
end

-- ---- the beast ------------------------------------------------------------
--
-- CheckEncounterRoamMon stages wTempWildMonSpecies AND wCurPartyLevel before
-- returning carry, so the level a repel measures is the beast's 40.  A level
-- 41 lead really does repel Raikou on the cart.
do
  local world, game = repelWorld({ mon("QUAGSIRE", 41) })
  Roamers.init(game.save, { force = true, encounters = ENCOUNTERS })
  game.save.roamers[1].map = "ROUTE_42"
  world.roamerRandom = function() return 1 end -- slot 1 past both gates
  game.save.repelSteps = 250
  check(not world:tryWildEncounter(), "a level 41 lead repels the beast itself")
  check(world.started == nil, "no roaming battle starts")
  check(game.save.roamers[1].hp == 0,
    "and .InitRoamHP never runs, so the beast keeps its unrolled struct")

  game.save.party = { mon("QUAGSIRE", 40) }
  check(world:tryWildEncounter(), "a level 40 lead does not")
  eq(world.started.roaming, 1, "and it is the roaming battle")
end

-- ---- SWEET SCENT ----------------------------------------------------------
--
-- SweetScentEncounter (engine/events/sweet_scent.asm) is CanEncounterWildMon,
-- GetMapEncounterRate and ChooseWildEncounter -- and then straight to
-- wScriptVar.  CheckRepelEffect is not in it, so the move works through a
-- Max Repel exactly as the cart lets it.
do
  local world, game = repelWorld({ mon("QUAGSIRE", 40) })
  game.save.repelSteps = 250
  check(world:sweetScentEncounter(), "SWEET SCENT ignores a ticking REPEL")
  eq(world.started.wild.species, "HOOTHOOT", "and turns up the map's own slot")
end

S.finish()
