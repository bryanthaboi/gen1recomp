local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_town_map"

-- pokefirered/data/maps/PalletTown_RivalsHouse/scripts.inc:144
local ITEM_TOWN_MAP = 361
local FOREST, FOREST_X, FOREST_Y = "FR_VIRIDIAN_FOREST", 29, 61
local PALLET, PALLET_X, PALLET_Y = "FR_PALLET_TOWN", 5, 7

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import2_town_map")
    love.event.quit(0)
  else
    print("FAIL import2_town_map failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local RegionMap = require("src.ui.game3.region_map")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TOWN_MAP, 1)

  local function countFrames()
    local blob, ring = 0, 0
    for _, icon in ipairs(RegionMap.dungeonIcons()) do
      if icon.frame == 1 then ring = ring + 1 else blob = blob + 1 end
    end
    return blob, ring
  end

  local function openMap()
    local used = ItemUse.useField(session, session.bag, ITEM_TOWN_MAP)
    for _ = 1, 300 do
      if RegionMap.inputReady() then break end
      U.wait(1)
    end
    return used == true and RegionMap.isOpen and RegionMap.isOpen()
  end

  -- src/region_map.c:3011 GetDungeonMapsecType before the forest is entered
  result(RegionMap.dungeonIconFrame("MAPSEC_VIRIDIAN_FOREST") == 0,
    "VIRIDIAN FOREST starts on frame 0, the unvisited blob")

  if not result(openMap(), "the TOWN MAP opened the region map") then return finish() end

  local plain = RegionMap._images and RegionMap._images["dungeon_icon"]
  local visited = RegionMap.dungeonIconVisitedImage()
  result(plain ~= nil and plain ~= false, "the baked frame 0 marker loaded from the cache")
  result(visited ~= nil, "the baked frame 1 marker loaded from the cache")
  if plain and visited then
    result(plain:getWidth() == 8 and plain:getHeight() == 8,
      string.format("frame 0 is %dx%d", plain:getWidth(), plain:getHeight()))
    result(visited:getWidth() == 8 and visited:getHeight() == 8,
      string.format("frame 1 is %dx%d", visited:getWidth(), visited:getHeight()))
  end

  local blob0, ring0 = countFrames()
  print(string.format("[driver] before the forest: %d blobs, %d rings", blob0, ring0))
  result(blob0 > 10 and ring0 == 0, "every dungeon marker starts on frame 0")
  U.wait(20)
  U.shot(game, DIR .. "/import2_town_map_01_none_visited.png")

  U.tap(game, "b")
  for _ = 1, 200 do
    if not RegionMap.isOpen() then break end
    U.wait(1)
  end
  result(not (RegionMap.isOpen and RegionMap.isOpen()), "B closed the region map")

  -- pokefirered/data/maps/ViridianForest/scripts.inc:6 ON_TRANSITION setworldmapflag
  Map.load(nil, game, FOREST, { x = FOREST_X, y = FOREST_Y, facing = "up" })
  if game.session then
    game.session.x, game.session.y = FOREST_X, FOREST_Y
    game.session.facing = "up"
  end
  Player.cellX, Player.cellY = FOREST_X, FOREST_Y
  Player.px, Player.py = FOREST_X * 16, FOREST_Y * 16
  Player.targetX, Player.targetY = FOREST_X, FOREST_Y
  U.wait(120)
  result(RegionMap.isFlagSet("FLAG_WORLD_MAP_VIRIDIAN_FOREST") == true,
    "walking into VIRIDIAN FOREST ran setworldmapflag")
  result(RegionMap.dungeonIconFrame("MAPSEC_VIRIDIAN_FOREST") == 1,
    "VIRIDIAN FOREST is now frame 1, the visited ring")

  if not result(openMap(), "the TOWN MAP opened again from the forest") then return finish() end
  local blob1, ring1 = countFrames()
  print(string.format("[driver] after the forest: %d blobs, %d rings", blob1, ring1))
  result(ring1 == 1 and blob1 == blob0 - 1,
    string.format("exactly one marker flipped to the ring (%d rings, %d blobs)", ring1, blob1))
  -- src/data/region_map/region_map_layout_kanto.h:28
  result(RegionMap.currentLocationName() == "ROUTE 2",
    "the cursor sits on the ROUTE 2 cell, got " .. tostring(RegionMap.currentLocationName()))
  result(RegionMap.currentDungeonName() == "VIRIDIAN FOREST",
    "the dungeon line under it reads VIRIDIAN FOREST, got "
      .. tostring(RegionMap.currentDungeonName()))
  U.wait(20)
  U.shot(game, DIR .. "/import2_town_map_02_forest_visited.png")

  U.tap(game, "b")
  for _ = 1, 200 do
    if not RegionMap.isOpen() then break end
    U.wait(1)
  end

  Map.load(nil, game, PALLET, { x = PALLET_X, y = PALLET_Y, facing = "down" })
  if game.session then
    game.session.x, game.session.y = PALLET_X, PALLET_Y
    game.session.facing = "down"
  end
  Player.cellX, Player.cellY = PALLET_X, PALLET_Y
  Player.px, Player.py = PALLET_X * 16, PALLET_Y * 16
  Player.targetX, Player.targetY = PALLET_X, PALLET_Y
  U.wait(120)
  if not result(openMap(), "the TOWN MAP opened back in PALLET TOWN") then return finish() end
  local blob2, ring2 = countFrames()
  result(ring2 == 1 and blob2 == blob1,
    string.format("the ring survives the walk back (%d rings, %d blobs)", ring2, blob2))
  result(RegionMap.currentLocationName() == "PALLET TOWN",
    "the player icon is back on PALLET TOWN, got " .. tostring(RegionMap.currentLocationName()))
  U.wait(20)
  U.shot(game, DIR .. "/import2_town_map_03_both_frames.png")

  U.tap(game, "b")
  for _ = 1, 200 do
    if not RegionMap.isOpen() then break end
    U.wait(1)
  end
  finish()
end
