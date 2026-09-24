local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_gift_menu"

-- pokefirered/include/constants/flags.h:1391
local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS gift_menu")
    love.event.quit(0)
  else
    print("FAIL gift_menu failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Boot = require("src.ui.game3.boot")
  local Ui = require("src.ui.game3.mystery_gift")
  local MysteryGift = require("src.core.game3.mystery_gift")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/data/scripts/questionnaire.inc:26 setflag FLAG_SYS_MYSTERY_GIFT_ENABLED
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_SYS_MYSTERY_GIFT_ENABLED, true)

  local mystic
  for _, entry in ipairs(MysteryGift.builtins()) do
    if entry.key == "mystic_ticket" then mystic = entry end
  end
  result(mystic ~= nil, "the built-in set carries the MYSTIC TICKET card")
  result(MysteryGift.receiveCard(session, mystic.card), "the Wonder Card saves onto the session")

  result(game:saveGame() ~= false, "the game saved")
  U.wait(30)

  game:returnToTitle()
  U.wait(60)
  local function phase() return game.boot and game.boot.phase end
  result(phase() == "title", "back on the title screen, phase=" .. tostring(phase()))

  local info = game.boot.continueInfo or {}
  result(info.mysteryGift == true, "the reloaded save carries the Mystery Gift flag")

  for _ = 1, 40 do
    if phase() == "menu" then break end
    U.tap(game, "start")
    U.wait(30)
  end
  result(phase() == "menu", "the main menu opened, phase=" .. tostring(phase()))
  for _ = 1, 60 do
    if (game.boot.fadeT or 0) == 0 then break end
    U.wait(1)
  end
  U.wait(10)

  local rows = Boot.menuItems(game.boot)
  print("[driver] main menu rows: " .. table.concat(rows, " | "))
  -- pokefirered/src/main_menu.c:370 MAIN_MENU_MYSTERYGIFT
  result(#rows == 4, "the main menu shows MYSTERY GIFT and keeps EXIT")
  result(rows[3] == "MYSTERY GIFT", "MYSTERY GIFT takes the third window")
  result(rows[4] == "EXIT", "EXIT is the fourth row")
  U.shot(game, DIR .. "/gift_menu_01_main_menu_rows.png")

  for _ = 1, 3 do
    U.tap(game, "down")
    U.wait(6)
  end
  result(game.boot.menuIndex == 4, "the cursor reached the EXIT row")
  result((game.boot.menuScroll or 0) > 0, "the menu scrolled to show EXIT")
  U.shot(game, DIR .. "/gift_menu_01b_exit_row_scrolled.png")
  U.tap(game, "up")
  U.wait(6)
  result(game.boot.menuIndex == 3, "the cursor reached the MYSTERY GIFT row")
  U.shot(game, DIR .. "/gift_menu_02_mystery_gift_row.png")

  U.tap(game, "a")
  for _ = 1, 400 do
    if phase() == Boot.PHASE.MYSTERY_GIFT then break end
    U.wait(1)
  end
  result(phase() == Boot.PHASE.MYSTERY_GIFT, "the Mystery Gift screen opened")
  U.wait(10)
  local st = game.boot.gift
  result(type(st) == "table" and st.state == Ui.STATE.MAIN_MENU,
    "it opens on WONDER CARDS / WONDER NEWS / EXIT")
  U.shot(game, DIR .. "/gift_menu_03_front_end.png")

  local function backToMenu()
    if st.state == Ui.STATE.OFFER_LIST then U.tap(game, "b") end
    for _ = 1, 300 do
      if st.state == Ui.STATE.MAIN_MENU and not st.msg then break end
      if st.msg and st.msg.revealed >= st.msg.total then U.tap(game, "a") end
      U.wait(4)
    end
  end

  U.tap(game, "a")
  U.wait(2)
  result(st.state == Ui.STATE.SEARCHING and not st.isNews,
    "WONDER CARDS fetches the list, not the saved card, state=" .. tostring(st.state))
  local cardDeadline = love.timer.getTime() + 15
  while st.state == Ui.STATE.SEARCHING and love.timer.getTime() < cardDeadline do U.wait(1) end
  print("[driver] card fetch ended in state=" .. tostring(st.state) .. " err=" .. tostring(st.lastError))
  result(st.state == Ui.STATE.OFFER_LIST or st.state == Ui.STATE.RESULT_MSG,
    "the fetch ends on the card list or the cart's error, state=" .. tostring(st.state))
  U.wait(30)
  U.shot(game, DIR .. "/gift_menu_04_card_list.png")
  backToMenu()
  result(st.state == Ui.STATE.MAIN_MENU, "B backs out to the Mystery Gift menu")

  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "a")
  result(st.state == Ui.STATE.SEARCHING and st.isNews, "WONDER NEWS fetches the list at once")
  local fetchDeadline = love.timer.getTime() + 15
  while st.state == Ui.STATE.SEARCHING and love.timer.getTime() < fetchDeadline do U.wait(1) end
  print("[driver] news fetch ended in state=" .. tostring(st.state) .. " err=" .. tostring(st.lastError))
  result(st.state == Ui.STATE.OFFER_LIST or st.state == Ui.STATE.RESULT_MSG,
    "the fetch ends on the news list or the cart's error, state=" .. tostring(st.state))
  U.wait(30)
  U.shot(game, DIR .. "/gift_menu_06_news_list.png")
  if st.state == Ui.STATE.OFFER_LIST then U.tap(game, "b") end
  for _ = 1, 300 do
    if st.state == Ui.STATE.MAIN_MENU and not st.msg then break end
    if st.msg and st.msg.revealed >= st.msg.total then U.tap(game, "a") end
    U.wait(4)
  end
  result(st.state == Ui.STATE.MAIN_MENU, "B comes back to the Mystery Gift menu")

  U.tap(game, "b")
  for _ = 1, 200 do
    if phase() == Boot.PHASE.MENU then break end
    U.wait(1)
  end
  result(phase() == Boot.PHASE.MENU, "B leaves the screen for the main menu")

  finish()
end
