local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_bag_use"

-- pokefirered/include/constants/items.h:90
local ITEM_REPEL = 86
-- pokefirered/include/constants/items.h:273
local ITEM_OLD_ROD = 262
-- pokefirered/include/constants/items.h:422
local ITEM_POKE_FLUTE = 350
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_bag_use")
    love.event.quit(0)
  else
    print("FAIL stitchuif_bag_use failures=" .. failures)
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
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local ItemsData = require("src.core.game3.items_data")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_REPEL, 2)
  Bag.add(session.bag, ITEM_OLD_ROD, 1)
  Bag.add(session.bag, ITEM_POKE_FLUTE, 1)
  result(Bag.has(session.bag, ITEM_REPEL, 2) == true, "two REPELs are in the bag")
  result(Bag.has(session.bag, ITEM_OLD_ROD, 1) == true, "the OLD ROD is in the bag")
  result(Bag.has(session.bag, ITEM_POKE_FLUTE, 1) == true, "the POKé FLUTE is in the bag")

  Map.load(nil, game, PALLET, { x = 7, y = 16, facing = "down" })
  place(7, 16, "down")
  U.wait(90)
  result(Space.mapId == PALLET, "stood on the Pallet Town beach, map=" .. tostring(Space.mapId))
  result(ItemUse.canFish() == true, "facing the sea, CanFish passes")

  local function openStart()
    for _ = 1, 20 do
      if StartMenu.isOpen() then return true end
      U.tap(game, "start")
      U.wait(12)
    end
    return StartMenu.isOpen()
  end

  local function openBag()
    if not openStart() then return false end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "bag" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if BagMenu.isOpen() and not BagMenu._open then break end
      U.wait(4)
    end
    return BagMenu.isOpen()
  end

  local function toPocket(pocket)
    for _ = 1, 12 do
      if BagMenu.currentPocket() == pocket then return true end
      U.tap(game, "right")
      U.wait(20)
    end
    return BagMenu.currentPocket() == pocket
  end

  local function toRow(itemId)
    local target
    for i, r in ipairs(BagMenu.list()) do
      if ItemsData.toNumericId(r.id) == itemId then target = i end
    end
    if not target then return false end
    for _ = 1, 30 do
      if BagMenu.cursor == target then return true end
      U.tap(game, BagMenu.cursor < target and "down" or "up")
      U.wait(8)
    end
    return BagMenu.cursor == target
  end

  local function pressUse()
    U.tap(game, "a")
    U.wait(10)
    if BagMenu.mode ~= "action" then return false end
    for _ = 1, 8 do
      if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(30)
    return true
  end

  result(openBag(), "the START menu opened the bag")
  result(toPocket("ITEMS"), "on the ITEMS pocket, got " .. tostring(BagMenu.currentPocket()))
  result(toRow(ITEM_REPEL), "cursor on REPEL")
  result(pressUse(), "USE picked from the item menu")

  result(BagMenu.isOpen() == true, "the bag stayed open for the REPEL message")
  result(BagMenu.mode == "message", "the bag is in message mode, got " .. tostring(BagMenu.mode))
  result(tostring(BagMenu.messageText):find("used the\nREPEL.", 1, true) ~= nil,
    "the repel line is gText_PlayerUsedVar2: " .. tostring(BagMenu.messageText))
  result(session.repelSteps == 100, "repel steps armed, got " .. tostring(session.repelSteps))
  result(Bag.get(session.bag, ITEM_REPEL) == 1, "one REPEL left")
  U.shot(game, DIR .. "/stitchuif_bag_use_01_repel_message.png")

  U.tap(game, "b")
  U.wait(20)
  result(BagMenu.mode == "list" and BagMenu.isOpen(), "B returned to the item list")
  U.shot(game, DIR .. "/stitchuif_bag_use_02_back_to_list.png")

  result(toPocket("KEY_ITEMS"), "on the KEY ITEMS pocket, got " .. tostring(BagMenu.currentPocket()))
  result(toRow(ITEM_POKE_FLUTE), "cursor on the POKé FLUTE")
  result(pressUse(), "USE picked for the POKé FLUTE")
  result(BagMenu.isOpen() == true, "the flute left the bag open")
  result(BagMenu.mode == "message", "the flute message is in the bag, got " .. tostring(BagMenu.mode))
  result(tostring(BagMenu.messageText):find("Played the", 1, true) ~= nil,
    "the first page is on screen: " .. tostring(BagMenu.messageText))
  U.shot(game, DIR .. "/stitchuif_bag_use_03_flute_page1.png")
  U.tap(game, "a")
  U.wait(20)
  result(BagMenu.isOpen() and tostring(BagMenu.messageText):find("catchy tune", 1, true) ~= nil,
    "A turned to the second page in the bag: " .. tostring(BagMenu.messageText))
  U.shot(game, DIR .. "/stitchuif_bag_use_04_flute_page2.png")
  U.tap(game, "a")
  U.wait(20)
  result(BagMenu.mode == "list" and BagMenu.isOpen(), "the last page returned to the item list")

  result(toRow(ITEM_OLD_ROD), "cursor on the OLD ROD")
  result(pressUse(), "USE picked for the OLD ROD")
  for _ = 1, 120 do
    if not BagMenu.isOpen() then break end
    U.wait(2)
  end
  U.wait(30)
  result(BagMenu.isOpen() == false, "the bag closed for the rod")
  result(StartMenu.isOpen() == false, "the START menu closed with it")
  result(Field.isFishing() == true, "the fishing task is running")
  result(Player.fishing == true, "the player has the rod out")
  U.wait(30)
  U.shot(game, DIR .. "/stitchuif_bag_use_05_fishing_from_bag.png")

  finish()
end
