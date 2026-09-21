#!/usr/bin/env luajit
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
  print("[skip] game3_stitchcoll_ghost_ctx_test: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Ghosts = require("src.core.game3.ghosts")
local Player = require("src.core.game3.player")

local game = { data = {} }
Dataset.hydrate(game)

-- pokefirered/include/constants/metatile_behaviors.h:41
local MB_IMPASSABLE_NORTH = 0x32
local MAP = "FR_VICTORY_ROAD_1F"
local WALKER = 2

local def = game.data.maps[MAP]
check(def ~= nil, MAP .. " is in the cache")
if not def then finish() end
Collision.bindMap(game, MAP, def)
check(Collision.behaviorOn(def, 14, 5) == MB_IMPASSABLE_NORTH,
  "(14,5) carries MB_IMPASSABLE_NORTH")
check(Collision.behaviorOn(def, 14, 4) ~= MB_IMPASSABLE_NORTH,
  "(14,4) above it is plain cave floor")

print("[test] 1. the ghost context answers with the direction it is handed")

local probePool = Objects.spawnFromDefs({ { localId = 1, x = 14, y = 5 } }, def)
local ctx = Ghosts._contextFor({ def = def, ox = 0, oy = 0 }, probePool)
eq(ctx.canEnter(14, 4, 14, 5, "up"), false,
  "northbound off the sealed edge is refused")
eq(ctx.canEnter(14, 6, 14, 5, "down"), true,
  "southbound off the same cell is allowed")
eq(ctx.canEnter(14, 4, 14, 5, nil), true,
  "a caller with no direction still gets the plain walkability answer")
eq(ctx.canEnter(-1, 4, 0, 4, "left"), false, "off the west edge is refused")

print("[test] 2. a captured pool obeys the edge with no mapDef of its own")

Objects.reset()
Objects.loadMap(game, MAP, def)
local live = Objects.find(WALKER)
check(live ~= nil, "the walker is loaded on " .. MAP)
if not live then finish() end
Player.cellX, Player.cellY = 11, 9
Player.px, Player.py = 11 * 16, 9 * 16
Player.moving = false
local Field = package.loaded["src.core.game3.field"]
if Field then Field.locked = false end

-- pokefirered/src/scrcmd.c:1162 ScrCmd_setobjectmovementtype
Objects.setObjectXY(WALKER, 14, 5)
Objects.setMovementType(WALKER, 3)
check(live.movement == "WALK" and live.range == "UP_DOWN",
  "the walker wanders up and down from (14,5)")

Ghosts.clear()
Ghosts.capture(MAP)
local pool = Ghosts._pools[MAP]
check(pool ~= nil, "walking off the seam captured the map into a ghost pool")
if not pool then finish() end
local ghost = pool.byId[WALKER]
check(ghost ~= nil, "the walker came along into the pool")
if not ghost then finish() end
eq(ghost.mapDef, nil,
  "a captured event object carries no mapDef, so only the context can refuse the step")

local ghostCtx = Ghosts._contextFor({ def = def, ox = 100, oy = 100 }, pool)
local visited = {}
for _ = 1, 6000 do
  Objects.tickPool(pool, game, ghostCtx)
  visited[ghost.targetX .. "," .. ghost.targetY] = true
end
local cells = {}
for k in pairs(visited) do cells[#cells + 1] = k end
table.sort(cells)
print("[info] the captured ghost visited " .. table.concat(cells, " "))
check(visited["14,6"] == true, "the captured ghost really wanders off the band")
check(visited["14,4"] ~= true, "and never crosses the sealed north edge")

finish()
