local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_surf_connections"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  result(failures == 0, "game3_surf_connections")
  love.event.quit(failures == 0 and 0 or 1)
end
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local ORDER = { "left", "down", "up", "right" }

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
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Anim = require("src.core.game3.tileset_anim")
  local Native = require("src.core.game3.tileset_native")
  local Permissions = require("src.world.gen2.Permissions")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  if not result(Runtime.getSession() ~= nil, "new_game_reached_field") then return finish() end

  local function setup(map, x, y, facing)
    Map.load(Runtime._mod, game, map, { x = x, y = y, facing = facing })
    Player.surfing, Player.elevation = true, 1
    U.wait(90)
    return result(Map.current == map and Player.cellX == x and Player.cellY == y
      and Player.surfing and Collision.isWater(x, y), "setup_" .. map)
  end
  local function step(dir, allowBlocked)
    local oldMap, x, y = Map.current, Player.cellX, Player.cellY
    for _ = 1, 24 do
      U.hold(game, dir, 1)
      if Player.moving or Map.current ~= oldMap then break end
    end
    for _ = 1, 48 do
      if not Player.moving then break end
      U.wait(1)
    end
    local moved = not Player.moving and (Map.current ~= oldMap or Player.cellX ~= x or Player.cellY ~= y)
    if not moved and not allowBlocked then result(false, "input_step_" .. dir) end
    return moved
  end
  local function at(map, x, y, label)
    local session = Runtime.getSession()
    return result(Map.current == map and Player.cellX == x and Player.cellY == y
      and Player.surfing and Player.elevation == 1 and session.map == map
      and session.x == x and session.y == y, label)
  end
  local function shot(name)
    return result(U.shot(game, DIR .. "/2394_" .. name .. ".png"), "shot_" .. name)
  end
  local function phases(name)
    U.wait(90)
    local pairs = { "general__rom_082d4b54", "general__rom_082d4b6c" }
    for index, phase in ipairs({ 2, 4 }) do
      local target = phase * 16 + 3
      local ready = false
      for _ = 1, 140 do
        if Anim.counter % 128 == target then ready = true; break end
        U.wait(1)
      end
      if not result(ready, name .. "_phase" .. phase .. "_timed") then return false end
      for _, pair in ipairs(pairs) do
        local entry = Anim._pairs and Anim._pairs[pair]
        if not result(entry and entry.frames.water == phase and Native._pairs[pair] ~= nil,
            name .. "_" .. pair .. "_frame" .. phase) then return false end
      end
      local before, ticks = Anim.counter, U.frame()
      if not shot(name .. "_" .. index .. "_water_frame" .. phase) then return false end
      print(string.format("[driver] %s phase=%d shot_counter=%d..%d shot_ticks=%d",
        name, phase, before, Anim.counter, U.frame() - ticks))
      if not result(Anim._waterFrame == phase, name .. "_capture_stayed_in_phase" .. phase) then return false end
    end
    return true
  end

  if not setup("FR_PALLET_TOWN", 9, 19, "down") then return finish() end
  if not step("down") or not at("FR_ROUTE_21_NORTH", 9, 0, "pallet_to_route21_surf") then
    result(false, "pallet_south_barrier"); return finish()
  end
  if not step("down") or not at("FR_ROUTE_21_NORTH", 9, 1, "route21_continues_beyond_seam") then return finish() end
  U.wait(90)
  if not shot("01_route21_beyond_pallet_barrier") then return finish() end
  if not step("up") or not step("up") or not at("FR_PALLET_TOWN", 9, 19, "route21_to_pallet_surf") then
    result(false, "pallet_reverse_barrier"); return finish()
  end
  if not setup("FR_ROUTE_21_NORTH", 9, 49, "down") then return finish() end
  if not step("down") or not at("FR_ROUTE_21_SOUTH", 9, 0, "route21_north_to_south_surf") then
    result(false, "route21_south_barrier"); return finish()
  end
  if not step("down") or not at("FR_ROUTE_21_SOUTH", 9, 1, "route21_south_continues") then return finish() end
  if not step("up") or not step("up") or not at("FR_ROUTE_21_NORTH", 9, 49, "route21_south_to_north_surf") then
    result(false, "route21_north_barrier"); return finish()
  end
  if not setup("FR_ROUTE_19", 0, 49, "left") or not phases("02_route19_seam") then return finish() end
  if not step("left") or not at("FR_ROUTE_20", 119, 9, "route19_to_route20_surf") then
    result(false, "route20_west_barrier"); return finish()
  end
  if not step("left") or not at("FR_ROUTE_20", 118, 9, "route20_continues_beyond_seam") then return finish() end
  if not phases("03_route20_seam") then return finish() end
  if not step("right") or not step("right") or not at("FR_ROUTE_19", 0, 49, "route20_to_route19_surf") then
    result(false, "route19_reverse_barrier"); return finish()
  end
  if not step("left") or not at("FR_ROUTE_20", 119, 9, "route20_reentered_for_seafoam") then return finish() end

  local function pathTo(gx, gy)
    local start = { x = Player.cellX, y = Player.cellY, surfing = Player.surfing }
    local queue, seen = { start }, { [start.y * 1024 + start.x] = true }
    for index = 1, 2400 do
      local node = queue[index]
      if not node then return nil end
      if node.x == gx and node.y == gy then
        while node.parent and node.parent ~= start do node = node.parent end
        return node.dir
      end
      for _, dir in ipairs(ORDER) do
        local d = DELTA[dir]
        local x, y = node.x + d[1], node.y + d[2]
        local key = y * 1024 + x
        if not seen[key] and Collision.inBounds(x, y) and not Objects.blocks(x, y)
            and not Collision.directionallyImpassable(node.x, node.y, x, y, dir) then
          local coll, water = Collision.cell(x, y), Collision.isWater(x, y)
          local land = Permissions.isWalkable(coll) and not Permissions.isLedge(coll)
            and Collision.elevationAt(x, y) == 3
          local warp = Collision.isWarpMetatileBehavior(Collision.behavior(x, y))
          if ((water and node.surfing) or land) and not warp then
            seen[key] = true
            queue[#queue + 1] = { x = x, y = y, parent = node, dir = dir, surfing = water }
          end
        end
      end
    end
  end
  for _ = 1, 180 do
    if Player.cellX == 60 and Player.cellY == 9 then break end
    local dir = pathTo(60, 9)
    if not dir then result(false, "seafoam_path_available"); return finish() end
    if not step(dir, true) then U.wait(16) end
    if Map.current ~= "FR_ROUTE_20" then result(false, "seafoam_path_stayed_on_route20"); return finish() end
  end
  if not result(Map.current == "FR_ROUTE_20" and Player.cellX == 60 and Player.cellY == 9
      and not Player.surfing and Player.elevation == 3, "seafoam_west_landing_reached_by_input") then return finish() end
  U.wait(45)
  if not shot("04_seafoam_west_landing") then return finish() end
  step("up")
  for _ = 1, 240 do
    if Map.current == "FR_SEAFOAM_ISLANDS_1F" and not require("src.core.game3.warp").isBusy() then break end
    U.wait(1)
  end
  if not result(Map.current == "FR_SEAFOAM_ISLANDS_1F", "seafoam_entrance_reached_by_input") then return finish() end
  U.wait(90)
  shot("05_inside_seafoam_west_entrance")
  finish()
end
