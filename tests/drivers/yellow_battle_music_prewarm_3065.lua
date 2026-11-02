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
  while now() - t < 8 do
    U.wait(1)
    local ps = ChipAudio.parkState()
    if now() - t >= 2.5 and ps and ps.ready then break end
  end
  U.log(("Route 1 settled %.2f s"):format(now() - t))
  local park = ChipAudio.parkState()
  local parkHits = ChipAudio.stats().parkHits
  U.log("park on Route 1", park and park.buffers, park and tostring(park.pushed),
    tostring(Music.current()), ChipAudio.stats().line)

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
  local frames, startFrames = 0, nil
  local floor = ChipAudio.MUSIC_PREROLL * 2
  local t0 = now()
  while now() - t0 < 6 do
    U.wait(1)
    frames = frames + 1
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
      startFrames = frames
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
  result(park ~= nil and park.ready,
    "the wild battle theme is parked on Route 1 before the encounter")
  result(st.parkHits == (parkHits or 0) + 1, "the battle cue takes the park")
  result(startFrames ~= nil and startFrames <= 2,
    ("battle theme first note within 2 frames of the cue (%s)")
      :format(tostring(startFrames)))
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

  U.teleport(game, "ROUTE_3", 16, 6, "left")
  U.wait(15)
  local ow = game.overworld
  local trainerNpc, stand
  for _, n in ipairs((ow and ow.npcs) or {}) do
    if n.def and n.def.trainerClass and not ow:trainerDefeated(n) then
      for _, side in ipairs({ { 0, 1, "up" }, { 0, -1, "down" },
                              { 1, 0, "left" }, { -1, 0, "right" } }) do
        local cx, cy = n.cellX + side[1], n.cellY + side[2]
        if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
          trainerNpc, stand = n, { cx, cy, side[3] }
          break
        end
      end
    end
    if trainerNpc then break end
  end
  result(trainerNpc ~= nil, "a Route 3 trainer to talk to")
  if not trainerNpc then love.event.quit(1) return end
  U.log("trainer", trainerNpc.def.trainerClass, trainerNpc.def.trainerParty,
    stand[1], stand[2])
  U.teleport(game, "ROUTE_3", stand[1], stand[2], stand[3])
  U.wait(10)
  local trainerParkHits = ChipAudio.stats().parkHits
  local cue = {}
  local realBattle = Music.playBattle
  Music.playBattle = function(...)
    if not cue.t then
      cue.park = ChipAudio.parkState()
      cue.t = now()
      cue.frame = 0
      realBattle(...)
      cue.depth = ChipAudio.stats().depth
      return
    end
    return realBattle(...)
  end
  U.tap(game, "a")
  local waitT = now()
  while now() - waitT < 3 do
    U.wait(1)
    local ps = ChipAudio.parkState()
    if ps and ps.ready then break end
  end
  for _ = 1, 40 do
    if cue.t then break end
    U.tap(game, "a")
    U.wait(6)
  end
  local trainerFrames
  local cueWait = now()
  while cue.t and now() - cueWait < 3 do
    U.wait(1)
    cue.frame = cue.frame + 1
    if not ChipAudio.awaitingFirstBuffer() then
      trainerFrames = cue.frame
      cue.ms = (now() - cue.t) * 1000
      break
    end
  end
  Music.playBattle = realBattle
  local wantTheme = game.data.audio.battle.trainer
  U.log("trainer cue", tostring(Music.current()), "frames",
    tostring(trainerFrames), ("%.1f ms"):format(cue.ms or -1),
    "buffers queued on the cue", tostring(cue.depth))
  result(cue.t ~= nil and Music.current() == wantTheme,
    "the trainer battle cue plays " .. tostring(wantTheme))
  local wantDef = game.data.audio.songs[wantTheme]
  result(cue.park ~= nil and cue.park.ready and wantDef ~= nil
      and cue.park.key:find("|" .. tostring(wantDef) .. "|", 1, true) ~= nil,
    "the trainer battle theme is parked before the cue")
  result(ChipAudio.stats().parkHits == (trainerParkHits or 0) + 1,
    "the trainer battle cue takes the park")
  result(trainerFrames ~= nil and trainerFrames <= 2,
    ("trainer battle theme first note within 2 frames of the cue (%s)")
      :format(tostring(trainerFrames)))
  love.event.quit(failed and 1 or 0)
end
