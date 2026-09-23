local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_strength_push"

local SE_FALL, SE_M_STRENGTH = 37, 207
-- pokefirered/include/constants/vars.h:152
local VAR_MAP_SCENE_VICTORY_ROAD_1F = 0x4064

local failures = 0
local function result(ok, label, detail)
  print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS strength_push")
    love.event.quit(0)
  else
    print("FAIL strength_push failures=" .. failures)
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
  local Objects = require("src.core.game3.objects")
  local Audio = require("src.core.game3.audio")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local FieldMoves = require("src.core.game3.field_moves")
  local FieldEffects = require("src.core.game3.field_effects")
  local Collision = require("src.core.game3.collision")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.repelSteps = 250

  local seLog = {}
  local origSe = Audio.playSe
  Audio.playSe = function(id, ...)
    seLog[#seLog + 1] = id
    return origSe(id, ...)
  end

  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    if game.session then game.session.x, game.session.y, game.session.facing = x, y, facing end
    Player.moving = false
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(60)
    Flags.setFlag(Space.store, ctx(), FieldMoves.SYS_FLAGS.USE_STRENGTH, true)
  end

  local function hasDust()
    for _, a in ipairs(FieldEffects._anims or {}) do
      if a.kind == "dust" then return true end
    end
    return false
  end

  local function holdUntilPush(dir)
    for _ = 1, 20 do
      U.hold(game, dir, 1)
      if Player.boulderPush then return true end
    end
    return false
  end

  goTo("FR_SEAFOAM_ISLANDS_B3F", 6, 16, "down")
  local b = Objects.find(6)
  result(b ~= nil and b.cellX == 6 and b.cellY == 17, "seafoam_boulder_at_6_17")
  if not b then return finish() end
  seLog = {}
  local startPy = b.py
  result(holdUntilPush("down"), "seafoam_push_started")
  result(seLog[1] == SE_M_STRENGTH, "seafoam_se_strength_on_push", "se=" .. table.concat(seLog, ","))
  result(hasDust(), "seafoam_dust_started")
  result(Player.cellX == 6 and Player.cellY == 16 and not Player.moving, "seafoam_player_walks_in_place")
  U.wait(15)
  local midPy = b.py
  result(b.moving and midPy > startPy and midPy < startPy + 16 and b.visible ~= false,
    "seafoam_boulder_mid_slide", string.format("py %s -> %s", tostring(startPy), tostring(midPy)))
  result(seLog[2] == nil, "seafoam_no_fall_before_slide_ends", "se=" .. table.concat(seLog, ","))
  U.shot(game, DIR .. "/2424_seafoam_boulder_mid_slide.png")
  for _ = 1, 40 do
    if not Player.boulderPush then break end
    U.wait(1)
  end
  result(Player.boulderPush == nil, "seafoam_push_finished")
  result(seLog[1] == SE_M_STRENGTH and seLog[#seLog] == SE_FALL,
    "seafoam_se_207_then_fall", "se=" .. table.concat(seLog, ","))
  result(b.visible == false or b.hidden == true, "seafoam_boulder_gone_into_hole")
  result(Player.cellX == 6 and Player.cellY == 16, "seafoam_player_never_stepped")
  U.shot(game, DIR .. "/2424_seafoam_boulder_fell.png")

  goTo("FR_VICTORY_ROAD_1F", 20, 14, "down")
  local vb
  for _, lid in ipairs({ 5, 6, 7 }) do
    local eo = Objects.find(lid)
    if eo and eo.graphicsId == FieldMoves.GFX_IDS.PUSHABLE_BOULDER then vb = vb or eo end
  end
  if not result(vb ~= nil, "vr_boulder_found") then return finish() end
  Objects.setObjectXY(vb.localId, 20, 15)
  U.wait(2)
  seLog = {}
  result(holdUntilPush("down"), "vr_push_started")
  U.wait(10)
  result(Flags.getVar(Space.store, ctx(), VAR_MAP_SCENE_VICTORY_ROAD_1F) ~= 100
      and not (Space.vm and Space.vm:isRunning()),
    "vr_switch_not_fired_mid_slide")
  for _ = 1, 40 do
    if not Player.boulderPush then break end
    U.wait(1)
  end
  for _ = 1, 900 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.wait(1)
  end
  U.wait(30)
  result(vb.cellX == 20 and vb.cellY == 16, "vr_boulder_on_switch")
  result(Flags.getVar(Space.store, ctx(), VAR_MAP_SCENE_VICTORY_ROAD_1F) == 100,
    "vr_switch_fires_after_slide",
    "var=" .. tostring(Flags.getVar(Space.store, ctx(), VAR_MAP_SCENE_VICTORY_ROAD_1F)))
  result(seLog[1] == SE_M_STRENGTH, "vr_se_strength", "se=" .. table.concat(seLog, ","))
  U.shot(game, DIR .. "/2424_vr_switch_pressed.png")

  goTo("FR_ROUTE_1", 5, 5, "down")
  local lx, ly
  for y = 1, 60 do
    for x = 1, 40 do
      if not lx and Collision.canEnter(game, x, y, {})
          and Collision.ledgeLanding(game, x, y, "down") then
        lx, ly = x, y
      end
    end
  end
  if not result(lx ~= nil, "ledge_found", tostring(lx) .. "," .. tostring(ly)) then return finish() end
  goTo("FR_ROUTE_1", lx, ly, "down")
  local jumped = false
  for _ = 1, 20 do
    U.hold(game, "down", 1)
    if Player.jumping then jumped = true break end
  end
  result(jumped, "ledge_jump_started")
  for _ = 1, 40 do
    if not Player.moving then break end
    U.wait(1)
  end
  U.wait(3)
  result(hasDust(), "ledge_landing_dust")
  U.shot(game, DIR .. "/2424_ledge_landing_dust.png")

  finish()
end
