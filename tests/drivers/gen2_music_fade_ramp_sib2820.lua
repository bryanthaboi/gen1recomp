-- ../pokecrystal/audio/engine.asm:603-669 FadeMusic
-- ../pokecrystal/home/audio.asm:308-324 FadeToMapMusic
-- ../pokecrystal/engine/overworld/scripting.asm:757-765 Script_musicfadeout
local U = require("tests.drivers.util")

local Music = require("src.core.Music")

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-music-fade-ramp"
  local fails = 0
  local function say(line) print("[gen2-fade] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen2 world did not boot")
    love.event.quit(1)
    return
  end

  world:warpToMapId("ROUTE_29", 20, 8, "left")
  U.wait(45)
  ok(world.map.id == "ROUTE_29", "landed on Route 29 (got "
    .. tostring(world.map.id) .. ")")
  local routeSong = Music.current()
  local mapSongs = game.data.audio and game.data.audio.mapSongs or {}
  local townSong = world:mapMusicSong("CHERRYGROVE_CITY")
    or mapSongs.CHERRYGROVE_CITY
  ok(routeSong ~= nil and townSong ~= nil and routeSong ~= townSong,
    "route and town songs differ (" .. tostring(routeSong) .. " / "
    .. tostring(townSong) .. ")")

  -- (data/maps/setup_scripts.asm:51, audio/engine.asm:618-624).
  local function ramp(expectSong, label)
    local levels, switchAt = {}, nil
    for frame = 1, 120 do
      U.wait(1)
      local level = Music.fadeLevel()
      if Music.current() == expectSong and not switchAt then
        switchAt = frame
        break
      end
      levels[#levels + 1] = level and tostring(level) or "-"
    end
    local counts, last = {}, nil
    for _, l in ipairs(levels) do
      if l == last then counts[#counts] = counts[#counts] + 1
      else counts[#counts + 1] = 1 last = l end
    end
    say(label .. " levels per frame: " .. table.concat(levels, " "))
    say(label .. " holds: " .. table.concat(counts, " ") .. ", switch at "
      .. tostring(switchAt))
    return levels, counts, switchAt
  end

  world:setMapMusic("CHERRYGROVE_CITY", true)
  ok(Music.current() == routeSong, "the route song keeps playing when the fade is armed")
  U.still(game, DIR .. "/sib2820_01_route29_fading_to_cherrygrove.png")
  local levels, counts, switchAt = ramp(townSong, "FadeToMapMusic")
  ok(table.concat(levels, " ", 1, 5) == "7 7 7 7 6",
    "the warp's leftover count of 4 runs out, then the first level drops")
  ok(table.concat(counts, " ") == "4 9 9 9 9 9 9 9",
    "levels 6..0 each hold control + 1 = 9 frames")
  ok(switchAt == 4 + 1 + 7 * 9,
    "the town song starts 4 + 1 + 7 * 9 frames after the write (got "
    .. tostring(switchAt) .. ")")
  ok(Music.fadeLevel() == nil, "the fade is cleared on the switch")

  U.wait(10)
  local order = game.data.audio.musicOrder
  local routeId
  for index, name in ipairs(order) do
    if name == routeSong then routeId = index - 1 end
  end
  ok(routeId ~= nil, "the route song has a music id (" .. tostring(routeId) .. ")")
  world:fadeOutMusic(routeId, 4)
  local levels2, counts2, switchAt2 = ramp(routeSong, "musicfadeout")
  ok(levels2[1] == "6", "musicfadeout: first drop on the first frame")
  ok(table.concat(counts2, " ") == "5 5 5 5 5 5 5",
    "musicfadeout: levels 6..0 each hold 5 frames")
  ok(switchAt2 == 1 + 7 * 5, "musicfadeout: the queued song starts at frame 36 (got "
    .. tostring(switchAt2) .. ")")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
