local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teachy_tmcase"

-- pokefirered/include/constants/items.h:438
local ITEM_TEACHY_TV = 366
-- pokefirered/include/constants/items.h:436
local ITEM_TM_CASE = 364
-- pokefirered/include/constants/items.h:301
local ITEM_TM02 = 290
-- pokefirered/include/constants/items.h:300
local ITEM_TM01 = 289
-- pokefirered/include/constants/items.h:17
local ITEM_POTION = 13

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_tmcase")
    love.event.quit(0)
  else
    print("FAIL teachy_tmcase failures=" .. failures)
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
  local TmCase = require("src.ui.game3.tm_case")
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
  Bag.add(session.bag, ITEM_TM02, 1)
  Bag.add(session.bag, ITEM_POTION, 3)

  -- pokefirered/src/item_use.c:534 InitTeachyTvFromBag
  local ok, kind = require("src.core.game3.item_use").useField(session, session.bag, ITEM_TEACHY_TV)
  result(ok and kind == "teachy_tv", "USE on the TEACHY TV opened the TV, kind=" .. tostring(kind))
  U.wait(30)
  if not result(TvUi.isOpen(), "the TEACHY TV screen is open") then return finish() end

  -- pokefirered/src/teachy_tv.c:188 gTeachyTvString_TMs
  for _ = 1, 4 do
    U.tap(game, "down")
    U.wait(12)
  end
  local row = TvUi.rows()[TvUi.cursor]
  if not result(row and row.index == TeachyTv.SCRIPT.TMS,
      "the cursor is on the TMs lesson, at " .. tostring(TvUi.cursor)) then
    return finish()
  end
  U.tap(game, "a")
  U.wait(10)

  -- pokefirered/src/teachy_tv.c:364 sTMsScript
  result(waitFor(function() return TvUi.phase == "hello" end, 700),
    "the POKé DUDE said hello, phase=" .. tostring(TvUi.phase))
  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.phase == "intro" end, 200),
    "TMsScript1 took over, phase=" .. tostring(TvUi.phase))
  U.wait(16)
  U.shot(game, DIR .. "/teachy_tmcase_01_intro.png")
  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the intro waits for a key press")
  U.tap(game, "a")

  -- pokefirered/src/item_menu.c:2162 InitPokedudeBag
  result(waitFor(function() return BagMenu.isOpen() and TvUi.suspended end, 300),
    "the pokedude bag opened, suspended=" .. tostring(TvUi.suspended))
  result(waitFor(function() return BagMenu.currentPocket() == "KEY_ITEMS" end, 300),
    "the demo switched to KEY ITEMS, at " .. tostring(BagMenu.currentPocket()))
  result(waitFor(function() return BagMenu.mode == "action" end, 300),
    "the demo opened the item menu on the TM CASE, mode=" .. tostring(BagMenu.mode))
  U.wait(10)
  U.shot(game, DIR .. "/teachy_tmcase_02_bag_use.png")

  -- pokefirered/src/item_menu.c:2385 exitCB = Pokedude_InitTMCase
  result(waitFor(function() return TmCase.isOpen() end, 400),
    "the bag handed off to the pokedude TM CASE")
  result(not BagMenu.isOpen(), "and the bag closed behind it")
  -- pokefirered/src/tm_case.c:1334 AddBagItem(ITEM_TM01, 1)
  result(#TmCase.list() == #TeachyTv.POKEDUDE_TMS,
    "the case holds the pokedude's four TMs, got " .. tostring(#TmCase.list()))
  result(Bag.get(session.bag, ITEM_TM02) == 0, "the player's own TM is put away")
  result(Bag.get(session.bag, ITEM_TM01) == 1, "TM01 is in the case")
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_03_pokedude_case.png")

  -- pokefirered/src/tm_case.c:1394 DPAD_DOWN
  result(waitFor(function() return TmCase.cursor > 1 end, 300),
    "the case scrolls itself, cursor=" .. tostring(TmCase.cursor))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_04_scrolling.png")

  -- pokefirered/src/tm_case.c:1419 gPokedudeText_TMTypes
  result(waitFor(function() return TmCase.mode == "message" end, 1200),
    "gPokedudeText_TMTypes is printing, mode=" .. tostring(TmCase.mode))
  local typesPages = TeachyTv.pagesOf(TeachyTv.TM_TYPES)
  result(TmCase.messageText == typesPages[1],
    "page 1 is gPokedudeText_TMTypes, got " .. tostring(TmCase.messageText))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_05_tm_types.png")
  for _ = 1, #typesPages do
    U.tap(game, "a")
    U.wait(10)
  end
  result(TmCase.mode == "list", "A paged through and handed the list back")

  -- pokefirered/src/tm_case.c:1430 gPokedudeText_ReadTMDescription
  result(waitFor(function() return TmCase.mode == "message" end, 1200),
    "the second lecture started, mode=" .. tostring(TmCase.mode))
  local descPages = TeachyTv.pagesOf(TeachyTv.TM_DESCRIPTION)
  result(TmCase.messageText == descPages[1],
    "page 1 is gPokedudeText_ReadTMDescription, got " .. tostring(TmCase.messageText))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_06_tm_description.png")
  for _ = 1, #descPages do
    U.tap(game, "a")
    U.wait(10)
  end

  -- pokefirered/src/tm_case.c:1446 tPokedudeState 21
  result(waitFor(function() return not TmCase.isOpen() end, 300), "the TM CASE closed itself")
  result(Bag.get(session.bag, ITEM_TM02) == 1, "the player's TM came back")
  result(Bag.get(session.bag, ITEM_TM01) == 0, "the pokedude's TMs are gone")
  result(Bag.get(session.bag, ITEM_TM_CASE) == 1,
    "still exactly one TM CASE, got " .. tostring(Bag.get(session.bag, ITEM_TM_CASE)))
  result(Bag.get(session.bag, ITEM_POTION) == 3, "and the player's three POTIONS")

  -- pokefirered/src/teachy_tv.c:1100 sWhereToReturnToFromBattle
  result(waitFor(function() return TvUi.phase == "outro" end, 400),
    "the TV resumed at TMsScript2, phase=" .. tostring(TvUi.phase))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_07_outro.png")
  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(8)
  end
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the outro waits for a key press")
  U.tap(game, "a")
  result(waitFor(function() return TvUi.state == "list" end, 500),
    "the lesson ended back on the list, state=" .. tostring(TvUi.state))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_tmcase_08_back_on_list.png")

  U.tap(game, "b")
  U.wait(40)
  result(not TvUi.isOpen(), "B closed the TV")

  finish()
end
