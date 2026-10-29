-- pokefirered/src/item_menu.c:1217 BeginMovingItemInPocket
-- pokeemerald/src/item_menu.c:1430 StartItemSwap

local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_bag_move_3069"
local POTION, ANTIDOTE, REPEL, TM01 = 13, 14, 86, 289

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_bag_move_3069 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.boot ~= nil, "boot reached") then return finish() end
  local ok, err = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  end)
  if not ok then print("[driver] new_game error: " .. tostring(err)) end
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local s = Runtime.getSession()
  if not result(s ~= nil, "new game session is live") then return finish() end
  local rse = require("src.core.game3.profile").family(s) == "rse"
  local tag = rse and "em" or "frlg"

  s.bag.pockets.ITEMS = {}
  Bag.add(s.bag, POTION, 3)
  Bag.add(s.bag, ANTIDOTE, 2)
  Bag.add(s.bag, REPEL, 1)

  local function order(bag)
    local out = {}
    for i, r in ipairs(Bag.listPocket(bag, "ITEMS")) do out[i] = ItemsData.toNumericId(r.id) end
    return table.concat(out, ",")
  end

  local function openBag(pocket)
    BagMenu.show(s, { session = s, pocket = pocket })
    for _ = 1, 120 do
      if BagMenu.isOpen() and BagMenu.mode == "list" and not BagMenu._open then break end
      U.wait(1)
    end
    U.wait(10)
  end

  local function closeBag()
    for _ = 1, 10 do
      if not BagMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(30)
    end
  end

  result(order(s.bag) == "13,14,86", "ITEMS starts POTION, ANTIDOTE, REPEL (" .. order(s.bag) .. ")")
  openBag("ITEMS")
  for _ = 1, 6 do
    if BagMenu.cursor == 1 then break end
    U.tap(game, "up")
    U.wait(8)
  end
  result(BagMenu.isOpen() and BagMenu.currentPocket() == "ITEMS" and BagMenu.cursor == 1,
    "bag open on POTION")

  U.tap(game, "select")
  U.wait(8)
  result(BagMenu.mode == "move" and BagMenu.moveFrom == 1, "SELECT starts moving POTION (mode=" .. tostring(BagMenu.mode) .. ")")
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(20)
  result(BagMenu.mode == "move" and BagMenu.cursor == 3, "cursor two rows down while moving (cursor=" .. tostring(BagMenu.cursor) .. ")")
  local num = rse and "02" or "01"
  result(U.still(game, DIR .. "/3069_" .. num .. "_" .. tag .. "_swap_line_above_repel.png"), "swap line screenshot written")

  U.tap(game, "select")
  U.wait(10)
  result(BagMenu.mode == "list", "SELECT drops the item")
  result(order(s.bag) == "14,13,86", "new order ANTIDOTE, POTION, REPEL (" .. order(s.bag) .. ")")
  result(BagMenu.cursor == 2, "cursor stays on POTION (cursor=" .. tostring(BagMenu.cursor) .. ")")

  if rse then
    closeBag()
    Bag.add(s.bag, TM01, 1)
    Bag.add(s.bag, TM01 + 1, 1)
    openBag("TM_CASE")
    U.tap(game, "select")
    U.wait(8)
    result(BagMenu.currentPocket() == "TM_CASE" and BagMenu.mode == "list", "TM/HM pocket refuses SELECT")
  end
  closeBag()
  result(not BagMenu.isOpen(), "bag closed")

  local saved = game:saveGame()
  result(saved ~= false, "game saved")
  local raw = SaveData.load()
  local loaded = raw and Schema.fromSaveTable(raw)
  result(loaded and order(loaded.bag) == "14,13,86",
    "order after save and reload ANTIDOTE, POTION, REPEL (" .. tostring(loaded and order(loaded.bag)) .. ")")

  finish()
end
