local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_berry_pouch_sell"

local ITEM_POKE_BALL = 4
local ITEM_POTION = 13
local ITEM_ORAN_BERRY = 139
local ITEM_BERRY_POUCH = 365

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS berry_pouch_sell")
    love.event.quit(0)
  else
    print("FAIL berry_pouch_sell failures=" .. failures)
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
  local ItemsData = require("src.core.game3.items_data")
  local BagMenu = require("src.ui.game3.bag_menu")
  local BerryPouch = require("src.ui.game3.berry_pouch")
  local ShopMenu = require("src.ui.game3.shop_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.money = 3000
  Bag.add(session.bag, ITEM_BERRY_POUCH, 1)
  Bag.add(session.bag, ITEM_ORAN_BERRY, 3)

  ShopMenu.show({ items = { ITEM_POKE_BALL, ITEM_POTION }, session = session })
  U.wait(20)
  U.tap(game, "down")
  U.wait(8)
  U.tap(game, "a")
  for _ = 1, 90 do
    if BagMenu.isOpen() and not BagMenu._open then break end
    U.wait(4)
  end
  result(BagMenu.isOpen() and BagMenu._location == "shop", "SELL opened the bag in shop mode")
  for _ = 1, 12 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(20)
  end
  local target
  for i, r in ipairs(BagMenu.list()) do
    if ItemsData.toNumericId(r.id) == ITEM_BERRY_POUCH then target = i end
  end
  for _ = 1, 30 do
    if not target or BagMenu.cursor == target then break end
    U.tap(game, BagMenu.cursor < target and "down" or "up")
    U.wait(8)
  end
  result(target ~= nil and BagMenu.cursor == target, "sell cursor on BERRY POUCH")
  U.tap(game, "a")
  for _ = 1, 60 do
    if BerryPouch.isOpen() then break end
    U.wait(4)
  end
  U.wait(20)
  -- pokefirered/src/item_menu.c:1830 GoToBerryPouch_Sell
  result(BerryPouch.isOpen() and BerryPouch._sellMode == true, "BERRY POUCH opened in sell mode")
  U.tap(game, "a")
  U.wait(12)
  local sell = BerryPouch._sell
  -- pokefirered/src/berry_pouch.c:1266 Task_ContextMenu_Sell
  result(BerryPouch.mode == "sell" and sell and sell.state == "qty"
    and tostring(sell.text):find("How many would you like to sell?", 1, true) ~= nil,
    "ORAN BERRY asks how many: " .. tostring(sell and sell.text))
  U.tap(game, "up")
  U.wait(8)
  result(sell and sell.qty == 2, "quantity went to 2")
  U.shot(game, DIR .. "/berry_sell_how_many.png")
  U.tap(game, "a")
  U.wait(12)
  result(sell and sell.state == "confirm" and sell.text == "I can pay ¥20.\nWould that be okay?",
    "price for 2 ORAN BERRY: " .. tostring(sell and sell.text))
  U.shot(game, DIR .. "/berry_sell_i_can_pay.png")
  local moneyBefore = session.money
  U.tap(game, "a")
  U.wait(12)
  result(sell and sell.state == "done" and tostring(sell.text):find("Turned over the", 1, true) ~= nil,
    "gText_TurnedOverItemsWorthYen: " .. tostring(sell and sell.text))
  result(session.money == moneyBefore + 20 and Bag.get(session.bag, ITEM_ORAN_BERRY) == 1,
    "sold 2 ORAN BERRY for 20, money=" .. tostring(session.money))
  U.shot(game, DIR .. "/berry_sell_turned_over.png")
  U.tap(game, "a")
  U.wait(12)
  result(BerryPouch.mode == "list" and BerryPouch._sell == nil, "back on the berry list")
  U.tap(game, "b")
  for _ = 1, 60 do
    if not BerryPouch.isOpen() then break end
    U.wait(4)
  end
  U.wait(20)
  result(BagMenu.isOpen() and BagMenu._location == "shop", "closing the pouch returns to the sell bag")
  BagMenu.close()
  ShopMenu.close()
  U.wait(10)
  finish()
end
