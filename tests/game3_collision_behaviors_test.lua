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

print("[test] 2b. land elevation mismatch on a fake layout")
do
  local W, H = 5, 4
  local ELEV = {
    3, 3, 3, 3, 3,
    4, 4, 4, 4, 0,
    3, 3, 3, 3, 3,
    1, 1, 4, 3, 1,
  }
  local COLL = {}
  for i = 1, W * H do COLL[i] = 0x00 end
  COLL[3 * W + 1], COLL[3 * W + 2], COLL[3 * W + 5] = 0x29, 0x29, 0x29
  local layout = { width = W, height = H }
  function layout:collArray() return COLL end
  function layout:collAt(x, y) return COLL[y * W + x + 1] end
  function layout:elevAt(x, y) return ELEV[y * W + x + 1] end
  function layout:midAt() return 0 end
  local fakeDef = { midLayout = layout, warps = {} }
  local fakeGame = { data = { maps = {} } }
  Collision.bindMap(fakeGame, "FAKE_ELEVATION", fakeDef)

  local function try(fx, fy, tx, ty, elev, surfing)
    return Collision.canEnter(fakeGame, tx, ty,
      { fromX = fx, fromY = fy, elevation = elev, surfing = surfing or false })
  end
  local ok, why = try(1, 0, 1, 1, 3)
  check(ok == false and why == "elevation",
    "elev 3 -> elev 4 on two collision-0 cells is refused (" .. tostring(why) .. ")")
  ok, why = try(1, 1, 1, 0, 4)
  check(ok == false and why == "elevation",
    "elev 4 -> elev 3 back off the plateau is refused (" .. tostring(why) .. ")")
  check(try(1, 1, 2, 1, 4) == true, "walking along the plateau at elev 4 is allowed")
  check(try(3, 1, 4, 1, 4) == true, "the plateau steps onto the elev 0 stair")
  check(try(4, 1, 4, 0, 0) == true, "from the stair (current elev 0) up to elev 3")
  check(try(4, 1, 4, 2, 0) == true, "from the stair (current elev 0) down to elev 3")
  check(try(1, 0, 1, 1, nil) == true, "no elevation passed keeps the old callers unchanged")
  check(try(1, 0, 1, 1, 0) == true, "current elevation 0 never mismatches")
  check(try(1, 3, 1, 2, 1, true) == true, "surfing elev 1 onto elev 3 land dismounts")
  ok, why = try(1, 3, 2, 3, 1, true)
  check(ok == false and why == "elevation",
    "surfing elev 1 onto elev 4 land is refused (" .. tostring(why) .. ")")
  check(try(0, 3, 1, 3, 1, true) == true, "surfing along elev 1 water")

  check(Collision.elevationMismatchOn(fakeDef, 3, 1, 1) == true, "elevationMismatchOn 3 vs 4")
  check(Collision.elevationMismatchOn(fakeDef, 3, 4, 1) == false, "elevationMismatchOn map elev 0")

  local Player = require("src.core.game3.player")
  Player.reset(1, 1, "down")
  check(Player.currentElevation == 0, "a spawn starts at currentElevation 0 like the cart")
  Player.updateElevation(1, 1)
  check(Player.currentElevation == 4 and Player.elevation == 4,
    "the next update derives elev 4 from the plateau cell")
  Player.cellX, Player.cellY = 3, 1
  Player.updateElevation(4, 1, 3, 1)
  check(Player.currentElevation == 0 and Player.elevation == 4,
    "stepping onto the stair drops currentElevation to 0 and keeps previousElevation 4")
  Player.cellX, Player.cellY = 4, 1
  Player.updateElevation(4, 2, 4, 1)
  check(Player.currentElevation == 3 and Player.elevation == 3,
    "stepping off the stair picks up elev 3")
  Player.reset(4, 1, "down")
  Player.updateElevation(4, 1)
  check(Player.currentElevation == 0, "a warp or load onto the stair leaves the player free (elev 0)")

  local Objects = require("src.core.game3.objects")
  local eo = { cellX = 1, cellY = 1, targetX = 1, targetY = 1, moving = false, currentElevation = 0 }
  Objects.updateElevation(eo)
  check(eo.currentElevation == 4, "an object on the plateau derives currentElevation 4")
  eo.mapDef = fakeDef
  eo.cellX, eo.cellY, eo.moving = 1, 2, false
  Objects.updateElevation(eo)
  check(eo.currentElevation == 3, "an object reads its own mapDef elevation")

  print("[test] 2c. forced movement, waterfall, objects, trainer sight and ledges honor elevation")
  local FM = require("src.core.game3.forced_movement")
  local function forced(x, y, facing, surfing, elev, beh)
    Player.reset(x, y, facing)
    Player.surfing = surfing
    Player.currentElevation = elev
    local moved = FM.tryDoMetatileBehaviorForcedMovement(fakeGame, beh)
    local tx, ty = Player.targetX, Player.targetY
    Player.moving, Player.surfing, Player.dismounting = false, false, false
    FM.forced = false
    return moved, tx, ty
  end
  local moved, tx, ty = forced(1, 0, "down", false, 3, MB.SPIN_DOWN)
  check(not moved and tx == 1 and ty == 0, "SpinDown from elev 3 into elev 4 is refused")
  moved, tx, ty = forced(1, 2, "right", false, 3, MB.SPIN_RIGHT)
  check(moved and tx == 2 and ty == 2, "SpinRight along elev 3 still moves")
  moved, tx, ty = forced(1, 3, "right", true, 1, MB.EASTWARD_CURRENT)
  check(not moved and tx == 1 and ty == 3, "an east current does not push a surfer onto elev 4 land")
  moved, tx, ty = forced(4, 3, "left", true, 1, MB.WESTWARD_CURRENT)
  check(moved and tx == 3 and ty == 3, "a west current still lands a surfer on elev 3 land")
  moved, tx, ty = forced(0, 3, "right", true, 1, MB.EASTWARD_CURRENT)
  check(moved and tx == 1 and ty == 3, "an east current still carries a surfer along elev 1 water")

  local Field = require("src.core.game3.field")
  local FieldMoves = require("src.core.game3.field_moves")
  local realCanEnter, realWf, realWfFlag = Collision.canEnter, FieldMoves.isWaterfallBehavior, Field._waterfall
  local seen
  Collision.canEnter = function(_, _, _, opts) seen = opts return true end
  FieldMoves.isWaterfallBehavior = function() return true end
  Field._waterfall = nil
  Player.reset(0, 2, "down")
  Player.surfing = true
  Player.currentElevation = 1
  Field.forcedMovementPending()
  Collision.canEnter, FieldMoves.isWaterfallBehavior, Field._waterfall = realCanEnter, realWf, realWfFlag
  Player.surfing = false
  check(seen and seen.elevation == 1, "the waterfall push passes the surfer's elevation")

  Objects._mapId = "FAKE_ELEVATION"
  Objects._byId, Objects._order = {}, {}
  local function npc(lid, x, y, elev)
    local o = { localId = lid, cellX = x, cellY = y, targetX = x, targetY = y, moving = false,
      visible = true, hidden = false, passable = false, currentElevation = elev }
    Objects._byId[lid] = o
    Objects._order[#Objects._order + 1] = lid
    return o
  end
  local block = npc(1, 3, 2, 4)
  check(Objects.blocks(3, 2, nil, 3) == false, "an elev 4 object does not block an elev 3 mover")
  check(Objects.blocks(3, 2, nil, 4) == true, "an elev 4 object blocks an elev 4 mover")
  check(Objects.blocks(3, 2, nil, 0) == true, "elev 0 movers collide with everything")
  check(Objects.blocks(3, 2) == true, "no elevation keeps the old callers unchanged")
  block.currentElevation = 0
  check(Objects.blocks(3, 2, nil, 3) == true, "an elev 0 object collides with everything")
  Player.reset(2, 2, "right")
  Player.currentElevation = 4
  check(Objects.playerBlocks(2, 2, 3) == false, "an elev 3 object walks through an elev 4 player")
  check(Objects.playerBlocks(2, 2, 4) == true, "an elev 4 object bumps an elev 4 player")
  check(Objects.playerBlocks(2, 2) == true, "playerBlocks with no elevation is unchanged")
  block.currentElevation = 4
  check(try(2, 2, 3, 2, 3) == true, "the player walks past an object on another elevation")
  local ok2, why2 = try(2, 2, 3, 2, nil)
  check(ok2 == false and why2 == "entity", "canEnter without elevation still stops at the object")
  Objects._byId, Objects._order = {}, {}
  npc(2, 1, 2, 3)
  ok2, why2 = try(1, 3, 1, 2, 1, true)
  check(ok2 == false and why2 == "entity", "a surfer cannot dismount onto an elev 3 object")
  Objects._byId[2].currentElevation = 4
  check(try(1, 3, 1, 2, 1, true) == true, "a surfer dismounts past an elev 4 object like GetObjectEventIdByPosition(x, y, 3)")

  local TrainerSight = require("src.core.game3.trainer_sight")
  Objects._byId, Objects._order = {}, {}
  local trainer = { localId = 9, cellX = 1, cellY = 0, facing = "down", sight = 4,
    currentElevation = 3, visible = true, hidden = false, moving = false }
  Player.reset(1, 2, "up")
  Player.currentElevation = 3
  local spotted = TrainerSight.checkLineOfSight(trainer, Player, fakeGame)
  check(spotted == false, "a trainer does not see across an elev 4 cell")
  trainer.cellX, trainer.cellY, trainer.facing = 0, 2, "right"
  Player.reset(3, 2, "left")
  Player.currentElevation = 3
  local dist
  spotted, dist = TrainerSight.checkLineOfSight(trainer, Player, fakeGame)
  check(spotted == true and dist == 3, "a trainer sees along its own elevation")
  npc(3, 1, 2, 4)
  check(TrainerSight.checkLineOfSight(trainer, Player, fakeGame) == true,
    "an object on another elevation does not block sight")
  Objects._byId[3].currentElevation = 3
  check(TrainerSight.checkLineOfSight(trainer, Player, fakeGame) == false,
    "an object on the same elevation blocks sight")
  Objects._byId, Objects._order = {}, {}
  Player.currentElevation = 4
  check(TrainerSight.checkLineOfSight(trainer, Player, fakeGame) == false,
    "an elev 3 trainer does not see an elev 4 player")
  trainer.cellX, trainer.cellY, trainer.facing = 4, 0, "down"
  Player.reset(4, 1, "up")
  Player.currentElevation, Player.elevation = 0, 4
  spotted, dist = TrainerSight.checkLineOfSight(trainer, Player, fakeGame)
  check(spotted == true and dist == 1, "a player on an elev 0 stair is seen from elev 3")
  trainer.cellX, trainer.cellY, trainer.facing = 1, 2, "down"
  Player.reset(1, 3, "up")
  Player.surfing, Player.currentElevation = true, 1
  check(TrainerSight.checkLineOfSight(trainer, Player, fakeGame) == false,
    "a land trainer does not see a surfer on elev 1 water")
  Player.surfing = false

  COLL[1 * W + 2] = 0xA3
  npc(4, 1, 2, 3)
  local lx, ly = Collision.ledgeLanding(fakeGame, 1, 0, "down")
  check(lx == 1 and ly == 2, "a ledge jump lands on an occupied cell like ShouldJumpLedge")
  COLL[2 * W + 3] = 0x07
  COLL[1 * W + 3] = 0xA3
  lx, ly = Collision.ledgeLanding(fakeGame, 2, 0, "down")
  check(lx == 2 and ly == 2, "a ledge jump does not test the landing tile")
  check(Collision.ledgeLanding(fakeGame, 2, 1, "down") == nil, "a wall is not a ledge")
  COLL[1 * W + 2], COLL[1 * W + 3], COLL[2 * W + 3] = 0x00, 0x00, 0x00
  Objects.clear()
  Collision.clear()
end

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

print("[test] 7. raised platforms are fenced by elevation")
local ELEV_EDGES = {
  { "FR_SAFARI_ZONE_EAST", 37, 16, 37, 17 },
  { "FR_SAFARI_ZONE_WEST", 19, 11, 19, 12 },
  { "FR_SAFARI_ZONE_NORTH", 40, 14, 40, 15 },
}
for _, row in ipairs(ELEV_EDGES) do
  local mapId, fx, fy, tx, ty = row[1], row[2], row[3], row[4], row[5]
  if bind(mapId) then
    local fe, te = Collision.elevationAt(fx, fy), Collision.elevationAt(tx, ty)
    check(fe == 3 and te == 4 and Collision.isWalkable(tx, ty),
      string.format("%s (%d,%d) elev %s and (%d,%d) elev %s are both open ground",
        mapId, fx, fy, tostring(fe), tx, ty, tostring(te)))
    local ok, why = Collision.canEnter(game, tx, ty, { fromX = fx, fromY = fy, elevation = fe })
    check(ok == false and why == "elevation",
      string.format("%s up onto the plateau is refused (%s)", mapId, tostring(why)))
    ok, why = Collision.canEnter(game, fx, fy, { fromX = tx, fromY = ty, elevation = te })
    check(ok == false and why == "elevation",
      string.format("%s down off the plateau is refused (%s)", mapId, tostring(why)))
  end
end
if bind("FR_SAFARI_ZONE_EAST") then
  check(Collision.elevationAt(40, 19) == 0, "Safari East (40,19) is an elevation 0 stair")
  check(Collision.canEnter(game, 40, 19, { fromX = 40, fromY = 18, elevation = 4 }) == true,
    "the plateau steps down onto the stair")
  check(Collision.canEnter(game, 40, 20, { fromX = 40, fromY = 19, elevation = 0 }) == true,
    "the stair steps down onto the sand")
end

local sweepMaps, sweepEdges, sweepWrong = 0, 0, 0
local ids = {}
for mapId in pairs(game.data.maps) do ids[#ids + 1] = mapId end
table.sort(ids)
for _, mapId in ipairs(ids) do
  local def = game.data.maps[mapId]
  if def.midLayout and def.midLayout.elevAt then
    Collision.bindMap(game, mapId, def)
    local found = false
    for y = 0, Collision._heightCells - 1 do
      for x = 0, Collision._widthCells - 1 do
        local a = Collision.elevationAt(x, y)
        for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
          local nx, ny = x + d[1], y + d[2]
          local b = Collision.elevationAt(nx, ny)
          if a and b and a ~= b and a ~= 0 and b ~= 0 and a ~= 15 and b ~= 15
              and a ~= 1 and b ~= 1
              and Collision.isWalkable(x, y) and Collision.isWalkable(nx, ny)
              and not Collision.isWater(x, y) and not Collision.isWater(nx, ny) then
            found = true
            sweepEdges = sweepEdges + 1
            if Collision.canEnter(game, nx, ny, { fromX = x, fromY = y, elevation = a }) ~= false
                or Collision.canEnter(game, x, y, { fromX = nx, fromY = ny, elevation = b }) ~= false then
              sweepWrong = sweepWrong + 1
              if sweepWrong <= 5 then
                print(string.format("[info] open elevation edge %s (%d,%d)<->(%d,%d)", mapId, x, y, nx, ny))
              end
            end
          end
        end
      end
    end
    if found then sweepMaps = sweepMaps + 1 end
  end
end
check(sweepEdges > 200 and sweepMaps >= 15,
  string.format("the sweep finds the FRLG elevation edges (%d edges on %d maps)", sweepEdges, sweepMaps))
check(sweepWrong == 0, "every land elevation edge refuses both directions, open=" .. sweepWrong)

finish()
