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

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL TOWN MAP & REGION MAP TESTS PASSED CLEANLY!")
end
