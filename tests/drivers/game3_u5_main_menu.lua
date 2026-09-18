local U = require("tests.drivers.util")
local Boot = require("src.ui.game3.boot")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local ok = true
  local function expect(cond, label)
    if cond then
      print("PASS " .. label)
    else
      print("FAIL " .. label)
      ok = false
    end
  end
  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function phase() return game.boot and game.boot.phase end

  local n = 0
  while phase() ~= "title" and n < 1200 do
    U.tap(game, "start")
    U.wait(30)
    n = n + 30
  end
  expect(phase() == "title", "reached title")
  if phase() ~= "title" then love.event.quit(1) return end

  Boot.setHasContinue(game.boot, true)
  if not game.boot.continueInfo then
    Boot.setContinueInfo(game.boot, {
      name = "RED", gender = 0, hours = 1, minutes = 23, hasDex = true, dexCount = 12, badges = 2,
    })
  end
  U.wait(60)
  U.shot(game, DIR .. "/u5_01_title.png")

  U.tap(game, "start")
  U.wait(2)
  expect(phase() == "title_cry", "start on title plays cry, no menu")
  U.shot(game, DIR .. "/u5_02_cry_title_still_up.png")

  waitFor(function() return (game.boot.white or 0) >= 8 end, 200)
  expect(phase() == "title_cry" and (game.boot.white or 0) >= 8, "fade to white after cry wait")
  U.shot(game, DIR .. "/u5_03_white_fade.png")

  waitFor(function() return phase() == "menu" end, 60)
  expect(phase() == "menu", "separate main menu after white fade")
  waitFor(function() return (game.boot.fadeT or 0) == 0 end, 30)
  U.wait(2)
  expect(not game.boot._titleActive, "title art torn down under menu")
  U.shot(game, DIR .. "/u5_04_main_menu_continue.png")

  U.tap(game, "down")
  U.wait(3)
  expect(game.boot.menuIndex == 2, "down moves to NEW GAME")
  U.tap(game, "down")
  U.wait(3)
  expect(game.boot.menuIndex == 2, "down clamps at NEW GAME")
  U.shot(game, DIR .. "/u5_05_main_menu_newgame_row.png")

  U.tap(game, "b")
  waitFor(function() return phase() == "title" end, 60)
  expect(phase() == "title", "B returns to title")
  U.wait(40)
  U.shot(game, DIR .. "/u5_06_b_back_to_title.png")

  Boot.setHasContinue(game.boot, false)
  U.tap(game, "start")
  local sawMenu = false
  for _ = 1, 200 do
    if phase() == "menu" then sawMenu = true end
    if phase() ~= "title_cry" and phase() ~= "title" then break end
    U.wait(1)
  end
  expect(not sawMenu and phase() == "controls", "no save goes straight to new game")
  U.wait(40)
  U.shot(game, DIR .. "/u5_07_nosave_new_game.png")

  love.event.quit(ok and 0 or 1)
end
