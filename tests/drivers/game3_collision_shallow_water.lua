local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_collision_shallow_water"

local FOUR_ISLAND = "FR_FOUR_ISLAND"
local ROUTE_21_NORTH = "FR_ROUTE_21_NORTH"
local SILPH = "FR_SILPH_CO_1F"

-- pokefirered/include/constants/metatile_behaviors.h:20
local MB_PUDDLE = 0x16
local MB_SHALLOW_WATER = 0x17

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS collision_shallow_water")
    love.event.quit(0)
  else
    print("FAIL collision_shallow_water failures=" .. failures)
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

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")

  local function settle(limit)
    for _ = 1, (limit or 240) do
      local busy = (Space.vm and Space.vm:isRunning())
        or (Message.isOpen and Message.isOpen())
      if not busy then return true end
      if Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
      end
      U.wait(4)
    end
    return false
  end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.moving = false
    Player.progress = 0
    Player.facing = facing or "down"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing)
    U.wait(90)
    local idle = settle(600)
    place(x, y, facing)
    U.wait(20)
    print(string.format("[driver] %s ready at (%d,%d) idle=%s",
      mapId, Player.cellX, Player.cellY, tostring(idle)))
  end

  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  local function step(dir)
    local fromX, fromY = Player.cellX, Player.cellY
    local d = DELTA[dir]
    local ok, why = Collision.canEnter(game, fromX + d[1], fromY + d[2],
      { fromX = fromX, fromY = fromY, dir = dir })
    print(string.format("[driver] step %s from (%d,%d): canEnter=%s reason=%s",
      dir, fromX, fromY, tostring(ok), tostring(why)))
    for _ = 1, 3 do
      U.hold(game, dir, 4)
      for _ = 1, 30 do
        U.wait(1)
        if not Player.moving then break end
      end
      if Player.cellX ~= fromX or Player.cellY ~= fromY then break end
    end
    return Player.cellX, Player.cellY
  end

  print("[driver] 1. Four Island shore puddle")
  goTo(FOUR_ISLAND, 15, 6, "left")
  result(Collision.behavior(14, 6) == MB_PUDDLE,
    string.format("%s (14,6) is MB_PUDDLE (0x%02X)", FOUR_ISLAND,
      Collision.behavior(14, 6) or 0))
  result(Collision.isWater(14, 6) == false, "the puddle is not surf water")
  local x, y = step("left")
  result(x == 14 and y == 6,
    string.format("walked west into the puddle, at (%d,%d)", x, y))
  x, y = step("left")
  result(x == 13 and y == 6,
    string.format("kept walking through the puddle, at (%d,%d)", x, y))
  result(Player.surfing ~= true, "walking the puddle did not put the player on Surf")
  U.shot(game, DIR .. "/collision_shallow_water_01_four_island_puddle.png")

  print("[driver] 2. Route 21 North shallow water")
  goTo(ROUTE_21_NORTH, 16, 23, "left")
  result(Collision.behavior(15, 23) == MB_SHALLOW_WATER,
    string.format("%s (15,23) is MB_SHALLOW_WATER (0x%02X)", ROUTE_21_NORTH,
      Collision.behavior(15, 23) or 0))
  result(Collision.isSurfable(Collision.behavior(15, 23)) == false,
    "MB_SHALLOW_WATER is not in sBehaviorSurfable")
  x, y = step("left")
  result(x == 15 and y == 23,
    string.format("waded west onto the shallow water, at (%d,%d)", x, y))
  result(Player.surfing ~= true, "wading did not put the player on Surf")
  U.shot(game, DIR .. "/collision_shallow_water_02_route21_shallow.png")
  x, y = step("down")
  result(x == 15 and y == 24,
    string.format("walked on south off the shallow water, at (%d,%d)", x, y))

  print("[driver] 3. Silph Co lobby pool keeps its map collision")
  goTo(SILPH, 13, 7, "down")
  result(Collision.behavior(13, 8) == MB_PUDDLE,
    string.format("%s (13,8) is MB_PUDDLE (0x%02X)", SILPH,
      Collision.behavior(13, 8) or 0))
  x, y = step("down")
  result(x == 13 and y == 7,
    string.format("the lobby pool still blocks the player, at (%d,%d)", x, y))
  U.shot(game, DIR .. "/collision_shallow_water_03_silph_pool_blocked.png")

  finish()
end
