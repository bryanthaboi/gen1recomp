-- pokeemerald/src/field_player_avatar.c:588 CheckMovementInputNotOnBike
-- pokeemerald/src/field_player_avatar.c:353 TryInterruptObjectEventSpecialAnim
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_run_bump_turn_2825", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_run_bump_turn_2825")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  F.noTrainerSight()
  F.setFlag("FLAG_SYS_B_DASH", true)

  S.check(F.goTo(game, "EM_ROUTE116", 21, 7, "up"), "Route 116 reached")
  local function open(x, y, fx, fy, dir)
    return Collision.canEnter(game, x, y, { fromX = fx, fromY = fy, dir = dir }) == true
      and not Collision.warpAt(x, y)
  end
  local spot
  for y = 4, 30 do
    for x = 4, 60 do
      if not spot and open(x, y + 2, x, y + 3, "up") and open(x, y + 1, x, y + 2, "up")
          and open(x, y, x, y + 1, "up") and open(x - 1, y, x, y, "left")
          and Collision.arrowWarpDir(Collision.behavior(x, y)) ~= "up"
          and not Collision.canEnter(game, x, y - 1, { fromX = x, fromY = y, dir = "up" }) then
        spot = { x = x, y = y }
      end
    end
  end
  if not S.check(spot ~= nil, "found a run-up into a wall with a free cell to the left") then return S.finish() end
  S.note(("run from (%d,%d) up into (%d,%d)"):format(spot.x, spot.y + 2, spot.x, spot.y - 1))
  F.goTo(game, "EM_ROUTE116", spot.x, spot.y + 2, "up")
  F.holdKeys(game, {}, 2)
  S.check(Player.turnArmed == true, "idle release leaves the turn armed before the run")

  local bumpFrame, ran
  F.holdKeys(game, { "up", "b" }, 80, function(i)
    if Player.moving and Player.running then ran = true end
    if Player.walkInPlace and Player.action then
      bumpFrame = i
      return true
    end
  end)
  S.check(ran == true, "the player runs up")
  S.check(bumpFrame ~= nil and Player.cellX == spot.x and Player.cellY == spot.y,
    "the run bumps the wall at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  S.still(game, "2825_01_run_bump_wall.png")

  local firstLeft, turnFrames, stepFrame = nil, 0, nil
  F.holdKeys(game, { "left", "b" }, 20, function(i)
    if not firstLeft then
      firstLeft = { facing = Player.facing, action = Player.action ~= nil, turnTimer = Player.turnTimer,
        moving = Player.moving, phase = Player.walkPhase() }
    end
    if Player.turnTimer > 0 then turnFrames = turnFrames + 1 end
    if Player.moving and Player.facing == "left" then
      stepFrame = i
      return true
    end
  end)
  S.note(("first left frame: facing=%s action=%s turnTimer=%d moving=%s phase=%d; left step on frame %s, turn frames %d")
    :format(tostring(firstLeft and firstLeft.facing), tostring(firstLeft and firstLeft.action),
      firstLeft and firstLeft.turnTimer or -1, tostring(firstLeft and firstLeft.moving),
      firstLeft and firstLeft.phase or -1, tostring(stepFrame), turnFrames))
  S.check(firstLeft ~= nil and not firstLeft.action, "the bump is cancelled on the first left frame")
  S.check(stepFrame == 1, "the left step starts on the first left frame (got " .. tostring(stepFrame) .. ")")
  S.check(turnFrames == 0, "no turn-in-place stall after the bump")
  S.still(game, "2825_02_left_step_same_frame.png")
  F.holdKeys(game, { "left", "b" }, 8)
  S.check(Player.cellX == spot.x - 1, "the player is one cell left after the step")

  F.holdKeys(game, {}, 80, function() return not Player.moving and Player.action == nil end)
  F.holdKeys(game, {}, 4)
  S.check(not Player.moving and Player.turnArmed == true and Player.facing == "left",
    "standing still facing left with the turn armed")
  F.holdKeys(game, { "right" }, 1)
  S.check(Player.facing == "right" and Player.turnTimer == 8 and not Player.moving,
    "a press away from the facing at standstill turns in place for 8 frames (turnTimer=" .. Player.turnTimer .. ")")
  S.still(game, "2825_03_standstill_turn_stride.png")
  F.holdKeys(game, { "down" }, 3)
  S.check(Player.facing == "right" and Player.turnTimer > 0 and not Player.moving,
    "a new direction during the turn is ignored (facing " .. tostring(Player.facing) .. ")")
  local turned, idle = false, 0
  F.holdKeys(game, { "down" }, 20, function()
    if Player.facing == "down" then turned = true return true end
    idle = idle + 1
  end)
  S.check(turned and Player.turnTimer == 8 and not Player.moving,
    "a different direction held when the turn ends turns again after " .. idle .. " ignored frames")
  S.check(idle == 4, "the turn holds input for 8 frames in all (ignored " .. (3 + idle) .. ")")
  F.holdKeys(game, {}, 10)
  F.holdKeys(game, { "right" }, 1)
  S.check(Player.facing == "right" and Player.turnTimer == 8, "a second different direction from standstill turns again")
  F.holdKeys(game, {}, 10)
  F.holdKeys(game, { "right" }, 12, function() return Player.moving end)
  S.check(Player.moving and Player.facing == "right", "the facing direction from standstill steps")
  S.finish()
end
