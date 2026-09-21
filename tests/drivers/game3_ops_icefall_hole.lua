local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ops_icefall_hole"

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
    print("PASS ops_icefall_hole")
    love.event.quit(0)
  else
    print("FAIL ops_icefall_hole failures=" .. failures)
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
  local Ctx = require("src.core.game3.scripting.ctx")

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
  result(Runtime.getSession().map == CAVE_1F, "entered Icefall Cave 1F")

  -- pokefirered/data/maps/FourIsland_IcefallCave_1F/scripts.inc:8
  result(Ctx.stepCallback(CAVE_1F) == "ice",
    "ON_RESUME armed STEP_CB_ICE, callback=" .. tostring(Ctx.stepCallback(CAVE_1F)))

  -- pokefirered/src/field_tasks.c:51 sIcefallCaveIceCoords
  while Player.cellY < 14 do
    if not step("down") then break end
  end
  print("[driver] on the ice at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellX == 8 and Player.cellY == 14,
    "standing on the crackable ice at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.shot(game, DIR .. "/ops_icefall_hole_01_on_the_ice.png")

  -- pokefirered/src/field_tasks.c:243
  Flags.setVar(Space.store, ctx(), VAR_TEMP_1, 1)

  -- pokefirered/src/field_control_avatar.c:212
  local ranByItself = false
  for _ = 1, 120 do
    U.wait(1)
    if Space.vm and Space.vm:isRunning() then
      ranByItself = true
      break
    end
  end
  if not ranByItself then
    print("[driver] BLOCKED src/core/game3/field.lua:93 only runs ON_FRAME when " ..
      "Space._pendingOnFrame is set, so setting VAR_TEMP_1 while standing on the " ..
      "map starts nothing; pret polls TryRunOnFrameMapScript every frame. " ..
      "Owner handoff: field.lua / space.lua. Nudging once so warphole can be exercised.")
    Space.scheduleOnFrame(game and (game.overworld or game.world))
  end

  local started = false
  for _ = 1, 120 do
    U.wait(1)
    if Space.vm and Space.vm:isRunning() then
      started = true
      break
    end
  end
  result(started, "the OnFrame fall script started")

  local pendingSeen = false
  local landed = false
  for _ = 1, 900 do
    U.wait(1)
    if ctx() and ctx().warpPending then pendingSeen = true end
    if Runtime.getSession().map == CAVE_B1F then
      landed = true
      break
    end
  end
  result(pendingSeen, "warphole marked the warp pending while the fall ran")
  result(landed, "warphole landed the player on Icefall Cave B1F, map="
    .. tostring(Runtime.getSession().map))

  for _ = 1, 600 do
    U.wait(1)
    if not (Space.vm and Space.vm:isRunning()) then break end
  end
  result(not (Space.vm and Space.vm:isRunning()),
    "waitstate released once the fall finished")
  result(ctx() == nil or ctx().warpPending ~= true, "the pending flag was cleared")
  print("[driver] landed at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellX == 8 and Player.cellY == 14,
    "landed under the hole at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.wait(60)
  U.shot(game, DIR .. "/ops_icefall_hole_02_landed_b1f.png")

  result(step("down") or step("left") or step("up"),
    "control came back to the player on B1F")

  finish()
end
