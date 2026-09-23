local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_item_pc_screens"

local ITEM_POTION = 13
local ITEM_ANTIDOTE = 14
local ITEM_BURN_HEAL = 15
local ITEM_ICE_HEAL = 16
local ITEM_ESCAPE_ROPE = 85
local ITEM_REPEL = 86
local ITEM_TM01 = 289

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS item_pc_screens")
    love.event.quit(0)
  else
    print("FAIL item_pc_screens failures=" .. failures)
    love.event.quit(1)
  end
end

local function waitFor(pred, n)
  for _ = 1, n do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
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
  local Storage = require("src.core.game3.storage")
  local PcMenu = require("src.ui.game3.pc_menu")
  local ItemPc = require("src.ui.game3.item_pc")
  local BagMenu = require("src.ui.game3.bag_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local st = Storage.ensure(session)
  st.items = {
    { id = ITEM_POTION, qty = 1 },
    { id = ITEM_REPEL, qty = 5 },
    { id = ITEM_ANTIDOTE, qty = 2 },
    { id = ITEM_BURN_HEAL, qty = 1 },
    { id = ITEM_ICE_HEAL, qty = 3 },
    { id = ITEM_ESCAPE_ROPE, qty = 1 },
    { id = ITEM_TM01, qty = 1 },
  }
  Bag.add(session.bag, ITEM_POTION, 3)
  Bag.add(session.bag, ITEM_REPEL, 1)

  PcMenu.show({ session = session, startMode = "player_pc" })
  U.wait(10)
  U.tap(game, "a")
  U.wait(10)
  result(PcMenu.mode == "item_storage", "ITEM STORAGE opened")
  U.tap(game, "a")
  local opened = waitFor(function() return ItemPc.isOpen() and not ItemPc._fx end, 120)
  -- pokefirered/src/player_pc.c:378
  result(opened, "WITHDRAW ITEM opened the full-screen item PC")
  U.wait(10)
  U.shot(game, DIR .. "/item_pc_withdraw_list.png")

  for _ = 1, 6 do U.tap(game, "down"); U.wait(4) end
  result(ItemPc.scroll == 2 and ItemPc.row == 4, "list scrolls like ListMenu (scroll=" .. ItemPc.scroll .. " row=" .. ItemPc.row .. ")")
  U.wait(10)
  U.shot(game, DIR .. "/item_pc_withdraw_scrolled_tm.png")
  for _ = 1, 6 do U.tap(game, "up"); U.wait(4) end
  U.tap(game, "down")
  U.wait(4)

  U.tap(game, "select")
  U.wait(6)
  result(ItemPc.mode == "move" and ItemPc.moveOrig == 1, "SELECT starts move mode on REPEL")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "down")
  U.wait(6)
  U.shot(game, DIR .. "/item_pc_move_mode.png")
  U.tap(game, "a")
  U.wait(6)
  result(st.items[2].id == ITEM_ANTIDOTE and st.items[3].id == ITEM_REPEL, "REPEL moved below ANTIDOTE")
  result(ItemPc.mode == "list" and ItemPc.scroll + ItemPc.row == 2, "cursor stays on REPEL")

  U.tap(game, "a")
  U.wait(6)
  result(ItemPc.mode == "submenu", "A opens the WITHDRAW / GIVE / CANCEL menu")
  U.shot(game, DIR .. "/item_pc_submenu.png")
  U.tap(game, "a")
  U.wait(6)
  result(ItemPc.mode == "qty" and ItemPc.qty == 1, "WITHDRAW asks how many")
  U.tap(game, "up")
  U.wait(4)
  U.tap(game, "up")
  U.wait(6)
  result(ItemPc.qty == 3, "quantity went to 3")
  U.shot(game, DIR .. "/item_pc_withdraw_how_many.png")
  U.tap(game, "a")
  U.wait(6)
  result(ItemPc.mode == "result" and tostring(ItemPc.resultText):find("Withdrew", 1, true) ~= nil,
    "gText_WithdrewQuantItem: " .. tostring(ItemPc.resultText))
  U.shot(game, DIR .. "/item_pc_withdrew.png")
  U.tap(game, "a")
  U.wait(6)
  result(st.items[3].id == ITEM_REPEL and st.items[3].qty == 2 and Bag.get(session.bag, ITEM_REPEL) == 4,
    "3 REPEL moved from the PC to the bag")
  result(ItemPc.mode == "list", "back on the item list")

  local PartyMenu = require("src.ui.game3.party_menu")
  session.party = {}
  require("src.core.game3.party").giveMon(session, 6, 36)
  session.party[1].item = ITEM_REPEL
  session.party[1].heldItem = ITEM_REPEL
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  local partyOpen = waitFor(function() return PartyMenu.isOpen() and PartyMenu.mode == "give" end, 120)
  result(partyOpen and st.items[3].qty == 2 and Bag.get(session.bag, ITEM_REPEL) == 4,
    "GIVE opens the party menu without touching the PC or bag")
  U.wait(20)
  U.tap(game, "a")
  U.wait(10)
  if PartyMenu.mode == "message" then
    U.shot(game, DIR .. "/item_pc_give_already_holding.png")
    U.tap(game, "a")
    U.wait(10)
  end
  -- pokefirered/src/party_menu.c:5468
  result(PartyMenu.mode == "yesno", "mon already holding REPEL asks to switch")
  U.shot(game, DIR .. "/item_pc_give_switch_yesno.png")
  U.tap(game, "a")
  U.wait(10)
  result(PartyMenu.mode == "message", "Yes shows gText_SwitchedPkmnItem: " .. tostring(PartyMenu._messageText))
  U.shot(game, DIR .. "/item_pc_give_switched.png")
  U.tap(game, "a")
  local back = waitFor(function() return not PartyMenu.isOpen() and ItemPc.mode == "list" end, 120)
  -- pokefirered/src/party_menu.c:5563
  result(back and st.items[3].id == ITEM_REPEL and st.items[3].qty == 1 and Bag.get(session.bag, ITEM_REPEL) == 5
    and session.party[1].item == ITEM_REPEL, "switch from the PC: PC REPEL -1, bag REPEL +1")
  U.wait(10)

  U.tap(game, "b")
  local closed = waitFor(function() return not ItemPc.isOpen() end, 120)
  U.wait(10)
  result(closed and PcMenu.mode == "item_storage" and PcMenu.cursor == 1,
    "B turns the item PC off and returns to ITEM STORAGE")

  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "a")
  local bagOpen = waitFor(function() return BagMenu.isOpen() and not BagMenu._open end, 120)
  -- pokefirered/src/player_pc.c:324
  result(bagOpen and BagMenu._location == "itempc" and BagMenu.currentPocket() == "ITEMS",
    "DEPOSIT ITEM opened the bag on the ITEMS pocket")
  U.wait(10)
  U.shot(game, DIR .. "/item_pc_deposit_bag.png")
  U.tap(game, "right")
  U.wait(20)
  result(BagMenu.currentPocket() == "ITEMS", "no pocket switching in the deposit bag")
  local potionRow
  for i, r in ipairs(BagMenu.list()) do
    if r.id == ITEM_POTION or tonumber(r.id) == ITEM_POTION then potionRow = i end
  end
  for _ = 1, 10 do
    if BagMenu.cursor == potionRow then break end
    U.tap(game, BagMenu.cursor < (potionRow or 1) and "down" or "up")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(6)
  result(BagMenu.mode == "deposit", "POTION x3 asks how many to deposit")
  U.tap(game, "up")
  U.wait(6)
  U.shot(game, DIR .. "/item_pc_deposit_how_many.png")
  U.tap(game, "a")
  U.wait(6)
  result(BagMenu.mode == "deposit_done" and tostring(BagMenu._depositText):find("Deposited", 1, true) ~= nil,
    "gText_DepositedStrVar2StrVar1s: " .. tostring(BagMenu._depositText))
  -- pokefirered/src/item_menu.c:1569
  result(Bag.get(session.bag, ITEM_POTION) == 3 and st.items[1].qty == 3 and BagMenu.list()[BagMenu.cursor].id == ITEM_POTION,
    "bag keeps POTION x3 under the Deposited box")
  U.shot(game, DIR .. "/item_pc_deposited.png")
  U.tap(game, "a")
  U.wait(6)
  result(Bag.get(session.bag, ITEM_POTION) == 1 and st.items[1].qty == 3, "2 POTION moved from the bag to the PC")
  U.tap(game, "b")
  local bagClosed = waitFor(function() return not BagMenu.isOpen() end, 120)
  U.wait(10)
  result(bagClosed and PcMenu.mode == "item_storage" and PcMenu.cursor == 2,
    "closing the deposit bag returns to ITEM STORAGE on DEPOSIT")
  PcMenu.close()
  U.wait(10)
  finish()
end
