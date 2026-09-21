local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchseam_mod_collision"

local BAND = "FR_VICTORY_ROAD_1F"
local NAOMI = 2
local BX, BY = 14, 5

local SHORE = "FR_PALLET_TOWN"
local BEACH_X, BEACH_Y = 8, 16

-- pokefirered/include/constants/metatile_behaviors.h:41
local MB_IMPASSABLE_NORTH = 0x32

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchseam_mod_collision")
    love.event.quit(0)
  else
    print("FAIL stitchseam_mod_collision failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Gen3Compat = require("src.mods.Gen3Compat")
  local WorldAPI = require("src.world.game3.WorldAPI")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local world = WorldAPI.new(game, "stitchseam-driver")
  local facade = Gen3Compat.resolve("src.world.Collision")
  result(type(facade) == "table" and type(facade.canMove) == "function",
    "a mod reaches src.world.Collision through the Gen 3 facade")

  print("[driver] scene 1: the direction blocked band on " .. BAND)
  goTo(BAND, 13, 6, "up")
  result(Map.current == BAND, "the player is standing in Victory Road 1F")
  result(Collision.behavior(BX, BY) == MB_IMPASSABLE_NORTH,
    string.format("(%d,%d) carries MB_IMPASSABLE_NORTH on the live map", BX, BY))

  -- pokefirered/src/scrcmd.c:1074 ScrCmd_setobjectxy
  Objects.setObjectXY(NAOMI, BX, BY)
  U.wait(20)
  local handle, why = world:npc(BAND, NAOMI)
  if not result(handle ~= nil,
      "mod.world:npc handed back a live handle (" .. tostring(why) .. ")") then
    return finish()
  end
  U.shot(game, DIR .. "/stitchseam_mod_collision_01_victory_road_band.png")

  result(handle:canStep("up") == false,
    "npc:canStep refuses the northbound step off the band")
  result(handle:canStep("down") == true,
    "and allows the southbound step off it")
  result(handle:canStep("left") == true,
    "and still allows walking west along it")

  local mover = { cellX = BX, cellY = BY, surfing = false }
  local okUp, whyUp = facade.canMove(nil, {}, mover, "up")
  result(okUp == false and whyUp == "tile",
    "Collision.canMove refuses the same northbound step, reason " .. tostring(whyUp))
  result(facade.canMove(nil, {}, mover, "down") == true,
    "and allows the same southbound step")

  local above = { cellX = BX, cellY = BY - 1, surfing = false }
  result(facade.canMove(nil, {}, above, "down") == false,
    "and refuses entering the band from the north")

  print("[driver] scene 2: the beach walker while the player surfs")
  goTo(SHORE, 7, 16, "right")
  result(Map.current == SHORE, "the player is standing on the Pallet Town beach")
  result(Collision.isWater(BEACH_X, BEACH_Y + 1) == true, "(8,17) is the ocean")

  Objects.setObjectXY(1, BEACH_X, BEACH_Y)
  U.wait(20)
  local walker = world:npc(SHORE, 1)
  if not result(walker ~= nil, "a Pallet Town object handle is live") then
    return finish()
  end

  Player.surfing = false
  result(walker:canStep("down") == false,
    "npc:canStep keeps the beach walker out of the sea")

  -- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
  Player.cellX, Player.cellY = 7, 17
  Player.px, Player.py = 7 * 16, 17 * 16
  Player.targetX, Player.targetY = 7, 17
  Player.surfing = true
  U.wait(30)
  U.shot(game, DIR .. "/stitchseam_mod_collision_02_surfing_beside_walker.png")
  result(walker:canStep("down") == false,
    "and still keeps her out of it while the player is surfing")
  result(walker:canStep("up") == true,
    "while she may still walk north along the beach")
  Player.surfing = false

  finish()
end
