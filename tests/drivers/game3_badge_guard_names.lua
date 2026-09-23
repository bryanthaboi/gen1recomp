local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_badge_guard_names"

local GATE = "FR_ROUTE_22_NORTH_ENTRANCE"
local ROUTE23 = "FR_ROUTE_23"
-- pokefirered/include/constants/flags.h:1364
local FLAG_BADGE01_GET = 0x820

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS badge_guard_names")
    love.event.quit(0)
  else
    print("FAIL badge_guard_names failures=" .. failures)
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
  local Message = require("src.ui.game3.message")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end

  for i = 0, 7 do
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_BADGE01_GET + i, true)
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function talkAndFind(want, shotName)
    U.tap(game, "a")
    local seen = ""
    for _ = 1, 20 do
      U.wait(20)
      if Message.isOpen() then
        Message.skipReveal()
        local page = Message.currentPage() or ""
        seen = seen .. " | " .. page
        if page:find(want, 1, true) then
          U.wait(2)
          U.shot(game, DIR .. "/" .. shotName)
          return true, page
        end
        U.tap(game, "a")
      end
    end
    return false, seen
  end

  local function closeAll()
    for _ = 1, 30 do
      if not (Message.isOpen() or (Space.vm and Space.vm:isRunning())) then break end
      U.tap(game, "a")
      U.wait(10)
    end
  end

  -- pokefirered/data/maps/Route22_NorthEntrance/map.json:21
  goTo(GATE, 8, 3, "up")
  local ok, text = talkAndFind("BOULDERBADGE", "2413_boulder_guard_badge_name.png")
  print("[driver] gate text: " .. tostring(text))
  result(ok, "route22 gate guard names BOULDERBADGE")
  result(not tostring(text):find("the 15", 1, true), "route22 gate guard text has no raw id 15")
  closeAll()

  -- pokefirered/data/maps/Route23/map.json:33
  goTo(ROUTE23, 15, 150, "up")
  ok, text = talkAndFind("CASCADEBADGE", "2413_cascade_guard_badge_name.png")
  print("[driver] route23 text: " .. tostring(text))
  result(ok, "route23 guard names CASCADEBADGE")
  result(not tostring(text):find("the 16", 1, true), "route23 guard text has no raw id 16")
  closeAll()

  finish()
end
