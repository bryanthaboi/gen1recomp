local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_runtime_indigo_camera"

-- pokefirered/data/maps/Route25_SeaCottage/scripts.inc:158
local COTTAGE = "FR_ROUTE_25_SEA_COTTAGE"
local PC_X, PC_Y = 4, 6
-- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:31
local PLATEAU = "FR_INDIGO_PLATEAU_EXTERIOR"
local PLATEAU_X, PLATEAU_Y = 11, 7
-- pokefirered/data/specials.inc:286
local SPAWN_CAMERA, REMOVE_CAMERA = 275, 276
-- pokefirered/data/maps/Route25_SeaCottage/scripts.inc:1
local BILL_IN_TELEPORTER, RETURN_AFTER_SS_TICKET = 2, 3
-- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:16
local VAR_MAP_SCENE = 0x4085

local CELL = 16
local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/runtime_indigo_camera.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS runtime_indigo_camera")
    love.event.quit(0)
  else
    say("FAIL runtime_indigo_camera failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
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
  local Objects = require("src.core.game3.objects")
  local Natives = require("src.core.game3.scripting.natives")
  local CameraObject = require("src.core.game3.camera_object")
  local FieldView = require("src.core.game3.field_view")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  result(Natives.ALLOW["special:" .. SPAWN_CAMERA] ~= nil,
    "SpawnCameraObject is bound")
  result(Natives.ALLOW["special:" .. REMOVE_CAMERA] ~= nil,
    "RemoveCameraObject is bound")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setFlag(id, on) Flags.setFlag(Space.store, ctx(), id, on) end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    U.wait(90)
  end

  local function pumpUntil(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function clearDialogs(frames)
    for _ = 1, frames do
      local busy = Message.isOpen() or Choice.active
      if not busy then return true end
      U.tap(game, "a")
      U.wait(8)
    end
    return false
  end

  -- pokefirered/data/maps/Route25_SeaCottage/scripts.inc:152
  say("[driver] Sea Cottage: the cell separator camera pan")
  goTo(COTTAGE, PC_X, PC_Y, "up")
  -- pokefirered/src/event_data.c:49
  setFlag(RETURN_AFTER_SS_TICKET, false)
  setFlag(BILL_IN_TELEPORTER, true)
  U.shot(game, DIR .. "/indigo_camera_01_cottage_pc.png")

  result(CameraObject.isActive() == false, "no camera object before the scene")

  U.tap(game, "a")
  U.wait(20)
  clearDialogs(90)

  local spawned = pumpUntil(600, function() return CameraObject.isActive() end)
  result(spawned, "SpawnCameraObject created the camera object")
  result(FieldView._game3CameraObjectSeam == true,
    "the camera object installed the field-view follow seam")
  if not spawned then
    U.shot(game, DIR .. "/indigo_camera_02_no_camera.png")
    return
  end

  local px0, py0 = Player.px, Player.py
  local cell0 = Player.cellX .. "," .. Player.cellY
  local panned = pumpUntil(900, function()
    local dx, dy = CameraObject.offset()
    return dx == 2 * CELL and dy == -2 * CELL
  end)
  local dx, dy = CameraObject.offset()
  result(panned, string.format(
    "the camera panned two cells up and two right, got %d,%d", dx, dy))
  result(Player.px == px0 and Player.py == py0,
    "the player never moved during the pan")
  result(Player.cellX .. "," .. Player.cellY == cell0,
    "the player is still on the PC tile, " .. Player.cellX .. "," .. Player.cellY)
  U.shot(game, DIR .. "/indigo_camera_02_pan_to_teleporters.png")

  local panBack = pumpUntil(1800, function()
    local bx, by = CameraObject.offset()
    return bx == 0 and by == 0 and not CameraObject.isActive()
  end)
  result(panBack, "RemoveCameraObject put the camera back on the player")
  result(Player.px == px0 and Player.py == py0,
    "the player still never moved for the whole scene")
  U.shot(game, DIR .. "/indigo_camera_03_camera_returned.png")
  clearDialogs(120)

  -- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:24
  say("[driver] Indigo Plateau: the pre-credits walk")
  setVar(VAR_MAP_SCENE, 1)
  goTo(PLATEAU, PLATEAU_X, PLATEAU_Y, "down")

  local started = pumpUntil(900, function() return CameraObject.isActive() end)
  result(started, "the credits scene spawned the camera object")
  if not started then
    U.shot(game, DIR .. "/indigo_camera_04_no_scene.png")
    return
  end
  local cam = CameraObject.object()
  local camPx0, camPy0 = cam.px, cam.py
  result(cam.cellX == PLATEAU_X and cam.cellY == PLATEAU_Y,
    string.format("the camera locked on the plaza at %d,%d", cam.cellX, cam.cellY))
  U.shot(game, DIR .. "/indigo_camera_04_plateau_locked.png")

  local drift = 0
  local maxAway = 0
  local shotTaken = false
  for _ = 1, 3600 do
    if not CameraObject.isActive() then break end
    local c = CameraObject.object()
    if c and (c.px ~= camPx0 or c.py ~= camPy0) then drift = drift + 1 end
    local ax, ay = CameraObject.offset()
    local away = math.max(math.abs(ax), math.abs(ay))
    if away > maxAway then maxAway = away end
    if not shotTaken and ay <= -2 * CELL then
      shotTaken = true
      U.shot(game, DIR .. "/indigo_camera_05_player_left_camera_held.png")
    end
    U.wait(1)
  end

  result(drift == 0,
    "the camera never moved off the plaza while the scene played")
  result(maxAway >= 2 * CELL, string.format(
    "the player walked at least two cells away from the held camera, got %d px",
    maxAway))
  result(shotTaken, "captured the frame with the player away from the camera")
  result(not CameraObject.isActive(),
    "RemoveCameraObject ran at the end of the scene")
  local fx, fy = CameraObject.offset()
  result(fx == 0 and fy == 0, string.format(
    "the camera is back on the player, %d,%d", fx, fy))
  U.shot(game, DIR .. "/indigo_camera_06_after_credits_scene.png")

  local rival = Objects.find(1)
  local oak = Objects.find(2)
  result(rival == nil or rival.visible == false, "the credits rival was removed")
  result(oak == nil or oak.visible == false, "Prof Oak was removed")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL runtime_indigo_camera driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
