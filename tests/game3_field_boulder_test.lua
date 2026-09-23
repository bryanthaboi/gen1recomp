#!/usr/bin/env luajit
-- pokefirered/src/field_player_avatar.c:1452 DoBoulderFinish
-- pokefirered/src/field_control_avatar.c:1066 HandleBoulderFallThroughHole
-- pokefirered/src/field_control_avatar.c:1076 HandleBoulderActivateVictoryRoadSwitch

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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_boulder_test: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")

local Runtime = require("src.core.game3.runtime")

local game = { data = {} }
Dataset.hydrate(game)

local session = { map = nil, flags = {}, vars = {} }
game.session = session
Runtime.session = session

local VR = "FR_VICTORY_ROAD_1F"
local SEAFOAM = "FR_SEAFOAM_ISLANDS_B3F"
-- pokefirered/data/maps/Route23/scripts.inc:8
local ELSEWHERE = "FR_VICTORY_ROAD_2F"
-- pokefirered/include/constants/vars.h:152
local VAR_VR1F = 16484
local FLAG_HIDE_SEAFOAM_B4F_BOULDER_1 = 76
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_3 = 72

local function enterMap(mapId)
  local def = game.data.maps[mapId]
  if not def then return nil end
  Field._game = game
  session.map = mapId
  Field._session = session
  Field.running = true
  Field.locked = false
  Field.clearMetatiles()
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, def)
  Objects.loadMap(game, mapId, def)
  Space.runOnLoad(mapId)
  return def
end

local function pumpVm(limit)
  local vm = Space.vm
  if not vm then return 0 end
  local n = 0
  while vm:isRunning() and n < (limit or 512) do
    vm:tick()
    n = n + 1
  end
  return n
end

local function standAt(x, y, facing)
  Player.moving = false
  Player.progress = 0
  Player.surfing = false
  Player.biking = false
  Player.cellX, Player.cellY = x, y
  Player.targetX, Player.targetY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.facing = facing or "down"
end

-- pokefirered/src/event_object_movement.c:8959 UpdateWalkSlowerAnim
local function pumpPush(frames)
  for _ = 1, frames or 33 do
    Objects.update(game)
    Player.update(game, nil)
  end
end

print("[test] 1. Victory Road 1F: the floor switch coord event is var-gated shut")
local vrDef = enterMap(VR)
check(vrDef ~= nil, VR .. " is in the cache")
if not vrDef then finish() end

local switch = nil
for _, ev in ipairs(vrDef.coordEvents or {}) do
  if ev.x == 20 and ev.y == 16 then switch = ev end
end
check(switch ~= nil and switch.scriptKey ~= nil, "a coord event sits on (20,16)")
if not switch then finish() end
check(tonumber(switch.var) == VAR_VR1F and tonumber(switch.value) == 99,
  "it wants VAR_MAP_SCENE_VICTORY_ROAD_1F == 99 (" .. tostring(switch.value) .. ")")
check(Collision.behavior(20, 16) == 0x20, "(20,16) carries MB_STRENGTH_BUTTON")
check(Flags.getVar(Space.store, Space.vm.ctx, VAR_VR1F) ~= 99,
  "the var never reaches 99, so the player path can never match")

local barrierTop = Field.metatileOverrideAt(VR, 12, 14)
local barrierBottom = Field.metatileOverrideAt(VR, 12, 15)
check(barrierTop ~= nil and barrierTop.impassable == true,
  "ON_LOAD walled (12,14) with the rock barrier")
check(barrierBottom ~= nil and barrierBottom.impassable == true,
  "ON_LOAD walled (12,15) with the rock barrier")
check(Collision.canEnter(game, 12, 15, { fromX = 12, fromY = 16, dir = "up" }) == false,
  "the barrier blocks the way to the Elite Four")

print("[test] 2. a player standing on the switch does NOT fire it")
standAt(20, 16, "down")
check(Field.tryCoordEvents(game, 20, 16) == false,
  "Field.tryCoordEvents refuses the var-gated trigger")
check(Flags.getVar(Space.store, Space.vm.ctx, VAR_VR1F) == 0,
  "the var is untouched")

print("[test] 3. a boulder pushed onto the switch fires it anyway")
Flags.setFlag(Space.store, nil, FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
local boulder = nil
for _, lid in ipairs({ 5, 6, 7 }) do
  local eo = Objects.find(lid)
  if eo and eo.graphicsId == FieldMoves.GFX_IDS.PUSHABLE_BOULDER then
    boulder = boulder or eo
  end
end
check(boulder ~= nil, "a pushable boulder is on the map")
if not boulder then finish() end
Objects.setObjectXY(boulder.localId, 20, 15)
standAt(20, 14, "down")
local result = Player.tryMove("down", game, false)
check(result == "push", "bumping the boulder southward pushes it (" .. tostring(result) .. ")")
check(Player.cellX == 20 and Player.cellY == 14 and not Player.moving,
  "the player walks in place instead of stepping")
check(boulder.moving == true and boulder.stepFrames == 32,
  "the boulder starts a 32-frame slide")
check(Flags.getVar(Space.store, Space.vm.ctx, VAR_VR1F) ~= 100,
  "the switch has not fired before the slide ends")
pumpPush(31)
check(boulder.moving == true and Player.boulderPush ~= nil,
  "the push is still running on frame 31")
pumpPush(2)
check(Player.boulderPush == nil, "the push task finished")
check(boulder.cellX == 20 and boulder.cellY == 16,
  string.format("the boulder landed on the switch (%d,%d)", boulder.cellX, boulder.cellY))
pumpVm()
check(Flags.getVar(Space.store, Space.vm.ctx, VAR_VR1F) == 100,
  "the floor-switch script ran and set the var to 100")
local openTop = Field.metatileOverrideAt(VR, 12, 14)
local openBottom = Field.metatileOverrideAt(VR, 12, 15)
check(openTop ~= nil and openTop.impassable == false,
  "(12,14) is open floor now")
check(openBottom ~= nil and openBottom.impassable == false,
  "(12,15) is open floor now")
check(Collision.canEnter(game, 12, 15, { fromX = 12, fromY = 16, dir = "up" }) == true,
  "the way north is walkable")

print("[test] 4. the barrier stays down across a map reload")
enterMap(ELSEWHERE)
enterMap(VR)
check(Flags.getVar(Space.store, Space.vm.ctx, VAR_VR1F) == 100, "the var survived")
check(Field.metatileOverrideAt(VR, 12, 14) == nil,
  "ON_LOAD did not re-wall (12,14)")
check(Field.metatileOverrideAt(VR, 12, 15) == nil,
  "ON_LOAD did not re-wall (12,15)")
check(Collision.canEnter(game, 12, 15, { fromX = 12, fromY = 16, dir = "up" }) == true,
  "the way north is still walkable")

print("[test] 5. Seafoam B3F: a boulder pushed into a hole falls through")
local sfDef = enterMap(SEAFOAM)
check(sfDef ~= nil, SEAFOAM .. " is in the cache")
if not sfDef then finish() end
check(Collision.behavior(6, 18) == 0x66, "(6,18) carries MB_FALL_WARP")
local sfBoulder = Objects.find(6)
check(sfBoulder ~= nil and sfBoulder.cellX == 6 and sfBoulder.cellY == 17,
  "boulder 6 starts at (6,17)")
if not sfBoulder then finish() end
check(tonumber(sfBoulder.trainerType) == FLAG_HIDE_SEAFOAM_B4F_BOULDER_1,
  "its trainerType carries the B4F reveal flag (" .. tostring(sfBoulder.trainerType) .. ")")

Flags.setFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1, true)
Flags.setFlag(Space.store, nil, FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
standAt(6, 16, "down")
local r2 = Player.tryMove("down", game, false)
check(r2 == "push", "the boulder is pushed south into the hole (" .. tostring(r2) .. ")")
check(sfBoulder.visible ~= false and sfBoulder.moving == true,
  "the boulder is still sliding toward the hole")
pumpPush(33)
check(Player.cellX == 6 and Player.cellY == 16, "the player never left (6,16)")
check(sfBoulder.visible == false and sfBoulder.hidden == true,
  "the boulder is gone from the floor")
check(Objects.at(6, 18) == nil, "nothing stands on the hole any more")
check(Flags.getFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == false,
  "the B4F reveal flag is cleared")
-- pokefirered/src/event_object_movement.c:1525 RemoveObjectEventByLocalIdAndMap
check(Flags.getFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B3F_BOULDER_3) == true,
  "the boulder's own hide flag IS set, as RemoveObjectEventByLocalIdAndMap does")

print("[test] 6. the reveal survives a map reload, the boulder stays gone")
enterMap(ELSEWHERE)
enterMap(SEAFOAM)
check(Flags.getFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == false,
  "the B4F boulder stays revealed")
local sfAgain = Objects.find(6)
check(sfAgain == nil or sfAgain.visible ~= true or sfAgain.hidden == true,
  "the B3F boulder stays gone after the reload, as on the cart")

finish()
