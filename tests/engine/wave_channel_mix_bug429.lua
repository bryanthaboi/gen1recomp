-- The shipped per-channel mix must be authentic, and the wave channel must
-- sit exactly one octave below a pulse at the same note (#429).  On hardware
-- ch3 counts 65536/(2048-x) against the pulses' 131072/(2048-x), and pokered
-- writes the frequency register for CHAN3 unmodified
-- (audio/engine_1.asm:904-944 Audio1_ApplyWavePatternAndFrequency loads only
-- the wave pattern), with no attenuation either
-- (Audio1_ApplyDutyCycleAndSoundLength:887 skips just the duty nibble).  A
-- CHANNEL_VOLUME/CHANNEL_PITCH of 0.25/0.5 on ch3 therefore buried every Ch3
-- countermelody at quarter amplitude and a second octave down.
-- ROM-free: ChipAsm blobs, no data/generated/.
--   luajit tests/engine/wave_channel_mix_bug429.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")
-- requiring ChipAudio is the point of the first block: the module pushes its
-- shipped CHANNEL_VOLUME / CHANNEL_PITCH into ChipSynth at load
local ChipAudio = require("src.core.ChipAudio")

-- ------- the shipped defaults

local vols = ChipSynth.getChannelVolumes()
local pitches = ChipSynth.getChannelPitches()
for hw = 1, 4 do
  check(vols[hw] == 1,
    ("channel %d ships at volume 1, not %s"):format(hw, tostring(vols[hw])))
  check(pitches[hw] == 1,
    ("channel %d ships at pitch 1, not %s"):format(hw, tostring(pitches[hw])))
end
-- ChipAudio.playMusic forwards these to the worker with every play command
-- (ChipAudio.lua:190-191 -> chip_worker.lua:50-54), so a non-unity default
-- reaches the threaded path as well as the synchronous one
local forwarded = ChipAudio.getChannelVolumes()
check(forwarded[3] == 1, "the wave gain handed to the worker is unity")
check(ChipAudio.getChannelPitches()[3] == 1,
  "the wave pitch handed to the worker is unity")

-- ------- fixtures: one note, once on a pulse and once on the wave channel

local data = { audio = {} }

-- +1 for the first half of the table and -1 for the second, so the wave
-- crosses zero twice per cycle exactly like a 50% duty pulse
local squareWave = {}
for index = 1, 32 do squareWave[index] = index <= 16 and 1 or -1 end

local function pulseSong(note, octave)
  return ChipAsm.song{
    channels = { { hw = 1, program = {
      { duty = 2 },
      { notetype = { speed = 12, volume = 15, fade = 0 } },
      { octave = octave },
      { note = note, len = 15 },
    } } },
  }
end

local function waveSong(note, octave)
  return ChipAsm.song{
    channels = { { hw = 3, program = {
      { notetype = { speed = 12, waveLevel = 1, waveInstrument = 0 } },
      { octave = octave },
      { note = note, len = 15 },
    } } },
    waves = { squareWave },
  }
end

local function crossings(sd)
  local count, prev = 0, sd:getSample(0)
  for index = 1, sd:getSampleCount() - 1 do
    local sample = sd:getSample(index)
    if prev * sample < 0 then count = count + 1 end
    prev = sample
  end
  return count
end

local function renderPulse(note, octave)
  return crossings(ChipAudio._renderMusicChannelForTest(
    data, pulseSong(note, octave), 0.25, 1))
end

local function renderWave(note, octave)
  return crossings(ChipAudio._renderMusicChannelForTest(
    data, waveSong(note, octave), 0.25, 3))
end

-- ------- one octave down, and only one

for _, spec in ipairs({ { "C", 4 }, { "G", 4 }, { "C", 5 } }) do
  local note, octave = spec[1], spec[2]
  local pulse = renderPulse(note, octave)
  local wave = renderWave(note, octave)
  check(pulse > 40, ("%s%d on the pulse channel sounds (%d crossings)")
    :format(note, octave, pulse))
  check(wave > 20 and math.abs(wave - pulse / 2) <= math.max(4, pulse * 0.06),
    ("%s%d on the wave channel is one octave down (%d vs %d crossings)")
      :format(note, octave, wave, pulse))
end

-- the wave channel one octave up from a pulse note lands on that pulse note,
-- which is the same statement from the other side
local waveUp = renderWave("C", 5)
local pulseAt = renderPulse("C", 4)
check(math.abs(waveUp - pulseAt) <= math.max(4, pulseAt * 0.06),
  ("wave C5 matches pulse C4 (%d vs %d crossings)"):format(waveUp, pulseAt))

-- ------- the 0.1.38 mix, so the guard above is known to bite

local brokenPitch, brokenVol
local baseValue = ChipAudio._traceFirstMusicSampleForTest(
  data, waveSong("C", 4))[1].value
ChipAudio.setChannelPitch(3, 0.5)
brokenPitch = renderWave("C", 4)
ChipAudio.setChannelVolume(3, 0.25)
brokenVol = ChipAudio._traceFirstMusicSampleForTest(
  data, waveSong("C", 4))[1].value
ChipAudio.setChannelVolumes({ 1, 1, 1, 1 })
ChipAudio.setChannelPitches({ 1, 1, 1, 1 })

local authentic = renderWave("C", 4)
check(brokenPitch > 0 and math.abs(brokenPitch - authentic / 2)
    <= math.max(4, authentic * 0.06),
  ("pitch 0.5 on ch3 drops a second octave (%d vs %d crossings)")
    :format(brokenPitch, authentic))
check(math.abs(baseValue) > 0 and math.abs(brokenVol - baseValue * 0.25) < 1e-9,
  "volume 0.25 on ch3 quarters the wave sample")
check(ChipSynth.getChannelVolumes()[3] == 1
  and ChipSynth.getChannelPitches()[3] == 1,
  "the mix is back at unity for the suites that follow")

T.finish("wave channel mix")
