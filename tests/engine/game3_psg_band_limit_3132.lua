package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local Mix = require("src.core.game3.m4a_mix")
local previousRate = Mix.SAMPLE_RATE

local RATE

local function render(voice, count, chunk)
  local left, right = {}, {}
  local state = { l = 0, r = 0 }
  local charge = math.exp(-2 * math.pi * 5 / RATE)
  local capL, capR = 0, 0
  local voices = { voice }
  local done = 0
  while done < count do
    local n = math.min(chunk or count, count - done)
    local outL, outR, alive = Mix.render(voices, n, {
      raw = true, hpfCapL = state.l, hpfCapR = state.r, hpfState = state,
    })
    voices = alive
    for index = 1, n do
      local l, r = outL[index] + capL, outR[index] + capR
      capL = l - outL[index] * charge
      capR = r - outR[index] * charge
      left[done + index], right[done + index] = l, r
    end
    done = done + n
  end
  return left, right
end

local function slice(samples, first)
  local out = {}
  for index = first, #samples do out[#out + 1] = samples[index] end
  return out
end

local function mean(samples)
  local sum = 0
  for index = 1, #samples do sum = sum + samples[index] end
  return sum / #samples
end

local function variance(samples)
  local average = mean(samples)
  local sum = 0
  for index = 1, #samples do
    local delta = samples[index] - average
    sum = sum + delta * delta
  end
  return sum / #samples
end

local function linePower(samples, frequency)
  local count = #samples
  local real, imaginary, weight = 0, 0, 0
  local step = 2 * math.pi * frequency / RATE
  for index = 1, count do
    local window = 0.5 - 0.5 * math.cos(2 * math.pi * (index - 0.5) / count)
    real = real + window * samples[index] * math.cos(step * index)
    imaginary = imaginary - window * samples[index] * math.sin(step * index)
    weight = weight + window
  end
  local amplitude = 2 * math.sqrt(real * real + imaginary * imaginary) / weight
  return amplitude * amplitude / 2
end

local function decibels(ratio)
  return 10 * math.log(math.max(ratio, 1e-30)) / math.log(10)
end

local function pulse(freq, duty)
  local voice = Mix.newCgbPulse({ freq = freq, duty = duty })
  voice.envVol = 15
  return voice
end

local function noise(key, short)
  local voice = Mix.newCgbNoise({ key = key, tone = { wavParam = short and 1 or 0 } })
  voice.envVol = 15
  return voice
end

local FULL = 15 / 32

local function suite(rate)
  RATE = Mix.setSampleRate(rate)
  local tag = (" at %d Hz"):format(RATE)

  do
    local harmonic = 2 * math.floor(RATE / 1040) + 1
    local fundamental = RATE / (harmonic - 0.37)
    local alias = harmonic * fundamental - RATE
    local samples = slice(render(pulse(fundamental, 2), RATE + 64), 65)
    check(alias > 100 and alias < fundamental - 100,
      ("harmonic %d of %.1f Hz folds to %.1f Hz"):format(harmonic, fundamental, alias) .. tag)
    local ratio = decibels(linePower(samples, alias) / linePower(samples, fundamental))
    check(ratio < -70,
      ("pulse harmonic %d does not fold back into the band (%.1f dB)")
        :format(harmonic, ratio) .. tag)
    local low, high = math.huge, -math.huge
    for index = 1, #samples do
      low = math.min(low, samples[index])
      high = math.max(high, samples[index])
    end
    check(low >= -1e-9 and high <= FULL + 1e-9, "pulse stays inside its envelope level" .. tag)
    check(math.abs(mean(samples) / FULL - 0.5) < 0.01, "pulse keeps its duty average" .. tag)
  end

  do
    local ramp = {}
    for index = 1, 32 do ramp[index] = math.floor((index - 1) / 2) end
    local harmonic = 4 * math.floor(RATE / 1040) + 2
    local fundamental = RATE / (harmonic - 0.37)
    local alias = harmonic * fundamental - RATE
    local voice = Mix.newCgbWave({ wave = ramp, freq = fundamental })
    voice.envVol = 15
    local samples = slice(render(voice, RATE + 64), 65)
    local ratio = decibels(linePower(samples, alias) / linePower(samples, fundamental))
    check(ratio < -80,
      ("wave harmonic %d does not fold back into the band (%.1f dB)")
        :format(harmonic, ratio) .. tag)
    check(math.abs(mean(samples) - 7.5 / 32) < 0.005, "wave keeps its table average" .. tag)
  end

  do
    local samples = slice(render(pulse(131072, 2), 8192 + 64), 65)
    for index = 1, #samples do samples[index] = samples[index] / FULL end
    check(variance(samples) < 0.01,
      ("a pulse above the Nyquist rate settles on its duty average (variance %.4f)")
        :format(variance(samples)) .. tag)
    check(math.abs(mean(samples) - 0.5) < 0.02, "and that average is the 50% duty" .. tag)
  end

  do
    local fast = slice(render(noise(80, false), 8192 + 256), 257)
    local slow = slice(render(noise(68, false), 8192 + 256), 257)
    local ratio = variance(fast) / variance(slow)
    check(ratio < 0.25,
      ("524288 Hz noise carries a fraction of 16384 Hz noise's in-band power (%.3f)")
        :format(ratio) .. tag)
    check(math.abs(mean(fast) / FULL - 0.5) < 0.05, "fast noise keeps its DC level" .. tag)
  end

  do
    local samples = slice(render(noise(80, true), 8192 + 256), 257)
    local tone = 524288 / 127
    local share = linePower(samples, tone) / variance(samples)
    check(share > 0.1,
      ("7-bit noise at 524288 Hz keeps its %.0f Hz pitch (%.3f of the power)")
        :format(tone, share) .. tag)
  end

  do
    local flat = {}
    for index = 1, 32 do flat[index] = 15 end
    local want = { [15] = 15, [12] = 11, [7] = 7, [3] = 3, [1] = 0 }
    for level, nibble in pairs(want) do
      local voice = Mix.newCgbWave({ wave = flat, freq = 440 })
      voice.envVol = level
      local samples = render(voice, 512)
      local steady = true
      for index = 2, #samples do
        if math.abs(samples[index] - nibble / 32) > 1e-9 then steady = false end
      end
      check(steady, ("a flat wave at envelope %d holds %d/32"):format(level, nibble) .. tag)
    end
  end

  do
    local voice = pulse(440, 1)
    voice.routeR = false
    local left, right = render(voice, 2048)
    local peak = 0
    for index = 1, #right do peak = math.max(peak, math.abs(right[index])) end
    check(peak < 1e-9 and variance(left) > 0.01, "a left-only voice stays out of the right side" .. tag)
  end

  do
    local whole = render(pulse(987.7, 3), 4096)
    local parts = render(pulse(987.7, 3), 4096, 97)
    local worst = 0
    for index = 1, #whole do
      worst = math.max(worst, math.abs(whole[index] - parts[index]))
    end
    check(worst < 1e-9, "chunked rendering matches one pass" .. tag)
  end

  do
    local voice = pulse(300, 2)
    local low, high = math.huge, -math.huge
    local voices = { voice }
    local state = { l = 0, r = 0 }
    local charge = math.exp(-2 * math.pi * 5 / RATE)
    local cap = 0
    for step = 1, 200 do
      voice.freq = 300 + step * 37
      voice.envVol = 4 + step % 12
      local outL = Mix.render(voices, 50, {
        raw = true, hpfCapL = state.l, hpfCapR = state.r, hpfState = state,
      })
      for index = 1, 50 do
        local value = outL[index] + cap
        cap = value - outL[index] * charge
        low = math.min(low, value)
        high = math.max(high, value)
      end
    end
    check(low >= -1e-9 and high <= FULL + 1e-9,
      ("pitch and envelope changes between chunks stay in range (%.4f..%.4f)")
        :format(low, high) .. tag)
  end

  do
    local voice = pulse(440, 2)
    voice.lengthRemaining = 1000
    local samples = render(voice, 2048)
    local tail = 0
    for index = 1003, #samples do tail = math.max(tail, math.abs(samples[index])) end
    check(voice.alive == false and tail < 1e-9 and variance(slice(samples, 1)) > 0,
      "a length-limited voice ends on time and leaves silence" .. tag)
  end
end

suite(44100)
suite(22050)
suite(48000)

Mix.setSampleRate(previousRate)

T.finish("game3 psg band limit")
