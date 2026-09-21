local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_start_forced"

local B2F = "FR_ROCKET_HIDEOUT_B2F"
local RUN_X, RUN_Y = 4, 4
local SPIN_X, SPIN_Y = 3, 4
local RUN_END_X, RUN_END_Y = 1, 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_start_forced")
    love.event.quit(0)
  else
    print("FAIL stitchuif_start_forced failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Space = require("src.core.game3.scripting.space")
  local ForcedMovement = require("src.core.game3.forced_movement")
  local StartMenu = require("src.ui.game3.start_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.repelSteps = 250

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(60)
  end

  local function push(dir)
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then return true end
    end
    return false
  end

  goTo(B2F, RUN_X, RUN_Y, "left")
  result(Space.mapId == B2F, "stood on Rocket Hideout B2F, map=" .. tostring(Space.mapId))
  result(Collision.behavior(SPIN_X, SPIN_Y) == 0x55,
    "(3,4) carries MB_SPIN_LEFT, got " .. tostring(Collision.behavior(SPIN_X, SPIN_Y)))
  result(StartMenu.isOpen() == false, "no start menu before the run")

  U.tap(game, "start")
  U.wait(20)
  result(StartMenu.isOpen() == true, "START opens the menu on a free tile")
  U.tap(game, "b")
  U.wait(20)
  result(StartMenu.isOpen() == false, "B closed the menu again")

  result(push("left"), "the player steps west onto MB_SPIN_LEFT")
  local took = false
  for _ = 1, 120 do
    if ForcedMovement.isForced() then took = true break end
    U.wait(1)
  end
  result(took, "PLAYER_AVATAR_FLAG_FORCED is set by the spinner")

  local opened, forcedFrames, shot = 0, 0, false
  for _ = 1, 600 do
    if not (Player.moving or ForcedMovement.isForced()) then break end
    if ForcedMovement.isForced() then
      forcedFrames = forcedFrames + 1
      U.tap(game, "start")
      if StartMenu.isOpen() then
        print("[driver] menu opened on forced frame " .. forcedFrames ..
          ", isForced now=" .. tostring(ForcedMovement.isForced()) ..
          " moving=" .. tostring(Player.moving))
        if ForcedMovement.isForced() then opened = opened + 1 end
        StartMenu.close()
        U.wait(6)
      end
      if not shot and forcedFrames >= 6 then
        shot = U.shot(game, DIR .. "/stitchuif_start_forced_02_start_mid_spin.png")
      end
    else
      U.wait(1)
    end
  end
  result(forcedFrames > 1, "the run spanned " .. forcedFrames .. " forced frames")
  result(opened == 0, "START never opened the menu while the run still owned the player")
  result(shot, "shot the player mid-spin with START pressed")

  result(Player.cellX == RUN_END_X and Player.cellY == RUN_END_Y,
    string.format("the run ended on the stop tile (%d,%d), got (%s,%s)",
      RUN_END_X, RUN_END_Y, tostring(Player.cellX), tostring(Player.cellY)))
  result(ForcedMovement.isForced() == false, "MB_STOP_SPINNING cleared the forced flag")
  result(StartMenu.isOpen() == false, "the menu is still shut when the run ends")

  U.tap(game, "start")
  U.wait(20)
  result(StartMenu.isOpen() == true, "START opens again once the run is over")
  U.shot(game, DIR .. "/stitchuif_start_forced_03_menu_after_run.png")
  U.tap(game, "b")
  U.wait(20)

  finish()
end
