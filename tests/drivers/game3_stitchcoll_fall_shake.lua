local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchcoll_fall_shake"

local CAVE_1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local CAVE_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"
-- pokefirered/include/constants/vars.h:9
local VAR_TEMP_1 = 0x4001

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchcoll_fall_shake")
    love.event.quit(0)
  else
    print("FAIL stitchcoll_fall_shake failures=" .. failures)
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
  local Field = require("src.core.game3.field")
  local FieldView = require("src.core.game3.field_view")
  local Warp = require("src.core.game3.warp")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
  end

  local function step(dir)
    local bx, by = Player.cellX, Player.cellY
    for _ = 1, 4 do
      U.hold(game, dir, 8)
      if Player.cellX ~= bx or Player.cellY ~= by then
        while Player.moving do U.wait(1) end
        return true
      end
    end
    return false
  end

  goTo(CAVE_1F, 8, 12, "down")
  result(Runtime.getSession().map == CAVE_1F, "walked into Icefall Cave 1F")

  -- pokefirered/src/field_tasks.c:51 sIcefallCaveIceCoords
  while Player.cellY < 14 do
    if not step("down") then break end
  end
  result(Player.cellX == 8 and Player.cellY == 14,
    "standing on the cracking ice at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.shot(game, DIR .. "/stitchcoll_fall_shake_01_on_the_ice.png")

  -- pokefirered/src/field_tasks.c:243 IcefallCaveIcePerStepCallback
  Flags.setVar(Space.store, ctx(), VAR_TEMP_1, 1)

  -- pokefirered/src/field_control_avatar.c:212 TryRunOnFrameMapScript
  local started = false
  for _ = 1, 120 do
    U.wait(1)
    if Space.vm and Space.vm:isRunning() then
      started = true
      break
    end
  end
  if not started then
    print("[driver] the ON_FRAME poll did not claim the frame on its own, nudging once")
    Space.scheduleOnFrame(game and (game.overworld or game.world))
    for _ = 1, 120 do
      U.wait(1)
      if Space.vm and Space.vm:isRunning() then
        started = true
        break
      end
    end
  end
  result(started, "the hole script started")

  -- pokefirered/src/field_effect.c:1249 FallWarpEffect_5
  local arrived, shookAt = false, nil
  for frame = 1, 900 do
    U.wait(1)
    if Runtime.getSession().map == CAVE_B1F then arrived = true end
    if arrived and (FieldView.cameraPanY or 0) ~= 0 then
      shookAt = frame
      break
    end
  end
  result(arrived, "the player fell through to B1F, map="
    .. tostring(Runtime.getSession().map))
  result(shookAt ~= nil,
    "the screen shakes when the player hits the floor, pan="
    .. tostring(FieldView.cameraPanY))
  -- pokefirered/src/field_effect.c:1274 FallWarpEffect_7
  result(Warp.isBusy() == true,
    "the fall sequence still owns the player while the screen shakes")
  print("[driver] Field.locked during the shake: " .. tostring(Field.locked))

  U.shot(game, DIR .. "/stitchcoll_fall_shake_02_landing_shake.png")
  print("[driver] pan right after the shake shot: " .. tostring(FieldView.cameraPanY))
  result((FieldView.cameraPanY or 0) ~= 0 and Warp.isBusy() == true,
    "the shake is still running and the player is still held after the shot")

  local settled = false
  for _ = 1, 120 do
    U.wait(1)
    if (FieldView.cameraPanY or 0) == 0 and not Warp.isBusy() then
      settled = true
      break
    end
  end
  result(settled, "the shake settled and the fall sequence ended")
  result((FieldView.cameraPanY or 0) == 0,
    "the camera pan is back to zero, pan=" .. tostring(FieldView.cameraPanY))

  U.wait(30)
  U.shot(game, DIR .. "/stitchcoll_fall_shake_03_control_back.png")
  result(step("down") or step("left") or step("up"),
    "control came back to the player on B1F")

  finish()
end
