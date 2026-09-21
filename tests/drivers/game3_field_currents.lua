local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_currents"

local ROUTE_20 = "FR_ROUTE_20"
local B4F = "FR_SEAFOAM_ISLANDS_B4F"
local START_X, START_Y = 9, 5
local CORNER_X = 16
local END_X, END_Y = 16, 1

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_currents")
    love.event.quit(0)
  else
    print("FAIL field_currents failures=" .. failures)
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
    Player.surfing = true
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

  -- pokefirered/data/maps/Route20/scripts.inc:5-27
  goTo(ROUTE_20, 30, 9, "left")

  goTo(B4F, START_X, START_Y, "right")
  result(Space.mapId == B4F, "surfed onto Seafoam Islands B4F, map=" .. tostring(Space.mapId))
  result(Player.surfing == true, "the player is on Surf")
  result(Collision.behavior(START_X, START_Y) == 0x50,
    "(9,5) carries MB_EASTWARD_CURRENT, got " ..
    tostring(Collision.behavior(START_X, START_Y)))
  result(Collision.behavior(CORNER_X, START_Y) == 0x52,
    "(16,5) carries MB_NORTHWARD_CURRENT, got " ..
    tostring(Collision.behavior(CORNER_X, START_Y)))
  result(U.shot(game, DIR .. "/field_currents_01_before.png"), "shot the surfer in the current")

  result(push("right"), "the surfer paddles one cell east")
  for _ = 1, 30 do
    if not Player.moving then break end
    U.wait(1)
  end
  result(Player.cellX > START_X, "the eastward current already moved them on")
  result(U.shot(game, DIR .. "/field_currents_02_carried_east.png"),
    "shot the surfer being carried east")

  for _ = 1, 600 do
    if not Player.moving then break end
    U.wait(1)
  end
  U.wait(4)
  result(Player.cellX == END_X and Player.cellY == END_Y,
    string.format("the currents deliver the surfer to (%d,%d), got (%s,%s)",
      END_X, END_Y, tostring(Player.cellX), tostring(Player.cellY)))
  result(ForcedMovement.forced == false, "leaving the last current cleared the forced flag")
  result(U.shot(game, DIR .. "/field_currents_03_maze_end.png"),
    "shot the end of the current maze")

  finish()
end
