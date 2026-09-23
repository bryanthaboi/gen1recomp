#!/usr/bin/env luajit
-- pokefirered/src/field_player_avatar.c:226 sForcedMovementFuncs
-- pokefirered/src/field_player_avatar.c:252 TryDoMetatileBehaviorForcedMovement
-- pokefirered/src/field_player_avatar.c:200 TryUpdatePlayerSpinDirection
-- pokefirered/src/field_control_avatar.c:136 FieldGetPlayerInput

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

print("[test] 1. the table is pret's, row for row")

-- pokefirered/src/field_player_avatar.c:229
local PRET_ROWS = {
  { 0x48, "Slip" },
  { 0x23, "Slip" },
  { 0x43, "WalkSouth" },
  { 0x42, "WalkNorth" },
  { 0x41, "WalkWest" },
  { 0x40, "WalkEast" },
  { 0x53, "PushedSouthByCurrent" },
  { 0x52, "PushedNorthByCurrent" },
  { 0x51, "PushedWestByCurrent" },
  { 0x50, "PushedEastByCurrent" },
  { 0x54, "SpinRight" },
  { 0x55, "SpinLeft" },
  { 0x56, "SpinUp" },
  { 0x57, "SpinDown" },
  { 0x47, "SlideSouth" },
  { 0x46, "SlideNorth" },
  { 0x45, "SlideWest" },
  { 0x44, "SlideEast" },
  { 0x13, "PushedSouthByCurrent" },
  { nil, "MatJump" },
  { nil, "MatSpin" },
}

eq(#ForcedMovement.TABLE, #PRET_ROWS, "the table has pret's 21 rows")
for i, row in ipairs(PRET_ROWS) do
  local beh, name = row[1], row[2]
  eq(ForcedMovement.TABLE[i] and ForcedMovement.TABLE[i].name, name,
    string.format("row %d is %s", i, name))
  if beh then
    local idx, hit = ForcedMovement.lookup(beh)
    eq(idx, i, string.format("behavior 0x%02X picks row %d", beh, i))
    eq(hit and hit.name, name, string.format("behavior 0x%02X applies %s", beh, name))
  end
end

-- pokefirered/src/metatile_behavior.c:620
check(ForcedMovement.lookup(0x58) == nil, "MB_STOP_SPINNING matches no row")
check(ForcedMovement.TABLE[20].check(0x00) == false, "the secret base jump mat is dead in FRLG")
check(ForcedMovement.TABLE[21].check(0x00) == false, "the secret base spin mat is dead in FRLG")

print("[test] 2. MetatileBehavior_IsForcedMovementTile")
-- pokefirered/src/metatile_behavior.c:266
for _, beh in ipairs({ 0x13, 0x23, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
                       0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57 }) do
  check(ForcedMovement.isForcedMovementTile(beh) == true,
    string.format("0x%02X is a forced movement tile", beh))
end
for _, beh in ipairs({ 0x00, 0x02, 0x20, 0x26, 0x27, 0x3F, 0x49, 0x4F, 0x58, 0x66, 0xD0, 0xD1 }) do
  check(ForcedMovement.isForcedMovementTile(beh) == false,
    string.format("0x%02X is NOT a forced movement tile", beh))
end
check(ForcedMovement.isForcedMovementTile(nil) == false, "a nil behavior is not forced")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_forced_movement_test: " .. tostring(Cache.reason))
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
local Encounters = require("src.core.game3.encounters")
local StepEvents = require("src.core.game3.step_events")

local game = { data = {} }
Dataset.hydrate(game)

local session = { map = nil, flags = {}, vars = {}, party = {} }
game.session = session
Runtime.session = session

local ROCKET_B2F = "FR_ROCKET_HIDEOUT_B2F"
local SEAFOAM_B4F = "FR_SEAFOAM_ISLANDS_B4F"
local ICEFALL_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"

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

local function standAt(x, y, facing, surfing)
  Player.reset(x, y, facing)
  Player.surfing = surfing == true
  ForcedMovement.reset()
end

local function walkAndSettle(dir, limit)
  local r = Player.tryMove(dir, game, false)
  if r == "turned" then r = Player.tryMove(dir, game, false) end
  local frames = 0
  while Player.moving and frames < (limit or 4000) do
    Player.tick(game)
    frames = frames + 1
  end
  return r, frames
end

print("[test] 3. Icefall Cave B1F: MB_ICE slides the player on")
local iceDef = enterMap(ICEFALL_B1F)
check(iceDef ~= nil, ICEFALL_B1F .. " is in the cache")
if not iceDef then finish() end
eq(Collision.behavior(20, 7), 0x00, "(20,7) is plain cave floor")
eq(Collision.behavior(19, 7), 0x23, "(19,7) carries MB_ICE")
eq(Collision.behavior(14, 7), 0x23, "(14,7) is still ice")
eq(Collision.behavior(13, 7), 0x00, "(13,7) is the wall the slide stops against")

standAt(20, 7, "left")
local r, frames = walkAndSettle("left")
eq(r, "step", "the player steps west off the floor onto the ice")
eq(Player.cellX, 14, "the slide carries the player to x=14")
eq(Player.cellY, 7, "the slide never leaves the row")
-- pokefirered/src/event_object_movement.c:8925 sStepTimes
eq(frames, 16 + 5 * 8, "one normal step plus five slips")
eq(ForcedMovement.forced, false, "the forced flag clears when the slide is blocked")
eq(Player.animDisabled, false, "the step animation is re-enabled when the slide ends")

print("[test] 4. a slip keeps the direction the player arrived with")
standAt(14, 4, "right")
eq(Collision.behavior(14, 4), 0x23, "(14,4) is ice")
standAt(13, 4, "right")
local _, iceFrames = walkAndSettle("right")
check(Player.cellX >= 14, "stepping east onto the ice keeps pushing east")
eq(Player.cellY, 4, "and never sideways")
check(iceFrames >= 16, "the entry step really ran")

print("[test] 5. Rocket Hideout B2F: a spinner chain ends on MB_STOP_SPINNING")
local spinDef = enterMap(ROCKET_B2F)
check(spinDef ~= nil, ROCKET_B2F .. " is in the cache")
if not spinDef then finish() end
eq(Collision.behavior(13, 7), 0x58, "(13,7) carries MB_STOP_SPINNING")
eq(Collision.behavior(12, 7), 0x54, "(12,7) carries MB_SPIN_RIGHT")

standAt(13, 7, "left")
local rs, spinFrames = walkAndSettle("left")
eq(rs, "step", "the player steps west onto the spinner")
eq(Player.cellX, 13, "MB_SPIN_RIGHT throws the player straight back east")
eq(Player.cellY, 7, "on the same row")
eq(Collision.behavior(Player.cellX, Player.cellY), 0x58, "onto the stop tile")
eq(spinFrames, 16 + 8, "one normal step plus one MOVE_SPEED_FAST_1 spin")
eq(ForcedMovement.forced, false, "MB_STOP_SPINNING clears the forced flag")
eq(Player.spinning, false, "and stops the spin animation")
eq(Player.facing, "right", "the player faces the way the spinner threw them")

print("[test] 6. a spinner keeps going over plain floor until a stop tile")
eq(Collision.behavior(3, 4), 0x55, "(3,4) carries MB_SPIN_LEFT")
eq(Collision.behavior(2, 4), 0x00, "(2,4) is plain floor in the middle of the run")
eq(Collision.behavior(1, 4), 0x58, "(1,4) is the stop tile")
standAt(4, 4, "left")
local rl, longFrames = walkAndSettle("left")
eq(rl, "step", "the player steps west onto MB_SPIN_LEFT")
eq(Player.cellX, 1, "the spin carries them across the plain tile to the stop tile")
eq(longFrames, 16 + 2 * 8, "one normal step plus two spins")
eq(ForcedMovement.lastSpinTile, 0x55, "lastSpinTile kept MB_SPIN_LEFT over the plain tile")

print("[test] 7. Seafoam B4F: the currents carry a surfer through the maze")
local seaDef = enterMap(SEAFOAM_B4F)
check(seaDef ~= nil, SEAFOAM_B4F .. " is in the cache")
if not seaDef then finish() end
eq(Collision.behavior(9, 5), 0x50, "(9,5) carries MB_EASTWARD_CURRENT")
eq(Collision.behavior(16, 5), 0x52, "(16,5) carries MB_NORTHWARD_CURRENT")
eq(Collision.behavior(16, 1), 0x52, "(16,1) is the last current cell of the column")

standAt(9, 5, "right", true)
local rc, curFrames = walkAndSettle("right")
eq(rc, "step", "the surfer paddles one cell east into the current")
eq(Player.cellX, 16, "the eastward current runs them to the corner")
eq(Player.cellY, 1, "the northward current then lifts them up the column")
-- pokefirered/src/event_object_movement.c:8925 sStepTimes
eq(curFrames, 16 + 10 * 6, "one paddle plus ten current pushes")
eq(ForcedMovement.forced, false, "leaving the current clears the forced flag")

print("[test] 8. a forced step rolls no encounter and burns no step counter")
local encCalls, stepCalls = 0, 0
local realOnStep = Encounters.onStep
local realOnStepTaken = StepEvents.onStepTaken
Encounters.onStep = function(...)
  encCalls = encCalls + 1
  realOnStep(...)
  return nil
end
StepEvents.onStepTaken = function(...) stepCalls = stepCalls + 1 return realOnStepTaken(...) end

enterMap(ICEFALL_B1F)
standAt(20, 7, "left")
walkAndSettle("left")
eq(encCalls, 0, "no wild encounter roll across the whole slide")
eq(stepCalls, 0, "no step counter across the whole slide")

eq(Collision.behavior(20, 9), 0x00, "(20,9) is plain floor")
eq(Collision.behavior(21, 9), 0x08, "(21,9) carries MB_CAVE")
standAt(20, 9, "right")
local rn = walkAndSettle("right")
eq(rn, "step", "an ordinary step east, clear of the ice")
eq(encCalls, 1, "an ordinary step DOES roll the encounter check")
eq(stepCalls, 1, "and DOES tick the step counters")

Encounters.onStep = realOnStep
StepEvents.onStepTaken = realOnStepTaken

print("[test] 9. a scripted walk over ice does not slide")
-- pokefirered/data/maps/PokemonLeague_HallOfFame/scripts.inc:21
local HALL = "FR_POKEMON_LEAGUE_HALL_OF_FAME"
local hallDef = enterMap(HALL)
check(hallDef ~= nil, HALL .. " is in the cache")
if hallDef then
  eq(Collision.behavior(5, 8), 0x23, "the Hall of Fame floor is MB_ICE")
  standAt(5, 9, "up")
  Field.locked = true
  Player.scriptStep("up")
  local n = 0
  while Player.moving and n < 200 do Player.tick(game) n = n + 1 end
  eq(Player.cellY, 8, "the scripted step lands one cell north and stops")
  eq(ForcedMovement.forced, false, "a locked field never starts forced movement")
  Field.locked = false
end

print("[test] 10. the per-step callback registry is wired")
enterMap(ICEFALL_B1F)
local Ctx = require("src.core.game3.scripting.ctx")
local function walkTicking(dir, extra)
  Player.facing = dir
  Player.turnTimer = 0
  Player.tryMove(dir, game, false)
  local frames = 0
  while Player.moving and frames < 4000 do
    ForcedMovement.runStepCallback(game)
    Player.tick(game)
    frames = frames + 1
  end
  for _ = 1, extra or 8 do ForcedMovement.runStepCallback(game) end
end
local realIce = ForcedMovement.stepCallbacks["ice"]
check(type(realIce) == "function", "STEP_CB_ICE has a registered handler")
local calls = 0
ForcedMovement.registerStepCallback("ice", function()
  calls = calls + 1
  return false
end)
Ctx.setStepCallback(Ctx.STEP_CB.ICE, session.map)
standAt(20, 9, "right")
walkTicking("right")
check(calls > 0, "STEP_CB_ICE reached the registered handler every frame")
Ctx.resetStepCallback()
standAt(20, 9, "right")
calls = 0
walkTicking("right")
eq(calls, 0, "STEP_CB_DUMMY reaches no handler")
ForcedMovement.registerStepCallback("ice", realIce)

print("[test] 11. a warp taken mid-slide drops the FORCED flag with the map")
enterMap(ICEFALL_B1F)
standAt(20, 7, "left")
Player.tryMove("left", game, false)
local guard = 0
while Player.moving and guard < 40 do Player.tick(game) guard = guard + 1 end
check(ForcedMovement.forced == true, "the slide is running and the FORCED flag is up")
check(ForcedMovement.isForced() == true, "isForced agrees while the map is the same")
-- pokefirered/src/field_player_avatar.c:1229 ClearPlayerAvatarInfo
enterMap(ROCKET_B2F)
check(ForcedMovement.isForced() == false,
  "the first read on the new map clears it, so step events are not suppressed")
check(ForcedMovement.forced == false, "and the flag itself is down")

finish()
