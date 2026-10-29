local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local ChipAudio = require("src.core.ChipAudio")
  local Music = require("src.core.Music")
  local now = love.timer.getTime
  local failed = false
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    result(false, "gold world booted")
    love.event.quit(1)
    return
  end
  game.save.party = {
    Mon.new(game.data, "CYNDAQUIL", 14), Mon.new(game.data, "PIDGEY", 12),
    Mon.new(game.data, "SENTRET", 11), Mon.new(game.data, "HOOTHOOT", 13),
    Mon.new(game.data, "BELLSPROUT", 10), Mon.new(game.data, "GEODUDE", 12),
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

  local requests, inFront = {}, false
  local realSfx, realCry = ChipAudio.prewarmSfx, ChipAudio.prewarmCry
  local realFront = ChipAudio.prewarmFront
  ChipAudio.prewarmSfx = function(data, name, ...)
    requests[#requests + 1] = { name = tostring(name), front = inFront }
    return realSfx(data, name, ...)
  end
  ChipAudio.prewarmCry = function(data, species, ...)
    requests[#requests + 1] = { name = "cry:" .. tostring(species),
                                cry = true, front = inFront }
    return realCry(data, species, ...)
  end
  if realFront then
    ChipAudio.prewarmFront = function(fn, ...)
      local args = { ... }
      return realFront(function()
        inFront = true
        local ok, err = pcall(fn, unpack(args))
        inFront = false
        if not ok then error(err, 0) end
      end)
    end
  end

  local started = world:startBattle({ wild = Mon.new(game.data, "RATTATA", 4) })
  result(started and true or false, "wild battle started")
  local startedT, drainedT, peak
  local t0 = now()
  while now() - t0 < 8 do
    U.wait(1)
    local st = ChipAudio.stats()
    local pending = st.prewarmQueued + st.prewarmInFlight
    if not peak or pending > peak then peak = pending end
    if not startedT and marks.playT and not ChipAudio.awaitingFirstBuffer() then
      startedT = now()
      U.log(("music started %.1fms after playMusic, depth=%s q=%d inflight=%d")
        :format((startedT - marks.playT) * 1000, tostring(st.depth),
          st.prewarmQueued, st.prewarmInFlight))
    end
    if startedT and not drainedT and pending == 0 and peak > 0 then
      drainedT = now()
      U.log(("prewarm drained %.1fms after playMusic, ready=%d depth=%s")
        :format((drainedT - marks.playT) * 1000, st.prewarmReady,
          tostring(st.depth)))
    end
  end
  ChipAudio.playMusic = realPlay
  ChipAudio.prewarmSfx, ChipAudio.prewarmCry = realSfx, realCry
  ChipAudio.prewarmFront = realFront
  local st = ChipAudio.stats()
  U.log("song", tostring(Music.current()), "peak prewarm", tostring(peak))
  U.log("stats", st.line)
  local frontCries, lastNames = 0, {}
  for _, r in ipairs(requests) do
    if r.cry and r.front then frontCries = frontCries + 1 end
  end
  for i = math.max(1, #requests - 1), #requests do
    lastNames[#lastNames + 1] = requests[i].name
  end
  table.sort(lastNames)
  local tail = table.concat(lastNames, ",")
  U.log("prewarm requests", tostring(#requests), "front cries",
    tostring(frontCries), "last", tail)

  result(frontCries == 2,
    ("both lead cries are front prewarms (%d)"):format(frontCries))
  result(tail == "Sfx_CaughtMon,Sfx_DexFanfare5079",
    "Sfx_DexFanfare5079 and Sfx_CaughtMon are the last battle prewarms ("
      .. tail .. ")")

  result(startedT ~= nil and tostring(Music.current()):find("Wild") ~= nil,
    "wild battle theme started")
  result(startedT ~= nil and marks.playT ~= nil
      and startedT - marks.playT < 0.5,
    "battle theme starts within 0.5 s of its cue on desktop")
  result(drainedT ~= nil, "the battle prewarm drains within 8 s")
  result(st.underruns == (marks.underrunsAtPlay or 0),
    "no music underrun after the cue")
  love.event.quit(failed and 1 or 0)
end
