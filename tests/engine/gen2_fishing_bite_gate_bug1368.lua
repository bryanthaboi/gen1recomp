-- The fishgroup bite roll, missing entirely before #1368: .Fish rolls the
-- group's OWN chance byte before the rod's cumulative list even runs
-- (engine/events/fish.asm:24-30), so every rod bites at whatever that byte
-- says (vanilla Gold is 50 percent + 1 for every group, not 2/3 or 1/2 by
-- rod).  A cache built before the extractor carried the byte has no
-- `chance` field on the group row at all and must keep fishing unconditionally.
--   luajit tests/engine/gen2_fishing_bite_gate_bug1368.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local World = require("src.world.gen2.World")

local DATA = {
  pokemon = {
    MAGIKARP = {
      name = "MAGIKARP", types = { "WATER", "WATER" },
      baseStats = { hp = 20, attack = 10, defense = 55, speed = 80,
        specialAttack = 15, specialDefense = 20 },
      levelMoves = {},
    },
  },
}

local COLL_FLOOR, COLL_WATER = 0x00, 0x29

local function fakeMap(waterCell)
  return {
    id = "TEST_MAP",
    def = { fishGroup = "FISHGROUP_POND" },
    cellCollision = function(_, x, y)
      return (x == waterCell[1] and y == waterCell[2])
        and COLL_WATER or COLL_FLOOR
    end,
    inBounds = function() return true end,
  }
end

-- Rod lists that always hand back a species once a bite happens, so only the
-- group gate (or its absence) decides the outcome below.
local function fishGroups(chance)
  return {
    FISHGROUP_POND = {
      chance = chance,
      old = { { chance = 256, species = "MAGIKARP", level = 10 } },
      good = { { chance = 256, species = "MAGIKARP", level = 20 } },
      super = { { chance = 256, species = "MAGIKARP", level = 40 } },
    },
  }
end

local function fakeWorld(chance)
  local game = { data = DATA, save = { party = {} } }
  local world = World.new(game)
  world.map = fakeMap({ 5, 4 })
  world.maps = { TEST_MAP = world.map.def }
  world.encounters = { fishGroups = fishGroups(chance) }
  world.player = { cellX = 5, cellY = 5, facing = "up" }
  return world
end

-- ---- chance 0: the group byte fails Random every time, always a nibble ---
-- engine/events/fish.asm:24-30
do
  local world = fakeWorld(0)
  for rod = 1, 3 do
    local outcome = world:rollFishing(({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" })[rod])
    eq(outcome, "nibble",
      "chance 0 nibbles on " .. ({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" })[rod])
  end
end

-- ---- chance 256: the group byte always passes, every rod finds the mon ---
do
  local world = fakeWorld(256)
  for _, rod in ipairs({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }) do
    local outcome, wild = world:rollFishing(rod)
    eq(outcome, "battle", "chance 256 always bites on " .. rod)
    check(wild and wild.species == "MAGIKARP",
      "and the rod's own list still resolves a species")
  end
end

-- ---- no chance field at all: an old cache keeps fishing unconditionally --
do
  local world = fakeWorld(nil)
  local outcome = world:rollFishing("OLD_ROD")
  eq(outcome, "battle",
    "a cache with no group chance byte is not gated at all")
end

T.finish("gen2 fishing bite gate bug1368")
