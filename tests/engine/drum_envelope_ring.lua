-- ..(audio/engine_1.asm ln 197)
-- ..(audio/sfx/noise_instrument01_1.asm ln 1)
--   luajit tests/engine/drum_envelope_ring.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")

local snare = ChipAsm.song{
  channels = {
    { hw = 4, program = {
      { notetype = { speed = 12 } },
      { drum = 1, len = 2 },
      { rest = 16 },
    } },
  },
  drums = {
    [1] = {
      { len = 1, volume = 12, fade = 1, parameter = 0x33 },
    },
  },
}

local engine = ChipSynth.newEngine({ audio = {} }, snare, { allowLoops = false })
local segs = engine:noiseInstrument(1)
local last = segs[#segs]
local ringMs = (last.endSample - last.startSample) / ChipSynth.SAMPLE_RATE * 1000
check(ringMs > 150 and ringMs < 220,
  ("snare instrument rings ~188ms, not the 17ms note (%0.1fms)"):format(ringMs))

local energyEarly, energyLate, energyEnd = 0, 0, 0
local total = math.floor(ChipSynth.SAMPLE_RATE * 0.25)
for i = 1, total do
  local s = engine:sample()
  local e = s * s
  local t = i / ChipSynth.SAMPLE_RATE
  if t < 0.02 then
    energyEarly = energyEarly + e
  elseif t > 0.05 and t < 0.12 then
    energyLate = energyLate + e
  elseif t > 0.20 then
    energyEnd = energyEnd + e
  end
end
check(energyEarly > 0, "snare attack is audible")
check(energyLate > energyEarly * 0.05,
  ("snare body still sounds at 50-120ms (early=%.4f late=%.4f)")
    :format(energyEarly, energyLate))
check(energyEnd < energyLate * 0.1,
  "snare has decayed by 200ms")

local hats = ChipAsm.song{
  channels = {
    { hw = 4, program = {
      { notetype = { speed = 12 } },
      { drum = 1, len = 2 },
      { drum = 1, len = 2 },
    } },
  },
  drums = {
    [1] = {
      { len = 1, volume = 8, fade = 1, parameter = 0x10 },
    },
  },
}
local hatEngine = ChipSynth.newEngine({ audio = {} }, hats, { allowLoops = false })
local hits = 0
local prev = 0
for _ = 1, math.floor(ChipSynth.SAMPLE_RATE * 0.3) do
  local s = math.abs(hatEngine:sample())
  if prev < 0.01 and s >= 0.01 then hits = hits + 1 end
  prev = s
end
check(hits >= 2, ("two rapid drum_notes both trigger (%d onsets)"):format(hits))

T.finish("drum envelope ring")
