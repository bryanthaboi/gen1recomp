package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")

local data = { audio = {} }

local function pulseSong()
  return ChipAsm.song{
    channels = { { hw = 1, program = {
      { duty = 2 },
      { notetype = { speed = 12, volume = 15, fade = 0 } },
      { octave = 4 },
      { note = "C", len = 15 },
    } } },
  }
end

local function noiseSong()
  return ChipAsm.sfx{
    channels = { { hw = 4, program = {
      { noiseNote = { len = 8, volume = 15, fade = 1, parameter = 0x34 } },
    } } },
  }
end

do
  local engine = ChipSynth.newEngine(data, pulseSong(), { allowLoops = false })
  local sawNeg, sawPos = false, false
  for _ = 1, 512 do
    local v = engine.channels[1]:sample()
    if v < -1e-12 then sawNeg = true end
    if v > 1e-12 then sawPos = true end
  end
  check(sawPos and not sawNeg,
    "pulse DAC is unipolar (high = volume, low = 0)")
end

do
  local engine = ChipSynth.newEngine(data, noiseSong(), {
    sfx = true, allowLoops = false,
  })
  local sawNeg, sawPos = false, false
  for _ = 1, 2048 do
    local v = engine.channels[1]:sample()
    if v < -1e-12 then sawNeg = true end
    if v > 1e-12 then sawPos = true end
  end
  check(sawPos and not sawNeg,
    "noise DAC is unipolar (LFSR high = volume, low = 0)")
end

local function crossingsAndSign(engine, frames)
  local count, prev = 0, nil
  local sawNeg, sawPos = false, false
  for _ = 1, frames do
    local sample = engine:sample()
    if sample < -1e-12 then sawNeg = true end
    if sample > 1e-12 then sawPos = true end
    if prev and prev * sample < 0 then count = count + 1 end
    prev = sample
  end
  return count, sawNeg, sawPos
end

do
  local engine = ChipSynth.newEngine(data, pulseSong(), { allowLoops = false })
  local count, sawNeg, sawPos = crossingsAndSign(engine, 4000)
  check(sawNeg and sawPos, "HPF centers a unipolar pulse around analog 0")
  check(count > 20, ("HPF'd pulse crosses zero (%d crossings)"):format(count))
end

do
  local engine = ChipSynth.newEngine(data, noiseSong(), {
    sfx = true, allowLoops = false,
  })
  local count, sawNeg, sawPos = crossingsAndSign(engine, 8000)
  check(sawNeg and sawPos, "HPF centers noise / drums around analog 0")
  check(count > 50, ("HPF'd noise crosses zero (%d crossings)"):format(count))
end

do
  local song = pulseSong()
  ChipSynth.setChannelVolumes({ 1, 1, 1, 1 })
  local a = ChipSynth.newEngine(data, song, { allowLoops = false })
  local base = a.channels[1]:sample()
  ChipSynth.setChannelVolume(1, 0.25)
  local b = ChipSynth.newEngine(data, song, { allowLoops = false })
  local quarter = b.channels[1]:sample()
  ChipSynth.setChannelVolumes({ 1, 1, 1, 1 })
  check(base > 0 and math.abs(quarter - base * 0.25) < 1e-9,
    "channelVolume still quarters the unipolar DAC level")
end

eq(type(ChipSynth.newEngine), "function", "engine factory still exported")

T.finish("chip analog path")
