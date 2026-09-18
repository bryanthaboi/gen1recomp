local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local function le32(x)
  return string.char(x % 256, math.floor(x / 256) % 256, math.floor(x / 65536) % 256, math.floor(x / 16777216) % 256)
end
local function le16(x)
  return string.char(x % 256, math.floor(x / 256) % 256)
end

local function write_wav(path, L, R, rate)
  local n = math.max(1, #L)
  local sd = love.sound.newSoundData(n, rate, 16, 2)
  for i = 1, #L do
    local l, r = L[i] or 0, R[i] or 0
    if l > 1 then l = 1 elseif l < -1 then l = -1 end
    if r > 1 then r = 1 elseif r < -1 then r = -1 end
    sd:setSample(i - 1, 1, l)
    sd:setSample(i - 1, 2, r)
  end
  local s = sd:getString()
  local f = io.open(path, "wb")
  if not f then return false end
  f:write("RIFF", le32(36 + #s), "WAVE", "fmt ", le32(16), le16(1), le16(2), le32(rate), le32(rate * 4), le16(4), le16(16), "data", le32(#s))
  f:write(s)
  f:close()
  return true
end

local function write_wave_png(path, L, R, marks)
  local W, H = 1200, 300
  local img = love.image.newImageData(W, H)
  for x = 0, W - 1 do
    for y = 0, H - 1 do img:setPixel(x, y, 0.08, 0.08, 0.1, 1) end
  end
  local n = #L
  local per = math.max(1, math.floor(n / W))
  for x = 0, W - 1 do
    local lo, hi = 0, 0
    for i = x * per + 1, math.min(n, (x + 1) * per) do
      local v = ((L[i] or 0) + (R[i] or 0)) * 0.5
      if v < lo then lo = v end
      if v > hi then hi = v end
    end
    local y0 = math.floor(H / 2 - hi * (H / 2 - 2))
    local y1 = math.floor(H / 2 - lo * (H / 2 - 2))
    for y = math.max(0, y0), math.min(H - 1, y1) do img:setPixel(x, y, 0.55, 0.85, 1, 1) end
  end
  for _, m in ipairs(marks or {}) do
    local x = math.floor(m.at / per)
    if x >= 0 and x < W then
      for y = 0, H - 1, 3 do img:setPixel(x, y, m.r, m.g, m.b, 1) end
    end
  end
  local fd = img:encode("png")
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(fd:getString())
  f:close()
  return true
end

local function db(x)
  if x <= 1e-9 then return -180 end
  return 20 * math.log10(x)
end

return function(game)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
  end

  local msgByData = setmetatable({}, { __mode = "k" })
  local captured = {}
  local realNQS = love.audio.newQueueableSource
  love.audio.newQueueableSource = function(...)
    local real = realNQS(...)
    return setmetatable({}, {
      __index = function(_, k)
        local f = real[k]
        if type(f) ~= "function" then return f end
        if k == "queue" then
          return function(_, sd)
            local ok = real:queue(sd)
            local m = msgByData[sd]
            if ok ~= false and m then
              captured[#captured + 1] = { at = m.at, epoch = m.epoch, sd = sd }
            end
            return ok
          end
        end
        return function(_, ...) return f(real, ...) end
      end,
    })
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local t0 = love.timer.getTime()
  game:_handleBootAction({ action = "new_game", name = "RED" })

  local Audio = require("src.core.game3.audio")
  local Player = require("src.core.game3.m4a_player")
  local Mix = require("src.core.game3.m4a_mix")

  local realOut = Audio._outCh
  local proxy = {
    pop = function()
      local m = realOut:pop()
      if type(m) == "table" and m.data then msgByData[m.data] = m end
      return m
    end,
    clear = function() return realOut:clear() end,
    getCount = function() return realOut:getCount() end,
    push = function(_, v) return realOut:push(v) end,
  }
  if realOut then Audio._outCh = proxy end

  local LIST = { 258, 260 }
  local ready = false
  for f = 1, 1800 do
    U.wait(1)
    if Audio._fanfareSd[258] and Audio._fanfareSd[260] and Audio._fanfareSd[257] and Audio._bgmGen then
      ready = true
      print(string.format("[u11] prebaked 257/258/260 after %d frames (%.2fs since new game), bgm=%s", f, love.timer.getTime() - t0, tostring(Audio._bgmGen)))
      break
    end
  end
  check(ready, "u11 worker prebaked fanfares off the main thread")
  if not ready then love.event.quit(1) return end
  U.wait(240)

  local renders = 0
  local wrapped = {}
  local function hook()
    for _, k in ipairs({ "bakeSlot", "bakeSong", "renderBuffered", "start" }) do
      local real = Player[k]
      wrapped[k] = real
      Player[k] = function(...) renders = renders + 1; return real(...) end
    end
  end
  local function unhook()
    for k, real in pairs(wrapped) do Player[k] = real end
    wrapped = {}
  end

  local rate = Mix.SAMPLE_RATE
  local function stream(epoch)
    local list = {}
    for _, c in ipairs(captured) do
      if c.epoch == epoch and c.at then
        list[#list + 1] = { at = c.at, n = c.sd:getSampleCount(), sd = c.sd }
      end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    local last = 1
    return function(pos)
      local e = list[last]
      if not (e and pos >= e.at and pos < e.at + e.n) then
        e = nil
        for i, c in ipairs(list) do
          if pos >= c.at and pos < c.at + c.n then
            e = c
            last = i
            break
          end
        end
      end
      if not e then return nil end
      local o = pos - e.at
      return e.sd:getSample(o, 1), e.sd:getSample(o, 2)
    end
  end

  local results = {}
  for _, id in ipairs(LIST) do
    U.wait(120)
    local e0 = Audio._bgmEpoch
    hook()
    local c0 = love.timer.getTime()
    Audio.playFanfare(id)
    local callMs = (love.timer.getTime() - c0) * 1000
    local src = Audio._fanfareSource
    local playingNow = src ~= nil and src:isPlaying()
    local P = Audio._bgmBaseAt
    local e1 = Audio._bgmEpoch
    local frames = Audio._fanfareFrames
    local ticks = 0
    while Audio._fanfareActive and ticks < 900 do
      U.wait(1)
      ticks = ticks + 1
    end
    local resumeFrames = 0
    while not (Audio._bgmSource and Audio._bgmSource:isPlaying()) and resumeFrames < 120 do
      U.wait(1)
      resumeFrames = resumeFrames + 1
    end
    unhook()
    U.wait(300)
    results[#results + 1] = {
      id = id, e0 = e0, e1 = e1, P = P, frames = frames, ticks = ticks,
      callMs = callMs, playingNow = playingNow, renders = renders, resumeFrames = resumeFrames,
    }
    renders = 0
  end

  local BUF = Player.BUFFER_SAMPLES or 8192
  local ref = { voices = {} }
  local refSnaps, refAbs = {}, 0
  local capL0, capR0 = Mix._hpfCapL, Mix._hpfCapR
  Mix._hpfCapL, Mix._hpfCapR = 0, 0
  local refOk = Player.start(Audio._pack, Audio._cache, ref, Audio._bgmGen, { forceSeq = true })
  local function refRender()
    refSnaps[#refSnaps + 1] = Player.snapshotSlot(ref, refAbs)
    if #refSnaps > 64 then table.remove(refSnaps, 1) end
    local L, R = Player.renderBuffered(ref, BUF, { master = 1, sampleRate = rate, raw = true })
    refAbs = refAbs + BUF
    return L, R
  end

  for _, r in ipairs(results) do
    local tag = "u11 fanfare " .. r.id
    print(string.format("[u11] %d: playFanfare call %.2f ms, fanfare playing in same call=%s, main-thread renders=%d, stopAt=%s, countdown %d frames (sFanfares %s), BGM playing %d frames after continue",
      r.id, r.callMs, tostring(r.playingNow), r.renders, tostring(r.P), r.ticks, tostring(r.frames), r.resumeFrames))
    check(r.playingNow and r.callMs < 16.7, tag .. " starts in the same frame BGM stops (gap 0 frames)")
    check(r.renders == 0, tag .. " no synthesis on the main thread")
    check(r.resumeFrames <= 1, tag .. " BGM audible again within 1 frame of continue")

    local pre, post = stream(r.e0), stream(r.e1)
    local P = r.P or 0
    local firstAfter
    for _, c in ipairs(captured) do
      if c.epoch == r.e1 and c.at and (not firstAfter or c.at < firstAfter) then firstAfter = c.at end
    end
    print(string.format("[u11] %d: stop sample %d, first resumed buffer starts at %s", r.id, P, tostring(firstAfter)))
    check(firstAfter == P, tag .. " BGM continues from the stop sample")

    local sumB, nB, peakB = 0, 0, 0
    for k = math.max(0, P - rate * 2), P - 1 do
      local l, rr = pre(k)
      if l then
        sumB = sumB + l * l + rr * rr
        nB = nB + 2
        peakB = math.max(peakB, math.abs(l), math.abs(rr))
      end
    end
    local sd = Audio._fanfareSd[r.id]
    local sumF, nF, peakF, clipped = 0, 0, 0, 0
    local fN = math.min(sd:getSampleCount(), math.floor(r.frames / 60 * rate))
    for i = 0, sd:getSampleCount() - 1 do
      local l, rr = sd:getSample(i, 1), sd:getSample(i, 2)
      if i < fN then
        sumF = sumF + l * l + rr * rr
        nF = nF + 2
      end
      peakF = math.max(peakF, math.abs(l), math.abs(rr))
      if math.abs(l) >= 0.9999 or math.abs(rr) >= 0.9999 then clipped = clipped + 1 end
    end
    local rmsB = nB > 0 and math.sqrt(sumB / nB) or 0
    local rmsF = nF > 0 and math.sqrt(sumF / nF) or 0
    print(string.format("[u11] %d: BGM rms %.1f dB peak %.3f | fanfare rms %.1f dB peak %.3f | diff %+.1f dB | clipped %d | channels %d",
      r.id, db(rmsB), peakB, db(rmsF), peakF, db(rmsF) - db(rmsB), clipped, sd:getChannelCount()))
    check(sd:getChannelCount() == 2, tag .. " fanfare is stereo like BGM")
    check(clipped == 0, tag .. " fanfare has no clipped samples")
    check(nB > 0 and db(rmsF) - db(rmsB) < 6, tag .. " fanfare level within BGM mix range (< +6 dB)")

    local oldPeak, newPeak = 0, 0
    for k = P, P + 255 do
      local l, rr = pre(k)
      if l then oldPeak = math.max(oldPeak, math.abs(l), math.abs(rr)) end
      local l2, r2 = post(k)
      if l2 then newPeak = math.max(newPeak, math.abs(l2), math.abs(r2)) end
    end
    local refDiff = 1
    if refOk then
      while refAbs <= P do refRender() end
      refAbs = Player.stopAt(ref, refSnaps, P, refAbs) or refAbs
      Mix._hpfCapL, Mix._hpfCapR = 0, 0
      local L, R = Player.renderBuffered(ref, BUF, { master = 1, sampleRate = rate, raw = true })
      refDiff = 0
      for k = 0, 255 do
        local l2, r2 = post(P + k)
        if not l2 then refDiff = 1 break end
        refDiff = math.max(refDiff, math.abs(l2 - (L[k + 1] or 0)), math.abs(r2 - (R[k + 1] or 0)))
      end
    end
    print(string.format("[u11] %d: first 256 samples at the stop point: pre-stop stream peak %.4f, continued stream peak %.4f, diff vs fresh continue from the stop sample %.6f", r.id, oldPeak, newPeak, refDiff))
    check(refDiff <= 1 / 32767, tag .. " continued BGM has no held voices at the resume edge")

    local HL, HR = {}, {}
    local preN = rate * 2
    for k = P - preN, P - 1 do
      local l, rr = pre(k)
      HL[#HL + 1] = l or 0
      HR[#HR + 1] = rr or 0
    end
    local base = #HL
    local gap = math.floor(r.ticks / 60 * rate)
    local total = base + math.max(gap + rate * 3, sd:getSampleCount())
    for i = base + 1, total do HL[i] = 0; HR[i] = 0 end
    for i = 0, sd:getSampleCount() - 1 do
      HL[base + i + 1] = HL[base + i + 1] + sd:getSample(i, 1)
      HR[base + i + 1] = HR[base + i + 1] + sd:getSample(i, 2)
    end
    for k = 0, rate * 3 - 1 do
      local l, rr = post(P + k)
      local j = base + gap + k + 1
      HL[j] = HL[j] + (l or 0)
      HR[j] = HR[j] + (rr or 0)
    end
    local wavPath = DIR .. "/u11_heard_" .. r.id .. ".wav"
    local pngPath = DIR .. "/u11_heard_" .. r.id .. "_wave.png"
    local okW = write_wav(wavPath, HL, HR, rate)
    local okP = write_wave_png(pngPath, HL, HR, {
      { at = base, r = 1, g = 0.3, b = 0.3 },
      { at = base + gap, r = 0.3, g = 1, b = 0.3 },
    })
    print(string.format("[u11] %d: wrote %s (%s) and %s (%s)", r.id, wavPath, tostring(okW), pngPath, tostring(okP)))
  end

  Mix._hpfCapL, Mix._hpfCapR = capL0, capR0
  local e = Audio._pack.index.fanfares[258]
  local refSd = Player.bakeSong(Audio._pack, Audio._cache, 258, { maxSec = e.frames / 60 + 4 })
  local sd = Audio._fanfareSd[258]
  local maxd = 0
  if refSd and sd and refSd:getSampleCount() == sd:getSampleCount() then
    for i = 0, sd:getSampleCount() - 1 do
      maxd = math.max(maxd, math.abs(refSd:getSample(i, 1) - sd:getSample(i, 1)), math.abs(refSd:getSample(i, 2) - sd:getSample(i, 2)))
    end
  else
    maxd = 1
  end
  print(string.format("[u11] worker bake vs BGM-path reference render of 258: max sample diff %.6f", maxd))
  check(maxd == 0, "u11 worker fanfare bake matches the BGM mix path sample for sample")

  Audio._fanfareSd[257] = nil
  Audio._fanfareSrc[257] = nil
  hook()
  Audio.playFanfare(257)
  local waited = 0
  while not (Audio._fanfareSource and Audio._fanfareSource:isPlaying()) and waited < 120 do
    U.wait(1)
    waited = waited + 1
  end
  local r257 = renders
  unhook()
  print(string.format("[u11] 257 on-demand worker bake started after %d frames, main-thread renders=%d", waited, r257))
  check(waited < 60 and r257 == 0, "u11 uncached fanfare is baked by the worker, not the main thread")
  for _ = 1, 200 do
    if not Audio._fanfareActive then break end
    U.wait(1)
  end
  U.wait(30)

  print(string.format("[u11] done fails=%d", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
