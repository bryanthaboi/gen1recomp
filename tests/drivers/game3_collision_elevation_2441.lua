local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_collision_elevation_2441"

local failures = 0
local function result(ok, label, detail)
  print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS collision_elevation_2441")
    love.event.quit(0)
  else
    print("FAIL collision_elevation_2441 failures=" .. failures)
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
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local FieldMoves = require("src.core.game3.field_moves")
  local Message = require("src.ui.game3.message")
  local Bridge = require("src.core.game3.bridge")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.repelSteps = 5000

  local function settle(limit)
    for _ = 1, (limit or 240) do
      local busy = (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
      if not busy then return true end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end

  local function place(x, y, facing, surfing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.moving = false
    Player.progress = 0
    Player.facing = facing or "down"
    Player.surfing = surfing and true or false
    Player.dismounting = false
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
  end

  local function goTo(mapId, x, y, facing, surfing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing, surfing)
    U.wait(60)
    settle(600)
    place(x, y, facing, surfing)
    U.wait(10)
  end

  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  local function step(dir)
    local fromX, fromY = Player.cellX, Player.cellY
    local d = DELTA[dir]
    local ok, why = Collision.canEnter(game, fromX + d[1], fromY + d[2],
      { fromX = fromX, fromY = fromY, dir = dir, elevation = Player.currentElevation })
    print(string.format("[driver] %s from (%d,%d) cur=%s -> elev %s canEnter=%s %s",
      dir, fromX, fromY, tostring(Player.currentElevation),
      tostring(Collision.elevationAt(fromX + d[1], fromY + d[2])), tostring(ok), tostring(why)))
    for _ = 1, 3 do
      U.hold(game, dir, 4)
      for _ = 1, 60 do
        U.wait(1)
        if not Player.moving then break end
      end
      if Player.cellX ~= fromX or Player.cellY ~= fromY then break end
    end
    settle(200)
    return Player.cellX, Player.cellY, why
  end

  local function at(x, y) return Player.cellX == x and Player.cellY == y end
  local function pos() return string.format("at (%d,%d)", Player.cellX, Player.cellY) end

  print("[driver] 1. Safari Zone plateaus")
  local E = "FR_SAFARI_ZONE_EAST"
  goTo(E, 37, 16, "down")
  local _, _, why = step("down")
  result(at(37, 16) and why == "elevation", "east_sand_to_plateau_lip_blocked", pos())
  U.still(game, DIR .. "/2441_east_bump_below_plateau_lip.png")
  goTo(E, 37, 18, "up")
  step("up")
  result(at(37, 17), "east_walk_along_plateau", pos())
  _, _, why = step("up")
  result(at(37, 17) and why == "elevation", "east_plateau_to_sand_blocked", pos())
  U.still(game, DIR .. "/2441_east_bump_on_plateau_lip.png")

  goTo(E, 40, 18, "down")
  step("down")
  result(at(40, 19) and Player.currentElevation == 0, "east_stairs_down_onto_stair", pos())
  step("down")
  result(at(40, 20) and Player.currentElevation == 3, "east_stairs_down_to_sand", pos())
  step("up")
  step("up")
  result(at(40, 18) and Player.currentElevation == 4, "east_stairs_back_up_to_plateau", pos())
  U.still(game, DIR .. "/2441_east_back_up_the_rock_stairs.png")

  goTo("FR_SAFARI_ZONE_WEST", 19, 11, "down")
  _, _, why = step("down")
  result(at(19, 11) and why == "elevation", "west_plateau_edge_blocked", pos())
  goTo("FR_SAFARI_ZONE_NORTH", 40, 14, "down")
  _, _, why = step("down")
  result(at(40, 14) and why == "elevation", "north_plateau_edge_blocked", pos())

  print("[driver] 2. warps onto stairs and plateaus")
  goTo(E, 41, 19, "up")
  result(Player.currentElevation == 0, "warp_onto_stair_elev0", "cur=" .. tostring(Player.currentElevation))
  step("up")
  result(at(41, 18), "warp_onto_stair_then_up_to_plateau", pos())
  goTo(E, 41, 19, "down")
  step("down")
  result(at(41, 20), "warp_onto_stair_then_down_to_sand", pos())
  goTo(E, 38, 18, "right")
  result(Player.currentElevation == 4, "warp_onto_plateau_derives_elev4", "cur=" .. tostring(Player.currentElevation))
  step("right")
  result(at(39, 18), "warp_onto_plateau_walks", pos())

  print("[driver] 3. surfing")
  goTo(E, 30, 16, "up", true)
  step("up")
  result(at(30, 15) and Player.surfing, "surf_along_water", pos())
  goTo(E, 35, 16, "down", true)
  _, _, why = step("down")
  result(at(35, 16) and Player.surfing and why == "elevation", "surf_cannot_land_on_plateau", pos())
  U.still(game, DIR .. "/2441_surf_bump_against_plateau.png")
  step("right")
  for _ = 1, 30 do U.wait(1) end
  result(at(36, 16) and not Player.surfing, "surf_dismounts_onto_elev3_sand", pos())

  print("[driver] 4. bridge and ledge")
  goTo("FR_ROUTE_24", 11, 12, "down")
  for _ = 1, 3 do step("down") end
  result(at(11, 15), "nugget_bridge_walks", pos())
  U.still(game, DIR .. "/2441_nugget_bridge_walk.png")

  goTo("FR_ROUTE_22", 0, 0, "down")
  local lx, ly
  for y = 0, Collision._heightCells - 3 do
    for x = 0, Collision._widthCells - 1 do
      if not lx and Collision.isWalkable(x, y) and Collision.elevationAt(x, y) == 3
          and Collision.ledgeLanding(game, x, y, "down") and not Objects.blocks(x, y) then
        lx, ly = x, y
      end
    end
  end
  if result(lx ~= nil, "ledge_found_on_route22", tostring(lx) .. "," .. tostring(ly)) then
    goTo("FR_ROUTE_22", lx, ly, "down")
    local sawJump = false
    U.hold(game, "down", 4)
    for _ = 1, 80 do
      if Player.jumping then sawJump = true end
      U.wait(1)
      if not Player.moving then break end
    end
    result(sawJump and at(lx, ly + 2), "ledge_jump_lands", pos())
  end

  print("[driver] 5. Victory Road platform and stairs")
  local VR = "FR_VICTORY_ROAD_1F"
  goTo(VR, 8, 10, "down")
  _, _, why = step("down")
  result(at(8, 10) and why ~= nil, "vr_floor_to_platform_blocked", pos() .. " why=" .. tostring(why))
  U.still(game, DIR .. "/2441_vr_bump_below_platform.png")
  goTo(VR, 10, 8, "down")
  step("down")
  step("down")
  result(at(10, 10), "vr_stairs_down", pos())
  step("up")
  step("up")
  result(at(10, 8) and Player.currentElevation == 4, "vr_stairs_up", pos())

  print("[driver] 6. Seafoam B2F strength boulders")
  local SF = "FR_SEAFOAM_ISLANDS_B2F"
  local function boulder()
    for _, lid in ipairs(Objects._order) do
      local eo = Objects._byId[lid]
      if eo and eo.visible and not eo.hidden
          and eo.graphicsId == FieldMoves.GFX_IDS.PUSHABLE_BOULDER then
        return eo
      end
    end
  end
  local function push(dir, lid, bx, by, beforeShot)
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
    Objects.setObjectXY(lid, bx, by)
    U.wait(4)
    if beforeShot then
      local eo = Objects.find(lid)
      result(eo and eo.cellX == bx and eo.cellY == by, "seafoam_boulder_before_push",
        eo and string.format("boulder (%d,%d) %s", eo.cellX, eo.cellY, pos()))
      U.still(game, beforeShot)
    end
    for _ = 1, 10 do
      U.hold(game, dir, 2)
      if Player.boulderPush then break end
    end
    for _ = 1, 90 do
      if not Player.boulderPush then break end
      U.wait(1)
    end
    U.wait(10)
    return Objects.find(lid)
  end
  goTo(SF, 5, 9, "down")
  _, _, why = step("down")
  result(at(5, 9) and why == "elevation", "seafoam_floor_to_ledge_blocked", pos())
  local sb = boulder()
  if result(sb ~= nil, "seafoam_boulder_found") then
    local lid = sb.localId
    goTo(SF, 5, 8, "down")
    local b = push("down", lid, 5, 9, DIR .. "/2441_seafoam_boulder_before_push.png")
    result(b and b.cellX == 5 and b.cellY == 9 and at(5, 8) and Player.facing == "down",
      "seafoam_boulder_not_pushed_onto_elev4",
      b and string.format("boulder (%d,%d) cur=%s", b.cellX, b.cellY, tostring(b.currentElevation)))
    U.still(game, DIR .. "/2441_seafoam_boulder_after_refused_push.png")
    goTo(SF, 4, 9, "right")
    b = push("right", lid, 5, 9)
    result(b and b.cellX == 6 and b.cellY == 9, "seafoam_boulder_pushes_along_floor",
      b and string.format("boulder (%d,%d)", b.cellX, b.cellY))
  end

  print("[driver] 7. Pokemon Center escalator cells")
  local Warp = require("src.core.game3.warp")
  local PC1 = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  local PC2 = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
  goTo(PC1, 3, 6, "left")
  step("left")
  result(Map.current == PC1 and at(2, 6) and Player.currentElevation == 4, "pc1f_elev0_to_elev4_approach",
    pos() .. " cur=" .. tostring(Player.currentElevation))
  local onStairs = false
  for _ = 1, 20 do
    U.hold(game, "left", 1)
    for _ = 1, 60 do
      if Map.current == PC1 and at(1, 6) and not Player.moving then break end
      if Map.current ~= PC1 then break end
      U.wait(1)
    end
    if Map.current == PC1 and at(1, 6) and not Player.moving then
      onStairs = true
      U.still(game, DIR .. "/2441_pc1f_on_stairs.png")
      break
    end
    if Map.current ~= PC1 then break end
  end
  result(onStairs and Warp.isEscalatorActive(), "pc1f_on_stairs_before_warp", pos())
  for _ = 1, 600 do
    if Map.current == PC2 and not Warp.isBusy() then break end
    U.wait(1)
  end
  settle(300)
  U.wait(30)
  result(Map.current == PC2, "pc_stairs_up_reach_2f", tostring(Map.current) .. " " .. pos())
  U.still(game, DIR .. "/2441_pc2f_arrival.png")

  print("[driver] 8. save and continue standing on a Cerulean Cave platform")
  local CC = "FR_CERULEAN_CAVE_B1F"
  goTo(CC, 16, 9, "up")
  Bridge.persistSessionOnly(Runtime._mod, game)
  result(game:saveGame() ~= false, "saved_on_cave_platform")
  game:_handleBootAction({ action = "continue" })
  U.wait(60)
  for _ = 1, 400 do
    if game.phase ~= "quest_log" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(120)
  settle(300)
  local loaded = Runtime.getSession()
  result(loaded ~= nil and Space.mapId == CC and at(16, 9), "continue_on_cave_platform", pos())
  result(Player.currentElevation == 4, "continue_derives_elev4", "cur=" .. tostring(Player.currentElevation))
  step("up")
  result(at(16, 8), "continue_walks_on_platform", pos())
  _, _, why = step("up")
  result(at(16, 8) and why == "elevation", "continue_platform_edge_still_blocks", pos())
  U.still(game, DIR .. "/2441_continue_cave_platform_edge.png")

  finish()
end
