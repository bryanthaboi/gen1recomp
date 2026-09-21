local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_corner_prize"

local PRIZE_ROOM = "FR_CELADON_CITY_GAME_CORNER_PRIZE_ROOM"
-- pokefirered/include/constants/flags.h:604
local FLAG_GOT_COIN_CASE = 0x243
-- pokefirered/include/constants/items.h:312
local ITEM_TM13 = 301
local TM13_PRICE = 4000
-- pokefirered/include/constants/items.h:205
local ITEM_SMOKE_BALL = 194
local SMOKE_BALL_PRICE = 800

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS corner_prize")
    love.event.quit(0)
  else
    print("FAIL corner_prize failures=" .. failures)
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
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Bag = require("src.core.game3.bag")
  local Prize = require("src.ui.game3.prize_corner")
  local CoinsBox = require("src.ui.game3.coins_box")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function coins() return Bag.Coins.get(session) end
  local function bagCount()
    return Bag.get(session.bag, ITEM_TM13) or 0
  end

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:240
  Flags.setFlag(Space.store, ctx(), FLAG_GOT_COIN_CASE, true)
  Bag.Coins.set(session, TM13_PRICE)

  local function standAt(x, y)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = "up"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, "up"
    end
  end

  Map.load(nil, game, PRIZE_ROOM, { x = 6, y = 4, facing = "up" })
  standAt(6, 4)
  U.wait(90)
  result(Space.mapId == PRIZE_ROOM, "standing at the prize counter, map=" .. tostring(Space.mapId))
  result(coins() == TM13_PRICE, "the coin case holds " .. coins() .. " coins")
  U.shot(game, DIR .. "/corner_prize_01_prize_room.png")

  local function talkToClerk()
    U.tap(game, "a")
    U.wait(20)
    for _ = 1, 100 do
      if Prize.isOpen() then return true end
      if Message.isOpen() or Choice.active or (Space.vm and Space.vm:isRunning()) then
        U.tap(game, "a")
      end
      U.wait(10)
    end
    return Prize.isOpen()
  end

  if not talkToClerk() then
    print("[driver] no list from (6,4); trying the counter cell")
    standAt(6, 3)
    U.wait(30)
    talkToClerk()
  end
  if not result(Prize.isOpen(), "the TM clerk opened the prize list") then
    print("[driver] vm running=" .. tostring(Space.vm and Space.vm:isRunning()) ..
      " message=" .. tostring(Message.isOpen()) .. " choice=" .. tostring(Choice.active))
    return finish()
  end
  result(Prize.listId == Prize.LIST_TM_PRIZES,
    "the list is the TM prize list, id=" .. tostring(Prize.listId))
  result(CoinsBox.isVisible and CoinsBox.isVisible(), "the coins box is up beside the list")

  local rows = Prize.rows or {}
  result(#rows == 6, "the list has pret's six rows, got " .. #rows)
  local priced = 0
  for _, row in ipairs(rows) do
    if row.amount and row.column then priced = priced + 1 end
  end
  result(priced == 5, "five rows print a price in their own column, got " .. priced)
  print("[driver] row 1 name=" .. tostring(rows[1] and rows[1].name) ..
    " price=" .. tostring(rows[1] and rows[1].amount) ..
    " column=" .. tostring(rows[1] and rows[1].column))
  U.wait(20)
  U.shot(game, DIR .. "/corner_prize_02_tm_list.png")

  U.tap(game, "down")
  U.wait(10)
  result(Prize.cursor == 2, "the cursor walks down the list, at " .. tostring(Prize.cursor))
  U.shot(game, DIR .. "/corner_prize_03_cursor_moved.png")
  U.tap(game, "up")
  U.wait(10)
  result(Prize.cursor == 1, "and back up to TM13")

  local before = coins()
  U.tap(game, "a")
  U.wait(20)
  for _ = 1, 60 do
    if Choice.active then break end
    U.wait(5)
  end
  result(Choice.active, "the clerk asks to confirm the purchase")
  U.shot(game, DIR .. "/corner_prize_04_confirm.png")

  U.tap(game, "a")
  U.wait(20)
  for _ = 1, 200 do
    if bagCount() > 0 then break end
    if Message.isOpen() or Choice.active then U.tap(game, "a") end
    U.wait(6)
  end
  result(bagCount() > 0, "TM13 landed in the bag, count=" .. bagCount())
  result(coins() == before - TM13_PRICE,
    string.format("the purchase debited %d coins (%d to %d)", TM13_PRICE, before, coins()))
  U.shot(game, DIR .. "/corner_prize_05_bought.png")

  for _ = 1, 200 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if Message.isOpen() or Choice.active or Prize.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  result(not (Space.vm and Space.vm:isRunning()), "the script released the player")

  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local TmCase = require("src.ui.game3.tm_case")
  local ItemsData = require("src.core.game3.items_data")
  Bag.add(session.bag, ItemsData.ITEM_TM_CASE, 1)
  U.tap(game, "start")
  U.wait(30)
  if result(StartMenu.isOpen(), "the start menu opened") then
    local bagIdx
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "bag" then bagIdx = i break end
    end
    for _ = 1, 20 do
      if StartMenu.cursor == bagIdx then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(60)
    if result(BagMenu.isOpen(), "the bag opened") then
      local function rowFor(id)
        for i, r in ipairs(BagMenu.list() or {}) do
          if tonumber(r.id) == id then return i end
        end
      end
      for _ = 1, 6 do
        if rowFor(ItemsData.ITEM_TM_CASE) then break end
        U.tap(game, "right")
        U.wait(20)
      end
      local caseRow = rowFor(ItemsData.ITEM_TM_CASE)
      if result(caseRow ~= nil, "the TM CASE is in the KEY ITEMS pocket") then
        for _ = 1, 30 do
          if BagMenu.cursor == caseRow then break end
          U.tap(game, "down")
          U.wait(6)
        end
        U.tap(game, "a")
        U.wait(30)
        for _ = 1, 40 do
          if TmCase.isOpen() then break end
          U.tap(game, "a")
          U.wait(10)
        end
        if result(TmCase.isOpen(), "the TM CASE opened") then
          local found = false
          for _, r in ipairs(TmCase.list() or {}) do
            if tonumber(r.id) == ITEM_TM13 then found = true end
          end
          result(found, "TM13 is filed in the TM CASE")
          U.shot(game, DIR .. "/corner_prize_06_tm_case.png")
        end
      end
    end
    for _ = 1, 30 do
      if not (TmCase.isOpen() or BagMenu.isOpen() or StartMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(20)
    end
  end

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:203
  Bag.Coins.set(session, TM13_PRICE - 1)
  local short = coins()
  talkToClerk()
  if result(Prize.isOpen(), "the clerk opened the list again") then
    U.tap(game, "a")
    U.wait(20)
    for _ = 1, 60 do
      if Choice.active then break end
      U.wait(5)
    end
    U.tap(game, "a")
    U.wait(30)
    U.shot(game, DIR .. "/corner_prize_07_not_enough.png")
    for _ = 1, 200 do
      if not (Space.vm and Space.vm:isRunning()) then break end
      if Message.isOpen() or Choice.active or Prize.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
    result(coins() == short,
      string.format("a short purse buys nothing (%d still there)", coins()))
    result(bagCount() == 1, "the bag still holds exactly one TM13, count=" .. bagCount())
  end

  U.wait(30)
  U.shot(game, DIR .. "/corner_prize_08_back_at_counter.png")
  result(Space.mapId == PRIZE_ROOM, "the player is still in the prize room")

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:324
  local ItemsData = require("src.core.game3.items_data")
  local filled = 0
  local id = 1
  while filled < (ItemsData.CAPACITY.ITEMS or 42) and id <= 400 do
    if id ~= ITEM_SMOKE_BALL and ItemsData.pocketOf(id) == "ITEMS" then
      if Bag.add(session.bag, id, 1) then filled = filled + 1 end
    end
    id = id + 1
  end
  result(filled == ItemsData.CAPACITY.ITEMS, "the ITEMS pocket is full, slots=" .. filled)
  Bag.Coins.set(session, SMOKE_BALL_PRICE)
  local fullPurse = coins()

  standAt(2, 4)
  U.wait(30)
  if result(talkToClerk(), "the battle item clerk opened his list") then
    result(Prize.listId == Prize.LIST_BATTLE_ITEM_PRIZES,
      "the list is the battle item prize list, id=" .. tostring(Prize.listId))
    U.tap(game, "a")
    U.wait(20)
    for _ = 1, 60 do
      if Choice.active then break end
      U.wait(5)
    end
    U.tap(game, "a")
    U.wait(40)
    U.shot(game, DIR .. "/corner_prize_09_bag_full.png")
    for _ = 1, 200 do
      if not (Space.vm and Space.vm:isRunning()) then break end
      if Message.isOpen() or Choice.active or Prize.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
    result(coins() == fullPurse,
      string.format("a full bag buys nothing (%d still there)", coins()))
    result((Bag.get(session.bag, ITEM_SMOKE_BALL) or 0) == 0, "no SMOKE BALL reached the bag")
  end

  finish()
end
