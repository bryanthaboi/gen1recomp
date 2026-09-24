local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_forced_elevation_s4"

local failures = 0
local function result(ok, label, detail)
  print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS forced_elevation_s4")
    love.event.quit(0)
  else
    print("FAIL forced_elevation_s4 failures=" .. failures)
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
  local Message = require("src.ui.game3.message")
  local ForcedMovement = require("src.core.game3.forced_movement")
  local TrainerSight = require("src.core.game3.trainer_sight")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.repelSteps = 5000

  local function busy()
    return (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
  end

  local function settle(limit)
    for _ = 1, (limit or 240) do
      if not busy() then return true end
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

  local function step(dir)
    local fromX, fromY = Player.cellX, Player.cellY
    for _ = 1, 3 do
      U.hold(game, dir, 4)
      for _ = 1, 60 do
        U.wait(1)
        if not Player.moving then break end
      end
      if Player.cellX ~= fromX or Player.cellY ~= fromY then break end
    end
    settle(200)
  end

  local function at(x, y) return Player.cellX == x and Player.cellY == y end
  local function pos()
    return string.format("at (%d,%d) cur=%s surf=%s", Player.cellX, Player.cellY,
      tostring(Player.currentElevation), tostring(Player.surfing))
  end

  local function firstObject()
    for _, lid in ipairs(Objects._order) do
      local eo = Objects._byId[lid]
      if eo and eo.visible and not eo.hidden and not eo.passable then return eo end
    end
  end

  print("[driver] 1. constructed trainer on Safari Zone East sand, player on the rock stairs")
  local E = "FR_SAFARI_ZONE_EAST"
  goTo(E, 40, 18, "down")
  local Field = require("src.core.game3.field")
  for _ = 1, 600 do
    if not Field.locked and not busy() then break end
    U.wait(1)
  end
  result(not Field.locked, "field_unlocked_before_walking")
  goTo(E, 40, 18, "down")
  local stand = firstObject()
  if stand then
    Objects.setObjectXY(stand.localId, 40, 21)
    stand.frozen = true
    stand.facing = "up"
    local def = {}
    for k, v in pairs(stand.def or {}) do def[k] = v end
    def.graphics, def.graphicsId, def.graphicsVar = 39, 39, nil
    stand.def = def
    stand.graphicsId = 39
    stand.sprite = require("src.core.game3.scripting.gfx_ids").spriteFor(39) or stand.sprite
    require("src.core.game3.field_view")._nativeDirty = true
  end
  result(stand ~= nil and stand.cellX == 40 and stand.cellY == 21 and stand.currentElevation == 3,
    "safari_watcher_drawn_on_elev3_sand", stand and ("elev=" .. tostring(stand.currentElevation)) or "none")
  local watcher = { localId = stand and stand.localId or 250, cellX = 40, cellY = 21, facing = "up", sight = 3,
    currentElevation = 3, visible = true, hidden = false, moving = false }
  result(Player.currentElevation == 4
    and TrainerSight.checkLineOfSight(watcher, Player, game) == false,
    "safari_elev3_trainer_misses_elev4_plateau", pos())
  step("down")
  local seen, dist = TrainerSight.checkLineOfSight(watcher, Player, game)
  result(at(40, 19) and Player.currentElevation == 0 and seen == true and dist == 2,
    "safari_elev3_trainer_sees_player_on_elev0_stair", pos() .. " dist=" .. tostring(dist))
  local Popup = require("src.ui.game3.map_name_popup")
  for _ = 1, 900 do
    if not Popup.isActive() then break end
    U.wait(1)
  end
  U.wait(2)
  result(not Popup.isActive() and at(40, 19), "safari_map_name_popup_closed_before_shot", pos())
  U.still(game, DIR .. "/s4_safari_player_on_stair_in_sight_line.png")

  print("[driver] 2. an object on the Safari Zone East plateau still blocks the plateau walker")
  local obj = firstObject()
  if result(obj ~= nil, "safari_object_found") then
    goTo(E, 38, 18, "right")
    obj = Objects.find(obj.localId)
    Objects.setObjectXY(obj.localId, 39, 18)
    obj.frozen = true
    U.wait(4)
    step("right")
    result(at(38, 18) and obj.currentElevation == 4 and Player.currentElevation == 4,
      "plateau_object_same_elev_blocks", pos() .. " obj=" .. tostring(obj.currentElevation))
    U.still(game, DIR .. "/s4_safari_bump_into_elev4_object.png")
  end

  print("[driver] 3. a ledge jump lands on an occupied cell")
  local LM, lx, ly, npc
  for _, m in ipairs({ "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_4", "FR_ROUTE_22" }) do
    goTo(m, 0, 0, "down")
    lx, ly = nil, nil
    for y = 0, Collision._heightCells - 3 do
      for x = 0, Collision._widthCells - 1 do
        if not lx and Collision.isWalkable(x, y) and Collision.elevationAt(x, y) == 3
            and Collision.ledgeLanding(game, x, y, "down") and not Objects.blocks(x, y) then
          lx, ly = x, y
        end
      end
    end
    npc = firstObject()
    if lx and npc then LM = m break end
  end
  if result(LM ~= nil, "ledge_and_object_found",
      tostring(LM) .. " " .. tostring(lx) .. "," .. tostring(ly)) then
    goTo(LM, lx, ly, "down")
    npc = Objects.find(npc.localId)
    Objects.setObjectXY(npc.localId, lx, ly + 2)
    npc.frozen = true
    U.wait(2)
    local sawJump = false
    U.hold(game, "down", 4)
    local shotMid = false
    for i = 1, 80 do
      if Player.jumping then
        sawJump = true
        if not shotMid and i >= 8 then
          shotMid = U.still(game, DIR .. "/s4_ledge_midjump_toward_object_below_ledge.png")
        end
      end
      U.wait(1)
      if not Player.moving then break end
    end
    result(sawJump and shotMid and at(lx, ly + 2) and npc.cellX == lx and npc.cellY == ly + 2,
      "ledge_jump_lands_on_object_cell", pos())
    local ok = Collision.canEnter(game, lx, ly + 1, { fromX = lx, fromY = ly, dir = "down",
      elevation = Player.currentElevation })
    result(ok == false, "ledge_cell_itself_still_impassable")
  end

  print("[driver] 4. Seafoam B3F southward current against the elev 4 ledge")
  local B3F = "FR_SEAFOAM_ISLANDS_B3F"
  goTo(B3F, 16, 6, "down", true)
  result(Collision.behavior(16, 6) == 0x53, "b3f_current_cell_is_southward",
    "beh=" .. tostring(Collision.behavior(16, 6)))
  result(Collision.elevationAt(16, 7) == 4, "b3f_cell_below_is_elev4",
    "elev=" .. tostring(Collision.elevationAt(16, 7)))
  for _ = 1, 90 do U.wait(1) end
  result(at(16, 6) and Player.surfing and not Player.dismounting,
    "b3f_current_holds_surfer_at_ledge", pos())
  result(ForcedMovement.forced == false, "b3f_forced_flag_cleared")
  U.still(game, DIR .. "/s4_seafoam_b3f_current_held_below_elev4_ledge.png")

  print("[driver] 5. Route 12 fisher does not see a surfer below him")
  local R12 = "FR_ROUTE_12"
  goTo(R12, 17, 33, "up", true)
  local fisher
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.cellX == 17 and eo.cellY == 32 then fisher = eo end
  end
  if result(fisher ~= nil and (tonumber(fisher.sight) or 0) >= 1, "r12_fisher_found",
      fisher and ("sight=" .. tostring(fisher.sight) .. " elev=" .. tostring(fisher.currentElevation))) then
    fisher.facing = "down"
    local seen = TrainerSight.checkLineOfSight(fisher, Player, game)
    result(seen == false and Player.currentElevation == 1, "r12_fisher_misses_surfer", pos())
    for _ = 1, 120 do U.wait(1) end
    result(not busy() and at(17, 33) and Player.surfing, "r12_no_battle_after_wait", pos())
    U.still(game, DIR .. "/s4_route12_surfer_below_fisher_unseen.png")
  end

  finish()
end
