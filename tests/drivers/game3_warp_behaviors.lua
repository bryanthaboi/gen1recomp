local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_warp_behaviors"

local ROUTE_20 = "FR_ROUTE_20"
local SEAFOAM_1F = "FR_SEAFOAM_ISLANDS_1F"
local SEAFOAM_B1F = "FR_SEAFOAM_ISLANDS_B1F"
local SEAFOAM_B2F = "FR_SEAFOAM_ISLANDS_B2F"
local SEAFOAM_B3F = "FR_SEAFOAM_ISLANDS_B3F"
local VR3 = "FR_VICTORY_ROAD_3F"
local VR2 = "FR_VICTORY_ROAD_2F"
local GATE = "FR_ROUTE_7_EAST_ENTRANCE"
local ROUTE7 = "FR_ROUTE_7"
local MTMOON_1F = "FR_MT_MOON_1F"
local MTMOON_B1F = "FR_MT_MOON_B1F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS warp_behaviors")
    love.event.quit(0)
  else
    print("FAIL warp_behaviors failures=" .. failures)
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
  local Warp = require("src.core.game3.warp")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    U.wait(90)
  end

  local function holdUntil(dir, pred, maxFrames)
    for _ = 1, (maxFrames or 150) do
      if pred() then break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
  end

  local function stepOnto(dir, tx, ty)
    holdUntil(dir, function()
      if Player.moving then return Player.targetX == tx and Player.targetY == ty end
      return Player.cellX == tx and Player.cellY == ty
    end, 150)
    for _ = 1, 60 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(20)
  end

  local function pressUntilWarp(dir, fromMap)
    holdUntil(dir, function()
      return require("src.core.game3.warp").isBusy() or Map.current ~= fromMap
    end, 150)
  end

  local function settle(n)
    for _ = 1, (n or 400) do
      if not Warp.isBusy() then break end
      U.wait(1)
    end
    U.wait(30)
  end

  local function where()
    return tostring(Map.current), Player.cellX, Player.cellY
  end

  print("[driver] 1. Seafoam Islands 1F drop hole (21,8) -> B1F (21,8)")
  goTo(SEAFOAM_1F, 23, 8, "left")
  result(Collision.behavior(21, 8) == 0x66, "Seafoam 1F (21,8) is MB_FALL_WARP")
  result(Collision.warpAt(21, 8) ~= nil, "Seafoam 1F (21,8) indexes its warp event")
  U.shot(game, DIR .. "/warp_behaviors_01_seafoam_before.png")

  pressUntilWarp("left", SEAFOAM_1F)
  settle()
  local m, x, y = where()
  print(string.format("[driver] after the Seafoam hole: %s (%d,%d) facing=%s", m, x, y, Player.facing))
  result(m == SEAFOAM_B1F, "the drop hole warped to Seafoam B1F (" .. m .. ")")
  result(x == 21 and y == 8, string.format("landed on B1F (21,8), got (%d,%d)", x, y))
  result(Player.facing == "down", "a fall warp lands facing south (" .. tostring(Player.facing) .. ")")
  result((Player.spriteYOffset or 0) == 0, "the fall animation finished and the avatar is on the floor")
  result(Player.isVisible() == true, "the avatar is visible again after the fall")
  U.shot(game, DIR .. "/warp_behaviors_02_seafoam_landed.png")

  print("[driver] 2. Victory Road 3F drop hole (34,18) -> 2F (34,19)")
  goTo(VR3, 33, 18, "right")
  result(Collision.behavior(34, 18) == 0x66, "Victory Road 3F (34,18) is MB_FALL_WARP")
  pressUntilWarp("right", VR3)
  settle()
  m, x, y = where()
  print(string.format("[driver] after the Victory Road hole: %s (%d,%d)", m, x, y))
  result(m == VR2, "the drop hole warped to Victory Road 2F (" .. m .. ")")
  result(x == 34 and y == 19, string.format("landed on 2F (34,19), got (%d,%d)", x, y))
  U.shot(game, DIR .. "/warp_behaviors_03_victory_road_landed.png")

  print("[driver] 3. Route 7 west gate arrow warp (1,5)")
  goTo(GATE, 1, 4, "down")
  result(Collision.behavior(1, 5) == 0x63, "the gate's west exit (1,5) is MB_WEST_ARROW_WARP")

  stepOnto("down", 1, 5)
  m, x, y = where()
  print(string.format("[driver] after stepping onto the arrow tile: %s (%d,%d)", m, x, y))
  result(m == GATE and x == 1 and y == 5,
    "stepping onto a west-arrow tile from the north does not warp")
  U.shot(game, DIR .. "/warp_behaviors_04_arrow_standing.png")

  pressUntilWarp("left", GATE)
  settle()
  m, x, y = where()
  print(string.format("[driver] after pressing west on it: %s (%d,%d) facing=%s", m, x, y, Player.facing))
  result(m == ROUTE7, "pressing west on the arrow tile warps out to Route 7 (" .. m .. ")")
  result(x == 15 and y == 10, string.format("landed on Route 7 (15,10), got (%d,%d)", x, y))
  result(Player.facing == "left",
    "landing on an east-arrow tile faces west (" .. tostring(Player.facing) .. ")")
  U.shot(game, DIR .. "/warp_behaviors_05_arrow_warped.png")

  print("[driver] 4. Mt Moon 1F ladder (5,6) -> B1F (3,3)")
  goTo(MTMOON_1F, 6, 6, "left")
  result(Collision.behavior(5, 6) == 0x61, "Mt Moon 1F (5,6) is MB_LADDER")
  pressUntilWarp("left", MTMOON_1F)
  settle()
  m, x, y = where()
  print(string.format("[driver] after the ladder: %s (%d,%d) facing=%s", m, x, y, Player.facing))
  result(m == MTMOON_B1F, "the ladder warped to Mt Moon B1F (" .. m .. ")")
  result(x == 3 and y == 3, string.format("landed on B1F (3,3), got (%d,%d)", x, y))
  result(Player.facing == "left",
    "a ladder keeps the direction the player left with (" .. tostring(Player.facing) .. ")")
  U.shot(game, DIR .. "/warp_behaviors_06_ladder_landed.png")

  print("[driver] 5. Seafoam B2F drop hole (24,8) -> B3F (23,9), a current")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  -- pokefirered/data/maps/Route20/scripts.inc:5-27
  goTo(ROUTE_20, 30, 9, "left")
  goTo(SEAFOAM_B2F, 23, 8, "right")
  result(Collision.behavior(24, 8) == 0x66, "Seafoam B2F (24,8) is MB_FALL_WARP")
  U.shot(game, DIR .. "/warp_behaviors_07_seafoam_b2f_before.png")

  pressUntilWarp("right", SEAFOAM_B2F)
  for _ = 1, 400 do
    if not Warp.isBusy() then break end
    U.wait(1)
  end
  -- pokefirered/src/field_effect.c:1274-1291
  for _ = 1, 60 do
    if Player.surfing and tonumber(Flags.getVar(Space.store, nil, "VAR_TEMP_1")) == 1 then break end
    U.wait(1)
  end
  m, x, y = where()
  local landBeh = Collision.behavior(x, y)
  print(string.format("[driver] after the B2F hole: %s (%d,%d) beh=0x%02X surfing=%s water=%s var=%s",
    m, x, y, landBeh or 255, tostring(Player.surfing),
    tostring(Collision.isWater(x, y)), tostring(Flags.getVar(Space.store, nil, "VAR_TEMP_1"))))
  result(m == SEAFOAM_B3F, "the B2F drop hole warped to Seafoam B3F (" .. m .. ")")
  result(x == 23 and y == 9, string.format("landed on B3F (23,9), got (%d,%d)", x, y))
  result(landBeh == 0x53, "the landing cell is MB_SOUTHWARD_CURRENT")
  result(Collision.isSurfable(landBeh) == true, "MB_SOUTHWARD_CURRENT is in sBehaviorSurfable")
  result(Collision.isWater(x, y) == true, "a current bakes as water, not walkable floor")
  result(Player.surfing == true, "FallWarpEffect_7 put the player on Surf")
  result(tonumber(Flags.getVar(Space.store, nil, "VAR_TEMP_1")) == 1,
    "FallWarpEffect_7 set VAR_TEMP_1 for the B3F on-frame current script")
  U.shot(game, DIR .. "/warp_behaviors_08_seafoam_b3f_surf.png")

  finish()
end
