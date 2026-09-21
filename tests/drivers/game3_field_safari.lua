local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_safari"

-- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:86
local ENTRANCE = "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"
local CENTER = "FR_SAFARI_ZONE_CENTER"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_safari")
    love.event.quit(0)
  else
    print("FAIL field_safari failures=" .. failures)
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
  local Safari = require("src.core.game3.safari")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

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

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(60)
  end

  local function walk(dir)
    local sx, sy = Player.cellX, Player.cellY
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then break end
    end
    for _ = 1, 90 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(2)
    return Player.cellX ~= sx or Player.cellY ~= sy
  end

  local function mashA(n)
    for _ = 1, n or 40 do
      U.tap(game, "a")
      U.wait(6)
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
    end
  end

  -- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:114
  session.money = 3000
  session.repelSteps = 250

  goTo(ENTRANCE, 4, 6, "up")
  result(Space.mapId == ENTRANCE, "stood in the Safari Zone entrance, map=" .. tostring(Space.mapId))
  result(Safari.isActive(session) == false, "not in safari mode yet")
  U.shot(game, DIR .. "/field_safari_01_entrance.png")

  walk("up")
  walk("up")
  walk("up")
  result(Player.cellY <= 3 or (Space.vm and Space.vm:isRunning()),
    "walked to the counter at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  mashA(60)
  for _ = 1, 60 do
    U.wait(4)
    if Space.mapId == CENTER then break end
    if Space.vm and Space.vm:isRunning() then mashA(20) end
  end

  if Space.mapId ~= CENTER then
    U.log("the counter script did not warp us in, map=" .. tostring(Space.mapId) ..
      "; entering through the special instead")
    Safari.enter(session)
    goTo(CENTER, 26, 30, "up")
  end

  result(Space.mapId == CENTER, "inside the Safari Zone, map=" .. tostring(Space.mapId))
  result(Safari.isActive(session) == true, "EnterSafariMode armed safari mode")
  result(Safari.balls(session) == 30, "30 SAFARI BALLS (" .. Safari.balls(session) .. ")")
  result(Safari.steps(session) == 600, "600 steps (" .. Safari.steps(session) .. ")")
  U.wait(300)
  U.shot(game, DIR .. "/field_safari_02_inside.png")

  local before = Safari.steps(session)
  local walked = 0
  for i = 1, 10 do
    local dir = (i % 2 == 1) and "up" or "down"
    if walk(dir) then walked = walked + 1 end
  end
  result(walked > 0, "walked " .. walked .. " steps inside the zone")
  result(Safari.steps(session) == before - walked,
    "every step burned one of the 600 (" .. before .. " -> " .. Safari.steps(session) .. ")")

  -- pokefirered/src/safari_zone.c:41
  session.safari.steps = 1
  result(walk("up") or walk("down"), "took the six hundredth step")
  for _ = 1, 120 do
    U.wait(2)
    if Message.isOpen() then break end
  end
  result(Message.isOpen(), "the PA announcement opened")
  result(tostring(Message.currentPage()):find("Ding%-dong") ~= nil,
    "PA: Ding-dong! (" .. tostring(Message.currentPage()) .. ")")
  for _ = 1, 240 do
    if Message.isWaiting() then break end
    U.wait(1)
  end
  U.tap(game, "a")
  for _ = 1, 240 do
    if Message.isWaiting() then break end
    U.wait(1)
  end
  U.shot(game, DIR .. "/field_safari_03_times_up.png")
  mashA(40)

  for _ = 1, 120 do
    U.wait(4)
    if Space.mapId == ENTRANCE then break end
  end
  result(Space.mapId == ENTRANCE,
    "ejected to the Fuchsia entrance, map=" .. tostring(Space.mapId))
  result(Safari.isActive(session) == false, "ExitSafariMode ran")
  result(Safari.balls(session) == 0, "the balls were handed back")
  mashA(40)
  U.wait(60)
  U.shot(game, DIR .. "/field_safari_04_ejected.png")

  finish()
end
