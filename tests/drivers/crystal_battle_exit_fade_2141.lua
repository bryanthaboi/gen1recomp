-- ../pokecrystal/data/maps/setup_scripts.asm:127-140
-- ../pokecrystal/engine/overworld/map_setup.asm:181-189
-- ../pokecrystal/home/fade.asm:35-62
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-exit-fade-2141"
  os.execute("mkdir -p '" .. out .. "'")
  local shotN = 0
  local function shot(tag)
    shotN = shotN + 1
    game.capturePath = string.format("%s/%03d_%s.png", out, shotN, tag)
  end
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[exit-fade-2141] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")
  local save, data = game.save, game.data
  save.party = { Mon.new(data, "CYNDAQUIL", 12) }

  world.mapScenes = world.mapScenes or {}
  world.mapScenes.NEW_BARK_TOWN = 1
  world:warpToMapId("NEW_BARK_TOWN", 13, 7, "up")
  for _ = 1, 60 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(10)
  ok(world.map.id == "NEW_BARK_TOWN", "standing outside the player's house")

  U.hold(game, "up", 24)
  local whiteTicks, doorTicks, entered = 0, 0, false
  local lastDoorLevel
  for _ = 1, 120 do
    U.wait(1)
    if world.mapSetup then
      doorTicks = doorTicks + 1
      if world.fadeLevel == 1 then whiteTicks = whiteTicks + 1 end
      if world.fadeLevel ~= lastDoorLevel then
        lastDoorLevel = world.fadeLevel
        shot("door_in")
      end
    end
    if world.map and world.map.id == "PLAYERS_HOUSE_1F" and not world:busy() then
      entered = true
      break
    end
  end
  ok(entered, "the door warp finished")
  ok(whiteTicks == 2 + 4 + 2,
    ("door: white held %d ticks (want 8: last out row, load, first in row)"):format(whiteTicks))
  ok(doorTicks >= 20, ("door: the chain ran %d ticks"):format(doorTicks))

  local wild = Mon.new(data, "SENTRET", 3)
  ok(world:startBattle({ wild = wild }), "a wild battle starts")
  local screen
  for _ = 1, 600 do
    U.wait(1)
    local top = game.stack:top()
    if top and top.battle then screen = top break end
  end
  ok(screen ~= nil, "the battle screen is up")
  for _ = 1, 900 do
    if screen.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(screen.phase == "menu", "reached the battle menu")

  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "right")
  U.wait(4)
  U.tap(game, "a")

  local fadeTicks, rows, popped = 0, {}, false
  local returnWhite, returnTicks = 0, 0
  local lastReturnLevel
  for _ = 1, 900 do
    if game.stack:top() == screen then
      if screen.phase == "fadeout" then
        fadeTicks = fadeTicks + 1
        local row = screen:exitFadeBgp()
        if rows[#rows] ~= row then
          rows[#rows + 1] = row
          shot("battle_fadeout")
        end
      elseif (screen.messageTimer or 0) > 0 then
        U.tap(game, "a")
      end
    else
      popped = true
      if world.mapSetup then
        returnTicks = returnTicks + 1
        if world.fadeLevel == 1 then returnWhite = returnWhite + 1 end
        if world.fadeLevel ~= lastReturnLevel then
          lastReturnLevel = world.fadeLevel
          shot("battle_return")
        end
      elseif returnTicks > 0 then
        break
      end
    end
    U.wait(1)
  end
  ok(popped, "the battle popped")
  ok(fadeTicks == 24, ("the battle screen faded for %d ticks (want 24)"):format(fadeTicks))
  local rowText = {}
  for _, row in ipairs(rows) do rowText[#rowText + 1] = ("%02x"):format(row) end
  ok(table.concat(rowText, ",") == "90,40,00",
    "rows 2100 / 1000 / 0000 in order (" .. table.concat(rowText, ",") .. ")")
  ok(returnWhite == 4 + 2,
    ("return: white held %d ticks (want 6: load, first in row)"):format(returnWhite))
  ok(returnTicks == 12, ("return: the fade in ran %d ticks (want 12)"):format(returnTicks))
  ok(world.mapSetup == nil and world.fade == nil, "the return fade cleared")
  U.wait(5)
  shot("done")

  print("[exit-fade-2141] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- " .. shotN .. " shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
