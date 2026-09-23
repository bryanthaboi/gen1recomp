local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_scripted_warp_fade"

-- pokefirered/include/constants/flags.h:133
local FLAG_HIDE_TWO_ISLAND_GAME_CORNER_LOSTELLE = 0x075
-- pokefirered/include/constants/flags.h:138
local FLAG_HIDE_LOSTELLE_IN_BERRY_FOREST = 0x07A
-- pokefirered/include/constants/flags.h:700
local FLAG_RESCUED_LOSTELLE = 0x2A3

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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local Message = require("src.ui.game3.message")
  local Fade = require("src.ui.game3.fade")
  local Warp = require("src.core.game3.warp")
  local Collision = require("src.core.game3.collision")
  local MapCatalog = require("src.import.gba.map_catalog")
  local session = Runtime.getSession()
  if not check(session ~= nil, "warp_fade_new_game") then return finish() end

  local function place(x, y, facing)
    Player.moving, Player.progress = false, 0
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
    Player.px, Player.py, Player.facing = x * 16, y * 16, facing
    session.x, session.y, session.facing = x, y, facing
  end
  local function setFlag(id, on) Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, id, on) end

  session.party = {}
  Party.giveMon(session, 150, 100)
  session.party[1].moves, session.party[1].pp, session.party[1].maxPp = { 94 }, { 10 }, { 10 }

  local forest = MapCatalog.mapIdFor(1, 109)
  local corner = MapCatalog.mapIdFor(33, 0)
  setFlag(FLAG_HIDE_LOSTELLE_IN_BERRY_FOREST, false)
  setFlag(FLAG_RESCUED_LOSTELLE, false)
  Map.load(nil, game, forest, { x = 4, y = 9, facing = "up" })
  place(4, 9, "up")
  U.wait(90)

  local battled = false
  for _ = 1, 20000 do
    if Battle.isActive() then battled = true break end
    if Message.isOpen() or not Space.vm:isRunning() then U.tap(game, "a") end
    U.wait(4)
  end
  if not battled then
    local lostelle = require("src.core.game3.objects").find(1)
    U.log("lostelle", lostelle and lostelle.visible, lostelle and lostelle.cellX, lostelle and lostelle.cellY,
      "msg", Message.isOpen(), "vm", Space.vm:isRunning(), "map", Map.current,
      "ctx", Space.vm.ctx and Space.vm.ctx.status, Space.vm.ctx and Space.vm.ctx.mode)
    local pc = Space.vm.ctx and Space.vm.ctx.pc
    local list = pc and Space.vm.scripts[pc.listKey]
    local row = list and list[pc.index - 1]
    U.log("pc", pc and pc.listKey, pc and pc.index, row and row.op, row and tostring(row[1]))
  end
  if not check(battled, "lostelle_hypno_battle_started") then return finish() end
  local started = false
  for _ = 1, 60000 do
    if Warp.isBusy() then started = true break end
    if Message.isOpen() and Message.isWaiting and Message.isWaiting() then U.tap(game, "a")
    elseif Battle.isActive() then U.tap(game, "a") end
    U.wait(1)
  end
  if not check(started, "lostelle_scripted_warp_started") then return finish() end
  check(Map.current == forest, "lostelle_still_in_forest_when_warp_starts")
  check(Fade.isActive() and Fade.mode == Fade.MODE.TO_BLACK, "lostelle_fade_to_black_started")

  for _ = 1, 60 do
    if (Fade.t or 0) >= 8 then break end
    U.wait(1)
  end
  check(Map.current == forest and (Fade.t or 0) >= 8 and (Fade.t or 0) < 16,
    "lostelle_forest_half_faded (t=" .. tostring(Fade.t) .. ")")
  check(U.still(game, DIR .. "/U1_lostelle_mid_fade_out.png"), "lostelle_mid_fade_out_shot")

  local tAtSwap
  for _ = 1, 400 do
    if Map.current == corner then tAtSwap = Fade.t break end
    U.wait(1)
  end
  check(tAtSwap == 16, "lostelle_map_swapped_under_full_black (t=" .. tostring(tAtSwap) .. ")")

  for _ = 1, 60 do
    if Fade.isActive() and (Fade.t or 16) <= 8 then break end
    U.wait(1)
  end
  check(Map.current == corner and Fade.isActive() and (Fade.t or 0) > 0,
    "lostelle_corner_fading_in (t=" .. tostring(Fade.t) .. ")")
  check(not Message.isOpen(), "lostelle_game_corner_scene_waits_for_fade_in")
  check(U.still(game, DIR .. "/U1_lostelle_mid_fade_in.png"), "lostelle_mid_fade_in_shot")

  for _ = 1, 120 do
    if not Warp.isBusy() and not Fade.isActive() then break end
    U.wait(1)
  end
  check(not Warp.isBusy() and (Fade.t or 0) == 0, "lostelle_fade_in_finished")
  -- pokefirered/data/maps/TwoIsland_JoyfulGameCorner/scripts.inc:25
  check(Player.facing == "up", "lostelle_on_warp_turns_player_north (" .. tostring(Player.facing) .. ")")
  check(Player.cellX == 6 and Player.cellY == 6, "lostelle_player_at_6_6 ("
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  check(Flags.getFlag(Space.store, nil, FLAG_RESCUED_LOSTELLE)
    and not Flags.getFlag(Space.store, nil, FLAG_HIDE_TWO_ISLAND_GAME_CORNER_LOSTELLE),
    "lostelle_rescue_flags")
  U.wait(2)
  check(U.shot(game, DIR .. "/U1_lostelle_arrived_game_corner.png"), "lostelle_arrived_shot")
  for _ = 1, 900 do
    if not Space.vm:isRunning() and not Message.isOpen() then break end
    if Message.isOpen() and Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end

  local pc = MapCatalog.mapIdFor(12, 5)
  local cinnabar = MapCatalog.mapIdFor(3, 8)
  Map.load(nil, game, pc, { x = 7, y = 6, facing = "down" })
  place(7, 6, "down")
  U.wait(60)
  local doneDoor = false
  Space.vm.adapters.warp(3, 8, 255, 14, 11, function() doneDoor = true end, "warp")
  local sawDoorTile = false
  for _ = 1, 400 do
    if Map.current == cinnabar and not sawDoorTile then
      sawDoorTile = Collision.isWarpDoor(Collision.behavior(14, 11))
    end
    if Map.current == cinnabar and Player.moving then break end
    U.wait(1)
  end
  check(sawDoorTile, "cinnabar_dest_is_a_warp_door")
  check(Player.moving and Player.facing == "down", "cinnabar_player_steps_out_of_door")
  check(U.still(game, DIR .. "/U1_cinnabar_door_exit_step.png"), "cinnabar_door_exit_shot")
  for _ = 1, 300 do
    if doneDoor then break end
    U.wait(1)
  end
  check(doneDoor and Player.cellX == 14 and Player.cellY == 12,
    "cinnabar_player_ends_at_14_12 (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")

  local viridian = MapCatalog.mapIdFor(3, 1)
  place(Player.cellX, Player.cellY, "up")
  U.wait(10)
  local donePlain = false
  Space.vm.adapters.warp(3, 1, 255, 26, 28, function() donePlain = true end, "warpsilent")
  for _ = 1, 400 do
    if donePlain then break end
    U.wait(1)
  end
  check(donePlain and Map.current == viridian and Player.cellX == 26 and Player.cellY == 28,
    "plain_warp_reached_viridian_26_28")
  check(Player.facing == "down", "plain_warp_faces_south (" .. tostring(Player.facing) .. ")")
  check(U.shot(game, DIR .. "/U1_plain_warp_faces_south.png"), "plain_warp_shot")

  print(failures == 0 and "PASS game3_scripted_warp_fade" or "FAIL game3_scripted_warp_fade")
  finish()
end
