package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")

local data = { audio = {} }
local RATE = 44100
local previousRate = ChipSynth.SAMPLE_RATE
ChipSynth.setSampleRate(RATE)
ChipSynth.setChannelVolumes({ 1, 1, 1, 1 })
ChipSynth.setChannelPitches({ 1, 1, 1, 1 })

local function render(def, first, count)
  local engine = ChipSynth.newEngine(data, def, { allowLoops = false })
  local channel = engine.channels[1]
  for _ = 1, first do channel:sample() end
  local samples = {}
  for index = 1, count do samples[index] = channel:sample() end
  return samples, channel
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

local function squareSfx(register)
  return ChipAsm.sfx{
    channels = { { hw = 1, program = {
      { duty = 2 },
      { squareNote = { len = 16, volume = 15, fade = 0, frequency = register } },
      { squareNote = { len = 16, volume = 15, fade = 0, frequency = register } },
      { squareNote = { len = 16, volume = 15, fade = 0, frequency = register } },
      { squareNote = { len = 16, volume = 15, fade = 0, frequency = register } },
    } } },
  }
end

local function noiseSfx(parameter)
  return ChipAsm.sfx{
    channels = { { hw = 4, program = {
      { noiseNote = { len = 16, volume = 15, fade = 0, parameter = parameter } },
    } } },
  }
end

do
  local song = ChipAsm.song{
    channels = { { hw = 1, program = {
      { duty = 2 },
      { notetype = { speed = 12, volume = 15, fade = 0 } },
      { octave = 4 },
      { note = "C", len = 16 },
    } } },
  }
  local samples, channel = render(song, 64, RATE)
  local fundamental = 131072 / (2048 - channel.event.register)
  local harmonic = 85
  local alias = harmonic * fundamental - RATE
  check(alias > 100 and alias < fundamental - 100,
    ("harmonic %d of %.1f Hz folds to %.1f Hz"):format(harmonic, fundamental, alias))
  local ratio = decibels(linePower(samples, alias) / linePower(samples, fundamental))
  check(ratio < -70,
    ("pulse harmonic %d does not fold back into the band (%.1f dB)")
      :format(harmonic, ratio))
  local low, high = math.huge, -math.huge
  for index = 1, #samples do
    low = math.min(low, samples[index])
    high = math.max(high, samples[index])
  end
  check(low >= -1e-9 and high <= 1 + 1e-9, "pulse stays inside the DAC range")
  check(math.abs(mean(samples) - 0.5) < 0.01, "pulse keeps its duty average")
end

do
  local ramp = {}
  for index = 1, 32 do ramp[index] = math.floor((index - 1) / 2) end
  local song = ChipAsm.song{
    channels = { { hw = 3, program = {
      { notetype = { speed = 12, waveLevel = 1, waveInstrument = 0 } },
      { octave = 4 },
      { note = "C", len = 16 },
    } } },
    waves = { ramp },
  }
  local samples, channel = render(song, 64, RATE)
  local fundamental = 65536 / (2048 - channel.event.register)
  local harmonic = 170
  local alias = harmonic * fundamental - RATE
  local ratio = decibels(linePower(samples, alias) / linePower(samples, fundamental))
  check(ratio < -80,
    ("wave harmonic %d does not fold back into the band (%.1f dB)")
      :format(harmonic, ratio))
  check(math.abs(mean(samples) - 0.5) < 0.01, "wave keeps its table average")
end

do
  local samples = render(squareSfx(2047), 64, 8192)
  check(variance(samples) < 0.01,
    ("a pulse above the Nyquist rate settles on its duty average (variance %.4f)")
      :format(variance(samples)))
  check(math.abs(mean(samples) - 0.5) < 0.02, "and that average is the 50% duty")
end

do
  local fast = render(noiseSfx(0x00), 256, 8192)
  local slow = render(noiseSfx(0x50), 256, 8192)
  local ratio = variance(fast) / variance(slow)
  check(ratio < 0.25,
    ("524288 Hz noise carries a fraction of 16384 Hz noise's in-band power (%.3f)")
      :format(ratio))
  check(math.abs(mean(fast) - 0.5) < 0.05, "fast noise keeps its DC level")
end

do
  local samples = render(noiseSfx(0x08), 256, 8192)
  local tone = 524288 / 127
  local share = linePower(samples, tone) / variance(samples)
  check(share > 0.1,
    ("7-bit noise at 524288 Hz keeps its %.0f Hz pitch (%.3f of the power)")
      :format(tone, share))
end

do
  local samples = render(noiseSfx(0xE0), 0, 4096)
  local peak = 0
  for index = 1, #samples do peak = math.max(peak, math.abs(samples[index])) end
  check(peak == 0, "clock shift 14 leaves the LFSR unclocked and silent")
end

ChipSynth.setSampleRate(previousRate)

T.finish("chip band limit")
