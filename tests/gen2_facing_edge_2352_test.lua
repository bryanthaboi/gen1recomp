-- home/map.asm:1511 GetMovementPermissions
-- engine/events/overworld.asm:1444 FishFunction.TryFish
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 facing edge 2352")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")
local WorldAPI = require("src.world.gen2.WorldAPI")

local COLL_FLOOR, COLL_WATER = 0x00, 0x29

local function only(species)
  local list = { { chance = 256, species = species, level = 10 } }
  return { old = list, good = list, super = list }
end

local DATA = {
  items = { OLD_ROD = { name = "OLD ROD" } },
  moves = { SPLASH = { name = "SPLASH", pp = 40 } },
  pokemon = {
    MAGIKARP = {
      name = "MAGIKARP", types = { "WATER", "WATER" },
      baseStats = { hp = 20, attack = 10, defense = 55, speed = 80,
        specialAttack = 15, specialDefense = 20 },
      levelMoves = { { level = 1, move = "SPLASH" } },
    },
  },
}

local function buildWorld(maps, tilesets, mapId, encounters)
  local game = {
    data = DATA,
    save = { player = { name = "GOLD" }, party = {},
      inventory = { OLD_ROD = 1 } },
  }
  local world = World.new(game)
  game.world = world
  world.maps = maps
  world.tilesets = tilesets
  world.map = Map.new(maps[mapId], tilesets[maps[mapId].tileset])
  world.encounters = encounters
  world.player = {
    cellX = 0, cellY = 0, px = 0, py = 0, facing = "down", moving = false,
    turnArmed = true, update = function() return false end,
    setSprite = function() end,
  }
  world.pollTimeOfDay = function() end
  world.vm = { running = function() return false end, update = function() end }
  return world, game
end

local function place(world, x, y, facing)
  world.player.cellX, world.player.cellY = x, y
  world.player.facing = facing
end

local function hasAction(game, id)
  local rows = WorldAPI.new(game, "test"):availableFieldActions()
  for _, row in ipairs(rows) do
    if row.id == id then return true end
  end
  return false
end

do
  local tileset = { collision = {
    { COLL_FLOOR, COLL_FLOOR, COLL_FLOOR, COLL_FLOOR },
    { COLL_FLOOR, COLL_FLOOR, COLL_FLOOR, COLL_FLOOR },
    { COLL_WATER, COLL_WATER, COLL_WATER, COLL_WATER },
  } }
  local maps = {
    TOWN = { id = "TOWN", width = 2, height = 2, blocks = { 1, 1, 1, 1 },
      borderBlock = 2, tileset = "T", environment = "TOWN",
      fishGroup = "FISHGROUP_SHORE", bgEvents = {}, objects = {},
      connections = {
        south = { mapId = "ROUTE", offset = 0 },
        north = { mapId = "ROUTE", offset = 1 },
      } },
    ROUTE = { id = "ROUTE", width = 1, height = 2, blocks = { 1, 1 },
      borderBlock = 2, tileset = "T", environment = "ROUTE",
      bgEvents = {}, objects = {}, connections = {} },
  }
  local world, game = buildWorld(maps, { T = tileset }, "TOWN",
    { fishGroups = { FISHGROUP_SHORE = only("MAGIKARP") } })

  place(world, 1, 3, "down")
  eq(world.map:cellCollision(1, 4), COLL_WATER,
    "the unpadded grid still reads the border block below the south mouth")
  eq(world:fieldContext().facingColl, COLL_FLOOR,
    "facing south into the connection strip reads the neighbour's floor")
  eq(world:rollFishing("OLD_ROD"), "nowhere",
    "and the rod refuses there")
  check(not hasAction(game, "fish"),
    "and no FISH shortcut is offered at the mouth")

  place(world, 2, 0, "up")
  eq(world:fieldContext().facingColl, COLL_FLOOR,
    "facing north into an offset strip reads the neighbour's floor")
  eq(world:fieldContext().upColl, COLL_FLOOR,
    "and wTileUp reads it too")
  eq(world:rollFishing("OLD_ROD"), "nowhere", "and the rod refuses there too")

  place(world, 3, 3, "down")
  eq(world:fieldContext().facingColl, COLL_WATER,
    "past the end of the strip the border block is still water")
  check(world:rollFishing("OLD_ROD") ~= "nowhere",
    "so the rod still casts there")
  check(hasAction(game, "fish"), "and the FISH shortcut is offered")

  place(world, 0, 1, "left")
  eq(world:fieldContext().facingColl, COLL_WATER,
    "an edge with no connection keeps the border block")
  check(world:rollFishing("OLD_ROD") ~= "nowhere",
    "and fishing into it still casts")
end

do
  local home = os.getenv("HOME") or ""
  local roots = {
    os.getenv("CRYSTAL_CACHE") or "", os.getenv("GOLD_CACHE") or "",
    home .. "/Library/Application Support/LOVE/crystal-dev/crystal",
    home .. "/Library/Application Support/LOVE/bsa2237c/crystal",
    home .. "/Library/Application Support/LOVE/gold-dev/gold",
    home .. "/Library/Application Support/LOVE/bsa2237g/gold",
  }
  local maps, tilesets
  for _, root in ipairs(roots) do
    if root then
      local m = loadfile(root .. "/data/generated/maps.lua")
      local t = loadfile(root .. "/data/generated/tilesets.lua")
      if m and t then
        maps, tilesets = m(), t()
        break
      end
    end
  end
  if not (maps and maps.GOLDENROD_CITY) then
    check(true, "no gen2 cache: Goldenrod mouths (SKIP)")
  else
    local world = buildWorld(maps, tilesets, "GOLDENROD_CITY",
      { fishGroups = { FISHGROUP_SHORE = only("MAGIKARP") } })
    for x = 18, 21 do
      place(world, x, 35, "down")
      check(world:fieldContext().facingColl ~= COLL_WATER,
        "Goldenrod south road x=" .. x .. " faces Route 34, not water")
      eq(world:rollFishing("OLD_ROD"), "nowhere",
        "and the rod refuses at x=" .. x)
    end
    for x = 24, 27 do
      place(world, x, 0, "up")
      check(world:fieldContext().facingColl ~= COLL_WATER,
        "Goldenrod north road x=" .. x .. " faces Route 35, not water")
      eq(world:rollFishing("OLD_ROD"), "nowhere",
        "and the rod refuses at x=" .. x)
    end
    place(world, 0, 10, "left")
    eq(world:fieldContext().facingColl, COLL_WATER,
      "Goldenrod's west edge keeps its $35 water border")
  end
end

S.finish()
