local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchfield_onframe"

local ROUTE_20 = "FR_ROUTE_20"
local B2F = "FR_SEAFOAM_ISLANDS_B2F"
local B3F = "FR_SEAFOAM_ISLANDS_B3F"
local B4F = "FR_SEAFOAM_ISLANDS_B4F"
local ICEFALL_1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local ICEFALL_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"

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
    print("PASS stitchfield_onframe")
    love.event.quit(0)
  else
    print("FAIL stitchfield_onframe failures=" .. failures)
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
  local Warp = require("src.core.game3.warp")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(90)
  end

  local function waitFor(fn, limit)
    for _ = 1, (limit or 600) do
      if fn() then return true end
      U.wait(1)
    end
    return fn()
  end

  print("[driver] --- Seafoam Islands: the hole on B2F, the current on B3F ---")
  -- pokefirered/data/maps/Route20/scripts.inc:10 ResetSeafoamBouldersForB3F
  goTo(ROUTE_20, 30, 9, "left")
  goTo(B2F, 24, 9, "up")
  print("[driver] on " .. tostring(Space.mapId) .. " at (" .. tostring(Player.cellX)
    .. "," .. tostring(Player.cellY) .. ") elevation=" .. tostring(Player.currentElevation))
  U.shot(game, DIR .. "/stitchfield_onframe_01_b2f_below_hole.png")

  U.hold(game, "up", 24)
  local fell = waitFor(function() return Warp.isBusy and Warp.isBusy() end, 180)
  result(fell, "walking onto the B2F hole started the fall warp")

  local landed = waitFor(function()
    return Space.mapId == B3F and not (Warp.isBusy and Warp.isBusy())
  end, 900)
  result(landed, "the fall landed on Seafoam B3F, map=" .. tostring(Space.mapId))
  print("[driver] landed at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY)
    .. ") surfing=" .. tostring(Player.surfing) .. " VAR_TEMP_1=" .. tostring(getVar(VAR_TEMP_1)))
  -- pokefirered/src/field_effect.c:1285
  result(getVar(VAR_TEMP_1) == 1,
    "the surf arrival set VAR_TEMP_1 after the map was already loaded, got "
    .. tostring(getVar(VAR_TEMP_1)))

  -- pokefirered/src/field_control_avatar.c:212
  local fired = waitFor(function()
    return (Space.vm and Space.vm:isRunning()) or Space.mapId == B4F
  end, 240)
  result(fired, "the every-frame ON_FRAME poll started EnterByFalling")
  U.shot(game, DIR .. "/stitchfield_onframe_02_b3f_riding_current.png")

  local arrived = waitFor(function() return Space.mapId == B4F end, 1800)
  result(arrived, "the current carried the player down to B4F, map=" .. tostring(Space.mapId))
  U.wait(90)
  print("[driver] B4F at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  U.shot(game, DIR .. "/stitchfield_onframe_03_b4f_arrival.png")

  print("[driver] --- Icefall Cave 1F: the ice hole ---")
  goTo(ICEFALL_1F, 9, 21, "up")
  U.hold(game, "up", 24)
  waitFor(function() return not Player.moving end, 120)
  print("[driver] on " .. tostring(Space.mapId) .. " at (" .. tostring(Player.cellX)
    .. "," .. tostring(Player.cellY) .. ") locked=" .. tostring(Field.locked))
  result(Space.mapId == ICEFALL_1F and not (Space.vm and Space.vm:isRunning()),
    "standing on the ice with nothing running")
  U.shot(game, DIR .. "/stitchfield_onframe_04_icefall_on_ice.png")

  -- pokefirered/src/field_tasks.c:243
  setVar(VAR_TEMP_1, 1)
  local holeFired = waitFor(function()
    return (Space.vm and Space.vm:isRunning()) or Space.mapId == ICEFALL_B1F
  end, 120)
  result(holeFired, "the ice broke mid-map and ON_FRAME started FallDownHole")

  local dropped = waitFor(function() return Space.mapId == ICEFALL_B1F end, 1800)
  result(dropped, "the player dropped to Icefall Cave B1F, map=" .. tostring(Space.mapId))
  U.wait(90)
  U.shot(game, DIR .. "/stitchfield_onframe_05_icefall_b1f.png")

  finish()
end
