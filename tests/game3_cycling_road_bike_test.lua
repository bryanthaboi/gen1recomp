#!/usr/bin/env luajit
-- ROM-free unit tests for Game 3 (FireRed / LeafGreen) Cycling Road forced biking & dismount restrictions.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Player = require("src.core.game3.player")
local Flags = require("src.core.game3.scripting.flags")
local ItemUse = require("src.core.game3.item_use")
local Collision = require("src.core.game3.collision")
local RomText = require("src.core.game3.rom_text")
if not RomText.has("gText_CantDismountBike") then
  RomText.overrides.gText_CantDismountBike = require("src.core.game3.scripting.text_ir").fromAscii("CANT DISMOUNT")
end

local session = {
  flags = {},
  vars = {},
  store = { flags = {}, vars = {} }
}

-- 1. Test Player.isOnCyclingRoad
Player.cellX, Player.cellY = 0, 0
Flags.setFlag(session.store, nil, 0x830, false)
check(not Player.isOnCyclingRoad(session, 0, 0), "isOnCyclingRoad is false by default on neutral tile")

Flags.setFlag(session.store, nil, 0x830, true)
check(Player.isOnCyclingRoad(session, 0, 0), "isOnCyclingRoad is true when FLAG_SYS_ON_CYCLING_ROAD is set")

-- 2. Test Player.isOnCyclingRoad via metatile behaviors
Flags.setFlag(session.store, nil, 0x830, false)
Collision.behavior = function(x, y)
  if x == 10 and y == 10 then return 0xD0 end -- MB_CYCLING_ROAD_PULL_DOWN
  if x == 10 and y == 11 then return 0xD1 end -- MB_CYCLING_ROAD_PULL_DOWN_GRASS
  return 0x00
end

check(Player.isOnCyclingRoad(session, 10, 10), "isOnCyclingRoad is true for MB_CYCLING_ROAD_PULL_DOWN")
check(Player.isOnCyclingRoad(session, 10, 11), "isOnCyclingRoad is true for MB_CYCLING_ROAD_PULL_DOWN_GRASS")
check(not Player.isOnCyclingRoad(session, 5, 5), "isOnCyclingRoad is false for normal tile without flag")

-- 3. Test Surf dismount onto Cycling Road forces biking
Flags.setFlag(session.store, nil, 0x830, true)
Player.surfing = true
Player.dismounting = true
Player.biking = false
Player.targetX, Player.targetY = 10, 10
Player.cellX, Player.cellY = 10, 10
Player.moving = true
Player.surfHopping = false

-- Step onto cycling road land and complete step
local game = { session = session, save = { position = {} } }
local Runtime = require("src.core.game3.runtime")
Runtime.session = session

-- Let's run Player.tick to complete the dismount step
Player.progress = 1
for _ = 1, 32 do
  if not Player.moving then break end
  Player.tick(game)
end

check(Player.biking == true, "dismounting surf onto cycling road forces Player.biking = true")
check(Player.surfing == false, "Player.surfing is false after dismount")

-- 4. Test Surf dismount onto non-cycling-road land keeps player on foot
Flags.setFlag(session.store, nil, 0x830, false)
Collision.behavior = function() return 0x00 end
Player.surfing = true
Player.dismounting = true
Player.biking = false
Player.targetX, Player.targetY = 0, 0
Player.cellX, Player.cellY = 0, 0
Player.moving = true
Player.progress = 1

for _ = 1, 32 do
  if not Player.moving then break end
  Player.tick(game)
end

check(Player.biking == false, "dismounting surf on normal land leaves Player.biking = false")
check(Player.surfing == false, "Player.surfing is false after normal dismount")

-- 5. Test ItemUse.useBike on Cycling Road (cannot dismount)
session.map = "FR_PALLET_TOWN"
Flags.setFlag(session.store, nil, 0x830, true)
Player.biking = true
local ok, kind, text = ItemUse.useBike(session)
check(ok == false, "useBike returns false when trying to dismount on Cycling Road")
check(Player.biking == true, "Player.biking remains true after attempted dismount")
check(text ~= nil, "refusal text returned when trying to dismount on Cycling Road")

-- 6. Test ItemUse.useBike when on foot on Cycling Road (can mount)
Player.biking = false
local ok2, kind2, text2 = ItemUse.useBike(session)
check(ok2 == true, "useBike allows mounting when on foot on Cycling Road")
check(Player.biking == true, "Player.biking becomes true after mounting")

-- 7. Test ItemUse.useBike on normal outdoor land (can dismount and mount freely)
Flags.setFlag(session.store, nil, 0x830, false)
Player.biking = true
local ok3, kind3, text3 = ItemUse.useBike(session)
check(ok3 == true, "useBike allows dismounting on normal land")
check(Player.biking == false, "Player.biking is now false")

-- 8. Test save & load / Map.load on Cycling Road forces Player.biking = true
local Map = require("src.core.game3.map")
local Audio = require("src.core.game3.audio")
local Schema = require("src.core.game3.save_schema_firered")

-- Simulate fresh boot / uninitialized avatar state:
Player.biking = false
Flags.setFlag(session.store, nil, 0x830, true)
session.flags = session.flags or {}
session.flags[0x830] = true
local cyclingMapDef = {
  id = "FR_ROUTE_17",
  bikingAllowed = 1,
  music = 282,
  regionMapSectionId = 44,
  pair = "outdoor",
}
game.data = { maps = { FR_ROUTE_17 = cyclingMapDef } }
game.session = session
local Space = require("src.core.game3.scripting.space")
Space.store = session.store
Space.activate = function() end
Space.runEnterScripts = function() end

Map.load(nil, game, "FR_ROUTE_17", { x = 10, y = 10, facing = "down" })
check(Player.biking == true, "loading/continuing map on Cycling Road forces Player.biking = true")
check(Audio.specialMapSong() == Audio.MUS_CYCLING, "specialMapSong returns Audio.MUS_CYCLING when biking")

-- 9. Test Schema serialization preserves biking state
session.biking = Player.biking
local saveTable = Schema.toSaveTable(session)
check(saveTable.biking == true, "Schema.toSaveTable includes biking = true")
local restoredSession = Schema.fromSaveTable(saveTable)
check(restoredSession.biking == true, "Schema.fromSaveTable restores biking = true")

-- 10. Test dismounting on normal land and moving between outdoor maps keeps player on foot
Flags.setFlag(session.store, nil, 0x830, false)
session.flags[0x830] = false
Player.biking = true
ItemUse.useBike(session)
check(Player.biking == false, "dismounted bike on normal land")

local palletDef = {
  id = "FR_PALLET_TOWN",
  bikingAllowed = 1,
  pair = "outdoor",
}
local route1Def = {
  id = "FR_ROUTE_1",
  bikingAllowed = 1,
  pair = "outdoor",
}
game.data.maps.FR_PALLET_TOWN = palletDef
game.data.maps.FR_ROUTE_1 = route1Def
Map.load(nil, game, "FR_ROUTE_1", { x = 10, y = 35, facing = "up" })
check(Player.biking == false, "moving from Pallet Town to Route 1 while on foot leaves Player on foot")
Map.load(nil, game, "FR_PALLET_TOWN", { x = 10, y = 0, facing = "down" })
check(Player.biking == false, "moving back to Pallet Town leaves Player on foot")

-- 11. Test saving while on foot preserves biking = false
local onFootSave = Schema.toSaveTable(session)
check(onFootSave.biking == false, "Schema.toSaveTable records biking = false when on foot")
local restoredFoot = Schema.fromSaveTable(onFootSave)
check(restoredFoot.biking == false, "Schema.fromSaveTable restores biking = false when on foot")

-- 12. Test entering indoor map (e.g. Silph Co) while biking forces dismount to foot
local silphDef = {
  id = "FR_SILPH_CO_1F",
  bikingAllowed = 0,
  pair = "indoor",
}
local saffronDef = {
  id = "FR_SAFFRON_CITY",
  bikingAllowed = 1,
  pair = "outdoor",
}
game.data.maps.FR_SILPH_CO_1F = silphDef
game.data.maps.FR_SAFFRON_CITY = saffronDef

session = Runtime.getSession() or session
Player.biking = true
session.biking = true
Map.load(nil, game, "FR_SILPH_CO_1F", { x = 18, y = 21, facing = "up" })
check(Player.biking == false, "entering Silph Co 1F forces Player.biking = false")
check(session.biking == false, "session.biking is false in Silph Co")

-- Exiting Silph Co back to Saffron City keeps player on foot (not re-mounted)
Map.load(nil, game, "FR_SAFFRON_CITY", { x = 18, y = 22, facing = "down" })
check(Player.biking == false, "exiting Silph Co to Saffron City keeps Player on foot")

-- 13. Test loading directly into Silph Co via alreadyOnMap forces dismount to foot
Player.biking = true
session.biking = true
session.map = "FR_SILPH_CO_1F"
game.save = { biking = true, position = { map = "FR_SILPH_CO_1F", biking = true } }
Runtime.start(nil, game, session, { alreadyOnMap = true })
check(Player.biking == false, "loading directly into Silph Co with alreadyOnMap clears Player.biking")
check(session.biking == false, "session.biking cleared to false on Silph Co load")

-- 14. Test Gen 2 Bike.tryBike allows dismounting when in indoor environment
local Gen2Bike = require("src.world.gen2.Bike")
local dismountAction = Gen2Bike.tryBike({
  state = 1, -- PLAYER_BIKE
  environment = "INDOOR",
  collision = 0,
  alwaysOnBike = false,
})
check(dismountAction == "dismount", "Gen 2 Bike.tryBike allows dismount in INDOOR environment")

local Field = require("src.core.game3.field")
session = Runtime.getSession() or session
session.version = "firered"
session.flags = session.flags or {}
session.vars = session.vars or {}
session.store = session.store or { flags = {}, vars = {} }
Space.store = session.store
Field._game, Field._session = game, session
local defs = Flags.forVersion("firered")
local road, scene = defs.IDS.FLAG_SYS_ON_CYCLING_ROAD, defs.VAR_IDS.VAR_MAP_SCENE_ROUTE16
Flags.setFlag(session.store, nil, road, true)
Flags.setFlag(session, nil, road, true)
Flags.setVar(session.store, nil, scene, 1)
Player.biking, session.biking, game.save.biking = true, true, true
Field.flyTo(nil, nil, { dest = { map = "FR_SAFFRON_CITY", x = 18, y = 22 } })
check(not Flags.getFlag(session.store, nil, road) and not Flags.getFlag(session, nil, road),
  "Cycling Road Fly clears every road flag store")
check(Flags.getVar(session.store, nil, scene) == 0, "Cycling Road Fly resets Route 16 scene")
Map.load(nil, game, "FR_SILPH_CO_1F", { x = 18, y = 21, facing = "up" })
check(not Player.biking and not session.biking and not game.save.biking,
  "indoor entry after Cycling Road Fly keeps avatar session and save on foot")

local gate1F = { id = "FR_ROUTE16_NORTH_ENTRANCE_1F", bikingAllowed = 1, pair = "indoor" }
local gate2F = { id = "FR_ROUTE16_NORTH_ENTRANCE_2F", bikingAllowed = 0, pair = "indoor" }
local gate18_2F = { id = "FR_ROUTE18_EAST_ENTRANCE_2F", bikingAllowed = 0, pair = "indoor" }
game.data.maps[gate1F.id] = gate1F
game.data.maps[gate2F.id] = gate2F
game.data.maps[gate18_2F.id] = gate18_2F
Collision.behavior = function() return 0x00 end

local function staleSession()
  session.flags = { [road] = true, [tostring(road)] = true }
  session.store = { flags = { [road] = true }, vars = {} }
  local live = { flags = {}, vars = {} }
  Flags.setFlag(live, nil, road, false)
  Space.store = live
  Space.active = true
  return live
end

staleSession()
check(not Player.isOnCyclingRoad(session, 5, 5),
  "live Space store with road flag cleared beats stale session.flags")

local live = staleSession()
Flags.setFlag(live, nil, road, true)
check(Player.isOnCyclingRoad(session, 5, 5), "live Space store with road flag set reports Cycling Road")

staleSession()
session.map = gate1F.id
Player.biking, session.biking, game.save.biking = true, true, true
local okGate, _, gateText = ItemUse.useBike(session)
check(okGate == true and Player.biking == false and gateText == nil,
  "gate 1F dismount allowed after Route 16 OnTransition flag cleared only in live store")

local function climb(def, setLive)
  local st = staleSession()
  if setLive then Flags.setFlag(st, nil, road, true) end
  session.map = gate1F.id
  Player.biking, session.biking, game.save.biking = true, true, true
  Map.load(nil, game, def.id, { x = 5, y = 4, facing = "down" })
  return Player.biking == false and session.biking == false and game.save.biking == false
end
check(climb(gate2F, false), "Route 16 gate 2F arrives on foot with stale session road flag")
check(climb(gate2F, true), "Route 16 gate 2F arrives on foot even with live road flag set")
check(climb(gate18_2F, false), "Route 18 gate 2F arrives on foot with stale session road flag")

staleSession()
Flags.setFlag(Space.store, nil, road, true)
Player.biking, session.biking = false, false
Map.load(nil, game, "FR_ROUTE_17", { x = 10, y = 10, facing = "down" })
check(Player.biking == true, "road flag still forces the bike on a biking-allowed map")

Space.active = false
Space.store = { flags = {}, vars = {} }
session.flags = {}
session.store = { flags = {}, vars = {} }
Collision.behavior = function() return 0xD0 end
Player.biking, session.biking, game.save.biking = false, false, false
Map.load(nil, game, "FR_SAFFRON_CITY", { x = 10, y = 10, facing = "down" })
check(Player.biking == false, "pull-down tile of the previous map does not force the bike on the new map")
Collision.behavior = function() return 0x00 end

staleSession()
Player.biking, session.biking, game.save.biking = true, true, true
session.map = gate2F.id
Runtime.start(nil, game, session, { alreadyOnMap = true })
check(Player.biking == false and session.biking == false,
  "resuming on gate 2F with stale road flag stays on foot")
Space.active = false

local InteractionScripts = require("src.core.game3.scripting.interaction_scripts")
local savedBehaviors = InteractionScripts.behaviors
InteractionScripts.behaviors = { outdoor = { [0x101] = 0xD0, [0x102] = 0xD1 }, indoor = { [0x101] = 0xD0 } }
local LayoutNative = require("src.core.game3.layout_native")
local function stubLayout(pair, mids)
  local cells = {}
  for cy = 0, 19 do
    for cx = 0, 19 do
      cells[cy * 20 + cx + 1] = { mid = mids[cx .. "," .. cy] or 0x001, coll = 0, elev = 0 }
    end
  end
  return LayoutNative.fromDecoded({ width = 20, height = 20, cells = cells }, pair .. "_stub", pair)
end
local route16Def = {
  id = "FR_ROUTE_16", bikingAllowed = 1, pair = "outdoor",
  midLayout = stubLayout("outdoor", { ["4,8"] = 0x101, ["5,8"] = 0x102 }),
}
local noBikeDef = {
  id = "FR_ROUTE16_NORTH_ENTRANCE_2F", bikingAllowed = 0, pair = "indoor",
  midLayout = stubLayout("indoor", { ["4,8"] = 0x101 }),
}
game.data.maps[route16Def.id] = route16Def
game.data.maps[noBikeDef.id] = noBikeDef
Space.store = { flags = {}, vars = {} }
session.flags = {}
session.store = { flags = {}, vars = {} }
Collision.behavior = function() return 0x00 end

check(Collision.behaviorOn(route16Def, 4, 8) == 0xD0 and Collision.behaviorOn(route16Def, 6, 8) == nil,
  "destination layout resolves the pull-down tile through behaviorOn")
check(Player.isOnCyclingRoad(session, 4, 8, route16Def) and not Player.isOnCyclingRoad(session, 6, 8, route16Def),
  "isOnCyclingRoad samples the destination map layout")

Player.biking, session.biking, game.save.biking = false, false, false
session.map = "FR_SAFFRON_CITY"
Map.load(nil, game, route16Def.id, { x = 4, y = 8, facing = "down" })
check(Player.biking == true and session.biking == true,
  "pull-down tile on the destination map promotes the bike on entry")

Player.biking, session.biking, game.save.biking = false, false, false
Map.load(nil, game, route16Def.id, { x = 5, y = 8, facing = "down" })
check(Player.biking == true, "pull-down grass tile on the destination map promotes the bike")

Player.biking, session.biking, game.save.biking = false, false, false
Map.load(nil, game, route16Def.id, { x = 6, y = 8, facing = "down" })
check(Player.biking == false, "plain tile on the same map does not promote the bike")

Player.biking, session.biking, game.save.biking = true, true, true
Map.load(nil, game, noBikeDef.id, { x = 4, y = 8, facing = "down" })
check(Player.biking == false and session.biking == false,
  "pull-down tile on a no-bike map still dismounts")

InteractionScripts.behaviors = savedBehaviors

print(string.format("=== RESULTS: %d passed, %d failed ===", passed, failed))
if failed > 0 then os.exit(1) end

