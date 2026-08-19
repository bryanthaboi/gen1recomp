-- Gen 2 time-dependent fishing encounters (TimeFishGroups).
--
--   luajit tests/gen2_fishing_time_test.lua
--
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 fishing time")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local Encounter = require("src.battle.gen2.Encounter")
local Permissions = require("src.world.gen2.Permissions")

local COLL_FLOOR, COLL_WATER = 0x00, 0x29
local MAP_W, MAP_H = 10, 10

local function mon(name, level)
  return { species = name, id = name, name = name, baseStats = { hp = 50 }, level = level or 10 }
end

local function fakeData()
  return {
    pokemon = {
      MAGIKARP = mon("MAGIKARP"),
      KRABBY = mon("KRABBY"),
      KINGLER = mon("KINGLER"),
      CORSOLA = mon("CORSOLA"),
      STARYU = mon("STARYU"),
      SHELLDER = mon("SHELLDER"),
      CHINCHOU = mon("CHINCHOU"),
      LANTURN = mon("LANTURN"),
      TENTACRUEL = mon("TENTACRUEL"),
    },
    items = {
      OLD_ROD = { keyItem = true },
      GOOD_ROD = { keyItem = true },
      SUPER_ROD = { keyItem = true },
    },
  }
end

local function fishWorld(mapId, fishGroup, daytime)
  local map = {
    id = mapId,
    def = { id = mapId, width = MAP_W, height = MAP_H,
            environment = "ROUTE", fishGroup = fishGroup },
    cellCollision = function(self, cx, cy)
      return (cx == 5 and cy == 4) and COLL_WATER or COLL_FLOOR
    end,
  }
  local game = {
    save = {
      timeOfDay = daytime or "DAY",
      dailyFlags = {},
      player = { cellX = 5, cellY = 5, facing = "up" },
    },
    data = fakeData(),
  }
  local world = World.new(game)
  world.map = map
  world.maps = { [mapId] = map.def }
  world.player = game.save.player
  world.playerState = 0
  world.tod = daytime or "DAY"
  world.daytime = daytime or "DAY"
  return world, game
end

-- Test Shore group with TimeFishGroups (Corsola / Staryu)
local SHORE_ENCOUNTERS = {
  fishGroups = {
    FISHGROUP_SHORE = {
      id = "FISHGROUP_SHORE",
      chance = 255, -- always bite
      old = {
        { chance = 179, species = "MAGIKARP", level = 10 },
        { chance = 217, species = "MAGIKARP", level = 10 },
        { chance = 255, species = "KRABBY", level = 10 },
      },
      good = {
        { chance = 89, species = "MAGIKARP", level = 20 },
        { chance = 178, species = "KRABBY", level = 20 },
        { chance = 230, species = "KRABBY", level = 20 },
        { chance = 255, species = "CORSOLA", level = 20, timeGroup = 0,
          day = { species = "CORSOLA", level = 20 },
          nite = { species = "STARYU", level = 20 } },
      },
      super = {
        { chance = 102, species = "KRABBY", level = 40 },
        { chance = 178, species = "CORSOLA", level = 40, timeGroup = 1,
          day = { species = "CORSOLA", level = 40 },
          nite = { species = "STARYU", level = 40 } },
        { chance = 230, species = "KRABBY", level = 40 },
        { chance = 255, species = "KINGLER", level = 40 },
      },
    },
  },
}

-- Test Ocean group with TimeFishGroups (Shellder)
local OCEAN_ENCOUNTERS = {
  fishGroups = {
    FISHGROUP_OCEAN = {
      id = "FISHGROUP_OCEAN",
      chance = 255,
      old = {
        { chance = 179, species = "MAGIKARP", level = 10 },
        { chance = 217, species = "MAGIKARP", level = 10 },
        { chance = 255, species = "TENTACOOL", level = 10 },
      },
      good = {
        { chance = 89, species = "MAGIKARP", level = 20 },
        { chance = 178, species = "TENTACOOL", level = 20 },
        { chance = 230, species = "CHINCHOU", level = 20 },
        { chance = 255, species = "SHELLDER", level = 20, timeGroup = 2,
          day = { species = "SHELLDER", level = 20 },
          nite = { species = "SHELLDER", level = 20 } },
      },
      super = {
        { chance = 102, species = "CHINCHOU", level = 40 },
        { chance = 178, species = "SHELLDER", level = 40, timeGroup = 3,
          day = { species = "SHELLDER", level = 40 },
          nite = { species = "SHELLDER", level = 40 } },
        { chance = 230, species = "TENTACRUEL", level = 40 },
        { chance = 255, species = "LANTURN", level = 40 },
      },
    },
  },
}

-- ---- Direct Encounter.fishSlot tests ---------------------------------------
do
  -- Shore Good Rod at value 240 (slot 4) during DAY -> Corsola lv20
  local rollDay = Encounter.fishSlot(SHORE_ENCOUNTERS, "ROUTE_34", "GOOD_ROD",
    function(_n) return 240 end, { ROUTE_34 = { fishGroup = "FISHGROUP_SHORE" } }, nil, "DAY")
  check(rollDay ~= nil, "Shore Good Rod bites during DAY")
  eq(rollDay.species, "CORSOLA", "Shore Good Rod slot 4 is CORSOLA during DAY")
  eq(rollDay.level, 20, "Shore Good Rod slot 4 level is 20")

  -- Shore Good Rod at value 240 (slot 4) during NITE -> Staryu lv20
  local rollNite = Encounter.fishSlot(SHORE_ENCOUNTERS, "ROUTE_34", "GOOD_ROD",
    function(_n) return 240 end, { ROUTE_34 = { fishGroup = "FISHGROUP_SHORE" } }, nil, "NITE")
  check(rollNite ~= nil, "Shore Good Rod bites during NITE")
  eq(rollNite.species, "STARYU", "Shore Good Rod slot 4 is STARYU during NITE")
  eq(rollNite.level, 20, "Shore Good Rod slot 4 level is 20")

  -- Shore Super Rod at value 150 (slot 2) during DAY -> Corsola lv40
  local rollSuperDay = Encounter.fishSlot(SHORE_ENCOUNTERS, "ROUTE_34", "SUPER_ROD",
    function(_n) return 150 end, { ROUTE_34 = { fishGroup = "FISHGROUP_SHORE" } }, nil, "DAY")
  check(rollSuperDay ~= nil, "Shore Super Rod bites during DAY")
  eq(rollSuperDay.species, "CORSOLA", "Shore Super Rod slot 2 is CORSOLA during DAY")
  eq(rollSuperDay.level, 40, "Shore Super Rod slot 2 level is 40")

  -- Shore Super Rod at value 150 (slot 2) during NITE -> Staryu lv40
  local rollSuperNite = Encounter.fishSlot(SHORE_ENCOUNTERS, "ROUTE_34", "SUPER_ROD",
    function(_n) return 150 end, { ROUTE_34 = { fishGroup = "FISHGROUP_SHORE" } }, nil, "NITE")
  check(rollSuperNite ~= nil, "Shore Super Rod bites during NITE")
  eq(rollSuperNite.species, "STARYU", "Shore Super Rod slot 2 is STARYU during NITE")
  eq(rollSuperNite.level, 40, "Shore Super Rod slot 2 level is 40")

  -- Ocean Super Rod at value 150 (slot 2) during DAY/NITE -> Shellder lv40
  local rollOceanSuper = Encounter.fishSlot(OCEAN_ENCOUNTERS, "ROUTE_41", "SUPER_ROD",
    function(_n) return 150 end, { ROUTE_41 = { fishGroup = "FISHGROUP_OCEAN" } }, nil, "DAY")
  check(rollOceanSuper ~= nil, "Ocean Super Rod bites")
  eq(rollOceanSuper.species, "SHELLDER", "Ocean Super Rod slot 2 is SHELLDER")
  eq(rollOceanSuper.level, 40, "Ocean Super Rod slot 2 level is 40")
end

-- ---- World:rollFishing integration tests -----------------------------------
do
  -- World with Shore group in DAY time
  local worldDay, _ = fishWorld("ROUTE_34", "FISHGROUP_SHORE", "DAY")
  worldDay.encounters = SHORE_ENCOUNTERS

  -- Mock math.random / love.math.random to land on slot 2 of super rod (value ~150)
  love.math.random = function(n) return 151 end
  local outcome, wild = worldDay:rollFishing("SUPER_ROD")
  eq(outcome, "battle", "Super Rod triggers battle on Corsola slot")
  check(wild ~= nil, "Wild mon is created")
  eq(wild.species, "CORSOLA", "Wild mon is CORSOLA during DAY")
  eq(wild.level, 40, "Wild mon level is 40")

  -- World with Shore group in NITE time
  local worldNite, _ = fishWorld("ROUTE_34", "FISHGROUP_SHORE", "NITE")
  worldNite.encounters = SHORE_ENCOUNTERS
  local outcomeN, wildN = worldNite:rollFishing("SUPER_ROD")
  eq(outcomeN, "battle", "Super Rod triggers battle on Staryu slot")
  check(wildN ~= nil, "Wild mon is created")
  eq(wildN.species, "STARYU", "Wild mon is STARYU during NITE")
  eq(wildN.level, 40, "Wild mon level is 40")

  -- World with Ocean group -> Shellder
  local worldOcean, _ = fishWorld("ROUTE_41", "FISHGROUP_OCEAN", "DAY")
  worldOcean.encounters = OCEAN_ENCOUNTERS
  local outcomeO, wildO = worldOcean:rollFishing("SUPER_ROD")
  eq(outcomeO, "battle", "Super Rod triggers battle on Shellder slot")
  check(wildO ~= nil, "Wild mon is created")
  eq(wildO.species, "SHELLDER", "Wild mon is SHELLDER")
  eq(wildO.level, 40, "Wild mon level is 40")
end

-- ---- Real Gold cache integration tests (if present) ------------------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/.local/share/love/pokemon-love2d/gold"
  end
  local encChunk = loadfile(cache .. "/data/generated/encounters.lua")
  if not encChunk then
    check(true, "no gold cache: time fish groups (SKIP)")
  else
    local enc = encChunk() or {}
    local groups = enc.fishGroups or {}
    local shore = groups.FISHGROUP_SHORE
    check(shore ~= nil, "cache carries FISHGROUP_SHORE")
    if shore and shore.super then
      local slot2 = shore.super[2]
      check(slot2 ~= nil, "shore super rod has slot 2")
      if slot2 then
        eq(slot2.timeGroup, 1, "slot 2 timeGroup is 1")
        check(slot2.day ~= nil, "slot 2 has day entry")
        check(slot2.nite ~= nil, "slot 2 has nite entry")
        if slot2.day then eq(slot2.day.species, "CORSOLA", "day is CORSOLA") end
        if slot2.nite then eq(slot2.nite.species, "STARYU", "nite is STARYU") end
      end
    end

    local ocean = groups.FISHGROUP_OCEAN
    check(ocean ~= nil, "cache carries FISHGROUP_OCEAN")
    if ocean and ocean.super then
      local slot2 = ocean.super[2]
      check(slot2 ~= nil, "ocean super rod has slot 2")
      if slot2 then
        eq(slot2.timeGroup, 3, "slot 2 timeGroup is 3")
        check(slot2.day ~= nil, "slot 2 has day entry")
        if slot2.day then eq(slot2.day.species, "SHELLDER", "day is SHELLDER") end
      end
    end
  end
end
-- ---- Animation & Bobber State Machine tests --------------------------------
do
  local world, _ = fishWorld("ROUTE_34", "FISHGROUP_SHORE", "DAY")
  world.encounters = SHORE_ENCOUNTERS
  world.player.cellX = 5
  world.player.cellY = 5
  world.player.facing = "left"

  local wildMon = { species = "CORSOLA", level = 40 }
  world:beginFishing("battle", wildMon)

  check(world.fishing ~= nil, "Fishing state is initialized")
  eq(world.fishing.phase, "cast", "Initial phase is cast")
  eq(world.fishing.timer, 40, "Cast timer is 40 frames")
  check(world.fishing.bobber ~= nil, "Bobber is created")
  eq(world.fishing.bobber.cellX, 4, "Bobber target X is 4 (one cell left)")
  eq(world.fishing.bobber.cellY, 5, "Bobber target Y is 5")
  eq(world.fishing.bobber.px, 64, "Bobber px is 64")
  eq(world.fishing.bobber.py, 80, "Bobber py is 80")
  eq(world.player.fishing, true, "Player has fishing flag")

  -- Step through cast phase (40 frames + transition tick)
  for f = 1, 40 + 1 do
    world:updateFishing()
  end
  eq(world.fishing.phase, "bite", "Transitions to bite phase on battle outcome")
  eq(world.fishing.timer, 40, "Bite timer is 40 frames")

  -- Step through bite phase and check 1px alternating offset
  local seenOdd, seenEven = false, false
  for f = 1, 40 do
    world:updateFishing()
    if world.player.spriteYOffset == 1 then seenOdd = true end
    if world.player.spriteYOffset == 0 then seenEven = true end
  end
  check(seenOdd and seenEven, "Player sprite Y offset alternates during bite phase")
  -- Transition on next tick triggers text/battle and clears fishing state
  world:updateFishing()
  eq(world.fishing, nil, "Fishing state is cleared after bite completion")
  eq(world.player.fishing, nil, "Player fishing flag is cleared after bite completion")
end

S.finish()
