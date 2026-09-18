local U = require("tests.drivers.util")
local Boot = require("src.ui.game3.boot")
local Chrome = require("src.ui.game3.chrome")
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
  local function toTitle()
    local n = 0
    while phase() ~= "title" and n < 1500 do
      U.tap(game, "start")
      U.wait(30)
      n = n + 30
    end
    return phase() == "title"
  end
  local function err() return game.boot.saveError end

  expect(toTitle(), "reached title")
  if phase() ~= "title" then love.event.quit(1) return end

  Boot.setHasContinue(game.boot, true)
  Boot.setContinueInfo(game.boot, {
    name = "RED", gender = 0, hours = 1, minutes = 23, hasDex = true, dexCount = 12, badges = 2, frameType = 0,
  })
  U.tap(game, "start")
  waitFor(function() return phase() == "menu" and (game.boot.fadeT or 0) == 0 end, 300)
  U.wait(4)
  expect(phase() == "menu" and Chrome._user[0], "menu drawn with user frame type 1 from the cache")
  U.shot(game, DIR .. "/u5b_01_menu_user_frame_type1.png")

  game.boot.continueInfo.frameType = 6
  U.wait(4)
  expect(Chrome._user[6] ~= nil and Chrome._user[6] ~= false, "user frame type 7 loaded from the cache")
  U.shot(game, DIR .. "/u5b_02_menu_user_frame_type7.png")

  U.tap(game, "b")
  expect(waitFor(function() return phase() == "title" end, 120), "B back to title")
  U.wait(30)

  game.boot.timer = 2700 / 60 - 0.02
  expect(waitFor(function() return phase() == "title_restart" end, 10), "idle title enters the restart scene")
  waitFor(function()
    local f = game.boot.restartFade
    return f and f.bgY >= 8
  end, 120)
  local f = game.boot.restartFade
  expect(phase() == "title_restart" and f and f.bgY > 0 and f.bgY < 16, "title fading to black, no hard cut")
  U.shot(game, DIR .. "/u5b_03_restart_fading_black.png")
  expect(waitFor(function() return phase() == "intro" end, 600), "intro restarts after the black fade and BGM stop")
  U.wait(10)
  U.shot(game, DIR .. "/u5b_04_restart_back_to_intro.png")

  expect(toTitle(), "back to title for the save error")
  Boot.setHasContinue(game.boot, true)
  Boot.setSaveStatus(game.boot, "error")
  U.tap(game, "start")
  waitFor(function() return err() and (game.boot.fadeT or 0) == 0 end, 300)
  U.wait(30)
  expect(err() ~= nil and err().page == 1, "corrupted save window before the menu")
  U.shot(game, DIR .. "/u5b_05_save_corrupted_typing.png")
  waitFor(function() return err() and err().waiting end, 400)
  U.wait(10)
  expect(err() and err().waiting == "prompt", "page 1 waits on the down arrow")
  U.shot(game, DIR .. "/u5b_06_save_corrupted_prompt.png")
  U.tap(game, "a")
  waitFor(function() return err() and err().waiting == "done" end, 400)
  expect(err() and err().page == 2, "page 2 printed")
  U.shot(game, DIR .. "/u5b_07_save_corrupted_page2.png")
  U.tap(game, "a")
  waitFor(function() return phase() == "menu" and not err() and (game.boot.fadeT or 0) == 0 end, 120)
  U.wait(4)
  expect(phase() == "menu" and not err(), "menu after the corrupted-save window")
  U.shot(game, DIR .. "/u5b_08_menu_after_corrupted.png")

  U.tap(game, "b")
  waitFor(function() return phase() == "title" end, 120)
  U.wait(30)
  Boot.setHasContinue(game.boot, false)
  Boot.setSaveStatus(game.boot, "invalid")
  U.tap(game, "start")
  waitFor(function() return err() and err().waiting == "done" end, 600)
  U.wait(10)
  expect(err() and #err().pages == 1, "deleted save message")
  U.shot(game, DIR .. "/u5b_09_save_deleted.png")
  U.tap(game, "a")
  expect(waitFor(function() return phase() == "controls" end, 30), "new game after the deleted message")
  U.wait(40)
  U.shot(game, DIR .. "/u5b_10_deleted_new_game.png")

  love.event.quit(ok and 0 or 1)
end
