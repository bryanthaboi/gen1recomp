local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_r4_item_rom_text"

-- pokefirered/include/constants/items.h:90
local ITEM_REPEL = 86
local ITEM_POTION = 13
local ITEM_POKE_BALL = 4
local ITEM_ORAN_BERRY = 139
local ITEM_TM01 = 289
local ITEM_TM_CASE = 364
local ITEM_BERRY_POUCH = 365

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS r4_item_rom_text")
    love.event.quit(0)
  else
    print("FAIL r4_item_rom_text failures=" .. failures)
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
  local RomText = require("src.core.game3.rom_text")
  local BagMenu = require("src.ui.game3.bag_menu")
  local TmCase = require("src.ui.game3.tm_case")
  local BerryPouch = require("src.ui.game3.berry_pouch")
  local ShopMenu = require("src.ui.game3.shop_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.money = 3000
  Bag.add(session.bag, ITEM_REPEL, 3)
  Bag.add(session.bag, ITEM_POTION, 2)
  Bag.add(session.bag, ITEM_TM_CASE, 1)
  Bag.add(session.bag, ITEM_TM01, 1)
  Bag.add(session.bag, ITEM_BERRY_POUCH, 1)
  Bag.add(session.bag, ITEM_ORAN_BERRY, 3)

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

  local function toPocket(pocket)
    local want
    for i, p in ipairs(ItemsData.BAG_POCKET_ORDER) do
      if p == pocket then want = i end
    end
    for _ = 1, 12 do
      if BagMenu.currentPocket() == pocket then return true end
      U.tap(game, (want or 1) > BagMenu.pocketIdx and "right" or "left")
      U.wait(20)
    end
    return BagMenu.currentPocket() == pocket
  end

  BagMenu.show(session, { bag = session.bag })
  for _ = 1, 60 do
    if BagMenu.isOpen() and not BagMenu._open then break end
    U.wait(4)
  end
  result(BagMenu.isOpen(), "the bag opened")
  result(toPocket("ITEMS"), "on the ITEMS pocket")
  result(ItemsData.POCKET_LABEL.ITEMS == RomText.plain("sPocketNames[0]"), "pocket label is sPocketNames[0]")
  result(toRow(ITEM_REPEL), "cursor on REPEL")
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "action", "the item menu opened")
  result(RomText.at("sItemMenuContextActions", 0) == "USE", "USE comes from sItemMenuContextActions[0]")
  U.shot(game, DIR .. "/r4_bag_repel_selected_actions.png")

  for _ = 1, 8 do
    if BagMenu.ACTIONS[BagMenu.actionCursor] == "TOSS" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "toss", "TOSS asks how many (item_menu.c:1497), mode=" .. tostring(BagMenu.mode))
  U.shot(game, DIR .. "/r4_bag_toss_out_how_many.png")
  U.tap(game, "up")
  U.wait(8)
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "toss_confirm", "A asks gText_ThrowAwayStrVar2OfThisItemQM, mode=" .. tostring(BagMenu.mode))
  U.shot(game, DIR .. "/r4_bag_throw_away_confirm.png")
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "toss_done", "YES prints gText_ThrewAwayStrVar2StrVar1s, mode=" .. tostring(BagMenu.mode))
  U.shot(game, DIR .. "/r4_bag_threw_away.png")
  U.tap(game, "a")
  U.wait(12)
  result(Bag.get(session.bag, ITEM_REPEL) == 1, "two REPELs were thrown away, left " .. tostring(Bag.get(session.bag, ITEM_REPEL)))

  result(toPocket("KEY_ITEMS"), "on the KEY ITEMS pocket")
  result(toRow(ITEM_TM_CASE), "cursor on the TM CASE")
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "action", "the TM CASE item menu opened")
  U.shot(game, DIR .. "/r4_bag_tm_case_open_action.png")
  U.tap(game, "b")
  U.wait(12)
  BagMenu.close()
  U.wait(30)

  TmCase.show(session, session.bag)
  U.wait(40)
  result(TmCase.isOpen(), "the TM CASE opened")
  local Pokemon = require("src.core.game3.pokemon")
  -- pokefirered/src/data/battle_moves.h:3439
  result(tonumber((Pokemon.battleMove(Pokemon.moveFromTmItem(ITEM_TM01)) or {}).type) == 1,
    "TM01 FOCUS PUNCH is type 1 (FIGHTING)")
  local labelText = {}
  for _, seg in ipairs(TmCase.labelIr(ITEM_TM01)) do
    if seg.t == "text" then labelText[#labelText + 1] = seg.s end
  end
  labelText = table.concat(labelText)
  -- pokefirered/src/tm_case.c:678 GetTMNumberAndMoveString
  result(labelText == "№01 FOCUS PUNCH", "TM row label is №01 FOCUS PUNCH: " .. labelText)
  U.shot(game, DIR .. "/r4_tm_case_list.png")
  U.tap(game, "a")
  U.wait(12)
  result(TmCase.mode == "action", "TM01 is selected, mode=" .. tostring(TmCase.mode))
  U.shot(game, DIR .. "/r4_tm_case_selected.png")
  U.tap(game, "down")
  U.wait(8)
  U.tap(game, "a")
  U.wait(12)
  result(TmCase.mode == "message" and tostring(TmCase.messageText):find("can't be held", 1, true) ~= nil,
    "GIVE prints gText_ItemCantBeHeld: " .. tostring(TmCase.messageText))
  U.shot(game, DIR .. "/r4_tm_case_cant_be_held.png")
  TmCase.close()
  U.wait(30)

  BerryPouch.show(session, session.bag)
  U.wait(40)
  result(BerryPouch.isOpen(), "the BERRY POUCH opened")
  U.tap(game, "a")
  U.wait(12)
  result(BerryPouch.mode == "action", "ORAN BERRY is selected")
  U.shot(game, DIR .. "/r4_berry_pouch_selected.png")
  BerryPouch.close()
  U.wait(30)

  ShopMenu.show({ items = { ITEM_POKE_BALL, ITEM_POTION }, session = session })
  U.wait(20)
  result(ShopMenu._status == RomText.box("Text_MayIHelpYou"), "the clerk line is Text_MayIHelpYou")
  U.shot(game, DIR .. "/r4_shop_may_i_help_you.png")
  U.tap(game, "a")
  U.wait(60)
  result(ShopMenu.mode == "buy", "BUY opened the stock list")
  U.tap(game, "a")
  U.wait(12)
  result(ShopMenu.mode == "buy_qty" and ShopMenu._status:find("Certainly", 1, true) ~= nil,
    "gText_Var1CertainlyHowMany: " .. tostring(ShopMenu._status))
  U.shot(game, DIR .. "/r4_shop_certainly_how_many.png")
  U.tap(game, "up")
  U.wait(8)
  U.tap(game, "a")
  U.wait(12)
  result(ShopMenu._status == "POKé BALL, and you want 2.\nThat will be ¥400. Okay?",
    "gText_Var1AndYouWantedVar2: " .. tostring(ShopMenu._status))
  U.shot(game, DIR .. "/r4_shop_and_you_want.png")
  U.tap(game, "a")
  U.wait(12)
  result(Bag.get(session.bag, ITEM_POKE_BALL) == 2 and Bag.get(session.bag, 12) == 0,
    "two POKé BALLs and no PREMIER BALL")
  U.shot(game, DIR .. "/r4_shop_here_you_are.png")
  U.tap(game, "a")
  U.wait(12)
  U.tap(game, "b")
  U.wait(60)
  U.tap(game, "down")
  U.wait(8)
  U.tap(game, "a")
  for _ = 1, 90 do
    if BagMenu.isOpen() and not BagMenu._open then break end
    U.wait(4)
  end
  -- pokefirered/src/shop.c:288 CB2_GoToSellMenu
  result(BagMenu.isOpen() and BagMenu._location == "shop", "SELL opened the bag in shop mode")
  result(toPocket("ITEMS"), "sell bag on the ITEMS pocket")
  result(toRow(ITEM_POTION), "sell cursor on POTION")
  local moneyBefore = session.money
  U.tap(game, "a")
  U.wait(12)
  local sell = BagMenu._sell
  result(BagMenu.mode == "sell" and sell and sell.state == "qty"
    and tostring(sell.text):find("How many would you like to sell?", 1, true) ~= nil,
    "gText_HowManyWouldYouLikeToSell: " .. tostring(sell and sell.text))
  U.tap(game, "up")
  U.wait(8)
  result(sell and sell.qty == 2, "quantity went to 2")
  U.shot(game, DIR .. "/r4_shop_how_many_sell.png")
  U.tap(game, "a")
  U.wait(12)
  result(sell and sell.state == "confirm" and sell.text == "I can pay ¥300.\nWould that be okay?",
    "gText_ICanPayThisMuch_WouldThatBeOkay: " .. tostring(sell and sell.text))
  U.shot(game, DIR .. "/r4_shop_i_can_pay.png")
  U.tap(game, "a")
  U.wait(12)
  result(sell and sell.state == "done" and tostring(sell.text):find("Turned over the", 1, true) ~= nil,
    "gText_TurnedOverItemsWorthYen: " .. tostring(sell and sell.text))
  result(session.money == moneyBefore + 300 and Bag.get(session.bag, ITEM_POTION) == 0,
    "sold 2 POTIONs for 300, money=" .. tostring(session.money))
  U.shot(game, DIR .. "/r4_shop_turned_over.png")
  U.tap(game, "a")
  U.wait(12)
  result(BagMenu.mode == "list" and BagMenu._sell == nil, "back on the sell bag list")

  result(toPocket("KEY_ITEMS"), "sell bag on the KEY ITEMS pocket")
  result(toRow(ITEM_TM_CASE), "sell cursor on TM CASE")
  U.tap(game, "a")
  for _ = 1, 60 do
    if TmCase.isOpen() then break end
    U.wait(4)
  end
  U.wait(20)
  -- pokefirered/src/item_menu.c:1825 GoToTMCase_Sell
  result(TmCase.isOpen() and TmCase._sellMode == true, "TM CASE opened in sell mode")
  U.tap(game, "a")
  U.wait(12)
  local tmSell = TmCase._sell
  result(TmCase.mode == "sell" and tmSell and tmSell.state == "confirm"
    and tostring(tmSell.text):find("I can pay ¥1500.", 1, true) ~= nil,
    "single TM01 goes straight to the price: " .. tostring(tmSell and tmSell.text))
  U.shot(game, DIR .. "/r4_tm_case_sell_i_can_pay.png")
  U.tap(game, "b")
  U.wait(12)
  result(TmCase.mode == "list" and Bag.get(session.bag, ITEM_TM01) == 1, "B keeps the TM")
  U.tap(game, "b")
  for _ = 1, 60 do
    if BagMenu.isOpen() and not BagMenu._open and not TmCase.isOpen() then break end
    U.wait(4)
  end
  U.tap(game, "b")
  for _ = 1, 90 do
    if not BagMenu.isOpen() then break end
    U.wait(4)
  end
  U.wait(30)
  -- pokefirered/src/shop.c:330
  result(ShopMenu.isOpen() and ShopMenu.mode == "root"
    and ShopMenu._status == RomText.box("gText_AnythingElseICanHelp"),
    "closing the sell bag returns to the shop menu: " .. tostring(ShopMenu._status))
  U.shot(game, DIR .. "/r4_shop_anything_else.png")
  ShopMenu.close()
  U.wait(10)

  finish()
end
