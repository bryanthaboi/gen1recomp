#!/usr/bin/env luajit
-- pokefirered/src/field_control_avatar.c:965 SetupWarp
-- pokefirered/src/overworld.c:600 SetDynamicWarp
-- pokefirered/src/overworld.c:610 SetWarpDestinationToDynamicWarp

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

local Collision = require("src.core.game3.collision")

print("[test] 1. the forced-movement behavior predicates")
-- pokefirered/src/field_player_avatar.c:226 sForcedMovementFuncs
local PREDS = {
  isWalkEast = 0x40,
  isWalkWest = 0x41,
  isWalkNorth = 0x42,
  isWalkSouth = 0x43,
  isSlideEast = 0x44,
  isSlideWest = 0x45,
  isSlideNorth = 0x46,
  isSlideSouth = 0x47,
  isTrickHouseSlipperyFloor = 0x48,
  isWaterfall = 0x13,
}
for name, want in pairs(PREDS) do
  local fn = Collision[name]
  if type(fn) ~= "function" then
    check(false, "Collision." .. name .. " exists")
  else
    local wrong = 0
    for beh = 0x00, 0xFF do
      if (fn(beh) and true or false) ~= (beh == want) then wrong = wrong + 1 end
    end
    check(wrong == 0,
      string.format("%s is behavior 0x%02X and nothing else, wrong=%d", name, want, wrong))
    check(fn(nil) ~= true, name .. "(nil) is not true")
  end
end

print("[test] 2. the forced-movement table binds the predicates, not the literals")
local Forced = require("src.core.game3.forced_movement")
local WANT_ROW = {
  [0x40] = "WalkEast", [0x41] = "WalkWest", [0x42] = "WalkNorth", [0x43] = "WalkSouth",
  [0x44] = "SlideEast", [0x45] = "SlideWest", [0x46] = "SlideNorth", [0x47] = "SlideSouth",
}
for beh, name in pairs(WANT_ROW) do
  local _, row = Forced.lookup(beh)
  check(row ~= nil and row.name == name,
    string.format("behavior 0x%02X still selects %s (%s)", beh, name,
      tostring(row and row.name)))
end

print("[test] 3. cache-backed dynamic warps")
local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchcoll_dynamic_warp_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local Map = require("src.core.game3.map")
local function bind(mapId)
  local def = game.data.maps[mapId]
  if not def then
    check(false, mapId .. " is in the cache")
    return nil
  end
  if Map.ensureMidLayout then pcall(Map.ensureMidLayout, game, mapId, def) end
  Collision.bindMap(game, mapId, def)
  game.currentMap = mapId
  return def
end

local Runtime = require("src.core.game3.runtime")
local session = { map = "FR_SILPH_CO_ELEVATOR", x = 2, y = 5 }
Runtime.session = session

local ELEVATOR = "FR_SILPH_CO_ELEVATOR"
local elevDef = bind(ELEVATOR)
if not elevDef then finish() end

-- pokefirered/include/constants/maps.h:9
local exit = Collision.warpAt(2, 5)
check(exit ~= nil, "the Silph lift exit tile indexes its warp event")
check(exit ~= nil and tonumber(exit.mapNum) == 0x7F and tonumber(exit.mapGroup) == 0x7F,
  "the exit warp is MAP_DYNAMIC 127:127")
check(Collision.behavior(2, 5) == 0x65, "the exit tile is MB_SOUTH_ARROW_WARP")

session.dynamicWarp = nil
check(Collision.isArrowWarp(game, 2, 5, "down") == nil,
  "with no dynamic warp stored the exit resolves to nothing")

-- pokefirered/src/overworld.c:605 SetDynamicWarpWithCoords
session.dynamicWarp = { map = "FR_SILPH_CO_5F", warpId = 255, x = 22, y = 3 }
local hit = Collision.isArrowWarp(game, 2, 5, "down")
check(hit ~= nil and hit.destMap == "FR_SILPH_CO_5F" and hit.destX == 22 and hit.destY == 3,
  "setdynamicwarp coords drive the exit: " .. tostring(hit and hit.destMap) .. " " ..
  tostring(hit and hit.destX) .. "," .. tostring(hit and hit.destY))

-- pokefirered/src/overworld.c:564 SetPlayerCoordsFromWarp
local fifth = game.data.maps["FR_SILPH_CO_5F"]
local doorWarpIdx = nil
for i, w in ipairs(fifth and fifth.warps or {}) do
  if tostring(w.destMap) == ELEVATOR then doorWarpIdx = i end
end
check(doorWarpIdx ~= nil, "FR_SILPH_CO_5F has a warp into the lift")
if doorWarpIdx then
  session.dynamicWarp = { map = "FR_SILPH_CO_5F", warpId = doorWarpIdx - 1, x = -1, y = -1 }
  local byId = Collision.isArrowWarp(game, 2, 5, "down")
  local landing = fifth.warps[doorWarpIdx]
  check(byId ~= nil and byId.destX == tonumber(landing.x) and byId.destY == tonumber(landing.y),
    "a stored warp id wins over the coords, got " .. tostring(byId and byId.destX) .. "," ..
    tostring(byId and byId.destY))
end

session.dynamicWarp = { map = "FR_SILPH_CO_5F", warpId = 255, x = -1, y = -1 }
local centred = Collision.isArrowWarp(game, 2, 5, "down")
local layout = fifth and fifth.midLayout
check(centred ~= nil and layout ~= nil
  and centred.destX == math.floor(layout.width / 2)
  and centred.destY == math.floor(layout.height / 2),
  "a dummy warp id and dummy coords land on the middle of the map, got " ..
  tostring(centred and centred.destX) .. "," .. tostring(centred and centred.destY))

print("[test] 4. entering a MAP_DYNAMIC map records the way back")
local Player = require("src.core.game3.player")
bind("FR_SILPH_CO_5F")
local doorX = tonumber(fifth.warps[doorWarpIdx].x)
local doorY = tonumber(fifth.warps[doorWarpIdx].y)
Player.cellX, Player.cellY, Player.facing = doorX, doorY + 1, "up"
session.dynamicWarp = nil
check(Collision.noteDynamicWarpEntry(game, "FR_SILPH_CO_1F", 22, 3) == false,
  "warping to a plain map records nothing")
check(session.dynamicWarp == nil, "a plain warp leaves the stored dynamic warp alone")

check(Collision.noteDynamicWarpEntry(game, ELEVATOR, 2, 5) == true,
  "warping onto the lift's MAP_DYNAMIC tile records the origin")
local dw = session.dynamicWarp
check(type(dw) == "table" and dw.map == "FR_SILPH_CO_5F",
  "the recorded map is the floor the player left, got " .. tostring(dw and dw.map))
check(type(dw) == "table" and dw.x == doorX and dw.y == doorY,
  string.format("the recorded tile is the lift door (%d,%d), got %s,%s", doorX, doorY,
    tostring(dw and dw.x), tostring(dw and dw.y)))

-- pokefirered/src/field_control_avatar.c:960 GetWarpEventAtMapPosition
local awayX, awayY = doorX, doorY + 4
Player.cellX, Player.cellY, Player.facing = awayX, awayY, "down"
check(Collision.warpAt(awayX, awayY) == nil and Collision.warpAt(awayX, awayY + 1) == nil,
  string.format("the pose used for the next check owns no warp of its own (%d,%d)",
    awayX, awayY))
session.dynamicWarp = nil
check(Collision.noteDynamicWarpEntry(game, ELEVATOR, 2, 5, doorX, doorY) == true,
  "the warp that fired can be handed in instead of read off the player's pose")
local handed = session.dynamicWarp
check(type(handed) == "table" and handed.x == doorX and handed.y == doorY,
  string.format("the handed-in warp wins over the pose, got %s,%s",
    tostring(handed and handed.x), tostring(handed and handed.y)))

Player.cellX, Player.cellY, Player.facing = doorX, doorY + 1, "up"
session.dynamicWarp = nil
Collision.noteDynamicWarpEntry(game, ELEVATOR, 2, 5, 99, 99)
local nowarp = session.dynamicWarp
check(type(nowarp) == "table" and nowarp.x == doorX and nowarp.y == doorY,
  "a handed-in cell with no warp event on it falls back to the pose, got " ..
  tostring(nowarp and nowarp.x) .. "," .. tostring(nowarp and nowarp.y))

bind(ELEVATOR)
local back = Collision.isArrowWarp(game, 2, 5, "down")
check(back ~= nil and back.destMap == "FR_SILPH_CO_5F"
  and back.destX == doorX and back.destY == doorY,
  "stepping out of the lift without touching the panel returns to the lift door")

Runtime.session = nil
finish()
