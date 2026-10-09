#!/usr/bin/env luajit
-- pokeemerald/src/field_player_avatar.c:353 TryInterruptObjectEventSpecialAnim
-- pokefirered/src/field_player_avatar.c:156 TryInterruptObjectEventSpecialAnim

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local GameVersion = require("src.core.GameVersion")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")

local W, H = 16, 16
local grid = {}

local function setup(version)
  GameVersion.set(version)
  for i = 1, W * H do grid[i] = 0x00 end
  grid[4 * W + 5 + 1] = 0xff
  Collision._grid, Collision._widthCells, Collision._heightCells = grid, W, H
  Player.action = nil
  Player.moving = false
  Player.biking = false
  Player.surfing = false
  Player.turnTimer = 0
  Player.turnArmed = false
  Player.walkInPlace = false
  Player.cellX, Player.cellY = 5, 5
  Player.targetX, Player.targetY = 5, 5
  Player.px, Player.py = 80, 80
  Player.facing = "up"
end

local function input(held, pressed)
  return {
    isDown = function(_, k) return k == held end,
    wasPressed = function(_, k) return k == pressed end,
  }
end

local function bump()
  Player.tryMove("up", nil, true)
  for _ = 1, 3 do Player.update(nil, input("up")) end
end

for _, v in ipairs({ "emerald", "firered", "ruby" }) do
  print("[test] " .. v .. ": turning away cancels the wall bump")
  setup(v)
  bump()
  check(Player.action ~= nil and Player.walkInPlace, v .. " bump is running")
  Player.update(nil, input("left", "left"))
  check(Player.action == nil, v .. " bump cleared on a new direction")
  check(Player.moving and Player.targetX == 4 and Player.targetY == 5,
    v .. " player steps left on the same frame")

  print("[test] " .. v .. ": holding into the wall keeps bumping")
  setup(v)
  bump()
  Player.update(nil, input("up"))
  check(Player.action ~= nil, v .. " bump continues while still blocked")
end

print("[test] emerald: blocker cleared mid-bump cancels it")
setup("emerald")
bump()
grid[4 * W + 5 + 1] = 0x00
Player.update(nil, input("up"))
check(Player.action == nil and Player.moving and Player.targetY == 4,
  "emerald walks on once the cell opens")

print("[test] firered: blocker cleared mid-bump still finishes the bump")
setup("firered")
bump()
grid[4 * W + 5 + 1] = 0x00
Player.update(nil, input("up"))
check(Player.action ~= nil, "firered keeps the bump")

print("[test] bike bumps are not interruptible")
setup("emerald")
Player.biking = true
Player.tryMove("up", nil, true)
check(Player.action ~= nil and not Player.action.interruptible, "bike bump uninterruptible")
Player.biking = false
Player.action = nil

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
