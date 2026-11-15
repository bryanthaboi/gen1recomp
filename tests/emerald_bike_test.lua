package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("src.core.game3.se_ids").select("emerald")
require("src.core.game3.song_ids").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/scripts/events.lua") then
  print("emerald_bike_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()

local game = { data = {} }
Dataset.hydrate(game)

local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local ForcedMovement = require("src.core.game3.forced_movement")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Constants = require("src.core.game3.constants")
local Bike = require("src.core.game3.bike")
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local MB = require("src.core.game3.mb")
local C = Constants.of("emerald")

local audioLog = {}
package.loaded["src.core.game3.audio"] = setmetatable({
  playSe = function(id) audioLog[#audioLog + 1] = { se = id } end,
  setSavedSong = function(id) audioLog[#audioLog + 1] = { saved = id } end,
  changeMusicTo = function(id) audioLog[#audioLog + 1] = { song = id } end,
  bikeMusic = function(on) audioLog[#audioLog + 1] = { bikeMusic = on } end,
  stopSurfMusic = function() end,
}, { __index = function() return function() end end })

local session = { version = "emerald", map = nil, flags = {}, vars = {}, party = {}, name = "BRENDAN", bag = {} }
game.session = session
Runtime.session = session
Runtime._game = game
Field._game, Field._session, Field.running, Field.locked = game, session, true, false

local function load(mapId)
  session.map = mapId
  Field.clearMetatiles()
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, game.data.maps[mapId])
  Objects.loadMap(game, mapId, game.data.maps[mapId])
  require("src.core.game3.map").current = mapId
  Ctx.resetStepCallback()
end

local function fakeInput(held, pressed)
  held = held or {}
  pressed = pressed or held
  return {
    isDown = function(_, b) return held[b] == true end,
    wasPressed = function(_, b) return pressed[b] == true end,
  }
end

local function ticks(n, input)
  for _ = 1, n do Player.update(game, input) end
end

local function framesOfStep(input)
  local startX, startY = Player.cellX, Player.cellY
  Player.update(game, input)
  if not Player.moving then return nil end
  local frames = Player.stepFrames
  for _ = 1, 64 do
    Player.update(game, input)
    if Player.cellX ~= startX or Player.cellY ~= startY then break end
  end
  return frames
end

local function mount(kind, x, y, facing)
  Player.reset(x, y, facing)
  Player.biking = false
  Player.bikeType = nil
  local rse = Bike.rse(session)
  rse.getOnOff(kind, session)
  return rse
end

check(Bike.rse(session) ~= nil, "Emerald has the machAcroBike bike module")
check(Bike.rse({ version = "firered" }) == nil, "FireRed keeps its own bicycle")

local function clearRun(x0, x1, y0, y1, len)
  for y = y0, y1 do
    for x = x0, x1 do
      local free = true
      for i = 0, len do
        if not Collision.canEnter(game, x, y - i, {}) then free = false break end
      end
      if free then return x, y end
    end
  end
end

print("[test] Mach bike speed tiers on Route 110")
load("EM_ROUTE110")
local runX, runY = clearRun(3, 36, 10, 60, 10)
check(runX ~= nil, "Route 110 has a clear ten-cell run north (" .. tostring(runX) .. "," .. tostring(runY) .. ")")
local rse = mount("mach", runX, runY, "up")
eq(Player.biking, true, "GetOnOffBike puts the player on the bike")
eq(Player.bikeType, "mach", "Mach Bike transition flag")
eq(session.bikeType, "mach", "session remembers the bike")
local cycling = C:require("songs", "MUS_CYCLING")
local sawCycling = false
for _, e in ipairs(audioLog) do if e.song == cycling then sawCycling = true end end
check(sawCycling, "mounting plays MUS_CYCLING (" .. cycling .. ")")
local up = fakeInput({ up = true })
local tiers = {}
for i = 1, 5 do tiers[i] = framesOfStep(up) end
eq(tiers[1], 16, "first Mach step walks (PlayerWalkNormal)")
eq(tiers[2], 8, "second Mach step is PlayerWalkFast")
eq(tiers[3], 4, "third Mach step is PlayerWalkFaster")
eq(tiers[5], 4, "the Mach bike holds MOVE_SPEED_FASTER")
eq(rse.playerSpeed(), rse.SPEED.FASTEST, "GetPlayerSpeed reads PLAYER_SPEED_FASTEST at full speed")
local y0 = Player.cellY
ticks(1, fakeInput())
check(Player.moving and Player.targetY == y0 - 1, "releasing the D-pad coasts one more cell (TrySlowDown)")
local coasted = 0
for _ = 1, 60 do
  local before = Player.cellY
  Player.update(game, fakeInput())
  if Player.cellY ~= before then coasted = coasted + 1 end
end
check(coasted >= 2 and coasted <= 4, "the Mach bike rolls to a stop (" .. coasted .. " cells)")
eq(rse.state.speed, 0, "and ends standing")

print("[test] muddy slope (Granite Cave B1F)")
load("EM_GRANITE_CAVE_B1F")
check(Collision.isMuddySlope(Collision.behavior(9, 10)) and Collision.isMuddySlope(Collision.behavior(9, 9)),
  "Granite Cave B1F has the slope at (9,9)-(9,10)")
check(ForcedMovement.isForcedMovementTile(MB.require("MUDDY_SLOPE")), "muddy slope is a forced-movement tile")
check(ForcedMovement.isForcedMovementTile(MB.require("CRACKED_FLOOR")), "cracked floor is a forced-movement tile")
check(not ForcedMovement.isForcedMovementTile(MB.require("SPIN_RIGHT")), "FR spin tiles are not Emerald forced movement")
Player.reset(9, 11, "up")
Player.biking, Player.bikeType = false, nil
ticks(1, up)
ticks(40, up)
check(Player.cellY >= 10, "on foot the slope pushes the player back down (y=" .. Player.cellY .. ")")
local reachedTop = false
mount("mach", 9, 13, "up")
for _ = 1, 120 do
  Player.update(game, up)
  if Player.cellY <= 8 then reachedTop = true break end
end
check(reachedTop, "the Mach bike at speed climbs the slope (y=" .. Player.cellY .. ")")
mount("mach", 9, 11, "up")
for _ = 1, 80 do Player.update(game, up) end
check(Player.cellY >= 10, "from a standing start the Mach bike slides back (y=" .. Player.cellY .. ")")
mount("acro", 9, 11, "up")
for _ = 1, 80 do Player.update(game, up) end
check(Player.cellY >= 10, "the Acro bike never reaches PLAYER_SPEED_FASTEST (y=" .. Player.cellY .. ")")

print("[test] rails (Route 119)")
load("EM_ROUTE119")
check(Collision.isHorizontalRail(Collision.behavior(8, 5)), "Route 119 (8,5) is a horizontal rail")
check(Collision.isIsolatedHorizontalRail(Collision.behavior(10, 6)), "(10,6) is an isolated horizontal rail")
check(Collision.isHorizontalRail(Collision.behavior(10, 7)), "(10,7) is a horizontal rail")
Player.reset(7, 5, "right")
Player.biking, Player.bikeType = false, nil
local r, why = Player.tryMove("right", game, false)
check(r == "blocked" and why == "acro", "on foot the rail blocks (CheckAcroBikeCollision)")
rse = mount("acro", 7, 5, "right")
local right = fakeInput({ right = true })
eq(framesOfStep(right), 6, "the Acro bike rides onto the rail at MOVE_SPEED_FAST_2")
eq(Player.cellX, 8, "now on the rail")
ticks(1, fakeInput({ down = true }))
eq(Player.facing, "right", "a horizontal rail will not let the bike face south")
for _ = 1, 40 do
  if Player.cellX >= 10 then break end
  Player.update(game, right)
end
eq(Player.cellX, 10, "rode the rail to its end")
ticks(20, fakeInput())
eq(Player.moving, false, "stopped on the rail")
Player.update(game, fakeInput({ down = true, b = true }))
eq(rse.state.acroState, rse.ACRO.SIDE_JUMP, "DOWN + B within 4 frames is a side jump")
check(Player.moving and Player.jumping and Player.jumpType == "normal", "the side jump is a JUMP_TYPE_NORMAL hop")
eq(Player.facing, "right", "facing stays locked through the side jump")
ticks(20, fakeInput())
eq(Player.cellY, 6, "landed on the isolated rail")
ticks(10, fakeInput())
Player.update(game, fakeInput({ down = true, b = true }))
ticks(20, fakeInput())
eq(Player.cellY, 7, "a second side jump reaches the lower rail")
Player.update(game, fakeInput({ down = true }))
ticks(8, fakeInput({ down = true }))
eq(Player.cellY, 7, "plain DOWN on the rail does not step off it")

rse = mount("mach", 7, 5, "right")
eq(framesOfStep(right), 16, "the Mach bike may roll onto a long rail (COLLISION_HORIZONTAL_RAIL passes)")
ticks(30, fakeInput())
Player.update(game, fakeInput({ down = true, b = true }))
ticks(20, fakeInput())
eq(Player.cellY, 5, "the Mach bike has no side jump")

print("[test] wheelie and bunny hop")
load("EM_ROUTE119")
rse = mount("acro", 4, 13, "right")
Player.update(game, fakeInput({ b = true }))
eq(rse.state.acroState, rse.ACRO.WHEELIE_STANDING, "B from a standstill pops a wheelie")
check(Player.action ~= nil and Player.acroAnim and Player.acroAnim.kind == "back", "pop-wheelie anim runs")
local hopped = false
for _ = 1, 80 do
  Player.update(game, fakeInput({ b = true }, {}))
  if Player.action and Player.action.jump == "low" then hopped = true break end
end
check(hopped, "holding B 40 frames bunny hops in place")
eq(rse.state.acroState, rse.ACRO.BUNNY_HOP, "ACRO_STATE_BUNNY_HOP")
ticks(40, fakeInput({ b = true, right = true }, {}))
check(Player.cellX > 4, "hopping with RIGHT moves the hop (x=" .. Player.cellX .. ")")
ticks(40, fakeInput())
eq(rse.state.acroState, rse.ACRO.NORMAL, "releasing B lands the wheelie")

print("[test] item use: bikes, registered swap, dismount rules")
load("EM_ROUTE110")
Player.reset(27, 29, "up")
Player.biking, Player.bikeType = false, nil
local mach, acro = C:require("items", "ITEM_MACH_BIKE"), C:require("items", "ITEM_ACRO_BIKE")
local ok, kind = ItemUse.useBike(session, acro)
check(ok and kind == "bike" and Player.biking and Player.bikeType == "acro", "ACRO_BIKE mounts the Acro Bike")
ok = ItemUse.useBike(session, mach)
check(ok and not Player.biking, "any bike item dismounts (GetOnOffBike)")
ok = ItemUse.useBike(session, mach)
check(ok and Player.bikeType == "mach", "MACH_BIKE mounts the Mach Bike")
local cyclingFlag = Flags.forVersion("emerald").IDS.FLAG_SYS_CYCLING_ROAD
Flags.setFlag(Space.store, nil, cyclingFlag, true)
local ok2, _, text = ItemUse.useBike(session, mach)
check(not ok2 and type(text) == "string" and text:find("dismount", 1, true), "FLAG_SYS_CYCLING_ROAD: can't dismount")
Flags.setFlag(Space.store, nil, cyclingFlag, false)
ItemUse.useBike(session, mach)
load("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F")
session.map = "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
Player.reset(5, 5, "down")
local ok3, _, text3 = ItemUse.useBike(session, mach)
check(not ok3 and type(text3) == "string" and text3:find("DAD", 1, true), "indoors: Dad's advice (" .. tostring(text3) .. ")")
local specials = require("src.core.game3.bike.specials_rse").BY_NAME
session.registeredItem = mach
specials.SwapRegisteredBike()
eq(session.registeredItem, acro, "SwapRegisteredBike Mach -> Acro")
Player.biking, Player.bikeType = true, "acro"
local _, v = specials.GetPlayerAvatarBike()
eq(v, 1, "GetPlayerAvatarBike reads 1 on the Acro Bike")
Player.biking, Player.bikeType = false, nil
local ctx = { stringVars = {} }
local result = require("src.core.game3.bike.specials_rse").cyclingRoadResults(ctx, 9 * 60, 0)
eq(result, 10, "DetermineCyclingRoadResults: no bumps under 10 s scores 10")
eq(ctx.stringVars[2], " 9.00 seconds", "time string")

print("[test] per-step callbacks")
local function stepOnto(x, y, fromX, fromY)
  Player.reset(fromX, fromY, "down")
  ForcedMovement.runStepCallback(game)
  Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
end

load("EM_ROUTE113")
local Steps = require("src.core.game3.step_callbacks_rse")
Ctx.setStepCallback(Ctx.STEP_CB.ASH, "EM_ROUTE113")
Bag.add(session.bag, C:require("items", "ITEM_SOOT_SACK"), 1)
local ashX, ashY = 43, 2
local before = Steps.metatileAt(ashX, ashY)
eq(before, C:require("metatile_labels", "METATILE_Fallarbor_AshGrass"), "Route 113 (43,2) is ash grass")
stepOnto(ashX, ashY, ashX, ashY - 1)
for _ = 1, 5 do ForcedMovement.runStepCallback(game) end
eq(Steps.metatileAt(ashX, ashY), C:require("metatile_labels", "METATILE_Fallarbor_NormalGrass"),
  "ash is swept off the grass 4 frames after the step")
eq(Flags.getVar(Space.store, nil, C:require("vars", "VAR_ASH_GATHER_COUNT")), 1, "the Soot Sack gathers one ash")

load("EM_SKY_PILLAR_2F")
Ctx.setStepCallback(Ctx.STEP_CB.CRACKED_FLOOR, "EM_SKY_PILLAR_2F")
local iceVar = C:require("vars", "VAR_ICE_STEP_COUNT")
Flags.setVar(Space.store, nil, iceVar, 1)
check(Collision.isCrackedFloor(Collision.behavior(10, 5)), "Sky Pillar 2F (10,5) is cracked floor")
stepOnto(10, 5, 10, 4)
ForcedMovement.runStepCallback(game)
eq(Flags.getVar(Space.store, nil, iceVar), 0, "walking onto a cracked floor zeroes VAR_ICE_STEP_COUNT")
for _ = 1, 3 do ForcedMovement.runStepCallback(game) end
check(Collision.isCrackedFloorHole(Collision.behavior(10, 5)), "three frames later the floor is a hole")

load("EM_SOOTOPOLIS_CITY_GYM_1F")
Ctx.setStepCallback(Ctx.STEP_CB.ICE, "EM_SOOTOPOLIS_CITY_GYM_1F")
Flags.setVar(Space.store, nil, iceVar, 0)
check(Collision.isThinIce(Collision.behavior(3, 6)), "Sootopolis Gym (3,6) is thin ice")
stepOnto(3, 6, 3, 5)
for _ = 1, 7 do ForcedMovement.runStepCallback(game) end
eq(Flags.getVar(Space.store, nil, iceVar), 1, "thin ice counts a step")
eq(Steps.metatileAt(3, 6), C:require("metatile_labels", "METATILE_SootopolisGym_Ice_Cracked"), "and cracks")
check(Steps.isIceVisited(3, 6), "the row var marks (3,6) visited")
Field.clearMetatiles()
Collision.bindMap(game, "EM_SOOTOPOLIS_CITY_GYM_1F", game.data.maps.EM_SOOTOPOLIS_CITY_GYM_1F)
eq(Steps.setSootopolisGymCrackedIceMetatiles(), 1, "SetSootopolisGymCrackedIceMetatiles restores the visited crack")
stepOnto(3, 6, 3, 5)
for _ = 1, 7 do ForcedMovement.runStepCallback(game) end
eq(Flags.getVar(Space.store, nil, iceVar), 0, "cracked ice zeroes the count (the ON_FRAME fall)")
eq(Steps.metatileAt(3, 6), C:require("metatile_labels", "METATILE_SootopolisGym_Ice_Broken"), "and breaks")

load("EM_FORTREE_CITY")
Ctx.setStepCallback(Ctx.STEP_CB.FORTREE_BRIDGE, "EM_FORTREE_CITY")
local RAISED = C:require("metatile_labels", "METATILE_Fortree_BridgeOverTrees_Raised")
local LOWERED = C:require("metatile_labels", "METATILE_Fortree_BridgeOverTrees_Lowered")
eq(Steps.metatileAt(16, 14), RAISED, "Fortree (16,14) is a raised log bridge")
Player.reset(15, 14, "right")
Player.elevation = 4
ForcedMovement.runStepCallback(game)
eq(Steps.metatileAt(15, 14), LOWERED, "standing on the bridge when the callback starts lowers it")
Player.cellX, Player.targetX = 16, 16
ForcedMovement.runStepCallback(game)
eq(Steps.metatileAt(15, 14), RAISED, "the section stepped off rises")
eq(Steps.metatileAt(16, 14), LOWERED, "the section stepped onto sinks")
local bounced = false
for _ = 1, 16 do
  ForcedMovement.runStepCallback(game)
  if Steps.metatileAt(15, 14) == LOWERED then bounced = true end
end
check(bounced, "the old section bounces")
eq(Steps.metatileAt(15, 14), RAISED, "and settles raised")

load("EM_PACIFIDLOG_TOWN")
Ctx.setStepCallback(Ctx.STEP_CB.PACIFIDLOG_BRIDGE, "EM_PACIFIDLOG_TOWN")
local function logMid(stage, part) return C:require("metatile_labels", "METATILE_Pacifidlog_" .. stage .. "_" .. part) end
Player.reset(4, 17, "right")
ForcedMovement.runStepCallback(game)
eq(Steps.metatileAt(4, 17), logMid("SubmergedLogs", "HorizontalLeft"), "the log under the player sinks")
eq(Steps.metatileAt(5, 17), logMid("SubmergedLogs", "HorizontalRight"), "both halves of the log sink")
Player.cellX, Player.targetX = 5, 5
ForcedMovement.runStepCallback(game)
eq(Steps.metatileAt(4, 17), logMid("SubmergedLogs", "HorizontalLeft"), "walking along the same log keeps it under")
Player.cellY, Player.targetY = 16, 16
ForcedMovement.runStepCallback(game)
eq(Steps.metatileAt(4, 17), logMid("HalfSubmergedLogs", "HorizontalLeft"), "stepping off starts the log rising")
for _ = 1, 8 do ForcedMovement.runStepCallback(game) end
eq(Steps.metatileAt(4, 17), logMid("FloatingLogs", "HorizontalLeft"), "eight frames later it floats")
eq(Steps.metatileAt(5, 17), logMid("FloatingLogs", "HorizontalRight"), "both halves float")

T.finish("emerald_bike")
