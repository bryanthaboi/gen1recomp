local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_cycling_road"

-- pokefirered/src/bike.c:53 BikeInputHandler_Normal
-- pokefirered/include/constants/metatile_behaviors.h:128
local MB_CYCLING_ROAD_PULL_DOWN = 0xD0
local ROUTE17 = "FR_ROUTE_17"
-- pokefirered/include/constants/items.h:432 ITEM_BICYCLE
local ITEM_BICYCLE = 360

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_cycling_road")
    love.event.quit(0)
  else
    print("FAIL field_cycling_road failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local Party = require("src.core.game3.party")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  if not (session.party and session.party[1]) then
    session.party = {}
    Party.giveMon(session, 1, 40)
  end
  session.repelSteps = 250

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  Map.load(nil, game, ROUTE17, { x = 2, y = 12, facing = "down" })
  place(2, 12, "down")
  U.wait(90)
  result(Space.mapId == ROUTE17, "stood on Route 17, map=" .. tostring(Space.mapId))

  local sx, sy
  for y = 10, 150 do
    for x = 0, 23 do
      if Collision.behavior(x, y) == MB_CYCLING_ROAD_PULL_DOWN
          and Collision.isWalkable(x, y) and Collision.isWalkable(x, y + 1)
          and Collision.isWalkable(x, y + 2) then
        sx, sy = x, y
        break
      end
    end
    if sx then break end
  end
  if not result(sx ~= nil, "found a downhill cell on the cycling road") then return finish() end

  Map.load(nil, game, ROUTE17, { x = sx, y = sy, facing = "down" })
  place(sx, sy, "down")
  U.wait(60)
  result(Collision.behavior(sx, sy) == MB_CYCLING_ROAD_PULL_DOWN,
    string.format("standing on MB_CYCLING_ROAD_PULL_DOWN at (%d,%d)", sx, sy))

  -- pokefirered/src/item_use.c:253 FieldUseFunc_Bike
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_BICYCLE, 1)
  ItemUse.useField(session, session.bag, ITEM_BICYCLE, nil)
  U.wait(30)
  result(Player.biking == true, "the BICYCLE is out")
  U.shot(game, DIR .. "/field_cycling_road_01_bike_out.png")

  -- pokefirered/src/bike.c:61 JOY_HELD(B_BUTTON)
  place(sx, sy, "down")
  local brakeY = Player.cellY
  U.hold(game, "b", 90)
  local slipped = Player.cellY - brakeY
  result(slipped == 0, "holding B braked the bike (" .. slipped .. " cells in 90 frames)")
  U.shot(game, DIR .. "/field_cycling_road_02_braked.png")

  local y0 = Player.cellY
  U.wait(120)
  local rolled = Player.cellY - y0
  result(rolled > 4, "letting go rolled the bike " .. rolled .. " cells south")
  result(Player.cellX == sx, "and never sideways")
  U.shot(game, DIR .. "/field_cycling_road_03_rolled_downhill.png")
  result(Field.running == true, "the field survived the run")

  finish()
end
