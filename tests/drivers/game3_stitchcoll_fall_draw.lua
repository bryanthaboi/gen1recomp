local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchcoll_fall_draw"

local CAVE_1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local CAVE_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"
local HOLE_X, HOLE_Y = 8, 14

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchcoll_fall_draw")
    love.event.quit(0)
  else
    print("FAIL stitchcoll_fall_draw failures=" .. failures)
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
  local Warp = require("src.core.game3.warp")
  local Field = require("src.core.game3.field")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local StartMenu = require("src.ui.game3.start_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  Map.load(nil, game, CAVE_1F, { x = HOLE_X, y = HOLE_Y, facing = "down" })
  Player.reset(HOLE_X, HOLE_Y, "down")
  U.wait(90)
  if not result(session.map == CAVE_1F, "stood on the cracked ice in Icefall Cave 1F, map="
      .. tostring(session.map)) then
    return finish()
  end
  U.shot(game, DIR .. "/fall_draw_01_before.png")

  -- pokefirered/data/maps/FourIsland_IcefallCave_1F/scripts.inc:16 OnFrame VAR_TEMP_1
  Flags.setVar(Space.store, nil, "VAR_TEMP_1", 1)
  for _ = 1, 600 do
    if Warp.isBusy() then break end
    U.wait(1)
  end
  -- pokefirered/data/maps/FourIsland_IcefallCave_1F/scripts.inc:26 warphole
  result(Warp.isBusy() == true, "the map's on-frame FallDownHole script started the fall")

  local shot, lowest, deep = false, 0, nil
  local opened, unlockedFrames, busyFrames = 0, 0, 0
  for _ = 1, 900 do
    U.wait(1)
    local y2 = Player.spriteYOffset or 0
    if y2 < lowest then lowest = y2 end
    if Warp.isBusy() then
      busyFrames = busyFrames + 1
      if Field.locked ~= true then unlockedFrames = unlockedFrames + 1 end
      U.tap(game, "start")
      if StartMenu.isOpen and StartMenu.isOpen() then
        opened = opened + 1
        U.tap(game, "b")
      end
    end
    if session.map == CAVE_B1F and y2 < 0 and y2 > -48 and not shot then
      shot = true
      deep = y2
      U.shot(game, DIR .. "/fall_draw_02_mid_air.png")
    end
    if session.map == CAVE_B1F and not Warp.isBusy() then break end
  end

  result(shot, "the avatar was drawn above the floor mid-fall, y2=" .. tostring(deep))
  result(lowest <= -100, "the drop starts off the top of the screen, lowest y2=" .. tostring(lowest))
  result(session.map == CAVE_B1F, "the fall landed on B1F, map=" .. tostring(session.map))
  result((Player.spriteYOffset or 0) == 0, "and the avatar is back on the floor")
  -- pokefirered/src/field_effect.c:1160 LockPlayerFieldControls
  result(unlockedFrames == 0, "the field stayed locked for the whole fall, "
    .. unlockedFrames .. " of " .. busyFrames .. " busy frames were unlocked")
  -- pokefirered/src/field_control_avatar.c:108 FieldGetPlayerInput
  result(opened == 0, "START never opened the menu mid-fall, opened " .. opened .. " time(s)")
  U.wait(30)
  U.shot(game, DIR .. "/fall_draw_03_landed.png")

  finish()
end
