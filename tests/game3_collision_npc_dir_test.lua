#!/usr/bin/env luajit
-- pokefirered/src/event_object_movement.c:4830 GetCollisionAtCoords

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Objects = require("src.core.game3.objects")

print("[test] 1. the pooled step hands its source cell and direction to the context")

local seen = {}
local pool = Objects.spawnFromDefs({
  { localId = 1, x = 4, y = 4, movementType = 2 },
}, { midLayout = { width = 20, height = 20 } })
local eo = pool.byId[1]
check(eo ~= nil and eo.movement == "WALK",
  "MOVEMENT_TYPE_WANDER_AROUND spawns a walker")
local ctx = {
  canEnter = function(tx, ty, fromX, fromY, dir)
    seen[#seen + 1] = { tx = tx, ty = ty, fromX = fromX, fromY = fromY, dir = dir }
    return false
  end,
  blocks = function() return false end,
}
for _ = 1, 600 do
  Objects.tickPool(pool, nil, ctx)
end
check(#seen > 0, "the walker asked the context whether it could step")
local complete, matched = 0, 0
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
for _, s in ipairs(seen) do
  if s.fromX ~= nil and s.fromY ~= nil and s.dir ~= nil then
    complete = complete + 1
    local d = DELTA[s.dir]
    if d and s.fromX + d[1] == s.tx and s.fromY + d[2] == s.ty then
      matched = matched + 1
    end
  end
end
check(complete == #seen,
  string.format("every one of the %d context queries carried fromX/fromY/dir (%d did)",
    #seen, complete))
check(matched == #seen,
  string.format("and the source cell plus the direction land on the queried cell (%d/%d)",
    matched, #seen))

print("[test] 2. the owned-grid step is refused across a sealed edge")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_collision_npc_dir_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local game = { data = {} }
Dataset.hydrate(game)

-- pokefirered/include/constants/metatile_behaviors.h:41
local MB_IMPASSABLE_NORTH = 0x32
local MAP = "FR_VICTORY_ROAD_1F"
local NAOMI = 2

local def = game.data.maps[MAP]
check(def ~= nil, MAP .. " is in the cache")
if not def then finish() end
Collision.bindMap(game, MAP, def)

check(Collision.behavior(14, 5) == MB_IMPASSABLE_NORTH,
  "(14,5) carries MB_IMPASSABLE_NORTH")
check(Collision.cell(14, 5) ~= 0x07, "(14,5) is walkable rock, not a wall")
check(Collision.cell(14, 4) ~= 0x07, "(14,4) above it is walkable cave floor")
check(Collision.canEnter(game, 14, 4,
  { fromX = 14, fromY = 5, dir = "up", surfing = false }) == false,
  "canEnter refuses (14,5) -> (14,4) northbound")
check(Collision.canEnter(game, 14, 6,
  { fromX = 14, fromY = 5, dir = "down", surfing = false }) == true,
  "and allows (14,5) -> (14,6) southbound")

Objects.reset()
Objects.loadMap(game, MAP, def)
local naomi = Objects.find(NAOMI)
check(naomi ~= nil, "Naomi is loaded on " .. MAP)
if not naomi then finish() end

Player.cellX, Player.cellY = 11, 9
Player.px, Player.py = 11 * 16, 9 * 16
Player.moving = false
local Field = package.loaded["src.core.game3.field"]
if Field then Field.locked = false end

-- pokefirered/src/scrcmd.c:1162 ScrCmd_setobjectmovementtype
Objects.setObjectXY(NAOMI, 14, 5)
Objects.setMovementType(NAOMI, 3)
check(naomi.movement == "WALK" and naomi.range == "UP_DOWN",
  "Naomi now wanders up and down from (14,5)")

local visited = {}
for _ = 1, 6000 do
  Objects.update(game)
  visited[naomi.cellX .. "," .. naomi.cellY] = true
  visited[naomi.targetX .. "," .. naomi.targetY] = true
end
local seenCells = {}
for k in pairs(visited) do seenCells[#seenCells + 1] = k end
table.sort(seenCells)
print("[info] Naomi visited " .. table.concat(seenCells, " "))
check(visited["14,6"] == true,
  "she does step south off the band, so the walker really moves")
check(visited["14,4"] ~= true,
  "she never crosses the sealed north edge onto (14,4)")

print("[test] 3. a ghost-pool step is refused across the same sealed edge")

local Ghosts = require("src.core.game3.ghosts")
local ghostPool = Objects.spawnFromDefs({
  { localId = 1, x = 14, y = 5, movementType = 3, movementRangeX = 0, movementRangeY = 1 },
}, def)
local ghost = ghostPool.byId[1]
check(ghost ~= nil and ghost.movement == "WALK",
  "a wandering ghost-pool NPC stands on the band")
if not ghost then finish() end
local ghostCtx = Ghosts._contextFor({ def = def, ox = 100, oy = 100 }, ghostPool)
local ghostVisited = {}
for _ = 1, 6000 do
  Objects.tickPool(ghostPool, game, ghostCtx)
  ghostVisited[ghost.targetX .. "," .. ghost.targetY] = true
end
local ghostCells = {}
for k in pairs(ghostVisited) do ghostCells[#ghostCells + 1] = k end
table.sort(ghostCells)
print("[info] the ghost-pool NPC visited " .. table.concat(ghostCells, " "))
check(ghostVisited["14,6"] == true, "the ghost really wanders off the band")
check(ghostVisited["14,4"] ~= true,
  "and never crosses the sealed north edge, with the real Ghosts context")

print("[test] 4. an NPC does not walk out to sea while the player is surfing")

-- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
local SHORE = "FR_PALLET_TOWN"
local shoreDef = game.data.maps[SHORE]
check(shoreDef ~= nil, SHORE .. " is in the cache")
if not shoreDef then finish() end
Collision.bindMap(game, SHORE, shoreDef)
check(Collision.isWater(8, 17) == true, "(8,17) is Pallet Town ocean")
check(Collision.isWater(8, 16) == false, "(8,16) is the beach above it")

Objects.reset()
Objects.loadMap(game, SHORE, shoreDef)
local walker = Objects.find(1)
check(walker ~= nil, "a Pallet Town object is loaded")
if not walker then finish() end
Player.cellX, Player.cellY = 5, 14
Player.px, Player.py = 5 * 16, 14 * 16
Player.surfing = true
Objects.setObjectXY(1, 8, 16)
Objects.setMovementType(1, 3)
local wetVisited = {}
for _ = 1, 6000 do
  Objects.update(game)
  wetVisited[walker.targetX .. "," .. walker.targetY] = true
end
Player.surfing = false
check(wetVisited["8,15"] == true, "the walker moves north along the beach")
check(wetVisited["8,17"] ~= true,
  "and never steps into the sea because the player happens to be surfing")

print("[test] 5. the stock swimmers keep treading water and never come ashore")

local SEA, SWIMMER = "FR_ROUTE_19", 5
local seaDef = game.data.maps[SEA]
check(seaDef ~= nil, SEA .. " is in the cache")
if not seaDef then finish() end

for _, surfing in ipairs({ true, false }) do
  Collision.bindMap(game, SEA, seaDef)
  Objects.reset()
  Objects.loadMap(game, SEA, seaDef)
  local swimmer = Objects.find(SWIMMER)
  check(swimmer ~= nil and swimmer.movement == "WALK",
    "Route 19 object 5 is a wandering swimmer")
  if not swimmer then finish() end
  check(Collision.isWater(swimmer.cellX, swimmer.cellY) == true,
    string.format("and treads water at (%d,%d)", swimmer.cellX, swimmer.cellY))
  Player.cellX, Player.cellY = 2, 2
  Player.px, Player.py = 32, 32
  Player.moving = false
  Player.surfing = surfing
  local wet, dry = {}, 0
  for _ = 1, 6000 do
    Objects.update(game)
    local key = swimmer.targetX .. "," .. swimmer.targetY
    wet[key] = true
    if not Collision.isWater(swimmer.targetX, swimmer.targetY) then dry = dry + 1 end
  end
  local moved = 0
  for _ in pairs(wet) do moved = moved + 1 end
  check(moved > 1,
    "the swimmer wanders with Player.surfing=" .. tostring(surfing))
  check(dry == 0, "and never climbs out onto the land beside her")
end
Player.surfing = false

finish()
