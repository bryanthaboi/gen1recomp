local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_perm_reset"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_perm_reset")
    love.event.quit(0)
  else
    print("FAIL game3_perm_reset failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Objects = require("src.core.game3.objects")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  local LAB = "FR_OAKS_LAB"
  local RIVAL = 8

  Map.load(nil, game, LAB, { x = 6, y = 8, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 6, 8, "up"
  U.wait(60)

  local rival = Objects.find(RIVAL)
  if not result(rival ~= nil, "rival object 8 spawned in the lab") then return finish() end
  local baseX, baseY = rival.cellX, rival.cellY
  print(string.format("[driver] rival template position (%d,%d)", baseX, baseY))

  rival.hidden = false
  rival.visible = true
  Objects.setObjectXY(RIVAL, 6, 10)
  U.wait(30)
  rival = Objects.find(RIVAL)
  result(rival.cellX == 6 and rival.cellY == 10,
    string.format("setobjectxyperm put the rival at the lab door, got (%d,%d)", rival.cellX, rival.cellY))
  U.shot(game, DIR .. "/2317_01_rival_at_lab_door.png")

  Map.load(nil, game, "FR_PALLET_TOWN", { x = 8, y = 10, facing = "down" })
  game.session.x, game.session.y, game.session.facing = 8, 10, "down"
  U.wait(60)
  Map.load(nil, game, LAB, { x = 6, y = 8, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 6, 8, "up"
  U.wait(60)

  rival = Objects.find(RIVAL)
  if not result(rival ~= nil, "rival object 8 respawned after the round trip") then return finish() end
  rival.hidden = false
  rival.visible = true
  U.wait(10)
  result(rival.cellX == baseX and rival.cellY == baseY,
    string.format("re-entering the lab rebuilt the template, got (%d,%d) want (%d,%d)",
      rival.cellX, rival.cellY, baseX, baseY))
  U.shot(game, DIR .. "/2317_02_rival_back_at_template.png")

  Objects.setObjectXY(RIVAL, 6, 10)
  result(next(Objects._perm) ~= nil, "a perm bucket exists before the soft reset")

  game:returnToTitle()
  U.wait(60)

  result(next(Objects._perm) == nil, "returnToTitle cleared Objects._perm")
  result(Objects._mapId == nil, "returnToTitle cleared Objects._mapId")

  finish()
end
