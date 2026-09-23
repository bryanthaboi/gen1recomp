#!/usr/bin/env luajit
-- Kanto Town Map & Region Map Unit Test Suite

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("town_map")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local played = {}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) played[#played + 1] = id end,
  stopSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local RegionExtract = require("src.import.gba.region_map_extract")
local RegionMap = require("src.ui.game3.region_map")
local Position = require("src.ui.game3.region_map_position")
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local Dataset = require("src.core.game3.dataset")
local DEFS = Dataset.buildMaps()
require("src.core.game3.runtime")._game = { data = { maps = DEFS } }

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
local function runUntil(cond)
  for _ = 1, 400 do
    if cond() then return true end
    frame()
  end
  return cond()
end

local function cell(session)
  RegionExtract.ensureGenerated()
  session.def = function(id) return assert(DEFS[id], id) end
  return Position.playerCell(session, RegionExtract.GEOMETRY)
end

print("=== [TEST 1] GetPlayerPositionOnRegionMap ===")
do
  -- src/region_map.c:3096
  local x, y = cell({ map = "FR_PALLET_TOWN", x = 10, y = 8 })
  check(x == 4 and y == 11, "Pallet Town resolves to (4, 11)")
  x, y = cell({ map = "FR_VIRIDIAN_CITY", x = 20, y = 20 })
  check(x == 4 and y == 8, "Viridian City resolves to (4, 8)")
  x, y = cell({ map = "FR_PEWTER_CITY", x = 20, y = 20 })
  check(x == 4 and y == 4, "Pewter City resolves to (4, 4)")
  x, y = cell({ map = "FR_CERULEAN_CITY", x = 20, y = 20 })
  check(x == 14 and y == 3, "Cerulean City resolves to (14, 3)")
  -- src/region_map.c:3138
  x, y = cell({ map = "FR_PLAYERS_HOUSE_1F", x = 3, y = 3, escapeWarp = { map = "FR_PALLET_TOWN", x = 6, y = 8 } })
  check(x == 4 and y == 11, "the player's house resolves through the escape warp to Pallet Town")
  -- src/region_map.c:3271
  x, y = cell({ map = "FR_VIRIDIAN_FOREST", x = 30, y = 30 })
  check(x == 4 and y == 6, "Viridian Forest uses its override (4, 6)")
  -- src/region_map.c:3291-3301
  x, y = cell({ map = "FR_ROUTE_21_NORTH", x = 5, y = 5 })
  check(x == 4 and y == 12, "Route 21 North uses its override (4, 12)")
  -- src/region_map.c:3158-3171
  local tx, ty = cell({ map = "FR_ROUTE_1", x = 10, y = 0 })
  local bx, by = cell({ map = "FR_ROUTE_1", x = 10, y = 39 })
  check(tx == bx and ty < by, "Route 1 scales the player's y into its section")
  local secTop = RegionExtract.LAYOUTS[0].map[ty][tx]
  local secBottom = RegionExtract.LAYOUTS[0].map[by][bx]
  check(secTop == secBottom and RegionExtract.KANTO_GRID[ty][tx] == "MAPSEC_ROUTE_1", "both ends stay on ROUTE 1")
  -- src/region_map.c:3121
  x, y = cell({ map = "FR_MT_MOON_1F", x = 10, y = 10, escapeWarp = { map = "FR_ROUTE_4", x = 19, y = 5 } })
  check(RegionExtract.KANTO_GRID[y][x] == "MAPSEC_ROUTE_4", "Mt. Moon places the player on ROUTE 4 through the escape warp")
  -- src/region_map.c:1030-1049
  check(Position.regionFor(DEFS.FR_FOUR_ISLAND.regionMapSectionId, RegionExtract.LAYOUTS) == 2,
    "Four Island belongs to the SEVII 4-5 map")
  check(Position.regionFor(DEFS.SEVII_ONE_ISLAND.regionMapSectionId, RegionExtract.LAYOUTS) == 1,
    "One Island belongs to the SEVII 1-2-3 map")
  check(Position.regionFor(DEFS.FR_SEVEN_ISLAND.regionMapSectionId, RegionExtract.LAYOUTS) == 3,
    "Seven Island belongs to the SEVII 6-7 map")
  check(Position.regionFor(DEFS.FR_PALLET_TOWN.regionMapSectionId, RegionExtract.LAYOUTS) == 0,
    "Pallet Town belongs to Kanto")
end

print("=== [TEST 2] RegionMap Interactive Cursor Navigation & Landmark Updates ===")
do
  local closed = false
  local session = { map = "FR_PALLET_TOWN", x = 10, y = 8, gender = 0 }
  RegionMap.show({
    session = session,
    onClose = function() closed = true end,
  })

  check(RegionMap.isOpen() == true, "RegionMap is open")
  check(settle(), "the open animation reaches the input state")
  check(RegionMap.playerX == 4 and RegionMap.playerY == 11, "player location initialized at Pallet Town (4, 11)")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 11, "cursor location initialized at (4, 11)")
  check(RegionMap.currentLocationName() == "PALLET TOWN", "initial landmark name is PALLET TOWN")

  -- src/region_map.c:2754 HandleRegionMapInput, :2836 MoveMapCursor
  frame({ wasPressed = function() return false end, isDown = function(_, k) return k == "up" end })
  check(RegionMap.cursorY == 11, "a held direction slides the cursor before it moves a cell")
  for _ = 1, 3 do frame() end
  check(RegionMap.cursorY == 11, "the slide takes four frames")
  played = {}
  frame()
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 10, "cursor moved UP to (4, 10)")
  check(RegionMap.currentLocationName() == "ROUTE 1", "landmark name updated to ROUTE 1")
  check(#played == 0, "a route plays no scroll sound")

  press("up")
  played = {}
  press("up")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "cursor moved UP to (4, 8)")
  check(RegionMap.currentLocationName() == "VIRIDIAN CITY", "landmark name updated to VIRIDIAN CITY")
  -- src/region_map.c:1174
  check(played[1] == 101, "a town plays SE_DEX_SCROLL")

  frame({ wasPressed = function(_, k) return k == "up" or k == "right" end,
    isDown = function(_, k) return k == "up" or k == "right" end })
  for _ = 1, 4 do frame() end
  check(RegionMap.cursorX == 5 and RegionMap.cursorY == 7, "a diagonal hold moves both axes at once")

  check(RegionMap.state().palTinted == true, "the open map draws the 95% tinted bank 2")
  frame({ wasPressed = function(_, k) return k == "b" end, isDown = function(_, k) return k == "b" end })
  local tintOk, sawClose, sawUntinted = true, false, false
  for _ = 1, 400 do
    local s = RegionMap.state()
    if not s then break end
    if s.task == "mapCloseAnim" then
      sawClose = true
      local cs = s.anim.closeState
      if cs <= 2 and s.palTinted ~= true then tintOk = false end
      if cs >= 3 then
        if s.palTinted ~= false then tintOk = false end
        sawUntinted = true
      end
    elseif sawClose and s.palTinted ~= false then
      tintOk = false
    end
    frame()
  end
  -- src/region_map.c:2572
  check(sawClose and sawUntinted and tintOk, "close state 2 reloads sRegionMap_Pal untinted and it stays untinted")
  check(not RegionMap.isOpen(), "B runs the close animation and fade")
  check(closed == true, "onClose callback executed")
  RegionMap.show({ session = session })
  check(RegionMap.state().palTinted == true, "the next show draws tinted again")
  RegionMap.close()
end

print("=== [TEST 3] Inventory TOWN_MAP Item Use Integration ===")
do
  local bag = Bag.new()
  Bag.add(bag, 361, 1) -- Town Map
  local session = { map = "FR_CELADON_CITY", x = 30, y = 20, bag = bag }

  local ok, reason = ItemUse.useField(session, bag, 361, nil)
  check(ok == true, "ItemUse.useField accepts TOWN_MAP (item 361)")
  check(reason == "map", "useField returns 'map' reason")
  check(RegionMap.isOpen() == true, "RegionMap opened via ItemUse")
  settle()
  check(RegionMap.playerX == 11 and RegionMap.playerY == 6, "player position placed at Celadon City (11, 6)")
  check(RegionMap.currentLocationName() == "CELADON CITY", "Celadon City landmark active")
  -- src/region_map.c:2819
  check(RegionMap.state().fromField == true, "no BAG is open, so this is the field Town Map")
  press("select")
  check(runUntil(function() return not RegionMap.isOpen() end), "SELECT closes the field Town Map")
end

print("=== [TEST 4] Start Snapping & Dungeon Guide Modal ===")
do
  local session = { map = "FR_VIRIDIAN_CITY", x = 20, y = 20, gender = 0 }
  RegionMap.show({ session = session })
  settle()

  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "cursor at Viridian City (4, 8)")

  press("start")
  check(RegionMap.cursorX == 21 and RegionMap.cursorY == 13, "START snapped to Cancel button (21, 13)")
  local _, right = RegionMap.topBarText()
  check(right == "gText_RegionMap_AButtonCancel", "the top bar offers A CANCEL")

  press("start")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "START snapped back to Player Icon (4, 8)")

  press("up")
  press("up")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 6, "cursor at Viridian Forest (4, 6)")
  check(RegionMap.currentDungeonName() == "VIRIDIAN FOREST", "current dungeon is VIRIDIAN FOREST")
  check(RegionMap.state().text.dungeonType == RegionMap.MAPSECTYPE.NOT_VISITED,
    "the unvisited dungeon name uses the red text colour")

  press("a")
  check(RegionMap.previewDungeon == nil, "A on an unvisited dungeon opens no preview")
  check(RegionMap.isOpen() == true, "RegionMap stays open after the refused GUIDE")
  check(RegionMap.canGuideCursor() == false, "GUIDE is refused on a dungeon that has not been visited")

  -- pokefirered/data/maps/ViridianForest/scripts.inc:6
  session.flags = session.flags or {}
  session.flags["FLAG_WORLD_MAP_VIRIDIAN_FOREST"] = true
  check(RegionMap.canGuideCursor() == true, "GUIDE is offered on a visited dungeon")

  played = {}
  press("a", 0)
  check(RegionMap.previewDungeon == "MAPSEC_VIRIDIAN_FOREST", "Dungeon Preview Modal opened for Viridian Forest")
  -- src/region_map.c:2021-2030
  press("b", 20)
  check(RegionMap.previewDungeon == "MAPSEC_VIRIDIAN_FOREST", "B is ignored until the flavour text is printed")
  check(runUntil(function() local s = RegionMap.state() return s.preview and s.preview.text ~= nil end),
    "the GUIDE prints its text")
  press("b")
  check(runUntil(function() return RegionMap.previewDungeon == nil end), "B shrinks and closes the GUIDE")
  check(#played == 0, "the GUIDE plays no sound effects")
  check(RegionMap.isOpen() == true, "RegionMap still open after closing modal")
  settle()

  press("b")
  runUntil(function() return not RegionMap.isOpen() end)
  check(RegionMap.isOpen() == false, "RegionMap closed on B")
end

print("=== [TEST 5] Wall Town Map Metatile & Script Execution ===")
do
  local Interaction = require("src.core.game3.scripting.interaction_scripts")
  local CollisionStd = require("src.core.game3.scripting.collision_std")

  local scriptKey = Interaction.scriptFor(0x85, "up")
  check(scriptKey == "EventScript_WallTownMap", "Behavior 0x85 (MB_TOWN_MAP) maps to EventScript_WallTownMap")

  local collScript = CollisionStd.scriptFor(0x95)
  check(collScript == "EventScript_WallTownMap", "COLL_TOWN_MAP (0x95) maps to EventScript_WallTownMap")

  local Adapters = require("src.core.game3.scripting.adapters")
  local session = { map = "FR_VIRIDIAN_CITY", x = 20, y = 20 }
  package.loaded["src.core.game3.runtime"].getSession = function() return session end
  local hostAdapters = Adapters.host(nil, { session = session }, nil)
  local mapOpened = false
  hostAdapters.showTownMap(function()
    mapOpened = true
  end)
  check(RegionMap.isOpen() == true, "adapters.showTownMap opens RegionMap")
  RegionMap.close()
  check(RegionMap.isOpen() == false, "RegionMap closed cleanly")
  check(mapOpened == true, "showTownMap callback was executed")
end

print("=== [TEST 6] The Sevii maps (#2430) ===")
do
  RegionMap.show({ session = { map = "FR_FOUR_ISLAND", x = 12, y = 14 } })
  settle()
  check(RegionMap.state().selectedRegion == 2, "the Town Map on Four Island shows SEVII 4-5")
  check(RegionMap.currentLocationName() == "FOUR ISLAND", "and the cursor starts on FOUR ISLAND")
  RegionMap.close()
  for _, m in ipairs({ "FR_FOUR_ISLAND_POKEMON_CENTER_1F", "FR_FOUR_ISLAND_ICEFALL_CAVE_ENTRANCE", "FR_FOUR_ISLAND_ICEFALL_CAVE_BACK" }) do
    RegionMap.show({ session = { map = m, x = 5, y = 5 } })
    settle()
    check(RegionMap.state().selectedRegion == 2, m .. " opens SEVII 4-5")
    RegionMap.close()
  end
end

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL TOWN MAP & REGION MAP TESTS PASSED CLEANLY!")
end
