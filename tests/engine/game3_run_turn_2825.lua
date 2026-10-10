-- pokeemerald/src/field_player_avatar.c:588 CheckMovementInputNotOnBike
-- pokeemerald/src/field_player_avatar.c:353 TryInterruptObjectEventSpecialAnim
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")

local W, H = 16, 16
local grid = {}

local function setup(version, facing)
  GameVersion.set(version)
  for i = 1, W * H do grid[i] = 0x00 end
  grid[2 * W + 5 + 1] = 0xff
  Collision._grid, Collision._widthCells, Collision._heightCells = grid, W, H
  Player.reset(5, 6, facing)
  Player.biking = false
  Player.surfing = false
  Player.canDash = function() return true end
end

local function input(held, b)
  return {
    isDown = function(_, k) return k == held or (b and k == "b") end,
    wasPressed = function() return false end,
  }
end

local function framesUntilMoving(held, limit)
  for i = 1, limit do
    Player.update(nil, input(held, true))
    if Player.moving and Player.facing == held then return i end
  end
  return nil
end

for _, v in ipairs({ "emerald", "firered", "ruby" }) do
  setup(v, "up")
  Player.update(nil, input(nil))
  check(Player.turnArmed, v .. " idle release arms the turn")
  for _ = 1, 30 do Player.update(nil, input("up", true)) end
  check(Player.action ~= nil and Player.walkInPlace and Player.cellY == 3, v .. " run reaches the wall and bumps")
  eq(framesUntilMoving("left", 8), 1, v .. " new direction after the bump steps on the first frame")
  eq(Player.turnTimer, 0, v .. " no turn-in-place after the bump")

  setup(v, "up")
  Player.update(nil, input(nil))
  for _ = 1, 9 do Player.update(nil, input("up", true)) end
  check(Player.moving and Player.cellY == 5, v .. " second run step underway")
  local n = framesUntilMoving("left", 20)
  check(n ~= nil and Player.facing == "left" and Player.turnTimer == 0, v .. " mid-run turn is instant")
  eq(n, 8, v .. " left step begins the frame the up step ends")

  setup(v, "down")
  Player.update(nil, input(nil))
  eq(Player.tryMove("up", nil, true), "turned", v .. " a press away from the facing from standstill turns in place")
  eq(Player.turnTimer, 8, v .. " turn-in-place timer")
  for _ = 1, 3 do Player.update(nil, input("left", true)) end
  check(Player.facing == "up" and Player.turnTimer > 0 and not Player.moving,
    v .. " a new press during the turn is ignored")
  local ignored = 0
  for _ = 1, 20 do
    Player.update(nil, input("left", true))
    if Player.facing == "left" then break end
    ignored = ignored + 1
  end
  check(ignored == 4 and Player.facing == "left" and Player.turnTimer == 8 and not Player.moving,
    v .. " a different direction held when the turn ends turns again (" .. ignored .. ")")
  for _ = 1, 8 do Player.update(nil, input("left", true)) end
  check(Player.moving and Player.facing == "left" and Player.turnArmed == false,
    v .. " the same direction held when the second turn ends steps")

  setup(v, "down")
  Player.update(nil, input(nil))
  eq(Player.tryMove("up", nil, true), "turned", v .. " turn")
  for _ = 1, 8 do Player.update(nil, input(nil)) end
  check(Player.turnTimer == 0 and Player.turnArmed, v .. " release after the turn leaves it armed")
  eq(Player.tryMove("right", nil, true), "turned", v .. " a second direction from standstill turns again")

  setup(v, "up")
  Player.update(nil, input(nil))
  for _ = 1, 30 do Player.update(nil, input("up", true)) end
  for _ = 1, 40 do Player.update(nil, input(nil)) end
  check(Player.action == nil and Player.turnArmed, v .. " bump ends and release re-arms the turn")
  eq(Player.tryMove("left", nil, true), "turned", v .. " turn from standstill after the bump still turns")
end

T.finish("game3_run_turn_2825")
