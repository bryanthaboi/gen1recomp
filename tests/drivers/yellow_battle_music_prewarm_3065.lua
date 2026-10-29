return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local ChipAudio = require("src.core.ChipAudio")
  local Music = require("src.core.Music")
  local now = love.timer.getTime
  local failed = false
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  U.teleport(game, "ROUTE_1", 9, 20, "down")
  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 12),
    Pokemon.new(game.data, "PIDGEOTTO", 18),
    Pokemon.new(game.data, "BUTTERFREE", 14),
    Pokemon.new(game.data, "NIDORINO", 17),
    Pokemon.new(game.data, "GEODUDE", 13),
    Pokemon.new(game.data, "SPEAROW", 11),
  }
  local t = now()
  while now() - t < 2.5 do U.wait(1) end

  local marks = {}
  local realPlay = ChipAudio.playMusic
  ChipAudio.playMusic = function(...)
    if not marks.playT then
      marks.playT = now()
      local st = ChipAudio.stats()
      marks.queuedAtPlay, marks.inFlightAtPlay =
        st.prewarmQueued, st.prewarmInFlight
      marks.underrunsAtPlay = st.underruns
    end
    return realPlay(...)
  end
  local frontQueued = 0
  local realFront = ChipAudio.prewarmFront
  if realFront then
    ChipAudio.prewarmFront = function(...)
      local before = ChipAudio._effectStateForTest().queued
      realFront(...)
      frontQueued = frontQueued
        + (ChipAudio._effectStateForTest().queued - before)
    end
  end

  local api = require("src.world.WorldAPI").new(game, "bd3065")
  local ok, err = api:startWildBattle("PIDGEY", 3)
  U.log("startWildBattle", tostring(ok), tostring(err))
  ChipAudio.prewarmFront = realFront
  local backgroundAtPlay = marks.queuedAtPlay
    and (marks.queuedAtPlay - frontQueued)
  local startedT, drainedT, queuedAtStart, background, minDepth
  local floor = ChipAudio.MUSIC_PREROLL * 2
  local t0 = now()
  while now() - t0 < 6 do
    U.wait(1)
    local st = ChipAudio.stats()
    if startedT and backgroundAtPlay
        and st.prewarmQueued < backgroundAtPlay then
      background = true
    end
    if background and not drainedT and st.depth
        and (minDepth == nil or st.depth < minDepth) then
      minDepth = st.depth
    end
    if not startedT and marks.playT and not ChipAudio.awaitingFirstBuffer() then
      startedT = now()
      queuedAtStart = st.prewarmQueued
      U.log(("music started %.1fms after playMusic, depth=%s q=%d inflight=%d ready=%d")
        :format((startedT - marks.playT) * 1000, tostring(st.depth),
          st.prewarmQueued, st.prewarmInFlight, st.prewarmReady))
    end
    if startedT and not drainedT
        and st.prewarmQueued + st.prewarmInFlight == 0 then
      drainedT = now()
      U.log(("prewarm drained %.1fms after playMusic, ready=%d depth=%s")
        :format((drainedT - marks.playT) * 1000, st.prewarmReady,
          tostring(st.depth)))
    end
  end
  ChipAudio.playMusic = realPlay
  local st = ChipAudio.stats()
  U.log(("queued at play %s inflight %s"):format(
    tostring(marks.queuedAtPlay), tostring(marks.inFlightAtPlay)))
  U.log("stats", st.line)
  U.log("min depth during the background prewarm", tostring(minDepth))

  result(startedT ~= nil and Music.current() == "Music_WildBattle",
    "wild battle theme started")
  result(startedT ~= nil and marks.playT ~= nil
      and startedT - marks.playT < 0.5,
    "battle theme starts within 0.5 s of its cue on desktop")
  result(marks.inFlightAtPlay == 0,
    ("no battle prewarm reaches the worker before the theme's play (%s in flight)")
      :format(tostring(marks.inFlightAtPlay)))
  result(queuedAtStart ~= nil and backgroundAtPlay ~= nil
      and queuedAtStart >= backgroundAtPlay,
    "no background prewarm leaves the queue while the theme awaits its preroll")
  result(drainedT ~= nil, "the background prewarm drains within 6 s")
  result(background and minDepth ~= nil and minDepth >= floor,
    ("the background prewarm never digs the music queue under %d buffers (min %s)")
      :format(floor, tostring(minDepth)))
  result(st.underruns == (marks.underrunsAtPlay or 0),
    "no music underrun after the cue")
  love.event.quit(failed and 1 or 0)
end
