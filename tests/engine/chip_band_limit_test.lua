-- ChipSynth output is band-limited (an edge is spread across the two samples
-- it falls between), and the Gen 2 per-frame counters behave as
-- audio/engine.asm's do (#3132).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")

local data = { audio = {} }
local RATE = ChipSynth.SAMPLE_RATE

local function render(engine, count)
  local out = {}
  for index = 1, count do out[index] = engine.channels[1]:sample() end
  return out
end

-- share of the signal's AC power that sits away from every harmonic of
-- `fundamental`: for a periodic source that is alias energy and nothing else
local function inharmonicShare(samples, fundamental)
  local count = #samples
  local mean = 0
  for index = 1, count do mean = mean + samples[index] end
  mean = mean / count
  local total, off = 0, 0
  for bin = 1, count / 2 - 1 do
    local re, im = 0, 0
    local step = 2 * math.pi * bin / count
    for index = 1, count do
      -- Hann window keeps a harmonic inside its own few bins
      local window = 0.5 - 0.5 * math.cos(2 * math.pi * (index - 1) / count)
      local value = (samples[index] - mean) * window
      re = re + value * math.cos(step * (index - 1))
      im = im - value * math.sin(step * (index - 1))
    end
    local power = re * re + im * im
    total = total + power
    local harmonic = bin * RATE / count / fundamental
    if math.abs(harmonic - math.floor(harmonic + 0.5)) * fundamental
        > 4 * RATE / count then
      off = off + power
    end
  end
  return off / total
end

-- ------- pulse

do
  -- B7: register 2031, 131072 / 17 Hz.  Its 3rd harmonic is already past
  -- Nyquist at 44100 and every harmonic above folds back between the others.
  local song = ChipAsm.song{
    channels = { { hw = 1, program = {
      { duty = 0 },
      { notetype = { speed = 12, volume = 15, fade = 0 } },
      { octave = 7 },
      { note = "B", len = 16 },
    } } },
  }
  local engine = ChipSynth.newEngine(data, song, { allowLoops = false })
  local samples = render(engine, 2048)
  local share = inharmonicShare(samples, 131072 / 17)
  check(share < 0.12,
    ("a high pulse keeps its alias energy down (%.3f of AC power)"):format(share))
  local partial = false
  for index = 1, #samples do
    if samples[index] > 1e-9 and samples[index] < 1 - 1e-9 then partial = true end
  end
  check(partial, "a sample that straddles a pulse edge takes a level between the two")
end

do
  -- C2: 64 Hz, an edge every ~86 samples.  Away from an edge the output is
  -- exactly the DAC level, so band-limiting costs low notes nothing.
  local song = ChipAsm.song{
    channels = { { hw = 1, program = {
      { duty = 2 },
      { notetype = { speed = 12, volume = 15, fade = 0 } },
      { octave = 1 },
      { note = "C", len = 16 },
    } } },
  }
  local engine = ChipSynth.newEngine(data, song, { allowLoops = false })
  local samples = render(engine, 2048)
  local flat, between = 0, 0
  for index = 1, #samples do
    local value = samples[index]
    if value == 0 or value == 1 then flat = flat + 1 else between = between + 1 end
  end
  check(flat > 1900 and between < 60,
    ("a low pulse is still a square (%d flat, %d edge samples)"):format(flat, between))
end

-- ------- noise

do
  -- parameter $00: the LFSR clocks at 524288 Hz, about 12 times per sample
  local sfx = ChipAsm.sfx{
    channels = { { hw = 4, program = {
      { noiseNote = { len = 8, volume = 15, fade = 0, parameter = 0x00 } },
    } } },
  }
  local engine = ChipSynth.newEngine(data, sfx, { sfx = true, allowLoops = false })
  local samples = render(engine, 4096)
  local mean, between = 0, 0
  for index = 1, #samples do
    local value = samples[index]
    mean = mean + value
    if value > 1e-9 and value < 1 - 1e-9 then between = between + 1 end
  end
  mean = mean / #samples
  local power = 0
  for index = 1, #samples do power = power + (samples[index] - mean) ^ 2 end
  power = power / #samples
  check(between > 3500, "fast noise averages its clocks across a sample")
  check(math.abs(mean - 0.5) < 0.05, ("and keeps its mean level (%.3f)"):format(mean))
  -- point-sampled it is a full-scale coin flip, AC power 0.25
  check(power < 0.06, ("at a fraction of the point-sampled power (%.3f)"):format(power))
end

do
  -- parameter $77: one clock every ~300 samples, nothing to average
  local sfx = ChipAsm.sfx{
    channels = { { hw = 4, program = {
      { noiseNote = { len = 16, volume = 15, fade = 0, parameter = 0x77 } },
    } } },
  }
  local engine = ChipSynth.newEngine(data, sfx, { sfx = true, allowLoops = false })
  local samples = render(engine, 4096)
  local between = 0
  for index = 1, #samples do
    if samples[index] > 1e-9 and samples[index] < 1 - 1e-9 then between = between + 1 end
  end
  check(between < 20, ("slow noise is still two-level (%d edge samples)"):format(between))
end

-- ------- wave

do
  local function waveSong(level)
    local song = ChipAsm.song{
      channels = { { hw = 3, program = {
        { notetype = { speed = 12, waveLevel = level, waveInstrument = 0 } },
        { octave = 1 },
        { note = "C", len = 16 },
      } } },
    }
    local wave = {}
    for index = 1, 32 do wave[index] = index <= 16 and 15 or 5 end
    song.chip.waves = { wave }
    return song
  end
  local function peak(level)
    local engine = ChipSynth.newEngine(data, waveSong(level), { allowLoops = false })
    local high, low = 0, math.huge
    for _, value in ipairs(render(engine, 2048)) do
      high, low = math.max(high, value), math.min(low, value)
    end
    return high, low
  end
  local high, low = peak(1)
  check(math.abs(high - 1) < 1e-9 and math.abs(low - 5 / 15) < 1e-9, "wave level 1 plays the nibbles as they are")
  high, low = peak(2)
  check(math.abs(high - 7 / 15) < 1e-9 and math.abs(low - 2 / 15) < 1e-9,
    "wave level 2 shifts each nibble right one bit (15 -> 7, 5 -> 2)")
  high, low = peak(3)
  check(math.abs(high - 3 / 15) < 1e-9 and math.abs(low - 1 / 15) < 1e-9,
    "wave level 3 shifts each nibble right two bits (15 -> 3, 5 -> 1)")
  high = peak(0)
  eq(high, 0, "wave level 0 is mute")
end

-- ------- Gen 2 per-frame state (hand-assembled audio/engine.asm bytecode)

local function gen2(number, ...)
  return {
    generation = 2,
    chip = {
      blob = string.char(...),
      channels = { { number = number, address = 0x4000 } },
    },
  }
end

local function events(header, count)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = false })
  local out = {}
  for index = 1, count do out[index] = engine.channels[1]:nextEvent() end
  return out
end

do
  -- ChannelInit zeroes the struct: stored octave 0 is `octave 8`
  local list = events(gen2(1,
    0xD8, 0x01, 0xA0, -- note_type 1, 10, 0
    0x10,             -- note C_, 1
    0xFF), 1)
  eq(list[1].register, 2032, "a Gen 2 channel with no octave command plays octave 8")
end

do
  -- vibrato 0, 2, 2 over two-frame notes: the rate counter is not reloaded
  -- by a note, so it runs out on the first frame of every other note
  local list = events(gen2(2,
    0xD8, 0x01, 0xA0, -- note_type 1, 10, 0
    0xD4,             -- octave 4
    0xE1, 0x00, 0x22, -- vibrato 0, 2, 2
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0xFF), 6)
  eq(list[1].register, 1797, "note 1 starts on pitch (C4)")
  eq(list[1].registerSteps, nil, "and runs the counter down without a toggle")
  eq(list[2].register, 1798, "note 2 triggers a step above: the counter carried over")
  local steps = list[3].registerSteps
  eq(list[3].register, 1797, "note 3 triggers on pitch")
  check(steps and steps[1] == 1 and steps[2] == 1796,
    "and steps below on its second frame: the direction carried over too")
  eq(list[4].register, 1797, "note 4 is a whole note between toggles")
  eq(list[4].registerSteps, nil, "with nothing written after the trigger")
  eq(list[5].register, 1798, "note 5 is a step above again")
end

do
  -- vibrato 3, 2, 0: the delay is the one counter a note does reload
  local list = events(gen2(2,
    0xD8, 0x01, 0xA0,
    0xD4,
    0xE1, 0x03, 0x20, -- vibrato 3, 2, 0
    0x15, 0x15,       -- two six-frame notes
    0xFF), 2)
  for index = 1, 2 do
    local steps = list[index].registerSteps
    eq(list[index].register, 1797, "note " .. index .. " waits out the delay on pitch")
    check(steps and steps[1] == 3, "note " .. index .. " starts its vibrato on frame 3")
  end
  eq(list[1].registerSteps[2], 1798, "note 1 toggles up first")
  eq(list[2].registerSteps[2], 1796, "note 2 picks the direction up where note 1 left it")
end

do
  -- duty_cycle_pattern 0, 1, 2, 3 rotates every frame, notes or not
  local list = events(gen2(1,
    0xD8, 0x01, 0xA0,
    0xD4,
    0xDE, 0x1B,       -- duty_cycle_pattern 0, 1, 2, 3
    0x12, 0x02, 0x12, -- three frames, a three-frame rest, three frames
    0xFF), 3)
  eq(list[1].dutyStart, 0, "the pattern starts with the first note after the command")
  eq(list[3].dutyStart, 2, "and is six frames on after a note and a rest")
end

do
  -- nothing clears SOUND_DUTY_LOOP: a later duty_cycle is overwritten by the
  -- pattern every frame
  local list = events(gen2(1,
    0xD8, 0x01, 0xA0,
    0xD4,
    0xDE, 0x1B,
    0x12,
    0xDB, 0x02,       -- duty_cycle 2
    0x12,
    0xFF), 2)
  check(type(list[2].duty) == "table" and list[2].dutyStart == 3,
    "a duty_cycle after a duty_cycle_pattern leaves the pattern running")
end

do
  -- pitch_slide 1, 4, C_ on a C3 lasting eight frames.  LoadNote: distance
  -- 250 over 8 frames is 31 r 2, stored as amount 32, fraction 2.
  local program = {
    0xD8, 0x01, 0xA0,
    0xD5,             -- octave 3
    0xE0, 0x00, 0x41, -- pitch_slide 1, 4, C_
    0x17,             -- note C_, 8
    0xFF,
  }
  local list = events(gen2(1, unpack(program)), 1)
  local steps = list[1].registerSteps
  eq(list[1].register, 1547 + 32, "the slide has already moved once when the note triggers")
  eq(steps and #steps / 2, 6, "it writes on each of the next six frames")
  eq(steps and steps[#steps], 1547 + 7 * 32, "and stops short of the target instead of landing on it")
  check(steps and steps[#steps] < 1797, "it never passes the target")

  list = events(gen2(2, unpack(program)), 1)
  eq(list[1].register, 1547 + 32, "channel 2 triggers with the slid frequency too")
  eq(list[1].registerSteps, nil, "but never acts on NOTE_FREQ_OVERRIDE, so the slide stops there")
end

do
  -- a rest drops a pending slide: .noteover clears SOUND_PITCH_SLIDE
  local list = events(gen2(1,
    0xD8, 0x01, 0xA0,
    0xD5,
    0xE0, 0x00, 0x41,
    0x03,             -- rest 4
    0x17,
    0xFF), 2)
  eq(list[2].register, 1547, "a slide followed by a rest does not reach the next note")
end

T.finish("chip band limit")
