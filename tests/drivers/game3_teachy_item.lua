local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teachy_item"

-- pokefirered/data/maps/ViridianCity/scripts.inc:235 giveitem ITEM_TEACHY_TV
local ITEM_TEACHY_TV = 366
-- pokefirered/include/constants/items.h:436
local ITEM_TM_CASE = 364

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_item")
    love.event.quit(0)
  else
    print("FAIL teachy_item failures=" .. failures)
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
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local TeachyTv = require("src.core.game3.teachy_tv")
  local TvUi = require("src.ui.game3.teachy_tv")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)
  result(Bag.get(session.bag, ITEM_TEACHY_TV) == 1, "the TEACHY TV is in the KEY ITEMS pocket")
  result(not TeachyTv.hasTmCase(session), "the player has no TM CASE yet")

  local function openBagToTeachyTv()
    U.tap(game, "start")
    U.wait(30)
    if not result(StartMenu.isOpen(), "START opened the field menu") then return false end
    for _ = 1, 12 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "bag" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(60)
    if not result(BagMenu.isOpen(), "BAG opened") then return false end
    for _ = 1, 4 do
      if BagMenu.currentPocket() == "KEY_ITEMS" then break end
      U.tap(game, "right")
      U.wait(15)
    end
    if not result(BagMenu.currentPocket() == "KEY_ITEMS",
        "walked to KEY ITEMS, at " .. tostring(BagMenu.currentPocket())) then
      return false
    end
    local function selectedName()
      local rows = BagMenu.list()
      local row = rows and rows[BagMenu.cursor]
      return row and tostring(row.name) or nil
    end
    for _ = 1, 20 do
      if selectedName() == "TEACHY TV" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    return result(selectedName() == "TEACHY TV",
      "the bag cursor is on TEACHY TV, at " .. tostring(selectedName()))
  end

  if not openBagToTeachyTv() then return finish() end
  U.shot(game, DIR .. "/teachy_item_01_bag.png")

  U.tap(game, "a")
  U.wait(25)
  local firstAction = BagMenu.ACTIONS and BagMenu.ACTIONS[BagMenu.actionCursor]
  result(firstAction == "USE", "USE is the first key-item action, got " .. tostring(firstAction))
  U.tap(game, "a")
  U.wait(60)

  -- pokefirered/src/item_use.c:518 FieldUseFunc_TeachyTv
  if not result(TvUi.isOpen(), "USE opened the TEACHY TV") then
    U.shot(game, DIR .. "/teachy_item_02_no_tv.png")
    return finish()
  end
  result(TvUi.state == "list", "the TV opens on the lesson list, state=" .. tostring(TvUi.state))

  -- pokefirered/src/teachy_tv.c:201 sListMenuItems_NoTMCase
  local rows = TvUi.rows()
  result(#rows == 5, "five rows without a TM CASE, got " .. tostring(#rows))
  result(rows[1] and rows[1].index == TeachyTv.SCRIPT.BATTLE, "row 1 is the battle lesson")
  result(rows[4] and rows[4].index == TeachyTv.SCRIPT.CATCHING, "row 4 is the catching lesson")
  result(rows[5] and rows[5].index == TeachyTv.CANCEL, "row 5 is CANCEL")
  U.wait(30)
  U.shot(game, DIR .. "/teachy_item_02_lesson_menu.png")

  for _ = 1, 3 do
    U.tap(game, "down")
    U.wait(14)
  end
  result(TvUi.cursor == 4, "the cursor walked to the catching lesson, at " .. tostring(TvUi.cursor))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_item_03_cursor_catching.png")

  -- pokefirered/src/teachy_tv.c:740 TeachyTvOptionListController
  U.tap(game, "a")
  U.wait(10)
  result(TvUi.state == "lesson", "A started the lesson, state=" .. tostring(TvUi.state))
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.CATCHING,
    "whichScript is TTVSCR_CATCHING, got " .. tostring(TeachyTv.whichScript(session)))
  result(TvUi.stepName() == "transition_render_bg2",
    "the cluster starts on the transition, step=" .. tostring(TvUi.stepName()))

  local function waitFor(fn, budget)
    for _ = 1, (budget or 600) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end

  -- pokefirered/src/teachy_tv.c:782 TTVcmd_NpcMoveAndSetupTextPrinter
  result(waitFor(function() return TvUi.phase == "hello" end, 700),
    "the POKé DUDE walked in and said hello, phase=" .. tostring(TvUi.phase))
  print("[driver] hello page 1: " .. tostring(TvUi.pages()[1]))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_item_04_lesson_hello.png")

  -- pokefirered/src/teachy_tv.c:808 TeachyTvRenderMsgAndSwitchClusterFuncs
  U.tap(game, "b")
  U.wait(10)
  result(TvUi.stepName() == "end", "B jumped the cluster to TTVcmd_End")
  result(waitFor(function() return TvUi.state == "list" end, 200),
    "B dropped back to the lesson list, state=" .. tostring(TvUi.state))
  result(TvUi.isOpen(), "the TV is still open after B")
  U.wait(20)
  U.shot(game, DIR .. "/teachy_item_05_back_on_list.png")

  U.tap(game, "b")
  U.wait(45)
  result(not TvUi.isOpen(), "B on the list closed the TV")
  result(BagMenu.isOpen(), "the BAG is underneath again, the way CB2_BagMenuFromStartMenu returns")
  U.wait(20)
  U.shot(game, DIR .. "/teachy_item_06_back_in_bag.png")

  -- pokefirered/src/teachy_tv.c:553 TeachyTvSetupWindow
  Bag.add(session.bag, ITEM_TM_CASE, 1)
  result(TeachyTv.hasTmCase(session), "the TM CASE is in the bag now")
  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")
  U.wait(60)
  if not result(TvUi.isOpen(), "the TEACHY TV opened a second time") then return finish() end
  rows = TvUi.rows()
  result(#rows == 7, "seven rows with a TM CASE, got " .. tostring(#rows))
  result(rows[5] and rows[5].index == TeachyTv.SCRIPT.TMS, "the TM lesson appeared")
  result(rows[6] and rows[6].index == TeachyTv.SCRIPT.REGISTER, "the register lesson appeared")
  U.wait(30)
  U.shot(game, DIR .. "/teachy_item_07_tmcase_rows.png")

  U.tap(game, "b")
  U.wait(45)
  result(not TvUi.isOpen(), "the TV closed again")

  finish()
end
