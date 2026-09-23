local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_exit_mat_door"

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish() love.event.quit(failures == 0 and 0 or 1) end
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
  local Doors = require("src.core.game3.doors")
  local Warp = require("src.core.game3.warp")
  local Field = require("src.core.game3.field")
  local Fade = require("src.ui.game3.fade")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local session = Runtime.getSession()
  if not check(session ~= nil, "exit_mat_new_game") then return finish() end

  local sounds = {}
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, ...)
    sounds[#sounds + 1] = id
    return realPlaySe(id, ...)
  end

  local center = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  local def = game.data.maps[center]
  if not check(def ~= nil, "exit_mat_center_map_exists") then return finish() end
  Map.load(nil, game, center, { x = 7, y = 8, facing = "down" })
  U.wait(30)

  local mat
  for _, w in ipairs(def.warps or {}) do
    local hit = Collision.isExitWarp(game, w.x, w.y)
    if hit then mat = hit break end
  end
  if not check(mat ~= nil, "exit_mat_found") then return finish() end
  U.log("mat", mat.x, mat.y, "dest", mat.destMap, mat.destX, mat.destY)

  Player.moving, Player.progress = false, 0
  Player.cellX, Player.cellY, Player.targetX, Player.targetY = mat.x, mat.y, mat.x, mat.y
  Player.px, Player.py, Player.facing = mat.x * 16, mat.y * 16, "down"
  session.x, session.y, session.facing = mat.x, mat.y, "down"
  U.wait(10)

  sounds = {}
  U.hold(game, "down", 3)
  local started = false
  for _ = 1, 30 do
    if Warp.isBusy() then started = true break end
    U.wait(1)
  end
  if not check(started, "exit_mat_warp_started") then return finish() end
  local sawExit = false
  for _, id in ipairs(sounds) do if id == SE.SE_EXIT then sawExit = true end end
  check(sawExit, "exit_mat_plays_se_exit")

  for _ = 1, 200 do
    if Map.current == mat.destMap then break end
    U.wait(1)
  end
  check(Map.current == mat.destMap, "exit_mat_loaded_destination")
  check(Collision.isWarpDoor(Collision.behavior(mat.destX, mat.destY)), "exit_mat_dest_is_a_warp_door")
  check(not Player.visible, "exit_mat_player_hidden_until_door_opens")

  local swapAt = 0
  local openAt
  sounds = {}
  for f = 1, 120 do
    local a = Doors.getActiveAnim(mat.destMap, mat.destX, mat.destY)
    if a and a.mode == "open" then openAt = f break end
    U.wait(1)
    swapAt = f
  end
  check(openAt ~= nil and openAt >= 20, "exit_mat_door_opens_after_delay (" .. tostring(openAt) .. ")")
  local doorSe = false
  for _, id in ipairs(sounds) do
    if id == SE.SE_DOOR or id == SE.SE_SLIDING_DOOR then doorSe = true end
  end
  check(doorSe, "exit_mat_door_open_plays_door_se")

  for _ = 1, 60 do
    if Player.moving then break end
    U.wait(1)
  end
  check(Player.moving and Player.visible and Player.facing == "down", "exit_mat_player_steps_out")
  check(U.still(game, DIR .. "/exit_mat_step_out_of_door.png"), "exit_mat_step_shot")

  for _ = 1, 200 do
    if not Warp.isBusy() then break end
    U.wait(1)
  end
  check(not Warp.isBusy() and not Field.locked and not Fade.isActive(), "exit_mat_released")
  check(Player.cellX == mat.destX and Player.cellY == mat.destY + 1,
    "exit_mat_ends_below_door (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  check(Doors.getActiveAnim(mat.destMap, mat.destX, mat.destY) == nil, "exit_mat_door_closed")

  Audio.playSe = realPlaySe
  print(failures == 0 and "PASS game3_exit_mat_door" or "FAIL game3_exit_mat_door")
  finish()
end
