local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchfield_ground"

local FOUR_ISLAND = "FR_FOUR_ISLAND"
local ROUTE_21_NORTH = "FR_ROUTE_21_NORTH"
local EMBER_SPA = "FR_ONE_ISLAND_KINDLE_ROAD_EMBER_SPA"

-- pokefirered/include/constants/vars.h:186
local VAR_MAP_SCENE_FOUR_ISLAND = 0x4086

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchfield_ground")
    love.event.quit(0)
  else
    print("FAIL stitchfield_ground failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local FieldEffects = require("src.core.game3.field_effects")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function place(x, y, facing)
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
    U.wait(90)
  end

  local function waitFor(fn, limit)
    for _ = 1, (limit or 600) do
      if fn() then return true end
      U.wait(1)
    end
    return fn()
  end

  local function where()
    return tostring(Space.mapId) .. " (" .. tostring(Player.cellX) .. ","
      .. tostring(Player.cellY) .. ") facing=" .. tostring(Player.facing)
      .. " phase=" .. tostring(game.phase)
  end

  local function step(dir, x, y)
    for _ = 1, 240 do
      if Player.cellX == x and Player.cellY == y and not Player.moving then return true end
      if Player.moving and Player.targetX == x and Player.targetY == y then break end
      U.hold(game, dir, 1)
    end
    waitFor(function() return not Player.moving end, 90)
    if Player.cellX == x and Player.cellY == y then return true end
    print("[driver] step " .. dir .. " wanted (" .. x .. "," .. y .. ") at " .. where())
    return Player.cellX == x and Player.cellY == y
  end

  local function count(kind)
    local n = 0
    for _, anim in ipairs(FieldEffects._anims) do
      if anim.kind == kind then n = n + 1 end
    end
    return n
  end

  print("[driver] --- Four Island: the pond edge puddles ---")
  -- pokefirered/data/maps/FourIsland/scripts.inc:23 FourIsland_OnFrame
  Flags.setVar(Space.store, Space.vm and Space.vm.ctx, VAR_MAP_SCENE_FOUR_ISLAND, 1)
  goTo(FOUR_ISLAND, 20, 9, "left")
  print("[driver] on " .. tostring(Space.mapId) .. " at (" .. tostring(Player.cellX)
    .. "," .. tostring(Player.cellY) .. ") behavior="
    .. string.format("0x%02X", Collision.behavior(Player.cellX, Player.cellY) or 0))
  result(Collision.behavior(19, 9) == 0x16 and Collision.behavior(18, 9) == 0x16,
    "the cells west of the player are MB_PUDDLE")

  local rippled = false
  local splashed = false
  U.hold(game, "left", 1)
  for _ = 1, 200 do
    if count("ripple") >= 1 then rippled = true end
    if count("splash") >= 1 then splashed = true end
    if Player.cellX <= 18 and not Player.moving then break end
    U.hold(game, "left", 1)
  end
  result(Player.cellX <= 19, "walked off dry land onto the puddle cells, x=" .. Player.cellX)
  result(rippled, "the landing rippled")
  result(splashed, "puddle to puddle splashed")
  U.shot(game, DIR .. "/stitchfield_ground_01_four_island_puddle.png")

  print("[driver] --- Route 21 North: wading the sandbar ---")
  goTo(ROUTE_21_NORTH, 17, 24, "right")
  result(Collision.behavior(18, 24) == 0x17 and Collision.behavior(18, 25) == 0x17,
    "the sandbar cells are MB_SHALLOW_WATER")
  result(step("right", 18, 24), "stepped onto the sandbar")
  -- pokefirered/src/event_object_movement.c:5343 ShiftStillObjectEventCoords
  result(count("feet_water") == 1, "the first sandbar cell wades, effects="
    .. count("feet_water"))
  result(step("down", 18, 25), "waded along the sandbar")
  result(count("feet_water") == 1, "the feet-in-flowing-water effect is still running, effects="
    .. count("feet_water"))
  U.shot(game, DIR .. "/stitchfield_ground_03_route21_wading.png")
  result(step("left", 17, 25), "waded on")
  result(count("feet_water") == 1, "still exactly one effect, effects=" .. count("feet_water"))
  result(step("left", 16, 25), "stepped off the sandbar")
  result(count("feet_water") == 0, "and it stopped, effects=" .. count("feet_water"))

  print("[driver] --- Ember Spa: the hot spring ---")
  goTo(EMBER_SPA, 13, 10, "down")
  result(Collision.behavior(13, 11) == 0x28 and Collision.behavior(13, 12) == 0x28,
    "the spa pool is MB_HOT_SPRINGS")
  result(step("down", 13, 11), "stepped into the spa")
  -- pokefirered/src/event_object_movement.c:5343 ShiftStillObjectEventCoords
  result(count("hot_springs") == 1, "the first spring cell steams, effects="
    .. count("hot_springs"))
  result(step("down", 13, 12), "waded deeper")
  result(count("hot_springs") == 1, "the spa is still steaming, effects=" .. count("hot_springs"))
  U.shot(game, DIR .. "/stitchfield_ground_04_ember_spa_steam.png")
  result(step("up", 13, 11) and step("up", 13, 10), "climbed back out")
  result(count("hot_springs") == 0, "the steam stopped, effects=" .. count("hot_springs"))

  finish()
end
