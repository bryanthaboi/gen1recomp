local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_spinners"

local B2F = "FR_ROCKET_HIDEOUT_B2F"
local STOP_X, STOP_Y = 13, 7
local SPIN_RIGHT_X, SPIN_RIGHT_Y = 12, 7
local RUN_X, RUN_Y = 4, 4
local RUN_END_X, RUN_END_Y = 1, 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_spinners")
    love.event.quit(0)
  else
    print("FAIL field_spinners failures=" .. failures)
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

  local function settle(limit)
    for _ = 1, (limit or 600) do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(2)
  end

  goTo(B2F, STOP_X, STOP_Y, "left")
  result(Space.mapId == B2F, "stood on Rocket Hideout B2F, map=" .. tostring(Space.mapId))
  result(Collision.behavior(STOP_X, STOP_Y) == 0x58,
    "(13,7) carries MB_STOP_SPINNING, got " .. tostring(Collision.behavior(STOP_X, STOP_Y)))
  result(Collision.behavior(SPIN_RIGHT_X, SPIN_RIGHT_Y) == 0x54,
    "(12,7) carries MB_SPIN_RIGHT, got " ..
    tostring(Collision.behavior(SPIN_RIGHT_X, SPIN_RIGHT_Y)))
  U.wait(90)
  result(U.shot(game, DIR .. "/field_spinners_01_before.png"), "shot the stop tile")

  result(push("left"), "the player steps west onto the spinner")
  settle()
  result(Player.cellX == STOP_X and Player.cellY == STOP_Y,
    string.format("MB_SPIN_RIGHT threw the player back to (%d,%d), got (%s,%s)",
      STOP_X, STOP_Y, tostring(Player.cellX), tostring(Player.cellY)))
  result(ForcedMovement.forced == false, "MB_STOP_SPINNING cleared the forced flag")
  result(Player.spinning == false, "the spin animation stopped")
  result(U.shot(game, DIR .. "/field_spinners_02_thrown_back.png"),
    "shot the player back on the stop tile")

  goTo(B2F, RUN_X, RUN_Y, "left")
  result(Collision.behavior(3, 4) == 0x55,
    "(3,4) carries MB_SPIN_LEFT, got " .. tostring(Collision.behavior(3, 4)))
  result(Collision.behavior(2, 4) == 0x00,
    "(2,4) is plain floor mid-run, got " .. tostring(Collision.behavior(2, 4)))
  result(push("left"), "the player steps west onto MB_SPIN_LEFT")
  U.wait(18)
  result(Player.moving and Player.cellX < RUN_X,
    string.format("the spin carries on with no further input, at (%s,%s)",
      tostring(Player.cellX), tostring(Player.cellY)))
  result(U.shot(game, DIR .. "/field_spinners_03_mid_spin.png"), "shot the player mid-spin")
  settle()
  result(Player.cellX == RUN_END_X and Player.cellY == RUN_END_Y,
    string.format("the run ends on the stop tile (%d,%d), got (%s,%s)",
      RUN_END_X, RUN_END_Y, tostring(Player.cellX), tostring(Player.cellY)))
  result(Collision.behavior(Player.cellX, Player.cellY) == 0x58,
    "the cell under the player is MB_STOP_SPINNING")
  result(U.shot(game, DIR .. "/field_spinners_04_run_end.png"), "shot the end of the run")

  finish()
end
