#!/usr/bin/env luajit
-- Kanto Town Map & Region Map Unit Test Suite

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

local RegionExtract = require("src.import.gba.region_map_extract")
local RegionMap = require("src.ui.game3.region_map")
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")

print("=== [TEST 1] Kanto Map Section Grid Resolution ===")
do
  -- 1. Pallet Town (x=4, y=11)
  local locPallet = RegionExtract.resolveLocation("PALLET_TOWN", nil)
  check(locPallet.x == 4 and locPallet.y == 11, "Pallet Town resolved to (4, 11)")
  check(locPallet.name == "PALLET TOWN", "Pallet Town name verified")

  -- 2. Viridian City (x=4, y=8)
  local locViridian = RegionExtract.resolveLocation("VIRIDIAN_CITY", nil)
  check(locViridian.x == 4 and locViridian.y == 8, "Viridian City resolved to (4, 8)")
  check(locViridian.name == "VIRIDIAN CITY", "Viridian City name verified")

  -- 3. Pewter City (x=4, y=4)
  local locPewter = RegionExtract.resolveLocation("PEWTER_CITY", nil)
  check(locPewter.x == 4 and locPewter.y == 4, "Pewter City resolved to (4, 4)")

  -- 4. Cerulean City (x=14, y=3)
  local locCerulean = RegionExtract.resolveLocation("CERULEAN_CITY", nil)
  check(locCerulean.x == 14 and locCerulean.y == 3, "Cerulean City resolved to (14, 3)")

  -- 5. Sub-location / Building (Red's House -> Pallet Town coords)
  local locHouse = RegionExtract.resolveLocation("REDS_HOUSE_1F", nil)
  check(locHouse.x == 4 and locHouse.y == 11, "Red's House maps to Pallet Town coordinates")

  -- 6. Dungeon (Viridian Forest -> 4, 6)
  local locForest = RegionExtract.resolveLocation("VIRIDIAN_FOREST", "MAPSEC_VIRIDIAN_FOREST")
  check(locForest.x == 4 and locForest.y == 6, "Viridian Forest maps to (4, 6)")
  check(locForest.name == "VIRIDIAN FOREST", "Viridian Forest name verified")
end

print("=== [TEST 2] RegionMap Interactive Cursor Navigation & Landmark Updates ===")
do
  local closed = false
  local session = { map = "PALLET_TOWN", gender = 0 }
  RegionMap.show({
    session = session,
    onClose = function() closed = true end,
  })

  check(RegionMap.isOpen() == true, "RegionMap is open")
  check(RegionMap.playerX == 4 and RegionMap.playerY == 11, "player location initialized at Pallet Town (4, 11)")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 11, "cursor location initialized at (4, 11)")
  check(RegionMap.currentLocationName() == "PALLET TOWN", "initial landmark name is PALLET TOWN")

  local function press(btn)
    local inp = {
      wasPressed = function(_, k) return k == btn end,
      isDown = function() return false end,
    }
    RegionMap.handleInput(inp)
  end

  -- Move UP: (4, 11) -> (4, 10) (Route 1)
  press("up")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 10, "cursor moved UP to (4, 10)")
  check(RegionMap.currentLocationName() == "ROUTE 1", "landmark name updated to ROUTE 1")

  -- Move UP twice: (4, 10) -> (4, 9) -> (4, 8) (Viridian City)
  press("up")
  press("up")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "cursor moved UP to (4, 8)")
  check(RegionMap.currentLocationName() == "VIRIDIAN CITY", "landmark name updated to VIRIDIAN CITY")

  -- Press B to close
  press("b")
  check(RegionMap.isOpen() == false, "RegionMap closed on B button")
  check(closed == true, "onClose callback executed")
end

print("=== [TEST 3] Inventory TOWN_MAP Item Use Integration ===")
do
  local bag = Bag.new()
  Bag.add(bag, 361, 1) -- Town Map
  local session = { map = "CELADON_CITY", bag = bag }

  local ok, reason, msg = ItemUse.useField(session, bag, 361, nil)
  check(ok == true, "ItemUse.useField accepts TOWN_MAP (item 361)")
  check(reason == "map", "useField returns 'map' reason")
  check(RegionMap.isOpen() == true, "RegionMap opened via ItemUse")
  check(RegionMap.playerX == 11 and RegionMap.playerY == 6, "player position placed at Celadon City (11, 6)")
  check(RegionMap.currentLocationName() == "CELADON CITY", "Celadon City landmark active")
  RegionMap.close()
  check(RegionMap.isOpen() == false, "RegionMap closed cleanly")
end

print("=== [TEST 4] Start Snapping & Dungeon Guide Modal ===")
do
  local session = { map = "VIRIDIAN_CITY", gender = 0 }
  RegionMap.show({ session = session })

  local function press(btn)
    local inp = {
      wasPressed = function(_, k) return k == btn end,
      isDown = function() return false end,
    }
    RegionMap.handleInput(inp)
  end

  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "cursor at Viridian City (4, 8)")

  -- Press START: Snaps to Cancel Button (21, 13)
  press("start")
  check(RegionMap.cursorX == 21 and RegionMap.cursorY == 13, "START snapped to Cancel button (21, 13)")

  -- Press START again: Snaps back to Player Icon (4, 8)
  press("start")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 8, "START snapped back to Player Icon (4, 8)")

  -- Move UP to (4, 6) (Viridian Forest dungeon)
  press("up")
  press("up")
  check(RegionMap.cursorX == 4 and RegionMap.cursorY == 6, "cursor at Viridian Forest (4, 6)")
  check(RegionMap.currentDungeonName() == "VIRIDIAN FOREST", "current dungeon is VIRIDIAN FOREST")

  -- pokefirered/src/region_map.c:1266
  press("a")
  check(RegionMap.previewDungeon == nil, "A on an unvisited dungeon opens no preview")
  check(RegionMap.isOpen() == true, "RegionMap stays open after the refused GUIDE")
  check(RegionMap.selectedDungeonMapsecType() == RegionMap.MAPSECTYPE.NOT_VISITED,
        "Viridian Forest is NOT_VISITED on a fresh save")
  check(RegionMap.canGuideCursor() == false, "GUIDE is refused on a dungeon that has not been visited")

  -- pokefirered/data/maps/ViridianForest/scripts.inc:6
  session.flags = session.flags or {}
  session.flags["FLAG_WORLD_MAP_VIRIDIAN_FOREST"] = true
  check(RegionMap.selectedDungeonMapsecType() == RegionMap.MAPSECTYPE.VISITED,
        "Viridian Forest is VISITED once the world map flag is set")
  check(RegionMap.canGuideCursor() == true, "GUIDE is offered on a visited dungeon")

  press("a")
  check(RegionMap.previewDungeon == "MAPSEC_VIRIDIAN_FOREST", "Dungeon Preview Modal opened for Viridian Forest")

  -- Press B on modal: Closes Dungeon Preview Modal
  press("b")
  check(RegionMap.previewDungeon == nil, "Dungeon Preview Modal closed on B")
  check(RegionMap.isOpen() == true, "RegionMap still open after closing modal")

  -- Press B on map: Closes RegionMap
  press("b")
  check(RegionMap.isOpen() == false, "RegionMap closed on B")
end

print("=== [TEST 5] Wall Town Map Metatile & Script Execution ===")
do
  local Interaction = require("src.core.game3.scripting.interaction_scripts")
  local Std = require("src.core.game3.scripting.stdscripts")
  local CollisionStd = require("src.core.game3.scripting.collision_std")

  local scriptKey = Interaction.scriptFor(0x85, "up")
  check(scriptKey == "EventScript_WallTownMap", "Behavior 0x85 (MB_TOWN_MAP) maps to EventScript_WallTownMap")

  local collScript = CollisionStd.scriptFor(0x95)
  check(collScript == "EventScript_WallTownMap", "COLL_TOWN_MAP (0x95) maps to EventScript_WallTownMap")

  local script = Std.SCRIPTS.EventScript_WallTownMap
  check(script ~= nil, "EventScript_WallTownMap is defined in Std.SCRIPTS")
  check(script[1].op == "lockall", "WallTownMap step 1 is lockall")
  check(script[4].op == "fadescreen", "WallTownMap step 4 is fadescreen")
  check(script[5].op == "special" and script[5].id == Std.SPECIAL.FieldShowRegionMap, "WallTownMap step 5 is special FieldShowRegionMap")

  local Adapters = require("src.core.game3.scripting.adapters")
  local hostAdapters = Adapters.host(nil, { session = { map = "VIRIDIAN_CITY" } }, nil)
  local mapOpened = false
  hostAdapters.showTownMap(function()
    mapOpened = true
  end)
  check(RegionMap.isOpen() == true, "adapters.showTownMap opens RegionMap")
  RegionMap.close()
  check(RegionMap.isOpen() == false, "RegionMap closed cleanly")
  check(mapOpened == true, "showTownMap callback was executed")
end

print("=== [TEST 6] RegionMapExtract ROM Extraction & CacheFS Assets Validation ===")
do
  local Rom = require("src.import.gba.rom")
  local FileIO = require("src.import.gba.file_io")

  local romPath = "1636 - Pokemon Fire Red (U)(Squirrels).gba"
  local f = io.open(romPath, "rb")
  if f then
    f:close()
    local imports = FileIO.makeImports(romPath, "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "firered")
    local rom = Rom.open(imports, "firered")
    check(rom ~= nil, "FireRed ROM opened")

    local mockCache = {
      files = {},
      write = function(self, path, data)
        self.files[path] = data
        return true
      end,
      read = function(self, path)
        return self.files[path]
      end,
      exists = function(self, path)
        return self.files[path] ~= nil
      end,
    }

    local detail = RegionExtract.run(rom, mockCache, { cacheRoot = "data/generated/gba" })
    check(detail.ok == true, "RegionMapExtract.run returned ok")
    -- src/region_map.c:424
    check(detail.count == 10, "Extracted 10 region map chrome assets")

    local kantoRgba = mockCache:read("data/generated/gba/region_map/kanto_map.rgba")
    check(kantoRgba ~= nil and #kantoRgba == 240 * 160 * 4, "kanto_map.rgba has exact 240x160x4 dimensions (153600 bytes)")

    local kantoPng = mockCache:read("data/generated/gba/region_map/kanto_map.png")
    check(kantoPng ~= nil and #kantoPng > 0, "kanto_map.png emitted")

    local curRgba = mockCache:read("data/generated/gba/region_map/cursor.rgba")
    check(curRgba ~= nil and #curRgba == 16 * 16 * 4, "cursor.rgba has exact 16x16x4 dimensions")

    local dungRgba = mockCache:read("data/generated/gba/region_map/dungeon_icon.rgba")
    check(dungRgba ~= nil and #dungRgba == 8 * 8 * 4, "dungeon_icon.rgba has exact 8x8x4 dimensions")

    local redRgba = mockCache:read("data/generated/gba/region_map/player_red.rgba")
    check(redRgba ~= nil and #redRgba == 16 * 16 * 4, "player_red.rgba has exact 16x16x4 dimensions")

    local leafRgba = mockCache:read("data/generated/gba/region_map/player_leaf.rgba")
    check(leafRgba ~= nil and #leafRgba == 16 * 16 * 4, "player_leaf.rgba has exact 16x16x4 dimensions")

    local sevii123Rgba = mockCache:read("data/generated/gba/region_map/sevii123_map.rgba")
    check(sevii123Rgba ~= nil and #sevii123Rgba == 240 * 160 * 4, "sevii123_map.rgba has exact 240x160x4 dimensions")

    local ready = RegionExtract.ready(mockCache, "data/generated/gba")
    check(ready == true, "RegionMapExtract.ready reports true on extracted cache")

    rom:clearCache()
    imports:_close()
  else
    print("[skip] FireRed ROM not found for extraction test")
  end
end

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL TOWN MAP & REGION MAP TESTS PASSED CLEANLY!")
end
