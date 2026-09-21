#!/usr/bin/env luajit
-- pokefirered/src/field_control_avatar.c:825,856,901,944 and
-- pokefirered/src/overworld.c:910.

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

local MB = {
  CAVE_DOOR = 0x60, LADDER = 0x61,
  EAST_ARROW = 0x62, WEST_ARROW = 0x63, NORTH_ARROW = 0x64, SOUTH_ARROW = 0x65,
  FALL = 0x66, REGULAR = 0x67, LAVARIDGE_1F = 0x68, WARP_DOOR = 0x69,
  UP_ESCALATOR = 0x6A, DOWN_ESCALATOR = 0x6B,
  UP_RIGHT_STAIR = 0x6C, UP_LEFT_STAIR = 0x6D,
  DOWN_RIGHT_STAIR = 0x6E, DOWN_LEFT_STAIR = 0x6F,
  UNION_ROOM = 0x71,
}

print("[test] 1. the classifier seeds every live warp behavior as a warp cell")
local ScriptColl = require("src.core.game3.scripting.collision")
local SEEDED = {
  [MB.FALL] = 646, [MB.LAVARIDGE_1F] = 646, [MB.UNION_ROOM] = 750,
}
for beh, mid in pairs(SEEDED) do
  local byte = ScriptColl.fromCell(mid, 0, beh, "indoor")
  check(byte ~= nil and byte >= 0x60 and byte <= 0x7F,
    string.format("behavior 0x%02X seeds a warp COLL byte (0x%02X)", beh, byte or 0))
  local Permissions = require("src.world.gen2.Permissions")
  check(Permissions.isWalkable(byte) == true,
    string.format("behavior 0x%02X is walkable (0x%02X)", beh, byte or 0))
end
local fallByte = ScriptColl.fromCell(646, 0, MB.FALL, "indoor")
local Permissions = require("src.world.gen2.Permissions")
check(Permissions.warpFacesDown(fallByte) ~= true,
  string.format("MB_FALL_WARP does not seed a face-down warp (0x%02X)", fallByte))
-- pokefirered/src/metatile_behavior.c:5
for beh = 0x50, 0x53 do
  local byte = ScriptColl.fromCell(646, 0, beh, "indoor")
  check(byte == 0x29,
    string.format("current behavior 0x%02X seeds the water COLL byte (0x%02X)", beh, byte))
end

print("[test] 2. the metatile_behavior.c predicates")
local Collision = require("src.core.game3.collision")
local PREDS = {
  isWarpDoor = { MB.WARP_DOOR },
  isLadder = { MB.LADDER },
  isNonAnimDoor = { MB.CAVE_DOOR },
  isLavaridge1FWarp = { MB.LAVARIDGE_1F },
  isWarpPad = { MB.REGULAR },
  isUnionRoomWarp = { MB.UNION_ROOM },
  isFallWarp = { MB.FALL },
  isEscalator = { MB.UP_ESCALATOR, MB.DOWN_ESCALATOR },
  isArrowWarpBehavior = { MB.EAST_ARROW, MB.WEST_ARROW, MB.NORTH_ARROW, MB.SOUTH_ARROW },
  -- pokefirered/src/metatile_behavior.c:204
  isSurfable = {
    0x10, 0x11, 0x12, 0x13, 0x15, 0x1A, 0x1B, 0x50, 0x51, 0x52, 0x53,
  },
  -- pokefirered/src/field_control_avatar.c:901 IsWarpMetatileBehavior
  isStepWarpBehavior = {
    MB.WARP_DOOR, MB.LADDER, MB.UP_ESCALATOR, MB.DOWN_ESCALATOR, MB.CAVE_DOOR,
    MB.LAVARIDGE_1F, MB.REGULAR, MB.FALL, MB.UNION_ROOM,
  },
}
for name, want in pairs(PREDS) do
  local fn = Collision[name]
  if type(fn) ~= "function" then
    check(false, "Collision." .. name .. " exists")
  else
    local set = {}
    for _, beh in ipairs(want) do set[beh] = true end
    local wrong = 0
    for beh = 0x00, 0xFF do
      if (fn(beh) and true or false) ~= (set[beh] == true) then wrong = wrong + 1 end
    end
    check(wrong == 0, name .. " matches pret over every behavior byte, wrong=" .. wrong)
  end
end
-- pokefirered/src/metatile_behavior.c:202 is a FRLG stub.
check(type(Collision.isDeepSouthWarp) == "function" and Collision.isDeepSouthWarp(0x00) == false,
  "isDeepSouthWarp is always false in FRLG")
check(type(Collision.isStepWarpBehavior) == "function"
  and Collision.isStepWarpBehavior(nil) == false, "isStepWarpBehavior(nil) is false")

print("[test] 3. arrow warps carry their own press direction")
if type(Collision.arrowWarpDir) ~= "function" then
  check(false, "Collision.arrowWarpDir exists")
else
  check(Collision.arrowWarpDir(MB.EAST_ARROW) == "right", "MB_EAST_ARROW_WARP wants right")
  check(Collision.arrowWarpDir(MB.WEST_ARROW) == "left", "MB_WEST_ARROW_WARP wants left")
  check(Collision.arrowWarpDir(MB.NORTH_ARROW) == "up", "MB_NORTH_ARROW_WARP wants up")
  check(Collision.arrowWarpDir(MB.SOUTH_ARROW) == "down", "MB_SOUTH_ARROW_WARP wants down")
  check(Collision.arrowWarpDir(MB.LADDER) == nil, "MB_LADDER has no arrow direction")
end

print("[test] 4. GetAdjustedInitialDirection")
if type(Collision.arrivalFacing) ~= "function" then
  check(false, "Collision.arrivalFacing exists")
else
  local WANT = {
    [MB.CAVE_DOOR] = "down", [MB.WARP_DOOR] = "down",
    [MB.SOUTH_ARROW] = "up", [MB.NORTH_ARROW] = "down",
    [MB.WEST_ARROW] = "right", [MB.EAST_ARROW] = "left",
    [MB.UP_RIGHT_STAIR] = "left", [MB.DOWN_RIGHT_STAIR] = "left",
    [MB.UP_LEFT_STAIR] = "right", [MB.DOWN_LEFT_STAIR] = "right",
  }
  for beh, want in pairs(WANT) do
    check(Collision.arrivalFacing(beh, "left") == want,
      string.format("landing on 0x%02X faces %s", beh, want))
  end
  check(Collision.arrivalFacing(MB.LADDER, "left") == "left",
    "a ladder keeps the direction the player left with")
  check(Collision.arrivalFacing(0x00, "left") == "down",
    "hasDirectionSet is cleared, so a plain cell faces south")
  check(Collision.arrivalFacing(MB.FALL, "up") == "down",
    "a fall hole lands facing south")
end

print("[test] 5. cache-backed maps")
local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_warp_behaviors_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local function bind(mapId)
  local def = game.data.maps[mapId]
  if not def then
    check(false, mapId .. " is in the cache")
    return nil
  end
  local Map = require("src.core.game3.map")
  if Map.ensureMidLayout then pcall(Map.ensureMidLayout, game, mapId, def) end
  Collision.bindMap(game, mapId, def)
  return def
end

print("[test] 5a. Seafoam Islands 1F drop holes are live warps")
if bind("FR_SEAFOAM_ISLANDS_1F") then
  for _, hole in ipairs({ { 21, 8, 21, 8 }, { 30, 8, 29, 8 } }) do
    local x, y, dx, dy = hole[1], hole[2], hole[3], hole[4]
    check(Collision.behavior(x, y) == MB.FALL,
      string.format("Seafoam 1F (%d,%d) carries MB_FALL_WARP", x, y))
    check(Collision.isWalkable(x, y) == true,
      string.format("Seafoam 1F (%d,%d) is walkable", x, y))
    local w = Collision.warpAt(x, y)
    check(w ~= nil, string.format("Seafoam 1F (%d,%d) indexes its warp event", x, y))
    if w then
      check(tostring(w.destMap) == "FR_SEAFOAM_ISLANDS_B1F",
        string.format("(%d,%d) drops to B1F (%s)", x, y, tostring(w.destMap)))
      local b1 = game.data.maps["FR_SEAFOAM_ISLANDS_B1F"]
      local landing = b1 and b1.warps and b1.warps[tonumber(w.destWarp)]
      check(landing ~= nil and tonumber(landing.x) == dx and tonumber(landing.y) == dy,
        string.format("(%d,%d) lands on B1F (%d,%d), got (%s,%s)", x, y, dx, dy,
          tostring(landing and landing.x), tostring(landing and landing.y)))
    end
  end
end

print("[test] 5b. Victory Road 3F drop hole")
if bind("FR_VICTORY_ROAD_3F") then
  check(Collision.behavior(34, 18) == MB.FALL, "Victory Road 3F (34,18) carries MB_FALL_WARP")
  check(Collision.isWalkable(34, 18) == true, "Victory Road 3F (34,18) is walkable")
  local w = Collision.warpAt(34, 18)
  check(w ~= nil, "Victory Road 3F (34,18) indexes its warp event")
  if w then
    local vr2 = game.data.maps["FR_VICTORY_ROAD_2F"]
    local landing = vr2 and vr2.warps and vr2.warps[tonumber(w.destWarp)]
    check(tostring(w.destMap) == "FR_VICTORY_ROAD_2F"
      and landing ~= nil and tonumber(landing.x) == 34 and tonumber(landing.y) == 19,
      "Victory Road 3F (34,18) lands on 2F (34,19)")
  end
end

print("[test] 5c. Union Room warp pad")
if bind("FR_UNION_ROOM") or game.data.maps["FR_UNION_ROOM"] == nil then
  local def = game.data.maps["FR_UNION_ROOM"]
  if def then
    check(Collision.behavior(7, 11) == MB.UNION_ROOM, "Union Room (7,11) carries MB_UNION_ROOM_WARP")
    check(Collision.isWalkable(7, 11) == true, "Union Room (7,11) is walkable")
  else
    print("[info] FR_UNION_ROOM is not a game3 map in this cache")
  end
end

print("[test] 5d. Saffron Gym teleport pads are MB_REGULAR_WARP, not a map-name guess")
if bind("FR_SAFFRON_CITY_GYM") then
  check(Collision.behavior(18, 20) == MB.REGULAR, "Saffron Gym (18,20) carries MB_REGULAR_WARP")
  check(type(Collision.isWarpPad) == "function"
    and Collision.isWarpPad(Collision.behavior(18, 20)) == true,
    "Saffron Gym (18,20) is a warp pad")
  check(Collision.warpAt(18, 20) ~= nil, "Saffron Gym (18,20) indexes its warp event")
  -- pokefirered/src/field_control_avatar.c:879
  local pads, indexed = 0, 0
  for y = 0, Collision._heightCells - 1 do
    for x = 0, Collision._widthCells - 1 do
      if Collision.behavior(x, y) == MB.REGULAR then
        pads = pads + 1
        if Collision.warpAt(x, y) then indexed = indexed + 1 end
      end
    end
  end
  check(pads >= 2, "Saffron Gym carries " .. pads .. " MB_REGULAR_WARP pads")
  check(pads == indexed,
    string.format("every Saffron Gym warp pad indexes a warp event (%d/%d)", indexed, pads))
end

print("[test] 5e. an exit mat only warps on a press in its own direction")
if bind("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F") or true then
  local MATMAP = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  if game.data.maps[MATMAP] then
    bind(MATMAP)
    local mx, my
    for y = 0, Collision._heightCells - 1 do
      for x = 0, Collision._widthCells - 1 do
        if Collision.behavior(x, y) == MB.SOUTH_ARROW and Collision.warpAt(x, y) then
          mx, my = x, y
          break
        end
      end
      if mx then break end
    end
    check(mx ~= nil, MATMAP .. " has an indexed MB_SOUTH_ARROW_WARP mat")
    if mx then
      check(Collision.tryWarpAt(game, mx, my, "down") == false,
        string.format("landing on the mat at (%d,%d) does not warp by itself", mx, my))
      check(type(Collision.isArrowWarp) == "function"
        and Collision.isArrowWarp(game, mx, my, "down") ~= nil,
        "pressing down on the mat is an arrow warp")
      check(type(Collision.isArrowWarp) == "function"
        and Collision.isArrowWarp(game, mx, my, "up") == nil,
        "pressing up on a south-arrow mat is not an arrow warp")
    end
  else
    print("[info] " .. MATMAP .. " is not in this cache")
  end
end

print("[test] 5f. a west-arrow gate tile does not warp on landing")
if bind("FR_ROUTE_7_EAST_ENTRANCE") then
  check(Collision.behavior(1, 5) == MB.WEST_ARROW, "Route 7 east entrance (1,5) is MB_WEST_ARROW_WARP")
  check(Collision.warpAt(1, 5) ~= nil, "(1,5) indexes its warp event")
  local ok, res = pcall(Collision.tryWarpAt, game, 1, 5, "down")
  check(ok and res == false, "stepping onto the west-arrow tile from the north does not warp")
  check(type(Collision.isArrowWarp) == "function"
    and Collision.isArrowWarp(game, 1, 5, "left") ~= nil,
    "pressing west on it is an arrow warp")
  check(type(Collision.isArrowWarp) == "function"
    and Collision.isArrowWarp(game, 1, 5, "down") == nil,
    "pressing south on a west-arrow tile is not an arrow warp")
end

print("[test] 5g. the Seafoam fall landings are currents, and currents are water")
-- pokefirered/src/overworld.c:898 MetatileBehavior_IsSurfableInSeafoamIslands
local SEAFOAM_LANDINGS = {
  { "FR_SEAFOAM_ISLANDS_B3F", 23, 9, 0x53 },
  { "FR_SEAFOAM_ISLANDS_B3F", 24, 9, 0x53 },
  { "FR_SEAFOAM_ISLANDS_B4F", 8, 17, 0x52 },
  { "FR_SEAFOAM_ISLANDS_B4F", 9, 17, 0x52 },
}
for _, land in ipairs(SEAFOAM_LANDINGS) do
  local mapId, lx, ly, want = land[1], land[2], land[3], land[4]
  if bind(mapId) then
    local beh = Collision.behavior(lx, ly)
    check(beh == want,
      string.format("%s (%d,%d) is behavior 0x%02X, got 0x%02X", mapId, lx, ly, want, beh or 255))
    check(type(Collision.isSurfable) == "function" and Collision.isSurfable(beh) == true,
      string.format("%s (%d,%d) is surfable in sBehaviorSurfable", mapId, lx, ly))
    check(Collision.isWater(lx, ly) == true,
      string.format("%s (%d,%d) bakes as water, not walkable floor", mapId, lx, ly))
  end
end

finish()
