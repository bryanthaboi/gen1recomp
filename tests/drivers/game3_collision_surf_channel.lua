local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_collision_surf_channel"
io.stdout:setvbuf("no")

local B3F = "FR_SEAFOAM_ISLANDS_B3F"
local ROUTE_19 = "FR_ROUTE_19"
local SWIMMER = 5

-- pokefirered/include/constants/metatile_behaviors.h:21
local MB_SHALLOW_WATER = 0x17

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS collision_surf_channel")
    love.event.quit(0)
  else
    print("FAIL collision_surf_channel failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(150)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.repelSteps = 250

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
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    Player.surfing = true
    Player.dismounting = false
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(60)
    settle(200)
    place(x, y, facing or "down")
    U.wait(20)
  end

  print("[driver] 1. the Seafoam B3F current channel")
  goTo(B3F, 23, 8, "right")
  print(string.format("[driver] on %s at (%d,%d) surfing=%s",
    tostring(Space.mapId), Player.cellX, Player.cellY, tostring(Player.surfing)))
  result(Space.mapId == B3F, "surfed into Seafoam Islands B3F, map=" .. tostring(Space.mapId))
  result(Player.cellX == 23 and Player.cellY == 8,
    "the surfer sits on the mid-channel shallow cell")
  result(Player.surfing == true, "and is still on Surf there")
  result(Player.dismounting ~= true, "with no dismount queued")
  for _, cell in ipairs({ { 23, 8 }, { 24, 8 } }) do
    local cx, cy = cell[1], cell[2]
    result(Collision.behavior(cx, cy) == MB_SHALLOW_WATER,
      string.format("(%d,%d) is MB_SHALLOW_WATER (0x%02X)", cx, cy,
        Collision.behavior(cx, cy) or 0))
    result(Collision.elevationAt(cx, cy) == 1,
      string.format("(%d,%d) sits at elevation 1, below CanStopSurfing's elevation 3",
        cx, cy))
    result(Collision.isWater(cx, cy) == true,
      string.format("(%d,%d) still counts as surf water", cx, cy))
  end
  U.shot(game, DIR .. "/collision_surf_channel_01_seafoam_shallow.png")

  local okEast, whyEast = Collision.canEnter(game, 24, 8,
    { fromX = 23, fromY = 8, dir = "right", surfing = true })
  print("[driver] east onto (24,8): canEnter=" .. tostring(okEast)
    .. " reason=" .. tostring(whyEast))
  result(okEast == false and whyEast == "entity",
    "(24,8) is refused by the boulder standing on it, not by the water rule")

  local visited, dropped = {}, false
  local moved
  for _ = 1, 4 do
    moved = Player.tryMove("up", game, false)
    print("[driver] tryMove up -> " .. tostring(moved)
      .. " dismounting=" .. tostring(Player.dismounting))
    if moved == "step" then break end
    U.wait(8)
  end
  result(moved == "step", "the surfer steps north onto the current cell above")
  result(Player.dismounting ~= true, "leaving the shallow cell is not a dismount")
  for _ = 1, 120 do
    U.wait(1)
    visited[Player.cellX .. "," .. Player.cellY] = true
    if Player.surfing ~= true or Player.dismounting == true then dropped = true end
  end
  local cells = {}
  for k in pairs(visited) do cells[#cells + 1] = k end
  table.sort(cells)
  print("[driver] the surfer occupied " .. table.concat(cells, " "))
  result(visited["23,8"] == true, "the current carries him back over the shallow cell")
  result(not dropped, "Surf never dropped inside the channel")
  result(Player.surfing == true, "and the player is still surfing")

  print("[driver] 2. the Route 19 swimmer keeps wandering")
  goTo(ROUTE_19, 8, 25, "down")
  local swimmer = Objects.find(SWIMMER)
  if not result(swimmer ~= nil, "the Route 19 swimmer is loaded") then return finish() end
  result(swimmer.movement == "WALK", "she is a wandering object event")
  result(Collision.isWater(swimmer.cellX, swimmer.cellY) == true,
    string.format("and treads water at (%d,%d)", swimmer.cellX, swimmer.cellY))

  local homeX, homeY = swimmer.cellX, swimmer.cellY
  local wet, ashore, moved = {}, false, false
  for _ = 1, 300 do
    U.wait(1)
    wet[swimmer.cellX .. "," .. swimmer.cellY] = true
    if swimmer.cellX ~= homeX or swimmer.cellY ~= homeY then moved = true end
    if not Collision.isWater(swimmer.cellX, swimmer.cellY) then ashore = true end
  end
  local swum = {}
  for k in pairs(wet) do swum[#swum + 1] = k end
  table.sort(swum)
  print("[driver] the swimmer occupied " .. table.concat(swum, " "))
  result(moved, "she moves while the player floats beside her")
  result(not ashore, "and never climbs out onto the land")
  U.shot(game, DIR .. "/collision_surf_channel_02_route19_swimmer.png")

  finish()
end
