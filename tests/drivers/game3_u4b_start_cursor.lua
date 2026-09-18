local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function waitFor(pred, n)
  for _ = 1, n do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function finish()
  if failures == 0 then
    print("PASS u4b_start_cursor")
    love.event.quit(0)
  else
    print("FAIL u4b_start_cursor failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PLAYERS_HOUSE_2F", { x = 1, y = 2, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 1, 2, "up"
  U.wait(90)

  local StartMenu = require("src.ui.game3.start_menu")
  local function openMenu()
    U.tap(game, "start")
    return waitFor(function() return StartMenu.isOpen() end, 60)
  end
  local function closeMenu(btn)
    U.tap(game, btn or "b")
    return waitFor(function() return not StartMenu.isOpen() end, 60)
  end
  local function rowOf(id)
    for i, e in ipairs(StartMenu.ENTRIES) do
      if e.id == id then return i end
    end
  end

  if not result(openMenu(), "start opens the menu") then return finish() end
  U.wait(10)
  result(StartMenu.cursor == 1, "first open after boot on row 1")
  U.shot(game, DIR .. "/u4b_01_first_open_row1.png")

  U.tap(game, "down") U.wait(4)
  U.tap(game, "down") U.wait(4)
  local trainerRow = rowOf("trainer")
  result(StartMenu.cursor == trainerRow, "moved to trainer row " .. tostring(trainerRow))
  result(closeMenu("b"), "B closes")
  U.wait(20)

  result(openMenu(), "reopen")
  U.wait(10)
  result(StartMenu.cursor == trainerRow, "reopen keeps trainer row")
  U.shot(game, DIR .. "/u4b_02_reopen_keeps_trainer_row.png")

  local exitRow = rowOf("exit")
  for _ = 1, exitRow - StartMenu.cursor do
    U.tap(game, "down") U.wait(4)
  end
  result(StartMenu.cursor == exitRow, "cursor on EXIT")
  U.tap(game, "a")
  result(waitFor(function() return not StartMenu.isOpen() end, 60), "EXIT closes")
  U.wait(20)

  result(openMenu(), "reopen after EXIT")
  U.wait(10)
  result(StartMenu.cursor == exitRow, "reopen after EXIT lands on EXIT")
  U.shot(game, DIR .. "/u4b_03_reopen_on_exit.png")
  result(closeMenu("start"), "START closes")
  U.wait(10)

  Map.load(nil, game, "FR_PLAYERS_HOUSE_1F", { x = 8, y = 4, facing = "down" })
  game.session.x, game.session.y, game.session.facing = 8, 4, "down"
  U.wait(120)
  result(openMenu(), "open after map change")
  U.wait(10)
  result(StartMenu.cursor == exitRow, "map change keeps EXIT row")
  U.shot(game, DIR .. "/u4b_04_after_map_change_on_exit.png")
  closeMenu("b")
  U.wait(10)

  finish()
end
