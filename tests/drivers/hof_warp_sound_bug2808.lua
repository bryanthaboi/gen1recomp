-- home/overworld.asm:482 WarpFound2, home/overworld.asm:689 PlayMapChangeSound
--   tools/run_driver.sh red <identity> tests/drivers/hof_warp_sound_bug2808.lua <shotdir>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Sound = require("src.core.Sound")
  local story = dofile("data/scripts/story.lua")

  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    print((ok and "PASS " or "FAIL ") .. label)
    return ok
  end
  local function finish()
    U.log("done:", failures, "failure(s)")
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN = true
  game.save.flags.EVENT_BEAT_CHAMPION_RIVAL = true

  U.teleport(game, "CHAMPIONS_ROOM", 4, 3, "up")
  local ow = game.stack:top()
  check("standing in CHAMPIONS_ROOM", ow and ow.map and ow.map.id == "CHAMPIONS_ROOM")

  local rows = story.CHAMPIONS_ROOM.talk.TEXT_CHAMPIONSROOM_RIVAL
  local tail
  for i, row in ipairs(rows) do
    if row[1] == "move_player" and row[2] == "left" then
      tail = {}
      for j = i, #rows do tail[#tail + 1] = rows[j] end
      break
    end
  end
  check("found the WalkToHallOfFame tail of the champion script", tail ~= nil)
  if not tail then finish() end

  local cues = {}
  local origPlay = Sound.play
  Sound.play = function(data, name, ...)
    cues[#cues + 1] = { name = name, map = game.overworld and game.overworld.map
                        and game.overworld.map.id, frame = U.frame() }
    return origPlay(data, name, ...)
  end

  ow:queueScript(tail)
  local onWarpTile, expected
  for _ = 1, 1200 do
    U.wait(1)
    local o = game.overworld
    if o and o.map and o.map.id == "CHAMPIONS_ROOM" and not onWarpTile then
      local p = o.player
      if p.cellY == 0 and o.map:warpAtCell(p.cellX, p.cellY) then
        onWarpTile = { x = p.cellX, y = p.cellY }
        local t = o.map:tileAt(p.cellX * 2, p.cellY * 2)
        expected = (t == 0x0B) and "Go_Inside" or "Go_Outside"
        U.log(("player on warp (%d,%d) tile=0x%02X expect %s"):format(
          p.cellX, p.cellY, t or -1, expected))
      end
    end
    if o and o.map and o.map.id == "HALL_OF_FAME" and not o.transitioning then
      break
    end
  end
  Sound.play = origPlay

  local o = game.overworld
  check("script walked the player onto the HALL_OF_FAME warp", onWarpTile ~= nil)
  check("arrived in HALL_OF_FAME", o and o.map and o.map.id == "HALL_OF_FAME")
  local mapCues = {}
  for _, c in ipairs(cues) do
    U.log("sfx", c.name, "on", tostring(c.map), "frame", c.frame)
    if c.name == "Go_Inside" or c.name == "Go_Outside" then
      mapCues[#mapCues + 1] = c
    end
  end
  check("exactly one map change sound on the HoF warp", #mapCues == 1)
  check("map change sound is " .. tostring(expected),
        mapCues[1] ~= nil and mapCues[1].name == expected)
  check("map change sound fired from CHAMPIONS_ROOM",
        mapCues[1] ~= nil and mapCues[1].map == "CHAMPIONS_ROOM")
  if o and o.player then
    U.log("landed at", o.player.cellX, o.player.cellY, o.player.facing)
    check("landed on the HoF entry (4,7)", o.player.cellX == 4 and o.player.cellY == 7)
  end
  U.wait(20)
  U.still(game, DIR .. "/2808_01_hof_arrival.png")

  game.save.flags.EVENT_SAFARI_GAME_OVER = nil
  game.save.safari = { steps = 0, balls = 0 }
  U.teleport(game, "SAFARI_ZONE_CENTER", 14, 22, "down")
  local sow = game.stack:top()
  check("standing in SAFARI_ZONE_CENTER", sow and sow.map and sow.map.id == "SAFARI_ZONE_CENTER")
  local safariCues = {}
  Sound.play = function(data, name, ...)
    if name == "Go_Inside" or name == "Go_Outside" then
      safariCues[#safariCues + 1] = { name = name, map = game.overworld
                                      and game.overworld.map and game.overworld.map.id }
    end
    return origPlay(data, name, ...)
  end
  sow:safariGameOver("")
  for _ = 1, 600 do
    local g = game.overworld
    if g and g.map and g.map.id == "SAFARI_ZONE_GATE" and not g.transitioning then break end
    U.tap(game, "a")
    U.wait(3)
  end
  Sound.play = origPlay
  local g = game.overworld
  check("safari game over warped to SAFARI_ZONE_GATE", g and g.map and g.map.id == "SAFARI_ZONE_GATE")
  for _, c in ipairs(safariCues) do U.log("safari sfx", c.name, "on", tostring(c.map)) end
  check("safari game over warp plays one map change sound from SAFARI_ZONE_CENTER",
        #safariCues == 1 and safariCues[1].map == "SAFARI_ZONE_CENTER")
  if g and g.player then
    U.log("gate landing", g.player.cellX, g.player.cellY,
          "door tile:", tostring(g.map:isDoorTileCell(4, 0)))
  end
  finish()
end
