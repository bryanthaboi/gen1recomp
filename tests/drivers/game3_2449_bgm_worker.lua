local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_2449_bgm_worker"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Audio = require("src.core.game3.audio")
  result(Audio.isReady(), "2449 audio pack installed")
  result(Audio._worker and Audio._worker ~= false, "2449 bgm worker running")

  local maxQueued, playing = 0, false
  for _ = 1, 240 do
    U.wait(1)
    local q = #(Audio._bgmQueuedAt or {})
    if q > maxQueued then maxQueued = q end
    local src = Audio._bgmSource
    if src and src:isPlaying() then playing = true end
  end
  result(Audio._warned.worker == nil, "2449 no worker install failure")
  result(Audio._bgmGen ~= nil, "2449 bgm song " .. tostring(Audio._bgmGen))
  result(maxQueued > 0, "2449 worker PCM reached the source (" .. maxQueued .. " buffers)")
  result(playing, "2449 bgm source playing")
  if fails == 0 then
    U.shot(game, DIR .. "/2449_bgm_playing_new_game.png")
  end
  love.event.quit(fails == 0 and 0 or 1)
end
