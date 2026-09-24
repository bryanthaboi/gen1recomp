local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/worker_fs_chip_music"

return function(game)
  local ChipAudio = require("src.core.ChipAudio")
  local Music = require("src.core.Music")
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  result(U.newGame(game), "new game reached the overworld")
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local want = game.data.audio and game.data.audio.mapSongs and game.data.audio.mapSongs.ROUTE_1
  result(want ~= nil, "route 1 map song in the cache (" .. tostring(want) .. ")")
  for _ = 1, 200 do
    if Music.current() == want then break end
    U.wait(1)
  end
  local deadline = love.timer.getTime() + 8
  local playing = false
  while love.timer.getTime() < deadline do
    U.wait(1)
    local src = ChipAudio.currentSource()
    if src and src:isPlaying() then playing = true break end
  end

  local stats = ChipAudio.stats()
  print("chip stats: song=" .. tostring(Music.current()) .. " " .. stats.line)
  result(Music.current() ~= nil and Music.current() == want, "route 1 plays " .. tostring(want))
  result(stats.worker == "jit" or stats.worker == "interp", "chip worker running (" .. stats.worker .. ")")
  result((stats.buffers or 0) > 0, "chip worker PCM reached the source (" .. tostring(stats.buffers) .. " buffers)")
  result(playing, "chip music source playing")
  if fails == 0 then
    U.shot(game, DIR .. "/chip_music_route1_playing.png")
  end
  love.event.quit(fails == 0 and 0 or 1)
end
