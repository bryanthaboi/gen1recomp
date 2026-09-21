#!/usr/bin/env luajit
-- pokefirered/src/event_object_movement.c:4830 GetCollisionAtCoords
-- pokefirered/src/event_object_movement.c:4889 IsMetatileDirectionallyImpassable

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchseam_mod_collision_test: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Gen3Compat = require("src.mods.Gen3Compat")
local WorldAPI = require("src.world.game3.WorldAPI")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {} }
game.session = session
Runtime.session = session
Gen3Compat.bind(function() return game end)

-- pokefirered/include/constants/metatile_behaviors.h:41
local MB_IMPASSABLE_NORTH = 0x32
local BAND = "FR_VICTORY_ROAD_1F"
local NAOMI = 2
local BX, BY = 14, 5

local bandDef = game.data.maps[BAND]
check(bandDef ~= nil, BAND .. " is in the cache")
if not bandDef then finish() end

Field._game = game
session.map = BAND
Field._session = session
Field.running = true
Field.locked = false
Map.load(nil, game, BAND)
Player.reset(11, 9, "down")

eq(Map.current, BAND, "the real map loader put the engine on " .. BAND)
eq(Collision.behavior(BX, BY), MB_IMPASSABLE_NORTH,
  string.format("(%d,%d) carries MB_IMPASSABLE_NORTH", BX, BY))
check(Collision.isWalkable(BX, BY - 1), "(14,4) north of it is open cave floor")
check(Collision.isWalkable(BX, BY + 1), "(14,6) south of it is open cave floor")

print("[test] 1. mod.world npc:canStep obeys the direction-blocked metatile")

local api = WorldAPI.new(game, "stitchseam-test")
-- pokefirered/src/scrcmd.c:1074 ScrCmd_setobjectxy
Objects.setObjectXY(NAOMI, BX, BY)
local handle, why = api:npc(BAND, NAOMI)
check(handle ~= nil, "mod.world:npc handed back a live object handle (" ..
  tostring(why) .. ")")
if not handle then finish() end
eq(select(1, handle:position()), BX, "the handle stands on the banded cell (x)")
eq(select(2, handle:position()), BY, "the handle stands on the banded cell (y)")

eq(handle:canStep("up"), false,
  "canStep refuses the northbound step off MB_IMPASSABLE_NORTH")
eq(handle:canStep("down"), true, "and allows the southbound step off it")
eq(Collision.behavior(BX - 1, BY), MB_IMPASSABLE_NORTH,
  "(13,5) carries the same band, so the seal runs along the row")
eq(handle:canStep("left"), true,
  "and the band is sealed north only, so she may still walk west along it")

print("[test] 2. and the enter-blocked side of the same rule")

Objects.setObjectXY(NAOMI, BX, BY - 1)
local above = api:npc(BAND, NAOMI)
check(above ~= nil, "the handle now stands north of the band")
if not above then finish() end
eq(above:canStep("down"), false,
  "canStep refuses entering MB_IMPASSABLE_NORTH from the north")

print("[test] 3. a land object no longer borrows the player's surfing flag")

local SHORE = "FR_PALLET_TOWN"
local BEACH_X, BEACH_Y = 8, 16
local shoreDef = game.data.maps[SHORE]
check(shoreDef ~= nil, SHORE .. " is in the cache")
if not shoreDef then finish() end

session.map = SHORE
Map.load(nil, game, SHORE)
Player.reset(5, 14, "down")
eq(Map.current, SHORE, "the engine is on " .. SHORE)
check(Collision.isWater(BEACH_X, BEACH_Y + 1) == true, "(8,17) is the ocean")
check(Collision.isWater(BEACH_X, BEACH_Y) == false, "(8,16) is the beach above it")

Objects.setObjectXY(1, BEACH_X, BEACH_Y)
local walker = api:npc(SHORE, 1)
check(walker ~= nil, "a Pallet Town object handle is live")
if not walker then finish() end

-- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
Player.surfing = true
eq(walker:canStep("down"), false,
  "canStep keeps the beach walker out of the sea while the player surfs")
Player.surfing = false
eq(walker:canStep("down"), false, "and keeps her out of it on land too")
eq(walker:canStep("up"), true, "while she may still walk north along the beach")

print("[test] 4. an object that stands on water keeps the swimmer's verdict")

Objects.setObjectXY(1, BEACH_X, BEACH_Y + 1)
local swimmer = api:npc(SHORE, 1)
check(swimmer ~= nil, "the same object now treads water at (8,17)")
if not swimmer then finish() end
eq(swimmer:canStep("down"), true, "it may swim further out to (8,18)")
eq(swimmer:canStep("up"), false, "and may not climb out onto the beach")
Player.surfing = true
eq(swimmer:canStep("up"), false, "not even while the player is surfing")
Player.surfing = false

print("[test] 5. the src.world.Collision facade passes the same context")

session.map = BAND
Map.load(nil, game, BAND)
Player.reset(11, 9, "down")
Objects.setObjectXY(NAOMI, 11, 12)

local Facade = Gen3Compat.resolve("src.world.Collision")
check(type(Facade) == "table" and type(Facade.canMove) == "function",
  "mods reach Collision.canMove through the Gen 3 facade")
if not (Facade and Facade.canMove) then finish() end

local mover = { cellX = BX, cellY = BY, surfing = false }
local okUp, whyUp = Facade.canMove(nil, {}, mover, "up")
eq(okUp, false, "canMove refuses the northbound step off MB_IMPASSABLE_NORTH")
eq(whyUp, "tile", "and reports it as a tile refusal")
eq(Facade.canMove(nil, {}, mover, "down"), true,
  "and allows the southbound step off it")

local moverAbove = { cellX = BX, cellY = BY - 1, surfing = false }
eq(Facade.canMove(nil, {}, moverAbove, "down"), false,
  "canMove refuses entering MB_IMPASSABLE_NORTH from the north")

print("[test] 6. the facade still answers with the mover's own surfing flag")

session.map = SHORE
Map.load(nil, game, SHORE)
Player.reset(5, 14, "down")
Objects.setObjectXY(1, 5, 10)

local rider = { cellX = BEACH_X, cellY = BEACH_Y + 1, surfing = true }
eq(Facade.canMove(nil, {}, rider, "up"), true,
  "a surfing mover may come ashore onto the beach")
local lander = { cellX = BEACH_X, cellY = BEACH_Y, surfing = false }
local okSea, whySea = Facade.canMove(nil, {}, lander, "down")
eq(okSea, false, "a walking mover may not step into the sea")
eq(whySea, "tile", "and the sea refusal reaches the mod as a tile refusal")

finish()
