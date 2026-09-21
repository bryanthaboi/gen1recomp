local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teachy_lesson"

-- pokefirered/data/maps/ViridianCity/scripts.inc:235 giveitem ITEM_TEACHY_TV
local ITEM_TEACHY_TV = 366

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_lesson")
    love.event.quit(0)
  else
    print("FAIL teachy_lesson failures=" .. failures)
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

  local function waitFor(fn, budget)
    for _ = 1, (budget or 900) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "START opened the field menu") then return finish() end
  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "BAG opened") then return finish() end
  for _ = 1, 4 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(15)
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
  if not result(selectedName() == "TEACHY TV", "the bag cursor is on TEACHY TV") then return finish() end
  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")
  U.wait(60)
  if not result(TvUi.isOpen(), "USE opened the TEACHY TV") then return finish() end

  -- pokefirered/src/teachy_tv.c:201 sListMenuItems_NoTMCase
  for _ = 1, 3 do
    U.tap(game, "down")
    U.wait(14)
  end
  result(TvUi.cursor == 4, "the cursor walked to the catching lesson, at " .. tostring(TvUi.cursor))
  U.tap(game, "a")
  U.wait(10)
  result(TvUi.state == "lesson", "A started the lesson, state=" .. tostring(TvUi.state))
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.CATCHING,
    "whichScript is TTVSCR_CATCHING")

  -- pokefirered/src/teachy_tv.c:755 TTVcmd_TransitionRenderBg2TeachyTvGraphicInitNpcPos
  result(waitFor(function() return TvUi.title end, 200), "the title card came up")
  U.wait(10)
  U.shot(game, DIR .. "/teachy_lesson_01_title.png")

  -- pokefirered/src/teachy_tv.c:782 TTVcmd_NpcMoveAndSetupTextPrinter
  result(waitFor(function() return TvUi.phase == "hello" end, 600),
    "the POKé DUDE walked in and said hello, phase=" .. tostring(TvUi.phase))
  result(TvUi.hostVisible, "the host sprite is on screen at x=" .. tostring(TvUi.hostX))
  print("[driver] hello page 1: " .. tostring(TvUi.pages()[1]))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_lesson_02_hello.png")

  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(10)
  end
  -- pokefirered/src/teachy_tv.c:838 TTVcmd_TextPrinterSwitchStringByOptionChosen
  result(waitFor(function() return TvUi.phase == "intro" end, 200),
    "CatchingScript1 took over, phase=" .. tostring(TvUi.phase))
  result(#TvUi.pages() == #TeachyTv.introPages(TeachyTv.SCRIPT.CATCHING),
    "the lesson is showing CatchingScript1, pages=" .. tostring(#TvUi.pages()))
  print("[driver] intro page 1: " .. tostring(TvUi.pages()[TvUi.page]))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_lesson_03_page1.png")

  U.tap(game, "a")
  U.wait(20)
  result(TvUi.page == 2, "A advanced to page 2, at " .. tostring(TvUi.page))
  print("[driver] intro page 2: " .. tostring(TvUi.pages()[TvUi.page]))
  U.wait(10)
  U.shot(game, DIR .. "/teachy_lesson_04_page2.png")

  for _ = 1, #TvUi.pages() - 2 do
    U.tap(game, "a")
    U.wait(10)
  end
  -- pokefirered/src/teachy_tv.c:936 TTVcmd_EraseTextWindowIfKeyPressed
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the cluster waits for a key press, step=" .. tostring(TvUi.stepName()))
  result(TvUi.waitingForKey(), "the prompt arrow is up")
  U.tap(game, "a")
  U.wait(10)

  -- pokefirered/src/teachy_tv.c:947 TTVcmd_StartAnimNpcWalkIntoGrass
  result(waitFor(function() return TvUi.stepName() == "dude_move_up" end, 200),
    "the dude walks into the grass, step=" .. tostring(TvUi.stepName()))
  U.wait(24)
  U.shot(game, DIR .. "/teachy_lesson_05_grass_walk.png")

  -- pokefirered/src/teachy_tv.c:1069 TTVcmd_TaskBattleOrFadeByOptionChosen
  result(waitFor(function() return TvUi.stepName() ~= "dude_move_up"
    and TvUi.stepName() ~= "dude_move_right" end, 300),
    "the cluster reached the demonstration hand off, step=" .. tostring(TvUi.stepName()))
  local hasPokedude = pcall(require, "src.core.game3.battle.pokedude")
  print("[driver] battle/pokedude.lua present: " .. tostring(hasPokedude))
  result(waitFor(function() return TvUi.phase == "outro" end, 300),
    "the lesson resumed at CatchingScript2, phase=" .. tostring(TvUi.phase))
  result(TeachyTv.whichScript(session) == TeachyTv.SCRIPT.CATCHING,
    "and it is still the catching lesson")
  print("[driver] outro page 1: " .. tostring(TvUi.pages()[TvUi.page]))
  U.wait(20)
  U.shot(game, DIR .. "/teachy_lesson_06_demo_handoff.png")

  for _ = 1, #TvUi.pages() - 1 do
    U.tap(game, "a")
    U.wait(10)
  end
  result(waitFor(function() return TvUi.stepName() == "erase_text_window_if_key_pressed" end, 200),
    "the outro waits for a key press")
  U.tap(game, "a")
  U.wait(10)

  -- pokefirered/src/teachy_tv.c:1021 TTVcmd_RenderAndRemoveBg1EndGraphic
  result(waitFor(function() return TvUi.stepName() == "render_and_remove_bg1_end_graphic" end, 400),
    "the dude walked off, step=" .. tostring(TvUi.stepName()))

  -- pokefirered/src/teachy_tv.c:1043 TTVcmd_End
  result(waitFor(function() return TvUi.state == "list" end, 400),
    "the lesson ended back on the list, state=" .. tostring(TvUi.state))
  result(TeachyTv.hasWatched(session, TeachyTv.SCRIPT.CATCHING),
    "the catching lesson is marked watched")
  U.wait(20)
  U.shot(game, DIR .. "/teachy_lesson_07_back_on_list.png")

  U.tap(game, "b")
  U.wait(45)
  result(not TvUi.isOpen(), "B on the list closed the TV")
  result(BagMenu.isOpen(), "the BAG is underneath again")

  finish()
end
