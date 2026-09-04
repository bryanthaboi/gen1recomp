-- ESCAPE ROPE and DIG have to come out of the door that was walked in, not the
-- last door that happened to bank a triple.
--
--   GOLD_CACHE=".../gold" luajit tests/gen2_dig_warp_test.lua
--
-- home/map.asm EnterMapWarp calls `.SaveDigWarp` on EVERY warp: if the map
-- being left is outdoor (CheckOutdoorMap -- ROUTE or TOWN) and the one being
-- entered is indoor (CheckIndoorMap -- INDOOR, CAVE, DUNGEON or GATE), the
-- warp stepped on and the map left go into wDigWarpNumber / wDigMapGroup /
-- wDigMapNumber, and EscapeRopeOrDig's `.CheckCanDig` reads them straight back.
-- MOUNT_MOON_SQUARE and TIN_TOWER_ROOF are the routine's own exceptions:
-- outdoor maps sitting inside indoor ones, which the rope must never land on.
--
-- The port had only the -1 writer (the POKECENTER_2F / elevator contract in
-- tests/gen2_pokecenter_stairs_test.lua), so a cave entered by an ordinary
-- door banked nothing and the rope paid out to whatever was banked last.  DARK
-- CAVE has a Route 31 mouth and a Route 46 mouth, which is exactly the case
-- that tells the two apart.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 dig warp")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local probe = io.open(cache .. "/data/generated/maps.lua", "r")
if not probe then
  check(true, "gold cache absent (SKIP)")
  S.finish()
  return
end
probe:close()

local function loadLua(rel) return assert(loadfile(cache .. "/" .. rel))() end
local maps = loadLua("data/generated/maps.lua")
local tilesets = loadLua("data/generated/tilesets.lua")

-- The map data the whole rule reads: the environments the two Check routines
-- compare against, straight out of the extracted headers.
eq(maps.ROUTE_31.environment, "ROUTE", "Route 31 is an outdoor map")
eq(maps.DARK_CAVE_VIOLET_ENTRANCE.environment, "CAVE",
  "and DARK CAVE's Violet side is a cave")
eq(maps.ROUTE_31.warps[3].destMap, "DARK_CAVE_VIOLET_ENTRANCE",
  "Route 31's third warp is the cave mouth")
eq(maps.ROUTE_46.warps[3].destMap, "DARK_CAVE_VIOLET_ENTRANCE",
  "and Route 46's third warp is the other one")

-- A World over the real defs.  setMap is recorded rather than run (baking a
-- map image needs a graphics device); everything around it -- takeWarp,
-- recordWarpBackup, escapeRopeTarget, runEscapeWarp -- is the shipped code.
local function world(mapId)
  local game = { data = { audio = { sfxOrder = {} } }, save = { player = {} } }
  local w = World.new(game)
  w.maps, w.tilesets = maps, tilesets
  w.map = Map.new(maps[mapId], tilesets[maps[mapId].tileset])
  w.player = { cellX = 0, cellY = 0, facing = "up", moving = false }
  w.loaded = nil
  w.setMap = function(self, id, cx, cy, facing)
    self.loaded = { id = id, x = cx, y = cy, facing = facing }
    -- The stub stands in for the load, so the map the world believes it is
    -- standing on has to move with it or the next take reads the old warps.
    self.map = Map.new(maps[id], tilesets[maps[id].tileset])
    return true
  end
  return w
end

local function pump(w)
  for _ = 1, 256 do
    if not (w.mapSetup or w.moveState) then return end
    if w.mapSetup then w:updateMapSetup() else w:updateMovement() end
  end
end

local function walk(w, mapId, warpIndex)
  local taken = w:takeWarp(maps[mapId].warps[warpIndex])
  pump(w)
  return taken
end

-- ---- the door actually used ----------------------------------------------
do
  local w = world("ROUTE_31")
  check(walk(w, "ROUTE_31", 3), "into DARK CAVE off Route 31")
  eq(w.loaded and w.loaded.id, "DARK_CAVE_VIOLET_ENTRANCE", "landing in the cave")
  check(w.backupWarp ~= nil, "an outdoor-to-cave door banks the dig triple")
  eq(w.backupWarp.map, "ROUTE_31", "naming the route outside")
  eq(w.backupWarp.warp, 3, "and the mouth stepped on")

  -- EscapeRopeOrDig's .CheckCanDig, then the warp its script runs.
  local destMapId, destWarp = w:escapeRopeTarget()
  eq(destMapId, "ROUTE_31", "the rope resolves back to Route 31")
  check(w:runEscapeWarp(destMapId, destWarp), "and the rope warp runs")
  pump(w)
  eq(w.loaded.id, "ROUTE_31", "landing on Route 31")
  eq(w.loaded.x, maps.ROUTE_31.warps[3].x, "on the cave mouth's own x")
  eq(w.loaded.y, maps.ROUTE_31.warps[3].y, "and y")
end

-- The same cave, entered from the other side: the triple is re-banked on every
-- qualifying door, so the rope follows the player rather than the map.
do
  local w = world("ROUTE_46")
  check(walk(w, "ROUTE_46", 3), "into DARK CAVE off Route 46 instead")
  eq(w.backupWarp.map, "ROUTE_46", "the banked map is Route 46 now")
  eq(w.backupWarp.warp, 3, "with Route 46's own mouth")
  local destMapId, destWarp = w:escapeRopeTarget()
  eq(destMapId, "ROUTE_46", "so the rope comes out on Route 46")
  eq(destWarp.x, maps.ROUTE_46.warps[3].x, "at that mouth's x")
  eq(destWarp.y, maps.ROUTE_46.warps[3].y, "and y")
end

-- ---- what CheckOutdoorMap / CheckIndoorMap refuse -------------------------
do
  -- Walking OUT of the cave is indoor-to-outdoor: `.SaveDigWarp` returns at
  -- its first test and the banked triple is left standing.
  local w = world("ROUTE_31")
  check(walk(w, "ROUTE_31", 3), "in through the Route 31 mouth")
  local banked = w.backupWarp
  check(walk(w, "DARK_CAVE_VIOLET_ENTRANCE", 1), "and back out again")
  eq(w.loaded.id, "ROUTE_31", "out on Route 31")
  eq(w.backupWarp, banked, "leaving the dig triple exactly as it was")

  -- A GATE counts as indoor, so a route gate banks like any other door.
  check(walk(w, "ROUTE_31", 1), "into the Violet gate")
  eq(w.backupWarp.map, "ROUTE_31", "a GATE is CheckIndoorMap's fourth arm")
  eq(w.backupWarp.warp, 1, "banking the gate door")

  -- Gate to town is outdoor-bound: nothing banks.
  local townBanked = w.backupWarp
  check(walk(w, "ROUTE_31_VIOLET_GATE", 1), "out of the gate into Violet")
  eq(w.loaded.id, "VIOLET_CITY", "into Violet City")
  eq(w.backupWarp, townBanked, "with the triple untouched")

  -- Town to building is the ordinary case, and it banks.
  check(walk(w, "VIOLET_CITY", 5), "into the Violet Pokemon Center")
  eq(w.backupWarp.map, "VIOLET_CITY", "banking the town outside")
  eq(w.backupWarp.warp, 5, "and the centre's door")
end

-- ---- the two maps the routine excludes ------------------------------------
do
  local w = world("ROUTE_31")
  check(walk(w, "ROUTE_31", 3), "bank a real triple first")
  local banked = w.backupWarp
  -- MOUNT_MOON_SQUARE is a ROUTE map inside MOUNT_MOON, so the door out of it
  -- passes both environment tests and is refused by name anyway.
  eq(maps.MOUNT_MOON_SQUARE.environment, "ROUTE",
    "MOUNT MOON SQUARE really is an outdoor map")
  eq(maps.MOUNT_MOON.environment, "CAVE", "inside a cave")
  w.map = Map.new(maps.MOUNT_MOON_SQUARE,
    tilesets[maps.MOUNT_MOON_SQUARE.tileset])
  check(walk(w, "MOUNT_MOON_SQUARE", 1), "step off the square into the cave")
  eq(w.loaded.id, "MOUNT_MOON", "into MOUNT MOON")
  eq(w.backupWarp, banked,
    "the square is excluded by name: no dig warp is banked there")

  -- TIN_TOWER_ROOF is the other one, and it is a ROUTE map inside a DUNGEON.
  eq(maps.TIN_TOWER_ROOF.environment, "ROUTE", "so is the TIN TOWER roof")
  eq(maps.TIN_TOWER_9F.environment, "DUNGEON", "over a dungeon floor")
  w.map = Map.new(maps.TIN_TOWER_ROOF, tilesets[maps.TIN_TOWER_ROOF.tileset])
  check(walk(w, "TIN_TOWER_ROOF", 1), "down off the roof")
  eq(w.loaded.id, "TIN_TOWER_9F", "onto 9F")
  eq(w.backupWarp, banked, "and the roof banks nothing either")
end

-- ---- the -1 contract is untouched -----------------------------------------
do
  -- The staircase writer still wins on its own arm: an INDOOR-to-INDOOR warp
  -- banks nothing under the dig rule, and everything about POKECENTER_2F has
  -- to keep working (tests/gen2_pokecenter_stairs_test.lua pins the rest).
  local w = world("CHERRYGROVE_POKECENTER_1F")
  check(walk(w, "CHERRYGROVE_POKECENTER_1F", 3), "up the centre's stairs")
  eq(w.loaded.id, "POKECENTER_2F", "onto the shared 2F")
  eq(w.backupWarp.map, "CHERRYGROVE_POKECENTER_1F",
    "the -1 arrival banked the centre")
  eq(w.backupWarp.warp, 3, "and its staircase")

  -- And a dig triple banked outdoors does not make the rope work in a room
  -- that is not a cave: .CheckCanDig gates on the CURRENT map's environment.
  local town = world("CHERRYGROVE_CITY")
  check(walk(town, "CHERRYGROVE_CITY", 2), "into the Cherrygrove centre")
  eq(town.backupWarp.map, "CHERRYGROVE_CITY", "banking the town door")
  eq(town:escapeRopeTarget(), nil,
    "but a rope indoors still refuses: the map is not a cave or a dungeon")
end

S.finish()
