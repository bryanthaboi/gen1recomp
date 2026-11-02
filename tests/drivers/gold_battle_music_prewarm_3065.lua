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
  while now() - t < 8 do
    U.wait(1)
    local ps = ChipAudio.parkState()
    if now() - t >= 2.5 and ps and ps.ready then break end
  end
  local park = ChipAudio.parkState and ChipAudio.parkState()
  local parkHits = ChipAudio.stats().parkHits or 0

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
  local frames, startFrames = 0, nil
  local t0 = now()
  while now() - t0 < 8 do
    U.wait(1)
    frames = frames + 1
    local st = ChipAudio.stats()
    local pending = st.prewarmQueued + st.prewarmInFlight
    if not peak or pending > peak then peak = pending end
    if not startedT and marks.playT and not ChipAudio.awaitingFirstBuffer() then
      startedT = now()
      startFrames = frames
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
  result(park ~= nil and park.ready,
    "the wild battle theme is parked on the map before the encounter")
  result(st.parkHits == parkHits + 1, "the battle cue takes the park")
  result(startFrames ~= nil and startFrames <= 2,
    ("battle theme first note within 2 frames of the cue (%s)")
      :format(tostring(startFrames)))
  result(drainedT ~= nil, "the battle prewarm drains within 8 s")
  result(st.underruns == (marks.underrunsAtPlay or 0),
    "no music underrun after the cue")

  local function top()
    local s = game.stack and game.stack:top()
    return s and s.screenId
  end
  for _ = 1, 600 do
    if top() == "Gen2BattleState" then break end
    U.wait(1)
  end
  local battleScreen = game.stack:top()
  if top() == "Gen2BattleState" then
    battleScreen.battle.outcome = "run"
    battleScreen:finishBattle()
  end
  for _ = 1, 900 do
    if top() == nil and world:acceptsMenuInput() then break end
    U.wait(1)
  end
  result(top() == nil, "the wild battle closes back to the overworld")

  local VEC = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                right = { 1, 0 } }
  local BACK = { up = "down", down = "up", left = "right", right = "left" }
  world:warpToMapId("ROUTE_30", 5, 29, "right")
  U.wait(30)
  local trainerNpc, front
  for _, n in ipairs(world.npcs or {}) do
    local record = n.def and n.def.trainer
    local v = VEC[n.facing]
    if record and v and not world:trainerBeaten(record) then
      local fx, fy = n.cellX + v[1], n.cellY + v[2]
      local blocked = false
      for _, o in ipairs(world.npcs) do
        if o ~= n and o.cellX == fx and o.cellY == fy then blocked = true end
      end
      if not blocked then
        trainerNpc, front = n, { fx, fy, BACK[n.facing] }
        break
      end
    end
  end
  result(trainerNpc ~= nil, "a Route 30 trainer to battle")
  if not trainerNpc then love.event.quit(1) return end
  U.log("trainer", tostring(trainerNpc.def.trainer.class),
    tostring(trainerNpc.def.trainer.member), front[1], front[2])
  local trainerParkHits = ChipAudio.stats().parkHits or 0
  local cue = {}
  local realBattleMusic = world.playBattleMusic
  world.playBattleMusic = function(self, opts)
    if not cue.t and opts and opts.trainer then
      cue.park = ChipAudio.parkState()
      cue.t = now()
      cue.frame = 0
      cue.song = realBattleMusic(self, opts)
      cue.depth = ChipAudio.stats().depth
      return cue.song
    end
    return realBattleMusic(self, opts)
  end
  world:warpToMapId("ROUTE_30", front[1], front[2], front[3])
  U.wait(2)
  local waitT = now()
  local engaged = false
  while now() - waitT < 6 do
    U.wait(1)
    if not engaged and world:acceptsMenuInput() and top() == nil
        and not world:scriptRunning() then
      U.tap(game, "a")
    end
    engaged = engaged or world:scriptRunning()
    local ps = ChipAudio.parkState()
    if engaged and ps and ps.ready and now() - waitT > 1 then break end
  end
  for _ = 1, 60 do
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
  world.playBattleMusic = realBattleMusic
  U.log("trainer cue", tostring(cue.song), "frames", tostring(trainerFrames),
    ("%.1f ms"):format(cue.ms or -1), "buffers queued on the cue",
    tostring(cue.depth))
  result(cue.t ~= nil and cue.song ~= nil and Music.current() == cue.song,
    "the trainer battle cue plays " .. tostring(cue.song))
  local wantDef = cue.song and game.data.audio.songs[cue.song]
  result(cue.park ~= nil and cue.park.ready and wantDef ~= nil
      and cue.park.key:find("|" .. tostring(wantDef) .. "|", 1, true) ~= nil,
    "the trainer battle theme is parked before the cue")
  result((ChipAudio.stats().parkHits or 0) == trainerParkHits + 1,
    "the trainer battle cue takes the park")
  result(trainerFrames ~= nil and trainerFrames <= 2,
    ("trainer battle theme first note within 2 frames of the cue (%s)")
      :format(tostring(trainerFrames)))
  love.event.quit(failed and 1 or 0)
end
