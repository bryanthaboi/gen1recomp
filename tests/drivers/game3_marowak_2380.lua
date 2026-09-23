local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_marowak_2380"
return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish() love.event.quit(failures == 0 and 0 or 1) end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Battle = require("src.core.game3.battle")
  local Collision = require("src.core.game3.collision")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  if not check(session ~= nil, "marowak_new_game") then return finish() end
  session.party = {}
  Party.giveMon(session, 150, 100)
  session.party[1].moves, session.party[1].pp = { 94 }, { 10 }
  session.party[1].maxPp = { 10 }
  Bag.add(session.bag, 359, 1)
  local function place(x, y, facing)
    Player.moving, Player.progress = false, 0
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
    Player.px, Player.py, Player.facing = x * 16, y * 16, facing
    session.x, session.y, session.facing = x, y, facing
  end
  local function walk(dir)
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then break end
    end
    for _ = 1, 120 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(4)
  end
  Map.load(nil, game, "FR_POKEMON_TOWER_6F", { x = 11, y = 14, facing = "down" })
  place(11, 14, "down")
  U.wait(150)
  check(Flags.getVar(Space.store, nil, 0x4059) == 0, "marowak_scene_starts_zero")
  walk("down")
  for _ = 1, 300 do
    if Battle.isActive() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check(Battle.isActive(), "marowak_coord_script_started_battle") then return finish() end
  local farewell = false
  for _ = 1, 1800 do
    if not Battle.isActive() and Message.isOpen()
        and Message.currentPage():lower():find("mother", 1, true) then
      farewell = true
      break
    end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check(farewell and session.battleOutcome == 1, "marowak_win_reaches_farewell") then return finish() end
  U.wait(150)
  check(U.shot(game, DIR .. "/2380_marowak_mothers_spirit_farewell.png"), "marowak_farewell_screenshot_written")
  local deadline = love.timer.getTime() + 8
  while love.timer.getTime() < deadline do
    if not Message.isOpen() and not Space.vm:isRunning() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check(Flags.getVar(Space.store, nil, 0x4059) == 1, "marowak_scene_completed") then return finish() end
  walk("up")
  walk("down")
  check(Player.cellX == 11 and Player.cellY == 15 and not Space.vm:isRunning()
    and not Battle.isActive(), "marowak_first_trigger_stays_cleared")
  place(13, 16, "left")
  walk("left")
  check(Player.cellX == 12 and Player.cellY == 16 and not Space.vm:isRunning()
    and not Battle.isActive(), "marowak_second_trigger_stays_cleared")
  walk("left")
  if not check(Player.cellX == 11 and Player.cellY == 16
    and Collision.isStairWarp(game, 11, 16, "left") ~= nil,
    "marowak_standing_on_7f_stairs") then return finish() end
  walk("left")
  U.wait(180)
  if not check(Runtime.getSession().map == "FR_POKEMON_TOWER_7F", "marowak_reached_7f") then return finish() end
  check(U.shot(game, DIR .. "/2380_tower_7f_after_marowak.png"), "marowak_7f_screenshot_written")
  if not check(game:saveGame() == true, "marowak_save_written") then return finish() end
  game:_handleBootAction({ action = "continue" })
  U.wait(60)
  for _ = 1, 400 do
    if game.phase ~= "quest_log" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(180)
  session = Runtime.getSession()
  check(session and session.map == "FR_POKEMON_TOWER_7F"
    and Flags.getVar(Space.store, nil, 0x4059) == 1, "marowak_continue_keeps_scene_and_7f")
  Map.load(nil, game, "FR_POKEMON_TOWER_6F", { x = 11, y = 14, facing = "down" })
  place(11, 14, "down")
  U.wait(90)
  walk("down")
  check(not Space.vm:isRunning() and not Battle.isActive()
    and Flags.getVar(Space.store, nil, 0x4059) == 1, "marowak_no_respawn_after_reload")
  walk("down")
  if not check(Player.cellX == 11 and Player.cellY == 16
    and Collision.isStairWarp(game, 11, 16, "left") ~= nil,
    "marowak_standing_on_7f_stairs_after_reload") then return finish() end
  walk("left")
  U.wait(180)
  if check(session.map == "FR_POKEMON_TOWER_7F", "marowak_7f_access_after_reload") then
    check(U.shot(game, DIR .. "/2380_tower_7f_after_save_reload.png"), "marowak_reload_screenshot_written")
  end
  finish()
end
