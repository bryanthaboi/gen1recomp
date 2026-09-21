local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teachy_register"

-- pokefirered/include/constants/items.h:438
local ITEM_TEACHY_TV = 366
-- pokefirered/include/constants/items.h:436
local ITEM_TM_CASE = 364
-- pokefirered/include/constants/items.h:17
local ITEM_POTION = 13
local ITEM_ANTIDOTE = 14

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_register")
    love.event.quit(0)
  else
    print("FAIL teachy_register failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local TeachyTv = require("src.core.game3.teachy_tv")
  local TvUi = require("src.ui.game3.teachy_tv")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function waitFor(fn, budget)
    for _ = 1, (budget or 900) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)
  Bag.add(session.bag, ITEM_TM_CASE, 1)
  Bag.add(session.bag, ITEM_POTION, 3)

  -- pokefirered/src/item_use.c:534 InitTeachyTvFromBag
  local ok, kind = require("src.core.game3.item_use").useField(session, session.bag, ITEM_TEACHY_TV)
  result(ok and kind == "teachy_tv", "USE on the TEACHY TV opened the TV, kind=" .. tostring(kind))
  U.wait(30)
  if not result(TvUi.isOpen(), "the TEACHY TV screen is open") then return finish() end
  result(#TvUi.rows() == 7, "seven rows with a TM CASE, got " .. tostring(#TvUi.rows()))

  -- pokefirered/src/teachy_tv.c:191 gTeachyTvString_RegisterItem
  for _ = 1, 5 do
    U.tap(game, "down")
    U.wait(12)
  end
  local row = TvUi.rows()[TvUi.cursor]
  if not result(row and row.index == TeachyTv.SCRIPT.REGISTER,
      "the cursor is on the register lesson, at " .. tostring(TvUi.cursor)) then
    return finish()
  end
  U.tap(game, "a")
  U.wait(10)

  -- pokefirered/src/teachy_tv.c:384 sRegisterKeyItemScript
  result(waitFor(function() return TvUi.phase == "hello" end, 700),
    "the POKé DUDE said hello, phase=" .. tostring(TvUi.phase))
  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.phase == "intro" end, 200),
    "RegisterScript1 took over, phase=" .. tostring(TvUi.phase))
  print("[driver] intro page 1: " .. tostring(TvUi.pages()[TvUi.page]))
  U.wait(16)
  U.shot(game, DIR .. "/teachy_register_01_intro.png")
  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the intro waits for a key press")
  U.tap(game, "a")

  -- pokefirered/src/item_menu.c:2162 InitPokedudeBag
  result(waitFor(function() return BagMenu.isOpen() and TvUi.suspended end, 200),
    "the pokedude bag opened, suspended=" .. tostring(TvUi.suspended))
  result(Bag.get(session.bag, ITEM_POTION) == 1,
    "the pokedude bag has one POTION, not the player's three, got "
      .. tostring(Bag.get(session.bag, ITEM_POTION)))
  result(Bag.get(session.bag, ITEM_ANTIDOTE) == 1, "and the pokedude ANTIDOTE")
  U.wait(40)
  U.shot(game, DIR .. "/teachy_register_02_pokedude_bag.png")

  -- pokefirered/src/item_menu.c:2217 SwitchPockets
  result(waitFor(function() return BagMenu.currentPocket() == "KEY_ITEMS" end, 200),
    "the demo switched to KEY ITEMS, at " .. tostring(BagMenu.currentPocket()))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_register_03_key_items.png")

  -- pokefirered/src/item_menu.c:2224 OpenContextMenu
  result(waitFor(function() return BagMenu.mode == "action" end, 200),
    "the demo opened the item menu, mode=" .. tostring(BagMenu.mode))
  result(waitFor(function()
    return BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor] == "SET"
  end, 200), "the cursor moved to SET, on "
    .. tostring(BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor]))
  U.wait(10)
  U.shot(game, DIR .. "/teachy_register_04_set_action.png")

  -- pokefirered/src/item_menu.c:2232 gSaveBlock1Ptr->registeredItem
  result(waitFor(function() return session.registeredItem ~= nil end, 300),
    "the demo registered the TEACHY TV, got " .. tostring(session.registeredItem))
  U.wait(30)
  U.shot(game, DIR .. "/teachy_register_05_registered.png")

  -- pokefirered/src/item_menu.c:2082 RestorePlayerBag
  result(waitFor(function() return not BagMenu.isOpen() end, 400),
    "the demo closed the bag by itself")
  result(Bag.get(session.bag, ITEM_POTION) == 3,
    "the player's three POTIONS came back, got " .. tostring(Bag.get(session.bag, ITEM_POTION)))
  result(Bag.get(session.bag, ITEM_ANTIDOTE) == 0, "the pokedude ANTIDOTE is gone")
  result(session.registeredItem == nil, "the registration was a demonstration only")

  -- pokefirered/src/teachy_tv.c:1100 sWhereToReturnToFromBattle
  result(waitFor(function() return TvUi.phase == "outro" end, 300),
    "the TV resumed at RegisterScript2, phase=" .. tostring(TvUi.phase))
  print("[driver] outro page 1: " .. tostring(TvUi.pages()[TvUi.page]))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_register_06_outro.png")

  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the outro waits for a key press")
  U.tap(game, "a")
  result(waitFor(function() return TvUi.state == "list" end, 500),
    "the lesson ended back on the list, state=" .. tostring(TvUi.state))
  result(TeachyTv.hasWatched(session, TeachyTv.SCRIPT.REGISTER),
    "the register lesson is marked watched")
  U.wait(20)
  U.shot(game, DIR .. "/teachy_register_07_back_on_list.png")

  U.tap(game, "b")
  U.wait(40)
  result(not TvUi.isOpen(), "B closed the TV")

  finish()
end
