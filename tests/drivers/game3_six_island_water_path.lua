local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_six_island_water_path"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  result(failures == 0, "game3_six_island_water_path")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  if not result(Runtime.getSession() ~= nil, "new_game_reached_field") then return finish() end
  local WP = "FR_SIX_ISLAND_WATER_PATH"

  local function setup(map, x, y, facing)
    Map.load(Runtime._mod, game, map, { x = x, y = y, facing = facing })
    Player.surfing, Player.elevation = false, 3
    U.wait(60)
    return result(Map.current == map and Player.cellX == x and Player.cellY == y, "setup_" .. map .. "_" .. y)
  end
  local function step(dir)
    local oldMap, x, y = Map.current, Player.cellX, Player.cellY
    for _ = 1, 24 do
      U.hold(game, dir, 1)
      if Player.moving or Map.current ~= oldMap then break end
    end
    for _ = 1, 48 do
      if not Player.moving then break end
      U.wait(1)
    end
    return not Player.moving and (Map.current ~= oldMap or Player.cellX ~= x or Player.cellY ~= y)
  end
  local function at(map, x, y, label)
    local session = Runtime.getSession()
    return result(Map.current == map and Player.cellX == x and Player.cellY == y
      and session.map == map and session.x == x and session.y == y, label)
  end
  local function drawsWest(row, sourceMap, sx, sy, label)
    local mid, _, void = Map.worldMidAt(-1, row, Map.currentDef())
    local src = game.data.maps[sourceMap].midLayout
    return result(mid ~= nil and not void and mid == src:midAt(sx, sy), label)
  end

  if not setup("FR_SIX_ISLAND", 23, 12, "right") then return finish() end
  if not result(step("right"), "six_island_east_step") then return finish() end
  if not at(WP, 0, 52, "six_island_east_lands_on_water_path") then return finish() end
  result(#Map.neighborList == 3, "water_path_has_three_west_neighbors")
  drawsWest(52, "FR_SIX_ISLAND", 23, 12, "water_path_row52_draws_six_island")
  U.wait(30)
  result(U.still(game, DIR .. "/2456_water_path_six_island_west.png"), "shot_six_island_west")
  if not result(step("left"), "water_path_west_step_row52") then return finish() end
  at("FR_SIX_ISLAND", 23, 12, "water_path_row52_back_to_six_island")

  if setup(WP, 0, 10, "left") then
    drawsWest(10, "FR_SIX_ISLAND_GREEN_PATH", 71, 10, "water_path_row10_draws_green_path")
    U.wait(30)
    result(U.still(game, DIR .. "/2456_water_path_green_path_west.png"), "shot_green_path_west")
    result(step("left"), "water_path_west_step_row10")
    at("FR_SIX_ISLAND_GREEN_PATH", 71, 10, "water_path_row10_to_green_path")
  end

  if setup(WP, 0, 90, "left") then
    drawsWest(90, "FR_SIX_ISLAND_RUIN_VALLEY", 47, 10, "water_path_row90_draws_ruin_valley")
    result(step("left"), "water_path_west_step_row90")
    at("FR_SIX_ISLAND_RUIN_VALLEY", 47, 10, "water_path_row90_to_ruin_valley")
  end

  if setup(WP, 0, 48, "left") then
    result(step("left"), "water_path_west_step_row48")
    at("FR_SIX_ISLAND", 23, 8, "water_path_row48_to_six_island")
  end
  finish()
end
