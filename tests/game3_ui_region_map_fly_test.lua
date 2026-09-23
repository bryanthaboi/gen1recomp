#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("ui_region_map_fly")

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

local played = {}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) played[#played + 1] = id end,
  stopSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local RegionMap = require("src.ui.game3.region_map")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Dataset = require("src.core.game3.dataset")
require("src.core.game3.runtime")._game = { data = { maps = Dataset.buildMaps() } }

local SECTYPE = RegionMap.MAPSECTYPE
local PALLET = { map = "FR_PALLET_TOWN", x = 10, y = 8, gender = 0 }

Space.store = Flags.newStore()
local function setWorldMapFlag(name)
  Flags.setFlag(Space.store, nil, name, true)
end

local IDLE = { wasPressed = function() return false end, isDown = function() return false end }
local function frame(input) RegionMap.handleInput(input or IDLE) end
local function settle()
  for _ = 1, 400 do
    if RegionMap.inputReady() then return true end
    frame()
  end
  return false
end
local function press(btn, frames)
  frame({ wasPressed = function(_, k) return k == btn end, isDown = function(_, k) return k == btn end })
  for _ = 1, frames or 5 do frame() end
end
local function runUntilClosed()
  for _ = 1, 400 do
    if not RegionMap.isOpen() then return true end
    frame()
  end
  return false
end
local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

print("[test] 1. mapsec types follow the FLAG_WORLD_MAP_* flags")
eq(RegionMap.mapsecType("MAPSEC_PALLET_TOWN"), SECTYPE.NOT_VISITED,
  "Pallet Town is NOT_VISITED on a fresh store")
eq(RegionMap.mapsecType("MAPSEC_ROUTE_1"), SECTYPE.ROUTE, "Route 1 is a route")
eq(RegionMap.mapsecType(nil), SECTYPE.NONE, "an empty cell is NONE")
setWorldMapFlag("FLAG_WORLD_MAP_PALLET_TOWN")
setWorldMapFlag("FLAG_WORLD_MAP_VIRIDIAN_CITY")
eq(RegionMap.mapsecType("MAPSEC_PALLET_TOWN"), SECTYPE.VISITED,
  "Pallet Town is VISITED once its world map flag is set")
eq(RegionMap.mapsecType("MAPSEC_PEWTER_CITY"), SECTYPE.NOT_VISITED,
  "Pewter City is still NOT_VISITED")

print("[test] 2. viewer mode is unchanged")
do
  local closedWith, closedCalls = "unset", 0
  RegionMap.show({
    session = copy(PALLET),
    onClose = function(v) closedWith = v; closedCalls = closedCalls + 1 end,
  })
  settle()
  check(RegionMap.isFlyMode() == false, "show() with no mode is the viewer")
  check(RegionMap.hasFlyDestinations() == false, "the viewer has no fly destinations")
  eq(RegionMap.mapsecType("MAPSEC_ROUTE_4_POKECENTER"), SECTYPE.NONE,
    "the Route 4 Pokemon Center cell is NONE off the fly map")
  eq(#RegionMap.flyTargets(), 0, "the viewer places no fly icons")
  press("up")
  press("up")
  press("up")
  eq(RegionMap.cursorY, 8, "cursor walked up to Viridian City")
  press("up")
  press("up")
  -- pokefirered/src/region_map.c:1266
  press("a")
  eq(RegionMap.previewDungeon, nil, "an unvisited dungeon refuses the GUIDE preview")
  setWorldMapFlag("FLAG_WORLD_MAP_VIRIDIAN_FOREST")
  press("a")
  eq(RegionMap.previewDungeon, "MAPSEC_VIRIDIAN_FOREST", "A still opens the GUIDE preview")
  RegionMap.close()
  eq(closedCalls, 1, "onClose ran once")
  eq(closedWith, nil, "onClose was handed nil")
end

print("[test] 3. fly mode picks only flagged mapsecs")
do
  local picked, pickedId, pickCalls, closedCalls = "unset", "unset", 0, 0
  RegionMap.show({
    mode = "fly",
    session = copy(PALLET),
    onPick = function(sec, id) picked = sec; pickedId = id; pickCalls = pickCalls + 1 end,
    onClose = function() closedCalls = closedCalls + 1 end,
  })
  settle()
  check(RegionMap.isFlyMode() == true, "mode = fly is the fly map")
  eq(RegionMap.mapsecType("MAPSEC_ROUTE_4_POKECENTER"), SECTYPE.NOT_VISITED,
    "the Route 4 Pokemon Center cell exists on the fly map")
  eq(RegionMap.cursorX .. "," .. RegionMap.cursorY, "4,11", "the cursor starts on the player")
  local _, right = RegionMap.topBarText()
  eq(right, "gText_RegionMap_AButtonOK", "the fly map opens with A OK on the top bar")

  local targets = RegionMap.flyTargets()
  eq(#targets, 2, "two towns carry a fly icon")
  local seen = {}
  for _, t in ipairs(targets) do seen[t.sec] = t.x .. "," .. t.y end
  eq(seen["MAPSEC_PALLET_TOWN"], "4,11", "Pallet Town has a fly icon")
  eq(seen["MAPSEC_VIRIDIAN_CITY"], "4,8", "Viridian City has a fly icon")
  eq(seen["MAPSEC_PEWTER_CITY"], nil, "unvisited Pewter City has none")

  press("up")
  eq(RegionMap.cursorY, 10, "the cursor moves onto Route 1")
  check(RegionMap.canFlyToCursor() == false, "a route is not a fly target")
  press("a")
  eq(pickCalls, 0, "A on a route picks nothing")
  check(RegionMap.isOpen() == true, "A on a route leaves the map open")

  press("up")
  played = {}
  press("up")
  -- src/region_map.c:3933
  eq(played[1], 102, "a visited town plays SE_DEX_PAGE on the fly map")
  check(RegionMap.canFlyToCursor() == true, "Viridian City is a fly target")
  played = {}
  press("a", 0)
  eq(played[1], 1, "the pick plays SE_USE_ITEM")
  eq(pickCalls, 0, "the pick waits for the fade to black")
  check(runUntilClosed(), "the fly map closed after the fade")
  eq(pickCalls, 1, "A on a visited town calls onPick once")
  eq(picked, "MAPSEC_VIRIDIAN_CITY",
    "onPick receives the symbolic mapsec, the key fly_destinations.lua is built on")
  eq(pickedId, 89, "the numeric mapsec follows as the second argument")
  eq(closedCalls, 0, "onClose does not also fire on a pick")
  check(RegionMap.isFlyMode() == false, "the module falls back to viewer mode")

  -- pokefirered/src/region_map.c:4022
  local Field = require("src.core.game3.field")
  local dest = Field.flyDestination(picked)
  check(dest ~= nil, "the picked mapsec is a key of the field's fly destination table")
  eq(dest and dest.map, "FR_VIRIDIAN_CITY", "and it resolves to Viridian City")
end

print("[test] 3b. a failing consumer raises")
do
  local closedCalls = 0
  RegionMap.show({
    mode = "fly",
    session = copy(PALLET),
    onPick = function() error("consumer blew up") end,
    onClose = function() closedCalls = closedCalls + 1 end,
  })
  settle()
  press("up")
  press("up")
  press("up")
  check(RegionMap.canFlyToCursor() == true, "the cursor is on a fly target")
  local ok = pcall(function()
    press("a")
    runUntilClosed()
  end)
  check(ok == false, "onPick's error reaches the caller")
  eq(closedCalls, 0, "onClose does not swallow it")
  check(RegionMap.isOpen() == false, "the fly map still closed")
end

print("[test] 4. an unvisited town refuses, B cancels")
do
  local pickCalls, closedCalls, closedWith = 0, 0, "unset"
  RegionMap.show({
    mode = "fly",
    session = copy(PALLET),
    onPick = function() pickCalls = pickCalls + 1 end,
    onClose = function(v) closedCalls = closedCalls + 1; closedWith = v end,
  })
  settle()
  for _ = 1, 7 do press("up") end
  eq(RegionMap.cursorY, 4, "the cursor reached Pewter City")
  check(RegionMap.canFlyToCursor() == false, "an unvisited town is not selectable")
  press("a")
  eq(pickCalls, 0, "A on an unvisited town picks nothing")
  check(RegionMap.isOpen() == true, "the map stays open")
  press("b")
  check(runUntilClosed(), "B closes the fly map")
  eq(pickCalls, 0, "B picked nothing")
  eq(closedCalls, 1, "B ran onClose once")
  eq(closedWith, nil, "B handed onClose nil")
end

print("[test] 5. fly-map quirks: SELECT, START, the GUIDE")
do
  local pickCalls = 0
  RegionMap.show({
    mode = "fly",
    session = copy(PALLET),
    onPick = function() pickCalls = pickCalls + 1 end,
  })
  settle()
  press("select")
  check(RegionMap.isOpen() == true, "SELECT does not cancel the fly map")
  for _ = 1, 5 do press("up") end
  eq(RegionMap.cursorY, 6, "the cursor reached Viridian Forest")
  press("a")
  eq(RegionMap.previewDungeon, nil, "the fly map never opens the GUIDE")
  eq(pickCalls, 0, "a dungeon cell is not a fly target")
  played = {}
  press("start")
  eq(RegionMap.cursorX .. "," .. RegionMap.cursorY, "21,13", "START snapped to CANCEL")
  eq(played[#played], 225, "landing on CANCEL plays SE_M_SPIT_UP")
  -- src/region_map.c:3937
  press("start")
  eq(RegionMap.cursorX .. "," .. RegionMap.cursorY, "21,13", "the fly map's START keeps snapping to CANCEL")
  press("a")
  check(runUntilClosed(), "A on CANCEL closes the fly map")
  eq(pickCalls, 0, "A on CANCEL picks nothing")
end

print("[test] 6. indoors and underground refuse the destination")
do
  local pickCalls, closedCalls = 0, 0
  local indoor = { map = "FR_PLAYERS_HOUSE_1F", x = 3, y = 3, escapeWarp = { map = "FR_PALLET_TOWN", x = 6, y = 8 } }
  RegionMap.show({
    mode = "fly",
    session = indoor,
    onPick = function() pickCalls = pickCalls + 1 end,
    onClose = function() closedCalls = closedCalls + 1 end,
  })
  settle()
  check(RegionMap.flyBlockedByMapType() == true, "MAP_TYPE_INDOOR blocks the warp")
  check(RegionMap.canFlyToCursor() == true, "the target itself is still valid")
  played = {}
  press("a")
  runUntilClosed()
  eq(pickCalls, 0, "A indoors picks nothing")
  eq(#played, 0, "and plays no SE_USE_ITEM")
  eq(closedCalls, 1, "A indoors drops back through onClose")
  check(RegionMap.isOpen() == false, "the fly map closed")

  RegionMap.show({ mode = "fly", session = { map = "FR_MT_MOON_1F", x = 5, y = 5,
    escapeWarp = { map = "FR_ROUTE_4", x = 19, y = 5 } } })
  check(RegionMap.flyBlockedByMapType() == true, "MAP_TYPE_UNDERGROUND blocks the warp too")
  RegionMap.close()
  RegionMap.show({ mode = "fly", session = { map = "FR_ROUTE_1", x = 5, y = 5 } })
  check(RegionMap.flyBlockedByMapType() == false, "MAP_TYPE_ROUTE does not block")
  RegionMap.close()
end

print("[test] 7. the fly icon blinks frame 0 then frame 1")
do
  RegionMap.show({ mode = "fly", session = copy(PALLET) })
  for _ = 1, 400 do
    if RegionMap.state().icons.flyAnimStart then break end
    frame()
  end
  eq(RegionMap.flyIconFrame(), 0, "the icon starts on frame 0")
  for _ = 1, 29 do frame() end
  eq(RegionMap.flyIconFrame(), 0, "frame 0 holds for 30 ticks")
  frame()
  eq(RegionMap.flyIconFrame(), 1, "frame 1 takes over at tick 30")
  for _ = 1, 59 do frame() end
  eq(RegionMap.flyIconFrame(), 1, "frame 1 holds for 60 ticks")
  frame()
  eq(RegionMap.flyIconFrame(), 0, "the 90 tick cycle wraps to frame 0")
  RegionMap.close()
end

print("[test] 8. dungeon markers carry a visited frame")
do
  Space.store = Flags.newStore()
  eq(RegionMap.dungeonMapsecType("MAPSEC_VIRIDIAN_FOREST"), SECTYPE.NOT_VISITED,
    "Viridian Forest is NOT_VISITED on a fresh store")
  eq(RegionMap.dungeonIconFrame("MAPSEC_VIRIDIAN_FOREST"), 0, "it draws marker frame 0")
  setWorldMapFlag("FLAG_WORLD_MAP_VIRIDIAN_FOREST")
  eq(RegionMap.dungeonMapsecType("MAPSEC_VIRIDIAN_FOREST"), SECTYPE.VISITED,
    "the world map flag marks it VISITED")
  eq(RegionMap.dungeonIconFrame("MAPSEC_VIRIDIAN_FOREST"), 1, "it draws marker frame 1")
  eq(RegionMap.dungeonIconFrame("MAPSEC_MT_MOON"), 0, "Mt. Moon is still on frame 0")
  eq(RegionMap.dungeonIconFrame(nil), 0, "an empty cell asks for frame 0")

  eq(RegionMap.dungeonIconOffset(4, 14), 2,
    "the Pokemon Mansion marker is offset into Cinnabar Island's corner")
  eq(RegionMap.dungeonIconOffset(18, 3), 0,
    "the Rock Tunnel marker on the Route 10 Pokemon Center is not offset")
  eq(RegionMap.dungeonIconOffset(9, 3), 0, "the Mt. Moon marker on Route 4 is not offset")
  eq(RegionMap.dungeonIconOffset(12, 12), 2, "the Safari Zone marker sits in Fuchsia City")

  eq(RegionMap.dungeonSecAt(14, 3), nil, "Cerulean Cave is hidden without the RS link")
  setWorldMapFlag("FLAG_SYS_CAN_LINK_WITH_RS")
  eq(RegionMap.dungeonSecAt(14, 3), "MAPSEC_CERULEAN_CAVE",
    "the RS link reveals the Cerulean Cave marker")
end

print("[test] 9. START snap order and dungeon icon origin")
do
  local function at() return RegionMap.cursorX .. "," .. RegionMap.cursorY end
  RegionMap.show({ session = copy(PALLET) })
  settle()
  local home = at()
  check(RegionMap.hasSwitchButton() == false, "no switch button before the Sevii map")
  press("start")
  eq(at(), "21,13", "no switch button: START snaps to CANCEL")
  press("start")
  eq(at(), home, "then back to the player")
  RegionMap.close()

  setWorldMapFlag("FLAG_SYS_SEVII_MAP_123")
  RegionMap.show({ session = copy(PALLET) })
  settle()
  check(RegionMap.hasSwitchButton() == true, "the Sevii flag adds the switch button")
  press("start")
  eq(at(), "21,11", "switch button: START snaps to SWITCH first")
  press("start")
  eq(at(), "21,13", "then CANCEL")
  press("start")
  eq(at(), home, "then back to the player")

  local found = false
  for _, icon in ipairs(RegionMap.dungeonIcons()) do
    if icon.px == 32 + 4 * 8 + 2 and icon.py == 32 + 14 * 8 + 2 then found = true end
  end
  check(found, "the Pokemon Mansion marker sits at 8x+32+offset")
  RegionMap.close()
end

print("[test] 10. the fly map stays on the player's Sevii map")
do
  -- src/region_map.c:1028-1049, :3558, :3903
  setWorldMapFlag("FLAG_WORLD_MAP_ONE_ISLAND")
  local picked = nil
  RegionMap.show({ mode = "fly", session = { map = "SEVII_ONE_ISLAND", x = 12, y = 12 },
    onPick = function(sec) picked = sec end })
  settle()
  eq(RegionMap.state().selectedRegion, 1, "One Island opens the SEVII 1-2-3 fly map")
  eq(RegionMap.currentLocationName(), "ONE ISLAND", "the cursor starts on ONE ISLAND")
  local seen = {}
  for _, t in ipairs(RegionMap.flyTargets()) do seen[t.sec] = true end
  check(seen["MAPSEC_ONE_ISLAND"] == true, "One Island carries a fly icon")
  check(seen["MAPSEC_PALLET_TOWN"] == nil and seen["MAPSEC_VIRIDIAN_CITY"] == nil,
    "no Kanto town is offered from the Sevii Islands")
  eq(RegionMap.hasSwitchButton(), false, "the fly map has no SWITCH button")
  press("a")
  runUntilClosed()
  eq(picked, "MAPSEC_ONE_ISLAND", "One Island can be picked")
end

print("[test] 11. the switch menu")
do
  -- src/region_map.c:1553-1917
  setWorldMapFlag("FLAG_SYS_SEVII_MAP_4567")
  RegionMap.show({ session = copy(PALLET) })
  settle()
  press("start")
  played = {}
  press("a", 0)
  eq(played[1], 240, "A on SWITCH plays SE_M_HYPER_BEAM2")
  local s = RegionMap.state()
  for _ = 1, 100 do
    if s.switch and s.switch.mainState == 9 then break end
    frame()
  end
  eq(s.switch and s.switch.maxSelection, 3, "FLAG_SYS_SEVII_MAP_4567 offers four maps")
  local left, right = RegionMap.topBarText()
  eq(left, "gText_RegionMap_UpDownPick", "the top bar reads PICK")
  eq(right, "gText_RegionMap_AButtonOK", "and A OK")
  played = {}
  press("down", 0)
  eq(played[1], 245, "moving the pick plays SE_BAG_CURSOR")
  press("down", 0)
  eq(s.switch.currentSelection, 2, "the pick moved to SEVII 4-5")
  eq(s.bg0.region, 2, "the map behind follows the pick")
  check(s.player.visible == false, "the player icon hides off the player's map")
  played = {}
  press("a", 0)
  eq(played[1], 199, "A plays SE_M_SWIFT")
  for _ = 1, 100 do
    if s.switch == nil then break end
    frame()
  end
  eq(s.selectedRegion, 2, "the Town Map switched to SEVII 4-5")
  left, right = RegionMap.topBarText()
  eq(right, "gText_RegionMap_AButtonSwitch", "the top bar is back to A SWITCH")
  check(s.bg0.navelPatch == true, "Navel Rock stays hidden until it is visited")
  RegionMap.close()
end

if failed > 0 then
  print(failed .. " CHECK(S) FAILED")
  os.exit(1)
end
print("ALL REGION MAP FLY TESTS PASSED")
