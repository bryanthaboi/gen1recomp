-- Current tiles: DoPlayerMovement's .CheckTile, HI_NYBBLE_CURRENT arm.
--
--   luajit tests/gen2_currents_test.lua
--
-- $30-$3f are CURRENT tiles (engine/overworld/player_movement.asm): the low two
-- bits index .water_table, so COLL_WATERFALL $33 and COLL_CURRENT_DOWN $3b both
-- force DOWN.  The arm runs ABOVE .CheckTurning and .TryStep and returns
-- PLAYERMOVEMENT_CONTINUE, so it overrides the d-pad outright rather than being
-- refused by it.
--
-- The port mapped the whole $3x block to plain WATER and had no current arm at
-- all, which cost two things: the plunge down a waterfall needed the player to
-- hold DOWN (and never animated as a plunge), and a surfing player could walk
-- UP a waterfall column with the d-pad -- silently bypassing the HM07 +
-- ENGINE_RISINGBADGE gate at Tohjo Falls and Whirl Islands.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 currents")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

local Permissions = require("src.world.gen2.Permissions")
local World = require("src.world.gen2.World")
local Player = require("src.world.gen2.Player")
local FieldMoves = require("src.world.gen2.FieldMoves")

-- ---- the table -------------------------------------------------------------
--
-- `and $f0 / cp HI_NYBBLE_CURRENT` then `maskbits NUM_DIRECTIONS`.
eq(Permissions.currentDirection(0x30), "right", "COLL_WATERFALL_RIGHT")
eq(Permissions.currentDirection(0x31), "left", "COLL_WATERFALL_LEFT")
eq(Permissions.currentDirection(0x32), "up", "COLL_WATERFALL_UP")
eq(Permissions.currentDirection(0x33), "down", "COLL_WATERFALL is DOWN")
eq(Permissions.currentDirection(0x38), "right", "COLL_CURRENT_RIGHT")
eq(Permissions.currentDirection(0x39), "left", "COLL_CURRENT_LEFT")
eq(Permissions.currentDirection(0x3a), "up", "COLL_CURRENT_UP")
eq(Permissions.currentDirection(0x3b), "down", "COLL_CURRENT_DOWN is DOWN too")
-- The nybble is what is tested, not the four named constants, so the garbage
-- rows in between behave the same way the cart's would.
eq(Permissions.currentDirection(0x36), "up", "COLL_36 rides the same nybble")
eq(Permissions.currentDirection(0x29), nil, "plain COLL_WATER forces nothing")
eq(Permissions.currentDirection(0x23), nil, "and neither does ice")
eq(Permissions.currentDirection(0x24), nil,
  "COLL_WHIRLPOOL is tested above the nybble and takes FORCE_TURN instead")
eq(Permissions.currentDirection(nil), nil, "no tile, no current")
check(Permissions.isWater(0x33), "a waterfall tile is still WATER to surf on")
check(Permissions.isWaterfall(0x33) and Permissions.isWaterfall(0x3b),
  "CheckWaterfallTile still pairs the two the climb loops on")

-- ---- the step --------------------------------------------------------------
--
-- A column of $33 down the middle of a pond: (5,4) is the top of the fall,
-- (5,5) and (5,6) below it, plain water everywhere else.
local COLL_WATER, COLL_WATERFALL = 0x29, 0x33
local FALLS = {
  [4 * 100 + 5] = COLL_WATERFALL,
  [5 * 100 + 5] = COLL_WATERFALL,
  [6 * 100 + 5] = COLL_WATERFALL,
}

local function currentWorld(px, py)
  local game = {
    data = { items = {}, moves = {}, pokemon = {} },
    save = { player = { name = "GOLD", badges = {} }, party = {},
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  local cells = {}
  for y = 0, 9 do
    for x = 0, 9 do cells[y * 100 + x] = COLL_WATER end
  end
  for key, value in pairs(FALLS) do cells[key] = value end
  local map
  map = {
    id = "TOHJO_FALLS",
    width = 5, height = 5,
    def = { objects = {}, bgEvents = {}, environment = "CAVE",
      tileset = "TILESET_CAVE", width = 5, height = 5 },
    cellCollision = function(_, x, y) return cells[y * 100 + x] or COLL_WATER end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 10 and y < 10
    end,
    isWalkable = function(_, x, y)
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
  }
  world.map = map
  world.maps = { TOHJO_FALLS = map.def }
  world.player = Player.new(px, py, "up")
  world.entities = { world.player }
  world.npcs = {}
  world.playerState = FieldMoves.PLAYER_SURF
  world.encounters = {}
  world.pollTimeOfDay = function() end
  -- Nothing here draws, and nothing here is about the wild roll.
  world.noWildEncounters = true
  world.updatePeople = function() end
  return world, game
end

-- World:pollInput is the caller's job (Game2 does it once a fixed step);
-- `held` is the d-pad the arm is supposed to be overriding.
local function runSteps(world, frames, held)
  for _ = 1, frames do
    world.heldDir = held
    world:step()
  end
end

-- A surfing player standing on the top of the fall is carried DOWN with no
-- input at all: `.CheckTile` picks the direction before .CheckTurning ever
-- looks at the d-pad.
do
  local world = currentWorld(5, 4)
  eq(world.heldDir, nil, "no direction is held")
  runSteps(world, 64)
  eq(world.player.cellX, 5, "the plunge stays in the column")
  check(world.player.cellY > 4,
    "and the current carried the player down it with no press")
  check(world.player.cellY >= 7,
    "past the last waterfall tile and out onto open water")
end

-- The same tile refuses to be climbed: holding UP on a current tile is not a
-- bump, it is a DOWN step.
do
  local world = currentWorld(5, 5)
  runSteps(world, 48, "up")
  check(world.player.cellY > 5,
    "holding UP inside the column still moves the player DOWN")
  eq(world.player.cellX, 5, "and never off the column")
end

-- Which is what the HM07 gate at Tohjo Falls and Whirl Islands rests on: a
-- surfing player below the fall can step onto its bottom tile and is thrown
-- straight back off it, so the top is unreachable however long UP is held.
do
  local world = currentWorld(5, 8)
  local highest = world.player.cellY
  for _ = 1, 300 do
    world.heldDir = "up"
    world:step()
    if world.player.cellY < highest then highest = world.player.cellY end
  end
  check(highest >= 6,
    "the d-pad never carries a surfing player above the fall's bottom tile")
  check(world.player.cellY >= 6, "and it ends below it too")
end

-- Off the column it is an ordinary surf step again, so the current is a
-- property of the TILE and not a mode the player gets stuck in.
do
  local world = currentWorld(3, 6)
  runSteps(world, 48, "up")
  check(world.player.cellY < 6, "plain water still answers the d-pad")
end

-- The scripted climb is untouched: it moves the player with Player:scriptStep
-- under World:busy, which returns above the input block this arm lives in.
do
  local world = currentWorld(5, 7)
  world.fieldMove = { phase = "waterfall" }
  local before = world.player.cellY
  world:waterfallStep()
  runSteps(world, 20)
  check(world.player.cellY < before,
    "World:waterfallStep still climbs while the field move owns the world")
end

S.finish()
