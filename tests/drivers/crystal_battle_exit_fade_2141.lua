-- ../pokecrystal/data/maps/setup_scripts.asm:127-140
-- ../pokecrystal/engine/overworld/map_setup.asm:181-189
-- ../pokecrystal/home/fade.asm:35-62
-- ../pokecrystal/engine/tilesets/timeofday_pals.asm:160-187
-- ../pokecrystal/engine/events/whiteout.asm:1-21
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local World = require("src.world.gen2.World")

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
  -- home/time.asm GetTimeOfDay, engine/tilesets/timeofday_pals.asm:160-187
  local night = os.getenv("POKEPORT_FADE_NIGHT") == "1"
  if night then
    world.clockHour = 23
    world:applyPalettes()
  end

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
  local doorSheet, doorWhiten = 0, 0
  local lastDoorLevel
  for _ = 1, 200 do
    U.wait(1)
    if world.mapSetup then
      doorTicks = doorTicks + 1
      if world.fadeLevel == 1 then whiteTicks = whiteTicks + 1 end
      if world.fadeHold then doorSheet = doorSheet + 1 end
      if world.fadeWhiten then doorWhiten = doorWhiten + 1 end
      if world.fadeLevel ~= lastDoorLevel or world.fadeHold then
        lastDoorLevel = world.fadeLevel
        shot("door_in")
      end
    end
    if world.map and world.map.id == "PLAYERS_HOUSE_1F" and not world:busy() then
      entered = true
      break
    end
  end
  local doorHold = World.MAP_LOAD_WHITE_FRAMES
  ok(entered, "the door warp finished")
  ok(whiteTicks == 2 + doorHold + 2,
    ("door: level 1 held %d ticks (want %d: last out row, load, first in row)")
      :format(whiteTicks, 4 + doorHold))
  ok(doorSheet == doorHold,
    ("door: pure white held %d ticks (want %d, the LCD-off window alone)")
      :format(doorSheet, doorHold))
  ok(doorWhiten == 10,
    ("door: FillWhiteBGColor held %d ticks over the way out (want 10)")
      :format(doorWhiten))
  ok(doorTicks == 10 + doorHold + 8,
    ("door: the chain ran %d ticks (want %d)"):format(doorTicks, 18 + doorHold))

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
  local returnWhite, returnTicks, returnSheet = 0, 0, 0
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
        if world.fadeHold then returnSheet = returnSheet + 1 end
        if world.fadeLevel ~= lastReturnLevel or world.fadeHold then
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
  local warpHold = World.WARP_LOAD_WHITE_FRAMES
  ok(returnWhite == warpHold + 2,
    ("return: level 1 held %d ticks (want %d: load, first in row)")
      :format(returnWhite, warpHold + 2))
  ok(returnSheet == warpHold,
    ("return: pure white held %d ticks (want %d)"):format(returnSheet, warpHold))
  ok(returnTicks == warpHold + 2 + 6,
    ("return: the fade in ran %d ticks (want %d)")
      :format(returnTicks, warpHold + 8))
  ok(world.mapSetup == nil and world.fade == nil, "the return fade cleared")
  U.wait(5)
  shot("done")

  -- (engine/overworld/scripting.asm:1174-1184, engine/events/whiteout.asm:19)
  local lossMap = world.map.id
  save.party = { Mon.new(data, "CYNDAQUIL", 2) }
  save.party[1].hp = 1
  local loser = Mon.new(data, "SENTRET", 20)
  ok(world:startBattle({ wild = loser }), "a losing battle starts")
  local lossScreen
  for _ = 1, 600 do
    U.wait(1)
    local top = game.stack:top()
    if top and top.battle then lossScreen = top break end
  end
  ok(lossScreen ~= nil, "the losing battle screen is up")
  local lossWhite, lossSheet, lossPopped = 0, 0, false
  local lossPhase, lossFade, lossHold
  for _ = 1, 1800 do
    if game.stack:top() == lossScreen then
      U.tap(game, "a")
    else
      if not lossPopped then
        lossPopped = true
        lossPhase = world.mapSetup and world.mapSetup.phase
        lossFade, lossHold = world.fade, world.fadeHold
      end
      if world.mapSetup then
        if world.fadeLevel == 1 then lossWhite = lossWhite + 1 end
        if world.fadeHold then lossSheet = lossSheet + 1 end
        shot("whiteout_in")
      elseif lossWhite > 0 then
        break
      end
    end
    U.wait(1)
  end
  ok(lossPopped, "the lost battle popped")
  ok(lossFade == "white" and lossPhase == "in",
    ("whiteout: the spawn map fades in (fade=%s phase=%s)")
      :format(tostring(lossFade), tostring(lossPhase)))
  ok(lossHold == warpHold,
    ("whiteout: pure white armed for %s ticks (want %d)")
      :format(tostring(lossHold), warpHold))
  ok(lossSheet == warpHold and lossWhite == warpHold + 2,
    ("whiteout: held %d pure / %d level-1 ticks"):format(lossSheet, lossWhite))
  ok(world.map.id ~= lossMap, "and the player is at the spawn point")
  U.wait(5)
  shot("whiteout_done")

  -- engine/tilesets/timeofday_pals.asm:160-187 on a PALETTE_AUTO map
  if night then
    world:warpToMapId("NEW_BARK_TOWN", 13, 7, "up")
    for _ = 1, 200 do
      if not world:busy() then break end
      U.wait(1)
    end
    U.wait(10)
    ok(world.map.id == "NEW_BARK_TOWN" and world.daytime == "NITE",
      ("outdoors at night (map=%s daytime=%s)")
        :format(tostring(world.map.id), tostring(world.daytime)))
    world:battleReturnFade()
    local nightHold, nightPlane = 0, 0
    for _ = 1, 200 do
      if not world.mapSetup then break end
      if world.fadeHold then
        nightHold = nightHold + 1
      else
        nightPlane = nightPlane + 1
        shot("night_outdoor_in")
      end
      U.wait(1)
    end
    ok(nightHold == warpHold,
      ("night: pure white held %d ticks (want %d)"):format(nightHold, warpHold))
    ok(nightPlane == World.FADE_STEPS * World.FADE_STEP_FRAMES,
      ("night: %d ramp ticks through the palette remap (want %d)")
        :format(nightPlane, World.FADE_STEPS * World.FADE_STEP_FRAMES))
  end

  print("[exit-fade-2141] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- " .. shotN .. " shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
