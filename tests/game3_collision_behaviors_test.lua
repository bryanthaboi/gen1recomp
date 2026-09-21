#!/usr/bin/env luajit

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
  PUDDLE = 0x16,
  SHALLOW_WATER = 0x17,
  STRENGTH_BUTTON = 0x20,
  SAND = 0x21,
  ICE = 0x23,
  THIN_ICE = 0x26,
  CRACKED_ICE = 0x27,
  HOT_SPRINGS = 0x28,
  SAND_CAVE = 0x2B,
  EASTWARD_CURRENT = 0x50,
  WESTWARD_CURRENT = 0x51,
  NORTHWARD_CURRENT = 0x52,
  SOUTHWARD_CURRENT = 0x53,
  SPIN_RIGHT = 0x54,
  SPIN_LEFT = 0x55,
  SPIN_UP = 0x56,
  SPIN_DOWN = 0x57,
  STOP_SPINNING = 0x58,
  CYCLING_ROAD_PULL_DOWN = 0xD0,
  CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1,
}

local PLAIN_MID = 721

print("[test] 1. COLL bytes the classifier bakes per behavior")
local ScriptColl = require("src.core.game3.scripting.collision")
local function bake(beh, mapColl, kind)
  local byte, cat = ScriptColl.fromCell(PLAIN_MID, mapColl, beh, kind or "route")
  return byte, cat
end

for _, beh in ipairs({ MB.PUDDLE, MB.SHALLOW_WATER }) do
  for _, kind in ipairs({ "route", "town", "indoor" }) do
    local openByte, openCat = bake(beh, 0, kind)
    check(openByte == 0x00,
      string.format("0x%02X on %s with mapColl 0 bakes walkable ground (0x%02X %s)",
        beh, kind, openByte, tostring(openCat)))
    local shutByte = bake(beh, 1, kind)
    check(shutByte == 0x07,
      string.format("0x%02X on %s with mapColl 1 stays solid (0x%02X)", beh, kind, shutByte))
  end
end

local sandByte, sandCat = bake(MB.SAND_CAVE, 0)
check(sandByte == 0x00 and sandCat == "SAND",
  string.format("MB_SAND_CAVE bakes the same category as MB_SAND (0x%02X %s)",
    sandByte, tostring(sandCat)))
check(select(2, bake(MB.SAND, 0)) == sandCat,
  "MB_SAND and MB_SAND_CAVE share a category, as MetatileBehavior_IsSand does")

local grassByte, grassCat = bake(MB.CYCLING_ROAD_PULL_DOWN_GRASS, 0)
check(grassByte == 0x18 and grassCat == "TALL_GRASS",
  string.format("MB_CYCLING_ROAD_PULL_DOWN_GRASS bakes tall grass (0x%02X %s)",
    grassByte, tostring(grassCat)))
local pullByte = bake(MB.CYCLING_ROAD_PULL_DOWN, 0)
check(pullByte == 0x00,
  string.format("MB_CYCLING_ROAD_PULL_DOWN stays walkable road (0x%02X)", pullByte))

for _, beh in ipairs({ 0x10, 0x11, 0x12, 0x13, 0x15, 0x1A, 0x1B,
  MB.EASTWARD_CURRENT, MB.WESTWARD_CURRENT, MB.NORTHWARD_CURRENT, MB.SOUTHWARD_CURRENT }) do
  local byte, cat = bake(beh, 0)
  check(byte == 0x29 and cat == "WATER",
    string.format("sBehaviorSurfable member 0x%02X still bakes water (0x%02X %s)",
      beh, byte, tostring(cat)))
end

print("[test] 2. behavior predicates over every byte")
local Collision = require("src.core.game3.collision")
local PREDS = {
  isStrengthButton = { MB.STRENGTH_BUTTON },
  isIce = { MB.ICE },
  isThinIce = { MB.THIN_ICE },
  isCrackedIce = { MB.CRACKED_ICE },
  isHotSprings = { MB.HOT_SPRINGS },
  isEastwardCurrent = { MB.EASTWARD_CURRENT },
  isWestwardCurrent = { MB.WESTWARD_CURRENT },
  isNorthwardCurrent = { MB.NORTHWARD_CURRENT },
  isSouthwardCurrent = { MB.SOUTHWARD_CURRENT },
  isSpinRight = { MB.SPIN_RIGHT },
  isSpinLeft = { MB.SPIN_LEFT },
  isSpinUp = { MB.SPIN_UP },
  isSpinDown = { MB.SPIN_DOWN },
  isStopSpinning = { MB.STOP_SPINNING },
  isSpinTile = { MB.SPIN_RIGHT, MB.SPIN_LEFT, MB.SPIN_UP, MB.SPIN_DOWN },
  isCyclingRoadPullDown = { MB.CYCLING_ROAD_PULL_DOWN, MB.CYCLING_ROAD_PULL_DOWN_GRASS },
  isCyclingRoadPullDownGrass = { MB.CYCLING_ROAD_PULL_DOWN_GRASS },
}
local names = {}
for name in pairs(PREDS) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local fn = Collision[name]
  if type(fn) ~= "function" then
    check(false, "Collision." .. name .. " exists")
  else
    local set = {}
    for _, beh in ipairs(PREDS[name]) do set[beh] = true end
    local wrong = 0
    for beh = 0x00, 0xFF do
      if (fn(beh) and true or false) ~= (set[beh] == true) then wrong = wrong + 1 end
    end
    check(wrong == 0, name .. " matches pret over every behavior byte, wrong=" .. wrong)
    check(fn(nil) ~= true, name .. "(nil) is false")
  end
end

check(Collision.isSurfable(MB.PUDDLE) == false,
  "MB_PUDDLE is not in sBehaviorSurfable")
check(Collision.isSurfable(MB.SHALLOW_WATER) == false,
  "MB_SHALLOW_WATER is not in sBehaviorSurfable")
check(Collision.isSurfable(0x11) == true, "MB_FAST_WATER is still surfable")

print("[test] 3. the imported cache")
local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_collision_behaviors_test map checks: " .. tostring(Cache.reason))
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
    return false
  end
  Collision.bindMap(game, mapId, def)
  return true
end

local function countBeh(mapId, beh)
  if not bind(mapId) then return nil end
  local n = 0
  for y = 0, Collision._heightCells - 1 do
    for x = 0, Collision._widthCells - 1 do
      if Collision.behavior(x, y) == beh then n = n + 1 end
    end
  end
  return n
end

local CELL_COUNTS = {
  { "FR_FOUR_ISLAND", MB.PUDDLE, 28 },
  { "FR_SILPH_CO_1F", MB.PUDDLE, 88 },
  { "FR_ROUTE_21_NORTH", MB.SHALLOW_WATER, 41 },
  { "SEVII_ONE_ISLAND_KINDLE_ROAD", MB.SHALLOW_WATER, 104 },
  { "FR_VICTORY_ROAD_1F", MB.STRENGTH_BUTTON, 1 },
  { "FR_VICTORY_ROAD_2F", MB.STRENGTH_BUTTON, 2 },
  { "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F", MB.ICE, 70 },
  { "FR_FOUR_ISLAND_ICEFALL_CAVE_1F", MB.THIN_ICE, 9 },
  { "FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA", MB.HOT_SPRINGS, 37 },
  { "FR_MT_MOON_1F", MB.SAND_CAVE, 143 },
  { "FR_SEAFOAM_ISLANDS_B4F", MB.EASTWARD_CURRENT, 31 },
  { "FR_SEAFOAM_ISLANDS_B4F", MB.NORTHWARD_CURRENT, 142 },
  { "FR_SEAFOAM_ISLANDS_B3F", MB.SOUTHWARD_CURRENT, 45 },
  { "FR_ROCKET_HIDEOUT_B2F", MB.SPIN_RIGHT, 9 },
  { "FR_ROCKET_HIDEOUT_B2F", MB.SPIN_LEFT, 12 },
  { "FR_ROCKET_HIDEOUT_B2F", MB.SPIN_UP, 15 },
  { "FR_ROCKET_HIDEOUT_B2F", MB.SPIN_DOWN, 6 },
  { "FR_ROCKET_HIDEOUT_B2F", MB.STOP_SPINNING, 12 },
  { "FR_ROUTE_17", MB.CYCLING_ROAD_PULL_DOWN, 2041 },
  { "FR_ROUTE_17", MB.CYCLING_ROAD_PULL_DOWN_GRASS, 66 },
}
for _, row in ipairs(CELL_COUNTS) do
  local mapId, beh, want = row[1], row[2], row[3]
  local got = countBeh(mapId, beh)
  check(got == want,
    string.format("%s carries %d cells of behavior 0x%02X, got %s",
      mapId, want, beh, tostring(got)))
end

if bind("FR_FOUR_ISLAND") and Collision.cell(12, 6) == 0x29 then
  print("[skip] the mounted cache was baked before the classifier change; "
    .. "re-import to run the walkability checks")
  finish()
end

print("[test] 4. shallow water and puddles are walked on foot")
if bind("FR_FOUR_ISLAND") then
  check(Collision.behavior(12, 6) == MB.PUDDLE, "FR_FOUR_ISLAND (12,6) is MB_PUDDLE")
  check(Collision.isWater(12, 6) == false, "the puddle is not surf water")
  check(Collision.canEnter(game, 12, 6, { fromX = 12, fromY = 5, dir = "down" }) == true,
    "the player walks into the Four Island puddle on foot")
  check(Collision.canEnter(game, 13, 6, { fromX = 12, fromY = 6, dir = "right" }) == true,
    "and walks along it")
end
if bind("FR_ROUTE_21_NORTH") then
  check(Collision.behavior(15, 23) == MB.SHALLOW_WATER,
    "FR_ROUTE_21_NORTH (15,23) is MB_SHALLOW_WATER")
  check(Collision.isWater(15, 23) == false, "shallow water is not surf water")
  check(Collision.isWalkable(15, 23) == true, "shallow water is walkable")
end
if bind("FR_SILPH_CO_1F") then
  check(Collision.behavior(13, 8) == MB.PUDDLE, "FR_SILPH_CO_1F (13,8) is MB_PUDDLE")
  check(Collision.cell(13, 8) == 0x07,
    "the Silph lobby puddle keeps its map collision and stays solid")
  local ok, why = Collision.canEnter(game, 13, 8, { fromX = 13, fromY = 9, dir = "up" })
  check(ok == false and why == "tile",
    "walking into the Silph lobby puddle is refused (" .. tostring(why) .. ")")
end

-- pokefirered/src/field_player_avatar.c:597 CanStopSurfing
local SURF_CHANNEL = {
  { "FR_SEAFOAM_ISLANDS_B3F", 23, 8 }, { "FR_SEAFOAM_ISLANDS_B3F", 24, 8 },
  { "FR_SEAFOAM_ISLANDS_B4F", 8, 18 }, { "FR_SEAFOAM_ISLANDS_B4F", 9, 18 },
}
for _, row in ipairs(SURF_CHANNEL) do
  local mapId, x, y = row[1], row[2], row[3]
  if bind(mapId) then
    check(Collision.behavior(x, y) == MB.SHALLOW_WATER,
      string.format("%s (%d,%d) is MB_SHALLOW_WATER", mapId, x, y))
    check(Collision.elevationAt(x, y) == 1,
      string.format("%s (%d,%d) sits at elevation 1, inside the current channel",
        mapId, x, y))
    check(Collision.isWater(x, y) == true,
      string.format("%s (%d,%d) stays surf water, so the surfer does not dismount",
        mapId, x, y))
    check(Collision.canEnter(game, x, y, { surfing = false }) == false,
      string.format("%s (%d,%d) refuses a step on foot", mapId, x, y))
  end
end

print("[test] 5. sand caves, hot springs and the cycling road")
if bind("FR_MT_MOON_1F") then
  check(Collision.behavior(2, 2) == MB.SAND_CAVE, "FR_MT_MOON_1F (2,2) is MB_SAND_CAVE")
  check(Collision.isWalkable(2, 2) == true, "the Mt Moon sand floor is walkable")
end
if bind("FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA") then
  check(Collision.behavior(11, 11) == MB.HOT_SPRINGS, "Ember Spa (11,11) is MB_HOT_SPRINGS")
  check(Collision.isWalkable(11, 11) == true, "the Ember Spa pool is waded into")
  check(Collision.behavior(5, 4) == MB.HOT_SPRINGS, "Ember Spa (5,4) is MB_HOT_SPRINGS")
  check(Collision.isWalkable(5, 4) == false, "the walled-off spring cells stay solid")
end
if bind("FR_ROUTE_17") then
  check(Collision.behavior(15, 11) == MB.CYCLING_ROAD_PULL_DOWN_GRASS,
    "FR_ROUTE_17 (15,11) is MB_CYCLING_ROAD_PULL_DOWN_GRASS")
  check(Collision.isGrass(15, 11) == true,
    "the cycling road grass is still a wild encounter tile")
  check(Collision.behavior(2, 0) == MB.CYCLING_ROAD_PULL_DOWN,
    "FR_ROUTE_17 (2,0) is MB_CYCLING_ROAD_PULL_DOWN")
  check(Collision.isGrass(2, 0) == false, "the plain cycling road is not grass")
  check(Collision.isWalkable(2, 0) == true, "the plain cycling road is walkable")
end

print("[test] 6. the predicates see the real map cells")
local MAP_PREDS = {
  { "FR_VICTORY_ROAD_1F", 20, 16, "isStrengthButton" },
  { "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F", 16, 2, "isIce" },
  { "FR_FOUR_ISLAND_ICEFALL_CAVE_1F", 8, 3, "isThinIce" },
  { "FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA", 11, 11, "isHotSprings" },
  { "FR_SEAFOAM_ISLANDS_B3F", 15, 5, "isSouthwardCurrent" },
  { "FR_SEAFOAM_ISLANDS_B4F", 3, 1, "isNorthwardCurrent" },
  { "FR_ROCKET_HIDEOUT_B2F", 3, 6, "isSpinRight" },
  { "FR_ROCKET_HIDEOUT_B2F", 1, 4, "isStopSpinning" },
  { "FR_ROUTE_17", 2, 0, "isCyclingRoadPullDown" },
}
for _, row in ipairs(MAP_PREDS) do
  local mapId, x, y, name = row[1], row[2], row[3], row[4]
  if bind(mapId) then
    local beh = Collision.behavior(x, y)
    check(Collision[name](beh) == true,
      string.format("%s (%d,%d) behavior 0x%02X answers %s", mapId, x, y, beh or 0, name))
  end
end

finish()
