local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_town_map"

-- pokefirered/data/maps/PalletTown_RivalsHouse/scripts.inc:144
local ITEM_TOWN_MAP = 361

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS town_map")
    love.event.quit(0)
  else
    print("FAIL town_map failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local RegionMap = require("src.ui.game3.region_map")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TOWN_MAP, 1)

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "START opened the field menu") then return finish() end

  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  local entry = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
  if not result(entry and entry.id == "bag", "the START cursor reached BAG") then return finish() end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "BAG opened") then return finish() end

  for _ = 1, 4 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(15)
  end
  if not result(BagMenu.currentPocket() == "KEY_ITEMS",
      "walked to the KEY ITEMS pocket, at " .. tostring(BagMenu.currentPocket())) then
    return finish()
  end

  local function selectedName()
    local rows = BagMenu.list()
    local row = rows and rows[BagMenu.cursor]
    return row and tostring(row.name) or nil
  end
  for _ = 1, 20 do
    if selectedName() == "TOWN MAP" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  if not result(selectedName() == "TOWN MAP",
      "the bag cursor is on TOWN MAP, at " .. tostring(selectedName())) then
    return finish()
  end
  U.shot(game, DIR .. "/town_map_01_bag.png")

  U.tap(game, "a")
  U.wait(25)
  local firstAction = BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor]
  result(firstAction == "USE", "USE is the first key-item action, got " .. tostring(firstAction))
  U.tap(game, "a")
  U.wait(60)

  if not result(RegionMap.isOpen and RegionMap.isOpen(), "USE opened the Town Map") then
    return finish()
  end

  local images = RegionMap._images or {}
  local function loaded(key)
    return images[key] ~= nil and images[key] ~= false
  end
  for _, key in ipairs({ "kanto_map", "cursor", "dungeon_icon", "player_red" }) do
    result(loaded(key), "the ROM-baked " .. key .. " image is in use")
  end
  local mapImg = images["kanto_map"]
  if mapImg and mapImg.getWidth then
    result(mapImg:getWidth() == 240 and mapImg:getHeight() == 160,
      string.format("kanto_map is %dx%d", mapImg:getWidth(), mapImg:getHeight()))
  end
  local cursorImg = images["cursor"]
  if cursorImg and cursorImg.getWidth then
    result(cursorImg:getWidth() == 16 and cursorImg:getHeight() == 16,
      string.format("cursor is %dx%d", cursorImg:getWidth(), cursorImg:getHeight()))
  end

  result(RegionMap.currentLocationName() == "PALLET TOWN",
    "the Town Map opens on PALLET TOWN, got " .. tostring(RegionMap.currentLocationName()))
  U.wait(30)
  U.shot(game, DIR .. "/town_map_02_open.png")

  local startX, startY = RegionMap.cursorX, RegionMap.cursorY
  for _ = 1, 3 do
    U.tap(game, "up")
    U.wait(14)
  end
  for _ = 1, 10 do
    U.tap(game, "right")
    U.wait(14)
  end
  result(RegionMap.cursorX ~= startX or RegionMap.cursorY ~= startY,
    string.format("the cursor moved from (%d,%d) to (%d,%d)",
      startX, startY, RegionMap.cursorX, RegionMap.cursorY))
  print("[driver] cursor now on " .. tostring(RegionMap.currentLocationName()))
  U.wait(30)
  U.shot(game, DIR .. "/town_map_03_cursor_moved.png")

  -- src/region_map.c:2805
  U.tap(game, "b")
  U.wait(60)
  result(not (RegionMap.isOpen and RegionMap.isOpen()), "B closed the Town Map")

  finish()
end
