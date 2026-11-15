-- Pokemon swarms, WIRED.
--
--   luajit tests/gen2_swarm_test.lua
--
-- src/core/gen2/Roamers.lua has carried the whole swarm model for a while --
-- StoreSwarmMapIndices / SetSwarmFlag / CheckSwarmFlag / ActivateFishingSwarm
-- and the _SwarmWildmonCheck lookup -- with three dead links: the daily clear
-- had no call site, the encounter roll never consulted the tables, and the
-- cache carried no tables to consult.  This suite is those three.
--
--   CheckSwarmFlag            second row of CheckTimeEvents' `.do_daily`
--                             (engine/overworld/events.asm)
--   _SwarmWildmonCheck        the first thing LoadWildMonDataPointer does, for
--                             the grass list and the water one alike
--   SwarmGrassWildMons /      data/wild/swarm_grass.asm, swarm_water.asm,
--   SwarmWaterWildMons        emitted by RomExtractorGen2 as
--                             encounters.swarmGrass / .swarmWater
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 swarm")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Roamers = require("src.core.gen2.Roamers")
local Swarm = Roamers.Swarm

local COLL_TALL_GRASS = 0x18

local DATA = {
  items = {},
  moves = { TACKLE = { name = "TACKLE", pp = 35 } },
  pokemon = {
    NIDORAN_M = { name = "NIDORAN", index = 32, types = { "POISON", "POISON" },
      baseStats = { hp = 46, attack = 57, defense = 40, speed = 50,
        specialAttack = 40, specialDefense = 40 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
    YANMA = { name = "YANMA", index = 193, types = { "BUG", "FLYING" },
      baseStats = { hp = 65, attack = 65, defense = 45, speed = 95,
        specialAttack = 75, specialDefense = 45 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
  },
}

local function slots(species, level)
  local list = {}
  for i = 1, 7 do list[i] = { species = species, level = level } end
  return list
end

-- ROUTE_35's own list against the Yanma swarm's, both always-hit so the only
-- question a step asks is WHICH table was searched.
local ENCOUNTERS = {
  grass = {
    ROUTE_35 = { map = "ROUTE_35", rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = { MORN = slots("NIDORAN_M", 12), DAY = slots("NIDORAN_M", 12),
        NITE = slots("NIDORAN_M", 12) } },
  },
  swarmGrass = {
    ROUTE_35 = { map = "ROUTE_35", rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = { MORN = slots("YANMA", 14), DAY = slots("YANMA", 14),
        NITE = slots("YANMA", 14) } },
  },
  swarmWater = {},
}

local function swarmWorld()
  local game = {
    data = DATA,
    save = { player = { name = "GOLD", badges = {} },
      party = { { species = "YANMA", level = 5, hp = 20, maxHp = 20 } },
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.maps = { ROUTE_35 = { id = "ROUTE_35", group = 2, map = 5,
      width = 2, height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
      environment = "ROUTE" },
    ROUTE_36 = { id = "ROUTE_36", group = 2, map = 6, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, environment = "ROUTE" } }
  world.map = { id = "ROUTE_35", def = world.maps.ROUTE_35,
    width = 2, height = 2,
    cellCollision = function() return COLL_TALL_GRASS end }
  world.encounters = ENCOUNTERS
  world.player = { cellX = 0, cellY = 0 }
  world.daytime = "DAY"
  world.startBattle = function(self, opts) self.started = opts return true end
  return world, game
end

-- ---- the lookup arm --------------------------------------------------------
do
  local world, game = swarmWorld()
  check(world:tryWildEncounter(), "an ordinary step on Route 35 fights")
  eq(world.started.wild.species, "NIDORAN_M", "the map's own list")

  -- Script_swarm -> StoreSwarmMapIndices, which is World:setSwarm.
  world:setSwarm(2, 5)
  eq(game.save.swarmMap, "ROUTE_35", "the swarm command stores the map pair")
  check(game.save.dailyFlags.swarm, "and falls through into SetSwarmFlag")

  world.started = nil
  check(world:tryWildEncounter(), "the next step still fights")
  eq(world.started.wild.species, "YANMA",
    "but out of the swarm table, which _SwarmWildmonCheck searches first")
  eq(world.started.wild.level, 14, "at the swarm row's own level")

  -- The check is `cp d / cp e` against the CURRENT map: a swarm on Route 35
  -- does nothing to Route 36.
  world.map = { id = "ROUTE_36", def = world.maps.ROUTE_36,
    width = 2, height = 2,
    cellCollision = function() return COLL_TALL_GRASS end }
  world.started = nil
  check(not world:tryWildEncounter(),
    "a map the swarm is not on falls through to its own (absent) table")
  check(world.started == nil, "so nothing is fought there")
end

-- SWEET SCENT reaches the same ChooseWildEncounter, so it sees the swarm too.
do
  local world = swarmWorld()
  world:setSwarm(2, 5)
  check(world:sweetScentEncounter(), "SWEET SCENT turns something up")
  eq(world.started.wild.species, "YANMA", "and it is the swarm's mon")
end

-- ---- the daily clear -------------------------------------------------------
--
-- CheckTimeEvents `.do_daily` is CheckDailyResetTimer, CheckSwarmFlag,
-- CheckPokerusTick, CheckPhoneCall in that order.  The reset takes
-- DAILYFLAGS1_SWARM down; CheckSwarmFlag is what notices and clears the map
-- pair with it, and it is the ONLY thing that ever ends a swarm.
do
  local world, game = swarmWorld()
  world:setSwarm(2, 5)
  -- A day already banked, so the first poll is not the one that starts the
  -- timer (Apricorns.checkDailyResetTimer arms it on a save that has none).
  world:checkTimeEvents()
  check(game.save.swarmMap == "ROUTE_35",
    "a poll on the same day leaves the swarm up")
  check(Swarm.active(game.save), "the flag is still set")

  -- Roll the clock over the way the daily reset timer measures it.
  game.save.dailyReset.day = (game.save.dailyReset.day or 0) - 2
  world:checkTimeEvents()
  check(not Swarm.active(game.save), "the daily reset drops the flag")
  check(game.save.swarmMap == nil, "and CheckSwarmFlag clears the map pair")

  world.started = nil
  check(world:tryWildEncounter(), "the step after that still fights")
  eq(world.started.wild.species, "NIDORAN_M", "out of the map's own list again")
end

-- ActivateFishingSwarm rides the same flag and does NOT touch the map pair,
-- so the clear has to take both down together.
do
  local world, game = swarmWorld()
  world:setSwarm(2, 5)
  Swarm.setFishing(game.save, Swarm.FISH_QWILFISH)
  eq(Swarm.fishing(game.save), Swarm.FISH_QWILFISH, "the fishing swarm is up")
  world:checkTimeEvents() -- arms the timer, the way a save's first step does
  game.save.dailyReset.day = (game.save.dailyReset.day or 0) - 2
  world:checkTimeEvents()
  eq(Swarm.fishing(game.save), Swarm.FISH_NONE,
    "and goes down on the same daily tick")
end

-- ---- the extracted tables --------------------------------------------------
--
-- data/wild/swarm_grass.asm has four rows and swarm_water.asm one; the Yanma
-- swarm on Route 35 is the one the Dunsparce/Yanma phone calls arm.
do
  local cache = os.getenv("GOLD_CACHE")
  local encounters
  if cache then
    local chunk = loadfile(cache .. "/data/generated/encounters.lua")
    encounters = chunk and chunk()
  end
  if not (encounters and encounters.swarmGrass) then
    check(true, "no gold cache: swarm table shape (SKIP)")
  else
    local grass = encounters.swarmGrass
    check(grass.ROUTE_35 ~= nil, "SwarmGrassWildMons carries ROUTE_35")
    check(grass.ROUTE_38 ~= nil, "and ROUTE_38")
    check(grass.DARK_CAVE_VIOLET_ENTRANCE ~= nil,
      "and DARK_CAVE_VIOLET_ENTRANCE, which is the Dunsparce swarm")
    check(grass.MOUNT_MORTAR_1F_OUTSIDE ~= nil, "and MOUNT_MORTAR_1F_OUTSIDE")
    eq(grass.ROUTE_35.rates.DAY, 25, "Route 35's swarm rate is 10 percent")
    eq(grass.ROUTE_35.slots.DAY[3].species, "YANMA",
      "and slot 3 of its day list is the YANMA the swarm exists for")
    local water = encounters.swarmWater or {}
    check(water.MOUNT_MORTAR_1F_OUTSIDE ~= nil,
      "SwarmWaterWildMons carries the one Marill row")
    eq(water.MOUNT_MORTAR_1F_OUTSIDE.slots[2].species, "MARILL",
      "with MARILL in its middle slot")
  end
end

S.finish()
