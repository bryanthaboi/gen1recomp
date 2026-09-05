local U = require("tests.drivers.util")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"

-- pokecrystal/maps/TinTower1F.asm:15
local MAP = "TIN_TOWER_1F"
local SCENE = 0
local DOOR_X, DOOR_Y = 9, 15

return function(game)
  local fails = 0
  local function say(line) print("[quicksave2185] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local w = game.world
  if not (w and w.map) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  for _ = 1, 300 do
    if not w:busy() then break end
    U.wait(1)
  end
  local wrote = false
  local realWrite = game.writeSave
  game.writeSave = function(self, ...) wrote = true return realWrite(self, ...) end
  game:hotkey("f1")
  ok(wrote, "F1 saves normally while the player has control")
  U.shot(game, SHOTS .. "/2185_02_quicksave_allowed_when_idle.png")

  w.mapScenes[MAP] = SCENE
  w:warpToMapId(MAP, DOOR_X, DOOR_Y, "up")
  U.wait(60)
  ok(w.map and w.map.id == MAP, "arrived at " .. MAP)

  local scripted = false
  for _ = 1, 300 do
    if w:busy() and (w.vm and w.vm:running()) then scripted = true break end
    U.wait(1)
  end
  ok(scripted, "the Suicune scene script is walking the player north")

  wrote = false
  local handled = game:hotkey("f1")
  ok(handled == true, "F1 is still swallowed rather than leaking to Input")
  ok(not wrote, "and no save is written while the scene script runs")
  ok(game:quickSaveAllowed() == false, "quickSaveAllowed says so directly")
  U.shot(game, SHOTS .. "/2185_01_quicksave_refused_midscene.png")
  game.writeSave = realWrite

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
