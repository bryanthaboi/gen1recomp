local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchcoll_dynamic_warp"

local FLOOR = "FR_SILPH_CO_5F"
local ELEVATOR = "FR_SILPH_CO_ELEVATOR"
local DOOR_XY = { 22, 3 }
local EXIT_XY = { 2, 5 }

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchcoll_dynamic_warp")
    love.event.quit(0)
  else
    print("FAIL stitchcoll_dynamic_warp failures=" .. failures)
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
  local Elevator = require("src.core.game3.scripting.natives_elevator")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function walkUntil(btn, want, frames)
    for _ = 1, frames or 12 do
      if want() then return true end
      U.hold(game, btn, 16)
      U.wait(30)
    end
    return want()
  end

  goTo(FLOOR, DOOR_XY[1], DOOR_XY[2] + 1, "up")
  result(session.map == FLOOR, "the walk starts on SILPH CO 5F, got " .. tostring(session.map))
  U.shot(game, DIR .. "/stitchcoll_dynamic_warp_01_in_front_of_the_lift.png")

  local entered = walkUntil("up", function() return session.map == ELEVATOR end)
  result(entered, "walking north into the lift door arrives in the lift, got " ..
    tostring(session.map))
  -- pokefirered/src/field_control_avatar.c:982
  result(Elevator.dynamicWarpMap() == FLOOR,
    "entering the lift recorded the floor it was entered from, got " ..
    tostring(Elevator.dynamicWarpMap()))
  local dw = session.dynamicWarp
  result(type(dw) == "table" and dw.x == DOOR_XY[1] and dw.y == DOOR_XY[2],
    string.format("the recorded tile is the lift door (%d,%d), got %s,%s",
      DOOR_XY[1], DOOR_XY[2], tostring(dw and dw.x), tostring(dw and dw.y)))
  result(Player.cellX == EXIT_XY[1] and Player.cellY == EXIT_XY[2],
    string.format("the player stands on the lift's exit tile, got %s,%s",
      tostring(Player.cellX), tostring(Player.cellY)))
  U.shot(game, DIR .. "/stitchcoll_dynamic_warp_02_inside_the_lift.png")

  -- pokefirered/src/overworld.c:610
  local left = walkUntil("down", function() return session.map == FLOOR end)
  result(left, "walking south off the lift's MAP_DYNAMIC tile leaves the lift, got " ..
    tostring(session.map))
  result(Player.cellX == DOOR_XY[1] and Player.cellY == DOOR_XY[2],
    string.format("the lift puts the player back on the 5F door (%d,%d), got %s,%s",
      DOOR_XY[1], DOOR_XY[2], tostring(Player.cellX), tostring(Player.cellY)))
  U.shot(game, DIR .. "/stitchcoll_dynamic_warp_03_back_on_5f.png")

  finish()
end
