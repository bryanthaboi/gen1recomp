-- The fishing half of a swarm (engine/events/fish.asm).
--
--   luajit tests/gen2_fishing_swarm_test.lua   (ROM-free; the cache facts SKIP
--                                               without a gold cache)
--
-- Fish calls GetFishGroupIndex before it indexes FishGroups, and that routine
-- is the ONLY reader of wFishingSwarmFlag: a map whose MAP_FISHGROUP is
-- FISHGROUP_QWILFISH rolls FISHGROUP_QWILFISH_SWARM instead while the flag says
-- FISHSWARM_QWILFISH, and the same for Remoraid.  Nothing about the map header
-- changes, which is why the phone call that starts a swarm is one setval and
-- one special.
--
-- The port wired swarms into the grass and water tables (_SwarmWildmonCheck,
-- src/core/gen2/Roamers.lua Swarm.tables) and left fishing reading the header
-- alone, so `special ActivateFishingSwarm` had no reader at all: the Route 32
-- Qwilfish swarm and the Route 44 Remoraid swarm never reached a rod.
--
-- Everything below goes through World:rollFishing, which is what World:useRod
-- and World:tryFishing both call, rather than through Encounter directly.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 fishing swarm")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local Encounter = require("src.battle.gen2.Encounter")
local Roamers = require("src.core.gen2.Roamers")
local Permissions = require("src.world.gen2.Permissions")

local COLL_FLOOR, COLL_WATER = 0x00, 0x29
local MAP_W, MAP_H = 10, 10

-- constants/script_constants.asm.
eq(Encounter.FISHSWARM_NONE, 0, "FISHSWARM_NONE is 0")
eq(Encounter.FISHSWARM_QWILFISH, 1, "FISHSWARM_QWILFISH is 1")
eq(Encounter.FISHSWARM_REMORAID, 2, "FISHSWARM_REMORAID is 2")
eq(Roamers.Swarm.FISH_QWILFISH, Encounter.FISHSWARM_QWILFISH,
  "and the save-side names agree with them")
eq(Roamers.Swarm.FISH_REMORAID, Encounter.FISHSWARM_REMORAID, "for both")

-- One always-hit row per list, so the ROLL is never what these assert: whatever
-- comes back names the group it was rolled from.
local function only(species)
  local list = { { chance = 256, species = species, level = 10 } }
  return { old = list, good = list, super = list }
end

local ENCOUNTERS = {
  fishGroups = {
    FISHGROUP_POND = only("MAGIKARP"),
    FISHGROUP_QWILFISH = only("MAGIKARP"),
    FISHGROUP_QWILFISH_SWARM = only("QWILFISH"),
    FISHGROUP_QWILFISH_NO_SWARM = only("MAGIKARP"),
    FISHGROUP_REMORAID = only("GOLDEEN"),
    FISHGROUP_REMORAID_SWARM = only("REMORAID"),
  },
}

local function mon(name)
  return {
    name = name, types = { "WATER", "WATER" },
    baseStats = { hp = 20, attack = 10, defense = 55, speed = 80,
      specialAttack = 15, specialDefense = 20 },
    levelMoves = { { level = 1, move = "SPLASH" } },
  }
end

local DATA = {
  items = {},
  moves = { SPLASH = { name = "SPLASH", pp = 40 } },
  pokemon = {
    MAGIKARP = mon("MAGIKARP"), QWILFISH = mon("QWILFISH"),
    GOLDEEN = mon("GOLDEEN"), REMORAID = mon("REMORAID"),
  },
}

-- A world with one water tile at (5,4) and the player facing it from (5,5),
-- which is the only geometry .TryFish reads.
local function fishWorld(mapId, fishGroup)
  local cells = { [4 * 100 + 5] = COLL_WATER }
  local map
  map = {
    id = mapId,
    width = MAP_W, height = MAP_H,
    def = { bgEvents = {}, objects = {}, width = MAP_W, height = MAP_H,
      environment = "ROUTE", fishGroup = fishGroup },
    cellCollision = function(_, x, y) return cells[y * 100 + x] or COLL_FLOOR end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < MAP_W * 2 and y < MAP_H * 2
    end,
    isWalkable = function(_, x, y)
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
  }
  local game = {
    data = DATA,
    save = { player = { name = "GOLD" }, party = {}, inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.map = map
  world.maps = { [mapId] = map.def }
  world.encounters = ENCOUNTERS
  world.player = {
    cellX = 5, cellY = 5, px = 80, py = 80, facing = "up", moving = false,
    turnArmed = true, update = function() return false end,
    setSprite = function() end,
  }
  world.pollTimeOfDay = function() end
  world.vm = { running = function() return false end, update = function() end }
  return world, game
end

local function hooked(world, rod)
  local outcome, wild = world:rollFishing(rod or "OLD_ROD")
  return outcome, wild and wild.species
end

-- ---- ROUTE_32, the Qwilfish swarm -----------------------------------------
do
  local world, game = fishWorld("ROUTE_32", "FISHGROUP_QWILFISH")
  local outcome, species = hooked(world)
  eq(outcome, "battle", "the rod hooks something off the map's own group")
  eq(species, "MAGIKARP", "which is FISHGROUP_QWILFISH with no swarm running")

  -- `special ActivateFishingSwarm` with wScriptVar = FISHSWARM_QWILFISH: the
  -- save write the port already had, and the ONLY thing that changes here.
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_QWILFISH)
  outcome, species = hooked(world)
  eq(outcome, "battle", "the rod still hooks something during the swarm")
  eq(species, "QWILFISH", "and it is FISHGROUP_QWILFISH_SWARM's list")
  for _, rod in ipairs({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }) do
    local _, got = hooked(world, rod)
    eq(got, "QWILFISH", "the swap is per GROUP, so it covers the " .. rod)
  end

  -- The Remoraid swarm is a different flag value and must not touch this map.
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_REMORAID)
  local _, other = hooked(world)
  eq(other, "MAGIKARP", "a Remoraid swarm leaves Route 32 alone")

  -- CheckSwarmFlag is what ends it: the daily reset drops DAILYFLAGS1_SWARM and
  -- the next poll clears wFishingSwarmFlag with it.
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_QWILFISH)
  game.save.dailyFlags.swarm = false
  eq(Roamers.Swarm.check(game.save), 1, "CheckSwarmFlag answers 1 once it is down")
  local _, ended = hooked(world)
  eq(ended, "MAGIKARP", "and the rod is back on the map's own group")
end

-- ---- ROUTE_44, the Remoraid swarm -----------------------------------------
do
  local world, game = fishWorld("ROUTE_44", "FISHGROUP_REMORAID")
  local _, species = hooked(world)
  eq(species, "GOLDEEN", "Route 44 fishes FISHGROUP_REMORAID by default")
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_REMORAID)
  local _, swarmed = hooked(world)
  eq(swarmed, "REMORAID", "and FISHGROUP_REMORAID_SWARM while the swarm runs")
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_QWILFISH)
  local _, wrong = hooked(world)
  eq(wrong, "GOLDEEN", "a Qwilfish swarm leaves Route 44 alone")
end

-- ---- the groups the substitution must NOT touch ---------------------------
do
  -- FISHGROUP_QWILFISH_NO_SWARM is a map header value of its own, not a state
  -- of FISHGROUP_QWILFISH: GetFishGroupIndex compares against FISHGROUP_QWILFISH
  -- and FISHGROUP_REMORAID and nothing else.
  local world, game = fishWorld("ROUTE_33", "FISHGROUP_QWILFISH_NO_SWARM")
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_QWILFISH)
  local _, species = hooked(world)
  eq(species, "MAGIKARP",
    "FISHGROUP_QWILFISH_NO_SWARM never becomes a swarm group")

  local pond, pondGame = fishWorld("ROUTE_34", "FISHGROUP_POND")
  Roamers.Swarm.setFishing(pondGame.save, Roamers.Swarm.FISH_QWILFISH)
  local _, caught = hooked(pond)
  eq(caught, "MAGIKARP", "and an ordinary pond is untouched by either swarm")
end

-- ---- a cache with no swarm rows -------------------------------------------
do
  local world, game = fishWorld("ROUTE_32", "FISHGROUP_QWILFISH")
  world.encounters = { fishGroups = { FISHGROUP_QWILFISH = only("MAGIKARP") } }
  Roamers.Swarm.setFishing(game.save, Roamers.Swarm.FISH_QWILFISH)
  check(not pcall(hooked, world),
    "a cache with no swarm group is an error, not the map's own group")
end

-- ---- the group names in the real cache ------------------------------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local encChunk = loadfile(cache .. "/data/generated/encounters.lua")
  local mapChunk = loadfile(cache .. "/data/generated/maps.lua")
  if not (encChunk and mapChunk) then
    check(true, "no gold cache: fish group names (SKIP)")
  else
    local groups = (encChunk() or {}).fishGroups or {}
    local maps = mapChunk()
    for _, name in ipairs({ "FISHGROUP_QWILFISH", "FISHGROUP_QWILFISH_SWARM",
        "FISHGROUP_REMORAID", "FISHGROUP_REMORAID_SWARM" }) do
      check(groups[name] ~= nil, "the cache carries " .. name)
    end
    eq((maps.ROUTE_32 or {}).fishGroup, "FISHGROUP_QWILFISH",
      "ROUTE_32's header names the Qwilfish group")
    eq((maps.ROUTE_44 or {}).fishGroup, "FISHGROUP_REMORAID",
      "and ROUTE_44's the Remoraid one")
    -- The substitution is resolved against the cache's own group table.
    eq(Encounter.fishGroupFor({ fishGroups = groups }, "FISHGROUP_QWILFISH",
      Encounter.FISHSWARM_QWILFISH), "FISHGROUP_QWILFISH_SWARM",
      "so the real Route 32 header swaps")
    eq(Encounter.fishGroupFor({ fishGroups = groups }, "FISHGROUP_REMORAID",
      Encounter.FISHSWARM_REMORAID), "FISHGROUP_REMORAID_SWARM",
      "and so does the real Route 44 one")
  end
end

S.finish()
