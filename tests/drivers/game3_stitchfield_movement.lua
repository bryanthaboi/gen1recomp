local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchfield_movement"

local PLATEAU = "FR_INDIGO_PLATEAU_EXTERIOR"
-- pokefirered/include/constants/vars.h:185
local VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR = 0x4085

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchfield_movement")
    love.event.quit(0)
  else
    print("FAIL stitchfield_movement failures=" .. failures)
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
  local Movement = require("src.core.game3.scripting.movement")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local bundle = Space.bundle
  local leave = bundle and bundle.movements and bundle.movements["g3:08167311"]
  result(type(leave) == "table" and #leave == 7 and leave[1] == 0x3D,
    "the cart's Movement_PlayerLeave is six player_run_down")
  local acts = Movement.actionsFromBytes(leave or {})
  result(#acts == 6, "it decodes to six actions, got " .. #acts)

  local Objects = require("src.core.game3.objects")
  local STREAMS = {
    { key = "g3:081a75e1", name = "Common_Movement_FacePlayer" },
    { key = "g3:081bdf85", name = "Movement_CutTreeDown" },
    -- pokefirered/data/scripts/field_moves.inc:98 Movement_BreakRock
    { key = "g3:081be08f", name = "Movement_BreakRock" },
    -- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:136
    { key = "g3:08167337", name = "Movement_PushPlayerOutOfWay" },
    { key = "g3:0816440f", name = "Movement_ThiefFallIn" },
  }
  for _, s in ipairs(STREAMS) do
    local bytes = bundle and bundle.movements and bundle.movements[s.key]
    if not result(type(bytes) == "table", s.name .. " " .. s.key .. " is in the cache") then
      break
    end
    local n = #Movement.actionsFromBytes(bytes)
    result(n > 0, s.name .. " decodes to " .. n .. " actions, not zero")
    local fired = false
    Objects.applyMovement(Movement.LOCALID_PLAYER, bytes, function() fired = true end)
    local frames = 0
    for _ = 1, 180 do
      if fired then break end
      frames = frames + 1
      U.wait(1)
    end
    result(fired, s.name .. " finished its waitmovement in " .. frames
      .. " frames instead of hanging the script")
  end
  -- pokefirered/src/hall_of_fame.c:699 SetWarpsToRollCredits
  Flags.setVar(Space.store, Space.vm and Space.vm.ctx,
    VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR, 1)
  Map.load(nil, game, PLATEAU, { x = 11, y = 6, facing = "down" })
  Player.cellX, Player.cellY = 11, 6
  Player.px, Player.py = 11 * 16, 6 * 16
  Player.targetX, Player.targetY = 11, 6
  if game.session then game.session.x, game.session.y = 11, 6 end
  U.wait(60)

  result(Space.mapId == PLATEAU, "warped to the plateau, map=" .. tostring(Space.mapId))
  -- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:16
  result(Space.vm and Space.vm:isRunning() == true, "the credits scene is running")
  U.shot(game, DIR .. "/stitchfield_movement_01_credits_scene.png")

  local startY, maxY = Player.cellY, Player.cellY
  local midShot = false
  for _ = 1, 2400 do
    if Player.cellY > maxY then maxY = Player.cellY end
    if not midShot and Player.cellY >= 11 then
      midShot = true
      U.shot(game, DIR .. "/stitchfield_movement_02_player_running_off.png")
    end
    if not (Space.vm and Space.vm:isRunning()) then break end
    -- data/maps/IndigoPlateau_Exterior/scripts.inc:77
    if Flags.getVar(Space.store, Space.vm.ctx, VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR) == 0 then break end
    U.wait(1)
  end

  print("[driver] scene over at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY)
    .. "), started at y=" .. startY)
  result(midShot, "the player ran south past y=11, which only the run actions reach")
  result(Player.cellY == 14,
    "the six player_run_down landed the player at y=14, got " .. tostring(Player.cellY))
  result(maxY - 8 == 6, "the last leg was exactly six cells, got " .. tostring(maxY - 8))
  U.shot(game, DIR .. "/stitchfield_movement_03_off_screen.png")

  finish()
end
