-- Decode FireRed DirectSound samples (little-endian headers, s8 PCM).

local Sample = {}

local ffiOk, ffi = pcall(require, "ffi")

local function s8_at(pcm, idx)
  local i = math.floor(idx)
  if i < 0 or i >= #pcm then return 0 end
  local b
  if ffiOk and ffi then
    b = ffi.cast("const int8_t *", pcm)[i]
    return b / 128
  end
  b = pcm:byte(i + 1)
  local s = b >= 128 and (b - 256) or b
  return s / 128
end

--- Convert raw s8 PCM bytes to a love SoundData (mono 16-bit).
-- Resamples to outRate when native rate differs (OpenAL is unreliable with odd rates).
function Sample.s8ToSoundData(pcm, sampleRate, opts)
  opts = opts or {}
  if type(pcm) ~= "string" or #pcm == 0 then return nil end
  sampleRate = sampleRate or 13379
  if opts.cry then
    return (Sample.renderCry(pcm, sampleRate, opts.cry, opts))
  end
  local outRate = opts.outRate or sampleRate
  if not (love and love.sound and love.sound.newSoundData) then return nil end

  local nIn = #pcm
  local nOut = nIn
  local step = 1
  if outRate ~= sampleRate and sampleRate > 0 then
    nOut = math.max(1, math.floor(nIn * outRate / sampleRate + 0.5))
    step = sampleRate / outRate
  end

  local pan = opts.pan
  local env = opts.envelope
  local channels = pan and 2 or 1
  local sd = love.sound.newSoundData(nOut, outRate, 16, channels)
  local gainL, gainR = 1, 1
  if pan then
    gainL = (127 - pan) / 191
    gainR = (128 + pan) / 191
  end
  local frameRate = 16777216 / 280896
  local pos = 0
  for i = 0, nOut - 1 do
    local v = s8_at(pcm, pos)
    if env then
      local frame = math.floor(i * frameRate / outRate)
      if frame >= env.length then
        v = v * (env.release / 256) ^ (frame - env.length + 1)
      end
    end
    if channels == 2 then
      sd:setSample(i, 1, v * gainL)
      sd:setSample(i, 2, v * gainR)
    else
      sd:setSample(i, v)
    end
    pos = pos + step
  end
  return sd
end

Sample.GBA_FRAME_RATE = 16777216 / 280896
Sample.CRY_VOLUME = 120

-- pokefirered/src/sound.c:374
Sample.CRY_MODES = {
  [0] = { length = 140, release = 0, pitch = 15360, chorus = 0, reverse = false },
  [1] = { length = 20, release = 225, pitch = 15360, chorus = 0, reverse = false },
  [2] = { length = 140, release = 225, pitch = 15600, chorus = 20, reverse = false, volume = 90 },
  [3] = { length = 50, release = 200, pitch = 15800, chorus = 20, reverse = false, volume = 90 },
  [4] = { length = 25, release = 100, pitch = 15600, chorus = 192, reverse = true, volume = 90 },
  [5] = { length = 140, release = 200, pitch = 14440, chorus = 0, reverse = false },
  [6] = { length = 140, release = 220, pitch = 15555, chorus = 192, reverse = false, volume = 90 },
  [7] = { length = 10, release = 100, pitch = 14848, chorus = 0, reverse = false },
  [8] = { length = 60, release = 225, pitch = 15616, chorus = 0, reverse = false },
  [9] = { length = 15, release = 125, pitch = 15200, chorus = 0, reverse = true },
  [10] = { length = 100, release = 225, pitch = 15200, chorus = 0, reverse = false },
  [11] = { length = 140, release = 0, pitch = 15000, chorus = 0, reverse = false },
  [12] = { length = 20, release = 225, pitch = 15000, chorus = 0, reverse = false },
}

function Sample.cryParams(mode, volume)
  mode = tonumber(mode) or 0
  if not Sample.CRY_MODES[mode] then mode = 0 end
  local m = Sample.CRY_MODES[mode]
  return {
    mode = mode,
    length = m.length,
    release = m.release,
    pitch = m.pitch,
    chorus = m.chorus,
    reverse = m.reverse,
    volume = m.volume or tonumber(volume) or Sample.CRY_VOLUME,
  }
end

-- pokefirered/src/m4a.c:1711
function Sample.cryKeyTune(pitch)
  local b = (tonumber(pitch) or 15360) + 0x80
  b = b % 65536
  if b >= 32768 then b = b - 65536 end
  local key = math.floor(b / 256) % 128
  local tune = math.floor(b / 2) % 128
  return key, tune
end

-- pokefirered/src/m4a.c:1745
function Sample.cryChorusTune(chorus, tune)
  chorus = (tonumber(chorus) or 0) % 256
  if chorus >= 128 then chorus = chorus - 256 end
  return (chorus + tune) % 128
end

function Sample.cryRateMul(key, tune)
  return 2 ^ (((key - 60) * 64 + (tune - 64)) / (64 * 12))
end

function Sample.cryVoices(params)
  local key, tune = Sample.cryKeyTune(params.pitch)
  local voices = { { key = key, tune = tune, mul = Sample.cryRateMul(key, tune) } }
  if (tonumber(params.chorus) or 0) % 256 ~= 0 then
    local tune2 = Sample.cryChorusTune(params.chorus, tune)
    voices[2] = { key = key, tune = tune2, mul = Sample.cryRateMul(key, tune2) }
  end
  return voices
end

-- pokefirered/src/m4a_tables.c:259
function Sample.cryEnvelope(length, release)
  length = math.max(0, math.floor(tonumber(length) or 0))
  release = math.max(0, math.floor(tonumber(release) or 0))
  local tail = {}
  local env = 255
  while true do
    env = math.floor(env * release / 256)
    if env <= 0 then break end
    tail[#tail + 1] = env / 255
  end
  return {
    length = length,
    tail = tail,
    endFrame = length + #tail,
    gain = function(frame)
      if frame < length then return 1 end
      return tail[frame - length + 1] or 0
    end,
  }
end

function Sample.renderCryMix(pcm, sampleRate, params, opts)
  opts = opts or {}
  if type(pcm) ~= "string" or #pcm == 0 then return nil end
  sampleRate = sampleRate or 13379
  local outRate = opts.outRate or sampleRate
  local nIn = #pcm
  local env = Sample.cryEnvelope(params.length, params.release)
  local voices = Sample.cryVoices(params)
  local frameRate = Sample.GBA_FRAME_RATE
  local envSamples = math.ceil(env.endFrame * outRate / frameRate)
  local nOut = 0
  for _, v in ipairs(voices) do
    v.step = sampleRate * v.mul / outRate
    v.samples = math.ceil(nIn / v.step)
    v.outN = math.min(v.samples, envSamples)
    if v.outN > nOut then nOut = v.outN end
  end
  local gain = (tonumber(params.volume) or Sample.CRY_VOLUME) / 127
  local reverse = params.reverse and true or false
  local out = {}
  for i = 0, nOut - 1 do
    local g = env.gain(math.floor(i * frameRate / outRate)) * gain
    local acc = 0
    if g > 0 then
      for _, v in ipairs(voices) do
        if i < v.outN then
          local idx = math.floor(i * v.step)
          if reverse then idx = nIn - 1 - idx end
          acc = acc + s8_at(pcm, idx)
        end
      end
      acc = acc * g
      if acc > 1 then acc = 1 elseif acc < -1 then acc = -1 end
    end
    out[i + 1] = acc
  end
  local v1 = voices[1]
  local sampleFrames = v1.samples * frameRate / outRate
  local frames = math.min(env.endFrame, math.ceil(sampleFrames))
  return out, {
    frames = frames,
    endFrame = env.endFrame,
    voices = #voices,
    outRate = outRate,
    seconds = nOut / outRate,
  }
end

function Sample.renderCry(pcm, sampleRate, params, opts)
  opts = opts or {}
  local out, info = Sample.renderCryMix(pcm, sampleRate, params, opts)
  if not out then return nil end
  if not (love and love.sound and love.sound.newSoundData) then return nil, info end
  local n = math.max(1, #out)
  local pan = opts.pan
  local channels = pan and 2 or 1
  local sd = love.sound.newSoundData(n, info.outRate, 16, channels)
  local gainL, gainR = 1, 1
  if pan then
    gainL = (127 - pan) / 191
    gainR = (128 + pan) / 191
  end
  for i = 0, #out - 1 do
    local v = out[i + 1]
    if channels == 2 then
      sd:setSample(i, 1, v * gainL)
      sd:setSample(i, 2, v * gainR)
    else
      sd:setSample(i, v)
    end
  end
  return sd, info
end

--- Mid-C key freq helper: WaveData.freq is typically rate * 1024.
function Sample.waveRate(freqField)
  freqField = tonumber(freqField) or 0
  if freqField <= 0 then return 13379 end
  local rate = math.floor(freqField / 1024 + 0.5)
  if rate < 500 then rate = 13379 end
  if rate > 48000 then rate = 48000 end
  return rate
end

--- Read one sample blob from samples.bin given index meta {offset,size,freq}.
function Sample.loadPcm(samplesBin, meta)
  if type(samplesBin) ~= "string" or type(meta) ~= "table" then return nil end
  local off = meta.offset or 0
  local size = meta.size or 0
  if size <= 0 or off < 0 or off + size > #samplesBin then return nil end
  return samplesBin:sub(off + 1, off + size)
end

function Sample.makeSource(samplesBin, meta, opts)
  opts = opts or {}
  local pcm = Sample.loadPcm(samplesBin, meta)
  if not pcm then return nil end
  local rate = opts.rate or Sample.waveRate(meta.freq)
  local outRate = opts.outRate
  if not outRate then
    local MixOk, Mix = pcall(require, "src.core.game3.m4a_mix")
    outRate = (MixOk and Mix and Mix.SAMPLE_RATE) or 44100
  end
  local sd = Sample.s8ToSoundData(pcm, rate, { outRate = outRate, pan = opts.pan, envelope = opts.envelope })
  if not sd then return nil end
  if not (love and love.audio and love.audio.newSource) then return nil end
  local src = love.audio.newSource(sd, "static")
  if opts.loop and meta.loopStart and meta.loopStart > 0 and meta.loopStart < (meta.size or 0) then
    src:setLooping(true)
  end
  if opts.volume then src:setVolume(opts.volume) end
  return src, sd
end

-- GameFreak DPCM decode (WaveData.type == 1). Prefer extract-time linear PCM.
local DPCM_DELTA = {
  [0] = 0, 1, 4, 9, 16, 25, 36, 49, -64, -49, -36, -25, -16, -9, -4, -1,
}

function Sample.decodeGfdpcm(src, sampleCount)
  if type(src) ~= "string" or not sampleCount or sampleCount <= 0 then return "" end
  local function s8(b) return b >= 128 and (b - 256) or b end
  local function clamp(v)
    if v > 127 then return 127 end
    if v < -128 then return -128 end
    return v
  end
  local blocks = math.ceil(sampleCount / 64)
  local out, n = {}, 0
  local function push(v)
    v = clamp(v)
    n = n + 1
    out[n] = string.char((v + 256) % 256)
  end
  for bi = 0, blocks - 1 do
    local bp = bi * 0x21
    if bp + 1 > #src then break end
    local acc = s8(src:byte(bp + 1))
    push(acc)
    if n >= sampleCount then break end
    if bp + 2 > #src then break end
    acc = acc + DPCM_DELTA[src:byte(bp + 2) % 16]
    push(acc)
    if n >= sampleCount then break end
    for h = 2, 32 do
      if bp + 1 + h > #src then break end
      local byte = src:byte(bp + 1 + h)
      acc = acc + DPCM_DELTA[math.floor(byte / 16) % 16]
      push(acc)
      if n >= sampleCount then break end
      acc = acc + DPCM_DELTA[byte % 16]
      push(acc)
      if n >= sampleCount then break end
    end
    if n >= sampleCount then break end
  end
  return table.concat(out)
end

return Sample
