#!/usr/bin/env luajit
-- pokefirered/src/bike.c:53 BikeInputHandler_Normal
-- pokefirered/src/bike.c:199 BikeTransition_Downhill
-- pokefirered/src/bike.c:209 BikeTransition_Uphill
-- pokefirered/src/metatile_behavior.c:668 MetatileBehavior_IsCyclingRoadPullDownTile

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

local function eq(got, want, msg)
  check(got == want, msg .. " (" .. tostring(got) .. " == " .. tostring(want) .. ")")
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

local ForcedMovement = require("src.core.game3.forced_movement")

-- pokefirered/include/constants/metatile_behaviors.h:128
local MB_CYCLING_ROAD_PULL_DOWN = 0xD0
local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1

print("[test] 1. the pull tiles are a bike feature, not forced movement")
check(ForcedMovement.lookup(MB_CYCLING_ROAD_PULL_DOWN) == nil,
  "0xD0 matches no sForcedMovementFuncs row")
check(ForcedMovement.lookup(MB_CYCLING_ROAD_PULL_DOWN_GRASS) == nil,
  "0xD1 matches no sForcedMovementFuncs row")
check(ForcedMovement.isForcedMovementTile(MB_CYCLING_ROAD_PULL_DOWN) == false,
  "and MetatileBehavior_IsForcedMovementTile excludes 0xD0")
check(ForcedMovement.isForcedMovementTile(MB_CYCLING_ROAD_PULL_DOWN_GRASS) == false,
  "and 0xD1")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_cycling_road_test (cache-backed sections): " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")

local game = { data = {} }
Dataset.hydrate(game)
local MAP = "FR_ROUTE_17"
local session = { map = MAP, flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.session = session

local def = game.data.maps[MAP]
check(def ~= nil, MAP .. " is in the cache")
if not def then finish() end

Field._game, Field._session, Field.running, Field.locked = game, session, true, false
Space.activate(nil, MAP, game, nil)
Collision.bindMap(game, MAP, def)
Objects.loadMap(game, MAP, def)

print("[test] 2. Route 17 is paved with pull tiles")
local pulls, pullGrass = 0, 0
local w = (def.layout and def.layout.width) or 24
local h = (def.layout and def.layout.height) or 160
for y = 0, h + 8 do
  for x = 0, w + 8 do
    local b = Collision.behavior(x, y)
    if b == MB_CYCLING_ROAD_PULL_DOWN then pulls = pulls + 1 end
    if b == MB_CYCLING_ROAD_PULL_DOWN_GRASS then pullGrass = pullGrass + 1 end
  end
end
check(pulls > 1000, "0xD0 covers the road (" .. pulls .. " cells)")
check(pullGrass > 0, "0xD1 covers the grass strips (" .. pullGrass .. " cells)")

local startX, startY
for y = 10, h do
  for x = 0, w do
    if Collision.behavior(x, y) == MB_CYCLING_ROAD_PULL_DOWN
        and Collision.behavior(x, y + 1) == MB_CYCLING_ROAD_PULL_DOWN
        and Collision.behavior(x, y + 2) == MB_CYCLING_ROAD_PULL_DOWN
        and Collision.isWalkable(x, y - 1)
        and Collision.isWalkable(x, y + 1) and Collision.isWalkable(x, y + 2) then
      startX, startY = x, y
      break
    end
  end
  if startX then break end
end
check(startX ~= nil, "found a three-cell downhill run with room to climb back")
if not startX then finish() end

local function placeBiking()
  Player.reset(startX, startY, "down")
  Player.biking = true
end

local function ticks(n, input)
  for _ = 1, n do Player.update(game, input) end
end

local function fakeInput(held)
  held = held or {}
  return {
    isDown = function(_, b) return held[b] == true end,
    wasPressed = function(_, b) return held[b] == true end,
  }
end

print("[test] 3. no input starts a downhill step")
check(Field.locked == false, "the field is free before the first press")
placeBiking()
ticks(1, nil)
check(Player.moving == true, "the pull starts a step with no D-pad at all")
eq(Player.stepFrames, 4, "at MOVE_SPEED_FASTER, four frames a cell")
eq(Player.facing, "down", "facing south")

print("[test] 4. on foot the same tile does nothing")
Player.reset(startX, startY, "down")
Player.biking = false
ticks(60, nil)
eq(Player.cellY, startY, "a walker stands on the slope")

print("[test] 5. B is the brake")
placeBiking()
ticks(60, fakeInput({ b = true }))
eq(Player.cellY, startY, "holding B with no direction holds position")
check(Player.moving == false, "and starts no step at all")

print("[test] 6. pedalling north is uphill, at walking speed")
placeBiking()
Player.update(game, fakeInput({ up = true }))
check(Player.moving == true, "north starts a step")
eq(Player.stepFrames, 16, "MOVE_SPEED_NORMAL uphill")
eq(Player.facing, "up", "facing north")
ticks(16, fakeInput({ up = true }))
eq(Player.cellY, startY - 1, "the bike climbed one cell north")

print("[test] 7. pressing DOWN is still downhill, not a normal bike step")
placeBiking()
Player.update(game, fakeInput({ down = true }))
check(Player.moving == true, "south starts a step")
eq(Player.stepFrames, 4, "still MOVE_SPEED_FASTER")

print("[test] 8. off the pull tiles the bike is an ordinary bike again")
local plainX, plainY
for y = 0, h do
  for x = 0, w do
    local b = Collision.behavior(x, y)
    if b ~= nil and b ~= MB_CYCLING_ROAD_PULL_DOWN and b ~= MB_CYCLING_ROAD_PULL_DOWN_GRASS
        and Collision.isWalkable(x, y) then
      plainX, plainY = x, y
      break
    end
  end
  if plainX then break end
end
check(plainX ~= nil, "found a cell off the slope")
if plainX then
  Player.reset(plainX, plainY, "down")
  Player.biking = true
  ticks(60, nil)
  eq(Player.cellY, plainY, "no input, no motion")
end

print("[test] 9. left alone the road carries the bike the length of the slope")
placeBiking()
ticks(120, nil)
check(Player.cellY > startY + 5,
  "120 frames carried the bike " .. (Player.cellY - startY) .. " cells south")
eq(Player.cellX, startX, "and never sideways")

finish()
