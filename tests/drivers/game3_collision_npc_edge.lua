local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_collision_npc_edge"

local MAP = "FR_VICTORY_ROAD_1F"
local NAOMI = 2

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
    print("PASS collision_npc_edge")
    love.event.quit(0)
  else
    print("FAIL collision_npc_edge failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then
    return finish()
  end

  local function settle(limit)
    for _ = 1, (limit or 240) do
      local busy = (Space.vm and Space.vm:isRunning())
        or (Message.isOpen and Message.isOpen())
      if not busy then return true end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(4)
    end
    return false
  end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.moving = false
    Player.progress = 0
    Player.facing = facing or "down"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
  end

  Map.load(nil, game, MAP, { x = 11, y = 9, facing = "right" })
  place(11, 9, "right")
  U.wait(90)
  settle(600)
  place(11, 9, "right")
  U.wait(20)

  result(Collision.behavior(14, 5) == MB_IMPASSABLE_NORTH,
    string.format("%s (14,5) is MB_IMPASSABLE_NORTH (0x%02X)", MAP,
      Collision.behavior(14, 5) or 0))
  result(Collision.cell(14, 5) ~= 0x07, "(14,5) is walkable rock, not a wall")
  result(Collision.cell(14, 4) ~= 0x07, "(14,4) above it is open cave floor")

  -- pokefirered/src/scrcmd.c:1162 ScrCmd_setobjectmovementtype
  Objects.setObjectXY(NAOMI, 14, 5)
  Objects.setMovementType(NAOMI, 3)
  local naomi = Objects.find(NAOMI)
  if not result(naomi ~= nil, "Naomi is on the map") then return finish() end
  result(naomi.movement == "WALK" and naomi.range == "UP_DOWN",
    "Naomi wanders up and down from the sealed band at (14,5)")

  U.wait(20)
  U.shot(game, DIR .. "/collision_npc_edge_01_naomi_on_the_band.png")

  local visited = {}
  local shotSouth = false
  for _ = 1, 3000 do
    U.wait(1)
    visited[naomi.cellX .. "," .. naomi.cellY] = true
    visited[naomi.targetX .. "," .. naomi.targetY] = true
    if not shotSouth and naomi.cellY == 6 and not naomi.moving then
      U.shot(game, DIR .. "/collision_npc_edge_02_naomi_stepped_south.png")
      shotSouth = true
    end
  end

  local cells = {}
  for k in pairs(visited) do cells[#cells + 1] = k end
  table.sort(cells)
  print("[driver] Naomi occupied " .. table.concat(cells, " "))
  result(visited["14,6"] == true, "she really wanders: she reached (14,6)")
  result(visited["14,4"] ~= true, "she never crossed the sealed north edge to (14,4)")
  result(shotSouth, "the southward step was captured")

  local okUp = Collision.canEnter(game, 14, 4,
    { fromX = 14, fromY = 5, dir = "up", surfing = false })
  result(okUp == false, "GetCollisionAtCoords refuses her northbound step")

  finish()
end
