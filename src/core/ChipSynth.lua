-- Pure Game Boy audio synthesis (the DMG/GBC channel-program interpreter and
-- PCM renderer), factored out of ChipAudio so it can run on EITHER the main
-- thread (SFX/cries, and the synchronous music fallback) or the ChipAudio
-- worker thread (src/core/chip_worker.lua), which is where map/battle music is
-- synthesized so a song change never stutters the render thread.
--
-- Deliberately depends ONLY on `bit`, src.core.WorkerFs, love.sound and love.filesystem: no
-- love.audio (Sources are a playback concern the caller owns) and no
-- src.render.Assets (hot-reload registration stays in ChipAudio).  Both of
-- those are unavailable or main-thread-only inside a love.thread worker, so
-- keeping them out is what lets the same synth code run in the worker.

local bit = require("bit")

local ChipSynth = {}

-- Handheld tunable: the sbc/portmaster launcher exports POKEPORT_AUDIO_RATE
-- (22050) because synthesis cost scales linearly with the rate and the GB's
-- DAC content sits well below 11 kHz.  Module-level so ChipAudio and the
-- chip worker thread pick it up on load; unset/invalid falls back to 44100.
local SAMPLE_RATE = (function()
  local rate = tonumber(os.getenv("POKEPORT_AUDIO_RATE"))
  if rate and rate >= 8000 and rate <= 48000 then return math.floor(rate) end
  return 44100
end)()
local TICKS_PER_SECOND = 15360
local FRAME_TICKS = 256
local GB_CLOCK = 4194304

-- one 8192-sample stereo SoundData is the unit both the worker hands off and
-- the synchronous fallback queues; the source keeps MUSIC_BUFFER_COUNT of them
-- (~6s at 44100) for stall tolerance (window resize, a long GC pause)
local MUSIC_BUFFER_SAMPLES = 8192
local MUSIC_BUFFER_COUNT = 32

ChipSynth.SAMPLE_RATE = SAMPLE_RATE
ChipSynth.MUSIC_BUFFER_SAMPLES = MUSIC_BUFFER_SAMPLES
ChipSynth.MUSIC_BUFFER_COUNT = MUSIC_BUFFER_COUNT

-- Gen 2 SOUND option (MONO/STEREO): gates Music_StereoPanning's per-song
-- panning byte (audio/engine.asm:1987 wOptions STEREO bit).
local stereoEnabled = false

function ChipSynth.setStereo(enabled)
  stereoEnabled = not not enabled
end

function ChipSynth.getStereo()
  return stereoEnabled
end

local monoFastPath = true

function ChipSynth._setMonoFastPathForTest(enabled)
  monoFastPath = not not enabled
end

-- Runtime mix per hardware channel (1 pulse, 2 pulse, 3 wave, 4 noise).
-- Volume: 1 = authentic GB, 0 = mute.  Pitch: 1 = authentic, 2 = +1 octave,
-- 0.5 = -1 octave.  Applied at sample time so a live change reaches the next
-- buffer on both the sync path and the worker (via ChipAudio).
local channelVolume = { 1, 1, 1, 1 }
local channelPitch = { 1, 1, 1, 1 }

local function clampScale(scale)
  return math.max(0, tonumber(scale) or 0)
end

local function setChannelTable(table, hw, scale)
  hw = tonumber(hw)
  if not hw or hw < 1 or hw > 4 then return end
  table[hw] = clampScale(scale)
end

local function setChannelTables(table, values)
  if type(values) ~= "table" then return end
  for hw = 1, 4 do
    if values[hw] ~= nil then table[hw] = clampScale(values[hw]) end
  end
end

function ChipSynth.setChannelVolume(hw, scale)
  setChannelTable(channelVolume, hw, scale)
end

function ChipSynth.getChannelVolume(hw)
  return channelVolume[tonumber(hw) or 0] or 1
end

function ChipSynth.setChannelVolumes(volumes)
  setChannelTables(channelVolume, volumes)
end

function ChipSynth.getChannelVolumes()
  return { channelVolume[1], channelVolume[2], channelVolume[3], channelVolume[4] }
end

function ChipSynth.setChannelPitch(hw, scale)
  setChannelTable(channelPitch, hw, scale)
end

function ChipSynth.getChannelPitch(hw)
  return channelPitch[tonumber(hw) or 0] or 1
end

function ChipSynth.setChannelPitches(pitches)
  setChannelTables(channelPitch, pitches)
end

function ChipSynth.getChannelPitches()
  return { channelPitch[1], channelPitch[2], channelPitch[3], channelPitch[4] }
end

-- aliases for the noise/drum layer
function ChipSynth.setNoiseVolume(scale)
  ChipSynth.setChannelVolume(4, scale)
end

function ChipSynth.getNoiseVolume()
  return ChipSynth.getChannelVolume(4)
end

local PITCHES = {
  0xF82C, 0xF89D, 0xF907, 0xF96B, 0xF9CA, 0xFA23,
  0xFA77, 0xFAC7, 0xFB12, 0xFB58, 0xFB9B, 0xFBDA,
}
-- Gen 2 FrequencyTable (audio/notes.asm): index 0 = rest, then C_..B_ twice
-- so transpose can walk into the next octave without an octave command.
local GEN2_FREQUENCY = {
  0x0000,
  0xF82C, 0xF89D, 0xF907, 0xF96B, 0xF9CA, 0xFA23,
  0xFA77, 0xFAC7, 0xFB12, 0xFB58, 0xFB9B, 0xFBDA,
  0xFC16, 0xFC4E, 0xFC83, 0xFCB5, 0xFCE5, 0xFD11,
  0xFD3B, 0xFD63, 0xFD89, 0xFDAC, 0xFDCD, 0xFDED,
}
-- LuaGB / DMG 8-step duty tables (index 0-3); stored on channels as that index
local WAVE_PATTERN_TABLES = {
  [0] = {0, 0, 0, 0, 0, 0, 0, 1},
  [1] = {1, 0, 0, 0, 0, 0, 0, 1},
  [2] = {1, 0, 0, 0, 0, 1, 1, 1},
  [3] = {0, 1, 1, 1, 1, 1, 1, 0},
}
local WAVE_LEVEL = { [0] = 0, [1] = 1, [2] = 0.5, [3] = 0.25 }
local NOISE_DIVISORS = {
  [0] = 8, [1] = 16, [2] = 32, [3] = 48,
  [4] = 64, [5] = 80, [6] = 96, [7] = 112,
}


local HPF_CHARGE = 0.999958 ^ (GB_CLOCK / SAMPLE_RATE)
local LPF_ALPHA = 0.8
local MIX_SCALE = 0.5

local function buildShape(levels, count)
  local level, first, second = {}, { 0 }, { 0 }
  for k = 1, count do
    level[k] = levels[k]
    first[k + 1] = first[k] + levels[k] / count
    second[k + 1] = second[k] + (first[k] + levels[k] / (2 * count)) / count
  end
  return {
    n = count, level = level, first = first, second = second,
    mean = first[count + 1], turn = second[count + 1],
  }
end

local PULSE_SHAPES = {}
for duty = 0, 3 do
  PULSE_SHAPES[duty] = buildShape(WAVE_PATTERN_TABLES[duty], 8)
end

local function shapeIntegrals(shape, x)
  local whole = math.floor(x)
  local frac = x - whole
  local n = shape.n
  local scaled = frac * n
  local k = math.min(math.floor(scaled), n - 1)
  local u = (scaled - k) / n
  local level, first = shape.level[k + 1], shape.first[k + 1]
  local mean = shape.mean
  return whole * mean + first + level * u,
    mean * whole * (whole - 1) * 0.5 + whole * (shape.turn + mean * frac)
      + shape.second[k + 1] + first * u + level * u * u * 0.5
end

local function shapeMoments(shape, phase, delta)
  local n = shape.n
  local scaled = phase * n
  local k = math.min(math.floor(scaled), n - 1)
  local level = shape.level[k + 1]
  if delta < 1e-5 or scaled + delta * n < k + 1 then
    return level * 0.5, level * 0.5
  end
  local u = (scaled - k) / n
  local first = shape.first[k + 1]
  local h0 = first + level * u
  local g0 = shape.second[k + 1] + first * u + level * u * u * 0.5
  local h1, g1 = shapeIntegrals(shape, phase + delta)
  local lead = (g1 - g0) / (delta * delta) - h0 / delta
  return lead, (h1 - h0) / delta - lead
end

local function snapTicks(ticks)
  -- ticks -> samples at the configured rate.  The original baked 44100/15360
  -- in as the integer rational 1470/512; this form is identical at 44100
  -- ((ticks*44100 + 7680)/15360 == (ticks*1470 + 256)/512) but follows
  -- POKEPORT_AUDIO_RATE when the handheld build lowers the synth rate.
  return math.floor((ticks * SAMPLE_RATE + TICKS_PER_SECOND / 2) / TICKS_PER_SECOND)
end

function ChipSynth.setSampleRate(rate)
  rate = tonumber(rate)
  if rate then
    rate = math.floor(rate)
    if rate < 8000 then rate = 8000 elseif rate > 48000 then rate = 48000 end
    if rate ~= SAMPLE_RATE then
      SAMPLE_RATE = rate
      HPF_CHARGE = 0.999958 ^ (GB_CLOCK / SAMPLE_RATE)
      ChipSynth.SAMPLE_RATE = SAMPLE_RATE
    end
  end
  return SAMPLE_RATE
end

local cachedProgramFile
local cachedBanks

local function loadBanks(data)
  local audio = data.audio
  local WorkerFs = require("src.core.WorkerFs")
  local key = audio.programBytes and audio
    or (WorkerFs.normalize(audio.programPrefix) or "") .. tostring(audio.programFile)
  if cachedProgramFile == key and cachedBanks then
    return cachedBanks
  end
  local raw, readError = audio.programBytes
  if not raw then raw, readError = WorkerFs.read(audio.programPrefix, audio.programFile) end
  if not raw then error("could not read sound programs: " .. tostring(readError)) end
  local banks = {}
  for index, bank in ipairs(audio.bankOrder) do
    local first = (index - 1) * 0x4000 + 1
    banks[bank] = raw:sub(first, first + 0x3FFF)
  end
  cachedProgramFile, cachedBanks = key, banks
  return banks
end

-- drop the single-slot bank cache; the worker keeps its own copy of this
-- module's state, so ChipAudio.invalidate must reach it via a worker message
function ChipSynth.invalidateBanks()
  cachedProgramFile, cachedBanks = nil, nil
end

-- test-only: exercise loadBanks without building a full engine
function ChipSynth._loadBanksForTest(data)
  return loadBanks(data)
end

-- A def-local program (ChipAsm output) is mounted as pseudo-bank 0 next to
-- the ROM banks, so the 0x4000-window byte reader and every call/loop
-- target work unchanged.  The ROM's own cached bank table is never touched
-- because bank 0 differs per def, and a blob that carries its own waves and
-- drums renders even where programs.bin is unreadable.
local function engineBanks(data, chip)
  if not chip then return loadBanks(data) end
  local banks = {}
  local ok, romBanks = pcall(loadBanks, data)
  if ok then
    for bank, bytes in pairs(romBanks) do banks[bank] = bytes end
  end
  banks[0] = chip.blob
  return banks
end

local function romByte(banks, bank, address)
  local bytes = assert(banks[bank], "uncached audio bank " .. tostring(bank))
  local value = bytes:byte(address - 0x4000 + 1)
  if not value then
    error(("audio read outside bank %02X:%04X"):format(bank, address))
  end
  return value
end

local function romWord(banks, bank, address)
  return romByte(banks, bank, address)
    + romByte(banks, bank, address + 1) * 0x100
end

local function headerChannels(banks, header)
  local channels = {}
  local address = header.address
  local first = romByte(banks, header.bank, address)
  local count = bit.rshift(bit.band(first, 0xF0), 6) + 1
  for _ = 1, count do
    local descriptor = romByte(banks, header.bank, address)
    channels[#channels + 1] = {
      number = bit.band(descriptor, 0x0F) + 1,
      address = romWord(banks, header.bank, address + 1),
    }
    address = address + 3
  end
  return channels
end

-- Which software channels (CHAN5-8) an sfx occupies: its header carries one
-- 3-byte descriptor per channel.  Audio2_PlaySound walks exactly this list to
-- decide whether a new sfx may start at all (audio/engine_2.asm
-- .sfxChannelLoop), so Sound.playMove needs the set to reproduce that gate.
-- nil = not knowable here (a file def, or the banks are not readable yet),
-- which callers read as "no conflict".
function ChipSynth.effectChannels(data, def)
  if type(def) ~= "table" then return nil end
  local chip = def.chip
  local specs = chip and chip.channels
  if not specs then
    if not def.address then return nil end
    local ok, banks = pcall(engineBanks, data, chip)
    if not ok then return nil end
    local read
    ok, read = pcall(headerChannels, banks, def)
    if not ok then return nil end
    specs = read
  end
  local channels = {}
  for _, spec in ipairs(specs) do channels[#channels + 1] = spec.number end
  return channels
end

local function fadeValue(nibble)
  if bit.band(nibble, 8) ~= 0 then return -bit.band(nibble, 7) end
  return nibble
end

local Channel = {}
Channel.__index = Channel

function Channel.new(engine, spec, options)
  options = options or {}
  local hardware = (spec.number - 1) % 4 + 1
  local isSfxChannel = spec.number > 4
  -- Default LR tracks match pokegold MonoTracks / StereoTracks ($11/$22/…).
  local trackBit = bit.lshift(1, hardware - 1)
  local tracks = bit.bor(bit.lshift(trackBit, 4), trackBit)
  return setmetatable({
    engine = engine,
    bank = options.bank,
    address = spec.address,
    number = spec.number,
    hardware = hardware,
    wave = hardware == 3,
    noise = hardware == 4,
    sfx = isSfxChannel,
    executeMusic = not isSfxChannel,
    allowLoops = options.allowLoops ~= false,
    frequencyOffset = options.frequencyOffset or 0,
    frameTicks = options.frameTicks or FRAME_TICKS,
    plainTicks = (options.plainFrames or 0) * FRAME_TICKS,
    speed = 12,
    noteLength = 1, -- Gen 2 CHANNEL_NOTE_LENGTH (note_type)
    durationModifier = 0, -- Gen 2 fractional-frame carry
    volume = 12,
    fade = 0,
    duty = 2,
    -- ../pokecrystal/audio/engine.asm:2727
    octave = engine.generation == 2 and 0 or 4,
    transposition = 0, -- Gen 2: hi=octaves, lo=pitches
    pitchOffset = 0, -- Gen 2 pitch_offset (signed word add to freq)
    noiseKit = 0,
    noiseSampling = false, -- Gen 2 toggle_noise
    condition = 0, -- Gen 2 set_condition / sound_jump_if
    tracks = tracks, -- Gen 2 CHANNEL_TRACKS (NR51 bits for this channel)
    -- last Music_StereoPanning byte; remembered even while MONO so a live
    -- SOUND toggle can re-apply it without restarting the song (#1471)
    stereoPanning = nil,
    forcePanning = false, -- ForceStereoPanning ($e4) ignores the SOUND option
    waveInstrument = 0,
    waveLevel = 1,
    perfectPitch = false,
    vibrato = nil,
    vibratoDelayCount = 0,
    vibratoCounter = 0,
    vibratoUp = false,
    pendingSlide = nil,
    sweep = nil,
    callStack = {},
    loopCounts = {},
    event = nil,
    ended = false,
    phase = 0,
    noiseLfsr = 0x7FFF,
    noiseClock = 0,
    lag = 0,
    drumTail = nil,
    timeTicks = 0,
  }, Channel)
end

function Channel:byte()
  local value = romByte(self.engine.banks, self.bank, self.address)
  self.address = self.address + 1
  return value
end

function Channel:word()
  local value = romWord(self.engine.banks, self.bank, self.address)
  self.address = self.address + 2
  return value
end

-- ../pokered/audio/engine_1.asm:1306
function Channel:noteFrequency(note, octave)
  local signed = PITCHES[note + 1] - 0x10000
  return bit.band(
    bit.arshift(signed, math.max(0, (octave or self.octave) - 1)), 0x7FF)
end

function Channel:frequency(note, octave)
  local register = self:noteFrequency(note, octave)
  if self.perfectPitch then register = bit.band(register + 1, 0x7FF) end
  return bit.band(register + self.frequencyOffset, 0x7FF)
end

-- ../pokecrystal/audio/engine.asm:2138
function Channel:noteFrequencyGen2(note, octave)
  local trans = self.transposition or 0
  local pitch = note + bit.band(trans, 0x0F)
  local oct = (octave or self.octave) + bit.rshift(trans, 4)
  local signed = GEN2_FREQUENCY[pitch + 1] or 0
  if signed >= 0x8000 then signed = signed - 0x10000 end
  -- ../pokecrystal/audio/engine.asm:2174
  local shifts = math.max(0, 7 - oct)
  return bit.band(bit.arshift(signed, shifts), 0x7FF)
end

-- ../pokecrystal/audio/engine.asm:856
function Channel:frequencyGen2(note, octave)
  local register = self:noteFrequencyGen2(note, octave)
  register = bit.band(register + (self.pitchOffset or 0), 0x7FF)
  return bit.band(register + self.frequencyOffset, 0x7FF)
end

local function pitchSlide(frequency, target, frames, length, first)
  -- ../pokecrystal/audio/engine.asm:722
  local duration = frames - length
  if duration < 1 then duration = 1 end
  local frequencyLow, frequencyHigh = bit.band(frequency, 0xFF), bit.rshift(frequency, 8)
  local targetLow, targetHigh = bit.band(target, 0xFF), bit.rshift(target, 8)
  -- ../pokecrystal/audio/engine.asm:740
  local low = frequencyLow - targetLow
  local high = bit.band(frequencyHigh - (low < 0 and 1 or 0), 0xFF)
  local rising = high < targetHigh
  local distance
  if rising then
    -- ../pokecrystal/audio/engine.asm:762
    low = targetLow - frequencyLow
    high = bit.band(frequencyHigh - (low < 0 and 1 or 0), 0xFF)
    distance = bit.band(targetHigh - high, 0xFF) * 0x100 + bit.band(low, 0xFF)
  else
    -- ../pokecrystal/audio/engine.asm:788
    distance = bit.band(high - targetHigh, 0xFF) * 0x100 + bit.band(low, 0xFF)
  end
  -- ../pokecrystal/audio/engine.asm:805
  local amount = bit.band(math.floor(distance / duration) + 1, 0xFF)
  local fraction = distance % duration
  local accumulator = 0
  local registers = {}
  local value = frequency
  local sliding = true
  local start, stop = 1, nil
  if first then
    -- ../pokered/audio/engine_1.asm:1224
    registers[1] = bit.band(amount, 7) * 0x100
      + bit.band(fraction - duration + first, 0xFF)
    -- ../pokered/audio/engine_1.asm:1236
    accumulator = fraction
    start = 2
  end
  for frame = start, frames do
    if sliding then
      local stepped
      if rising then
        -- ../pokecrystal/audio/engine.asm:969
        accumulator = accumulator + fraction
        stepped = value + amount + (accumulator > 0xFF and 1 or 0)
        accumulator = bit.band(accumulator, 0xFF)
        stepped = bit.band(stepped, 0xFFFF)
        -- ../pokecrystal/audio/engine.asm:995
        if stepped > target then sliding = false else value = stepped end
      else
        -- ../pokecrystal/audio/engine.asm:1010
        stepped = value - amount - (fraction > 0x7F and 1 or 0)
        fraction = bit.band(fraction * 2, 0xFF)
        stepped = bit.band(stepped, 0xFFFF)
        -- ../pokecrystal/audio/engine.asm:1036
        if stepped < target then sliding = false else value = stepped end
      end
      if not sliding then stop = frame - 1 end
    end
    registers[frame] = value
  end
  return registers, stop
end

function Channel:durationTicks(length, plain)
  local tempo = self.sfx and (plain and FRAME_TICKS or self.frameTicks)
    or self.engine.tempo
  local speed = self.sfx and (self.executeMusic and self.speed or 1)
    or self.speed
  return length * speed * tempo
end

-- Gen 2 SetNoteDuration (audio/engine.asm).  Two eight-bit multiplies, and
-- BOTH of them throw the overflow away -- which is the whole character of the
-- routine and the reason it cannot be written as one product:
--
--   low     = LOW((length + 1) * NoteLength)     `ld a, l` after .Multiply
--   product = tempo * low + DurationModifier     16-bit, wraps
--   frames  = HIGH(product)                      `ld [hl], d`, one byte
--   modifier= LOW(product)                       carries into the next note
--
-- Keeping the full product instead is what made a cry run for seconds: a cry
-- sets CHANNEL_TEMPO to its length word (up to 576), so tempo * low routinely
-- runs past 16 bits and the truncation is load bearing rather than incidental.
--
-- NoteLength defaults to 1 and tempo to $100 -- LoadChannel's own defaults --
-- so a channel that never issues note_type or tempo still times correctly.
-- After toggle_sfx (executeMusic), fanfares like Sfx_CaughtMon use the
-- channel's tempo command, not the SFX frameTicks seed.
function Channel:durationTicksGen2(length)
  local tempo = (self.sfx and not self.executeMusic)
    and self.frameTicks or self.engine.tempo
  local low = bit.band((length + 1) * (self.noteLength or 1), 0xFF)
  local product = bit.band(tempo * low + (self.durationModifier or 0), 0xFFFF)
  self.durationModifier = bit.band(product, 0xFF)
  -- ../pokecrystal/audio/engine.asm:105
  local frames = math.floor(product / 256)
  if frames < 1 then frames = 1 end
  return frames * FRAME_TICKS
end

function Channel:timedEvent(event, ticks)
  local first = snapTicks(self.timeTicks)
  local firstFrame = math.floor(self.timeTicks / FRAME_TICKS)
  event.frameTicks = self.timeTicks - firstFrame * FRAME_TICKS
  self.timeTicks = self.timeTicks + ticks
  event.frames = math.floor(self.timeTicks / FRAME_TICKS) - firstFrame
  event.vibratoFrame = -1
  event.vibratoSample = self.vibrato and 0 or math.huge
  event.duration = ticks / TICKS_PER_SECOND
  event.samples = snapTicks(self.timeTicks) - first
  event.sample = 0
  event.elapsed = 0
  return event
end

function Channel:stepVibrato(event, frame)
  local vibrato = self.vibrato
  if self.engine.generation ~= 2 then
    -- ../pokered/audio/engine_1.asm:45
    if frame == 0 then return end
    -- ../pokered/audio/engine_1.asm:78
    local slide = event.slide
    if slide and not (slide.stop and frame > slide.stop) then return end
  end
  -- ../pokecrystal/audio/engine.asm:880
  if self.vibratoDelayCount > 0 then
    self.vibratoDelayCount = self.vibratoDelayCount - 1
    return
  end
  -- ../pokecrystal/audio/engine.asm:886
  if vibrato.above == 0 then return end
  -- ../pokecrystal/audio/engine.asm:894
  if self.vibratoCounter > 0 then
    self.vibratoCounter = self.vibratoCounter - 1
    return
  end
  -- ../pokecrystal/audio/engine.asm:905
  self.vibratoCounter = vibrato.rate
  local low = bit.band(event.register or 0, 0xFF)
  -- ../pokecrystal/audio/engine.asm:915
  if self.vibratoUp then
    self.vibratoUp = false
    low = math.max(0, low - vibrato.below)
  else
    self.vibratoUp = true
    low = math.min(0xFF, low + vibrato.above)
  end
  if event.register then
    -- ../pokecrystal/audio/engine.asm:394
    event.vibratoRegister = bit.band(event.register, 0x700) + low
  end
end

function Channel:pan()
  local mask = bit.lshift(1, self.hardware - 1)
  if self.engine.generation == 2 then
    local tracks = self.tracks or 0xFF
    return bit.band(bit.rshift(tracks, 4), mask) ~= 0,
      bit.band(tracks, mask) ~= 0
  end
  return bit.band(bit.rshift(self.engine.pan, 4), mask) ~= 0,
    bit.band(self.engine.pan, mask) ~= 0
end

-- Recompute CHANNEL_TRACKS from the remembered panning byte and the live
-- STEREO flag.  ForceStereoPanning stays put either way.
function Channel:applyStereoMix()
  local mask = bit.lshift(1, self.hardware - 1)
  local default = bit.bor(bit.lshift(mask, 4), mask)
  if self.forcePanning then
    return
  elseif stereoEnabled and self.stereoPanning then
    self.tracks = bit.band(self.stereoPanning, default)
  else
    self.tracks = default
  end
end

function Channel:tone(ticks, register, volume, fade)
  if register >= 0x800 then
    return self:timedEvent({ silence = true }, ticks)
  end
  local panLeft, panRight = self:pan()
  local slide
  local pending = self.pendingSlide
  if pending then
    if pending.registers then
      slide = {
        registers = pending.registers,
        stop = pending.stop,
        offset = self.engine.generation == 2
          and (self.pitchOffset or 0) + self.frequencyOffset or 0,
      }
    end
    self.pendingSlide = nil
  end
  return self:timedEvent({
    register = register,
    volume = volume == nil and self.volume or volume,
    fade = fade == nil and self.fade or fade,
    duty = self.duty,
    wave = self.wave,
    waveInstrument = self.waveInstrument,
    waveLevel = self.waveLevel,
    vibratoRegister = false,
    slide = slide,
    sweep = self.sfx and self.hardware == 1 and self.sweep or nil,
    panLeft = panLeft,
    panRight = panRight,
  }, ticks)
end

function Channel:noiseEvent(ticks, volume, fade, parameter)
  local panLeft, panRight = self:pan()
  return self:timedEvent({
    noise = true,
    volume = volume or self.volume,
    fade = fade or 0,
    noiseParameter = parameter,
    panLeft = panLeft, panRight = panRight,
  }, ticks)
end

function Channel:drumEvent(ticks, instrument)
  local panLeft, panRight = self:pan()
  local drum
  if self.engine.generation == 2 then
    drum = self.engine:drumInstrumentGen2(self.noiseKit or 0, instrument)
  else
    drum = self.engine:noiseInstrument(instrument)
  end
  return self:timedEvent({
    noise = true,
    drum = drum,
    panLeft = panLeft,
    panRight = panRight,
  }, ticks)
end

function Channel:silenceEvent(ticks)
  return self:timedEvent({ silence = true }, ticks)
end

function Channel:nextEvent()
  if self.engine.generation == 2 then
    return self:nextEventGen2()
  end
  if self.ended then return nil end
  for _ = 1, 100000 do
    local commandAddress = self.address
    local command = self:byte()

    if (self.executeMusic or not self.sfx) and command < 0xC0 then
      local note = bit.rshift(command, 4)
      local length = bit.band(command, 0x0F) + 1
      if self.noise then
        local instrument = note
        if command >= 0xB0 then instrument = self:byte() end
        return self:drumEvent(self:durationTicks(length), instrument)
      end
      local ticks = self:durationTicks(length)
      if self.pendingSlide then
        local frames = math.floor((self.timeTicks + ticks) / FRAME_TICKS)
          - math.floor(self.timeTicks / FRAME_TICKS)
        -- ../pokered/audio/engine_1.asm:799
        self.pendingSlide.registers, self.pendingSlide.stop = pitchSlide(
          self:noteFrequency(note), self.pendingSlide.target, frames,
          self.pendingSlide.length, self.perfectPitch and 1 or 0)
      end
      return self:tone(ticks, self:frequency(note))
    elseif command >= 0xC0 and command < 0xD0 then
      local length = bit.band(command, 0x0F) + 1
      -- ../pokered/audio/engine_1.asm:158
      self.pendingSlide = nil
      return self:silenceEvent(self:durationTicks(length))
    elseif command >= 0xD0 and command < 0xE0 then
      self.speed = bit.band(command, 0x0F)
      if not self.noise then
        local packed = self:byte()
        if self.wave then
          self.waveLevel = WAVE_LEVEL[bit.band(bit.rshift(packed, 4), 3)]
          self.waveInstrument = bit.band(packed, 0x0F)
        else
          self.volume = bit.rshift(packed, 4)
          self.fade = fadeValue(bit.band(packed, 0x0F))
        end
      end
    elseif command >= 0xE0 and command <= 0xE7 then
      self.octave = 8 - bit.band(command, 7)
    elseif command == 0xE8 then
      self.perfectPitch = not self.perfectPitch
    elseif command == 0xE9 then
      -- Unused command.
    elseif command == 0xEA then
      local delay, packed = self:byte(), self:byte()
      local depth = bit.rshift(packed, 4)
      -- ../pokered/audio/engine_1.asm:384
      self.vibrato = {
        delay = delay,
        above = bit.rshift(depth, 1) + bit.band(depth, 1),
        below = bit.rshift(depth, 1),
        rate = bit.band(packed, 0x0F),
      }
      self.vibratoDelayCount = delay
      self.vibratoCounter = self.vibrato.rate
    elseif command == 0xEB then
      local length, packed = self:byte(), self:byte()
      local octave = 8 - bit.rshift(packed, 4)
      self.pendingSlide = {
        length = length,
        -- ../pokered/audio/engine_1.asm:447
        target = self:noteFrequency(bit.band(packed, 0x0F), octave),
      }
    elseif command == 0xEC then
      self.duty = bit.band(self:byte(), 3)
    elseif command == 0xED then
      local high = self:byte()
      local low = self:byte()
      -- a header carrying its own tempo is one of audio/alternate_tempo.asm's
      -- Music_*AlternateTempo entry points, which re-point channel 1 at a
      -- stub that sets the tempo and jumps into the normal body -- the body's
      -- own tempo command never runs there, so ignore it here (#847)
      if not self.engine.tempoLocked then
        self.engine.tempo = high * 0x100 + low
      end
    elseif command == 0xEE then
      self.engine.pan = self:byte()
    elseif command == 0xEF or command == 0xF0 then
      self:byte()
    elseif command == 0xF8 then
      self.executeMusic = not self.executeMusic
    elseif command == 0xFC then
      local packed = self:byte()
      self.duty = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      }
    elseif command == 0xFD then
      self.callStack[#self.callStack + 1] = self.address + 2
      self.address = self:word()
    elseif command == 0xFE then
      local count, target = self:byte(), self:word()
      if count == 0 then
        if self.allowLoops then
          self.address = target
        else
          self.ended = true
          return nil
        end
      else
        local remaining = self.loopCounts[commandAddress]
        if remaining == nil then remaining = count end
        remaining = remaining - 1
        if remaining > 0 then
          self.loopCounts[commandAddress] = remaining
          self.address = target
        else
          self.loopCounts[commandAddress] = nil
        end
      end
    elseif command == 0xFF then
      local returnAddress = table.remove(self.callStack)
      if returnAddress then
        self.address = returnAddress
      else
        self.ended = true
        return nil
      end
    elseif self.sfx and command >= 0x20 and command < 0x30 then
      local length = bit.band(command, 0x0F) + 1
      local packed = self:byte()
      local volume = bit.rshift(packed, 4)
      local fade = fadeValue(bit.band(packed, 0x0F))
      -- audio/engine_2.asm:991-1013, :1015-1033, :1077-1096
      local plain = self.timeTicks < self.plainTicks
      local offset = plain and 0 or self.frequencyOffset
      if self.noise then
        -- Audio2_ApplyWavePatternAndFrequency adds wFrequencyModifier to the
        -- frequency low byte for every channel at or past CHAN5, the noise
        -- channel included (audio/engine_2.asm Audio2_ApplyFrequencyModifier).
        -- On CHAN8 that byte is the polynomial counter, so the modifier moves
        -- the noise pitch; it wraps at 8 bits, the carry landing in the high
        -- byte that noise does not use for frequency.  Dropping it left the
        -- battle hit sounds at their unmodified pitches, where super effective
        -- reads as the duller of the two (#826).
        local parameter = bit.band(self:byte() + offset, 0xFF)
        return self:noiseEvent(
          self:durationTicks(length, plain), volume, fade, parameter)
      end
      local register = bit.band(self:word() + offset, 0x7FF)
      return self:tone(self:durationTicks(length, plain), register, volume, fade)
    elseif command == 0x10 then
      local packed = self:byte()
      self.sweep = {
        pace = bit.band(bit.rshift(packed, 4), 7),
        subtract = bit.band(packed, 8) ~= 0,
        shift = bit.band(packed, 7),
      }
    else
      self.ended = true
      return nil
    end
  end
  self.ended = true
  return nil
end

-- Gen 2 music bytecode (pokegold macros/scripts/audio.asm, FIRST_MUSIC_CMD=$d0).
-- Notes share the Gen 1 packing; rest is pitch 0.  Call/loop opcodes are
-- swapped vs Gen 1 ($fe call, $fd loop) and $fc is sound_jump.
function Channel:nextEventGen2()
  if self.ended then return nil end
  for _ = 1, 100000 do
    local commandAddress = self.address
    local command = self:byte()

    if command < 0xD0 and self.sfx and not self.executeMusic then
      -- ParseSFXOrCry.  On a channel carrying SOUND_SFX or SOUND_CRY a byte
      -- under $d0 is not a packed note at all: it is a `square_note` /
      -- `noise_note` row, and SetNoteDuration is handed the WHOLE byte rather
      -- than its low nibble.  What follows is the volume envelope and then
      -- the raw frequency register -- two bytes on a tone channel, one on
      -- noise, where it is the polynomial counter instead.
      --
      -- Parsing these as music notes is what made every Gold cry and sound
      -- effect wrong: the envelope byte was read as a second note and the
      -- frequency low byte ($d8 for 1752, say) as a note_type command that
      -- then ate the next two bytes.
      local ticks = self:durationTicksGen2(command)
      local packed = self:byte()
      local volume = bit.rshift(packed, 4)
      local fade = fadeValue(bit.band(packed, 0x0F))
      if self.noise then
        local parameter = bit.band(self:byte() + self.frequencyOffset, 0xFF)
        return self:noiseEvent(ticks, volume, fade, parameter)
      end
      -- CHANNEL_PITCH_OFFSET is wCryPitch for a cry and the SFX pitch
      -- modifier otherwise; both land in frequencyOffset.  The add is 16-bit
      -- on hardware and only 11 bits reach the register, so a negative pitch
      -- stored as its unsigned word still comes out right.
      local register = bit.band(self:word() + self.frequencyOffset, 0x7FF)
      if self.wave then
        -- ../pokecrystal/audio/engine.asm:424
        self.waveInstrument = bit.band(packed, 0x0F)
        -- ../pokecrystal/audio/engine.asm:470
        self.waveLevel = WAVE_LEVEL[bit.band(volume, 3)]
      end
      return self:tone(ticks, register, volume, fade)
    elseif command < 0xD0 then
      local note = bit.rshift(command, 4)
      local length = bit.band(command, 0x0F)
      local ticks = self:durationTicksGen2(length)
      if note == 0 then
        -- ../pokecrystal/audio/engine.asm:121
        self.pendingSlide = nil
        return self:silenceEvent(ticks)
      end
      if self.noise and self.noiseSampling then
        -- ../pokecrystal/audio/engine.asm:1116
        if #self.engine:drumInstrumentGen2(self.noiseKit or 0, note) == 0 then
          local event = self:silenceEvent(ticks)
          event.dropDrumRows = true
          return event
        end
        return self:drumEvent(ticks, note)
      end
      if self.noise then
        return self:silenceEvent(ticks)
      end
      if self.pendingSlide then
        -- ../pokecrystal/audio/engine.asm:1197
        self.pendingSlide.registers = pitchSlide(
          self:noteFrequencyGen2(note), self.pendingSlide.target,
          ticks / FRAME_TICKS, self.pendingSlide.length)
      end
      return self:tone(ticks, self:frequencyGen2(note))
    elseif command >= 0xD0 and command <= 0xD7 then
      -- octave 8 → $d0 (stored 0); octave 1 → $d7 (stored 7)
      self.octave = bit.band(command, 7)
    elseif command == 0xD8 then -- note_type / drum_speed
      self.noteLength = self:byte()
      if not self.noise then
        local packed = self:byte()
        if self.wave then
          self.waveLevel = WAVE_LEVEL[bit.band(bit.rshift(packed, 4), 3)]
          self.waveInstrument = bit.band(packed, 0x0F)
        else
          self.volume = bit.rshift(packed, 4)
          self.fade = fadeValue(bit.band(packed, 0x0F))
        end
      end
    elseif command == 0xD9 then -- transpose
      self.transposition = self:byte()
    elseif command == 0xDA then -- tempo (big-endian)
      local high, low = self:byte(), self:byte()
      if not self.engine.tempoLocked then
        self.engine.tempo = high * 0x100 + low
      end
      self.durationModifier = 0
    elseif command == 0xDB then -- duty_cycle
      self.duty = bit.band(self:byte(), 3)
    elseif command == 0xDC then -- volume_envelope
      local packed = self:byte()
      if self.wave then
        self.waveLevel = WAVE_LEVEL[bit.band(bit.rshift(packed, 4), 3)]
        self.waveInstrument = bit.band(packed, 0x0F)
      else
        self.volume = bit.rshift(packed, 4)
        self.fade = fadeValue(bit.band(packed, 0x0F))
      end
    elseif command == 0xDD then -- pitch_sweep (SFX; keep for completeness)
      local packed = self:byte()
      self.sweep = {
        pace = bit.band(bit.rshift(packed, 4), 7),
        subtract = bit.band(packed, 8) ~= 0,
        shift = bit.band(packed, 7),
      }
    elseif command == 0xDE then -- duty_cycle_pattern
      local packed = self:byte()
      self.duty = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      }
    elseif command == 0xDF then -- toggle_sfx
      self.executeMusic = not self.executeMusic
    elseif command == 0xE0 then -- pitch_slide
      local length, packed = self:byte(), self:byte()
      local octave = bit.rshift(packed, 4)
      self.pendingSlide = {
        length = length,
        -- ../pokecrystal/audio/engine.asm:1771
        target = self:noteFrequencyGen2(bit.band(packed, 0x0F), octave),
      }
    elseif command == 0xE1 then -- vibrato
      local delay, packed = self:byte(), self:byte()
      local depth = bit.rshift(packed, 4)
      -- ../pokecrystal/audio/engine.asm:1697
      self.vibrato = {
        delay = delay,
        above = bit.rshift(depth, 1) + bit.band(depth, 1),
        below = bit.rshift(depth, 1),
        rate = bit.band(packed, 0x0F),
      }
      self.vibratoDelayCount = delay
      self.vibratoCounter = self.vibrato.rate
      self.vibratoUp = false
    elseif command == 0xE2 then -- unknownmusic0xe2
      self:byte()
    elseif command == 0xE3 then -- toggle_noise
      if self.noiseSampling then
        self.noiseSampling = false
      else
        self.noiseSampling = true
        self.noiseKit = self:byte()
      end
    elseif command == 0xE4 then -- force_stereo_panning
      local packed = self:byte()
      local mask = bit.lshift(1, self.hardware - 1)
      local default = bit.bor(bit.lshift(mask, 4), mask)
      self.tracks = bit.band(packed, default)
      self.forcePanning = true
      self.engine:refreshMonoMix()
    elseif command == 0xE5 then -- volume (global master; ignored for mix)
      self:byte()
    elseif command == 0xE6 then -- pitch_offset (big-endian)
      local high, low = self:byte(), self:byte()
      local value = high * 0x100 + low
      if value >= 0x8000 then value = value - 0x10000 end
      self.pitchOffset = value
    elseif command == 0xE7 or command == 0xE8 then -- unused
      self:byte()
    elseif command == 0xE9 then -- tempo_relative
      local adj = self:byte()
      if adj >= 0x80 then adj = adj - 0x100 end
      self.engine.tempo = bit.band(self.engine.tempo + adj, 0xFFFF)
    elseif command == 0xEA then -- restart_channel
      self.address = self:word()
    elseif command == 0xEB then -- new_song (unused in music streams)
      self:word()
    elseif command == 0xEC or command == 0xED then -- sfx priority on/off
      -- no-op for the PCM renderer
    elseif command == 0xEE then -- unknownmusic0xee
      self:word()
    elseif command == 0xEF then
      -- audio/engine.asm:1987 Music_StereoPanning: apply only when STEREO is on.
      -- The packed byte is kept either way so ChipSynth.applyStereo can honour
      -- a live SOUND toggle mid-song (#1471).
      local packed = self:byte()
      self.stereoPanning = packed
      self.forcePanning = false
      if stereoEnabled then
        local mask = bit.lshift(1, self.hardware - 1)
        local default = bit.bor(bit.lshift(mask, 4), mask)
        self.tracks = bit.band(packed, default)
      end
    elseif command == 0xF0 then -- sfx_toggle_noise
      if self.noiseSampling then
        self.noiseSampling = false
      else
        self.noiseSampling = true
        self.noiseKit = self:byte()
      end
    elseif command >= 0xF1 and command <= 0xF9 then
      -- music0xf1-f9 / unused: no params
    elseif command == 0xFA then -- set_condition
      self.condition = self:byte()
    elseif command == 0xFB then -- sound_jump_if
      local want, target = self:byte(), self:word()
      if self.condition == want then self.address = target end
    elseif command == 0xFC then -- sound_jump
      self.address = self:word()
    elseif command == 0xFD then -- sound_loop (Gen 2; Gen 1 used $fe)
      local count, target = self:byte(), self:word()
      if count == 0 then
        if self.allowLoops then
          self.address = target
        else
          self.ended = true
          return nil
        end
      else
        local remaining = self.loopCounts[commandAddress]
        if remaining == nil then remaining = count end
        remaining = remaining - 1
        if remaining > 0 then
          self.loopCounts[commandAddress] = remaining
          self.address = target
        else
          self.loopCounts[commandAddress] = nil
        end
      end
    elseif command == 0xFE then -- sound_call
      self.callStack[#self.callStack + 1] = self.address + 2
      self.address = self:word()
    elseif command == 0xFF then -- sound_ret
      local returnAddress = table.remove(self.callStack)
      if returnAddress then
        self.address = returnAddress
      else
        self.ended = true
        return nil
      end
    else
      self.ended = true
      return nil
    end
  end
  self.ended = true
  return nil
end

local function envelopeVolume(volume, fade, elapsed)
  if fade == 0 then return volume end
  local steps = math.floor(elapsed / (math.abs(fade) / 64))
  if fade > 0 then return math.max(0, volume - steps) end
  return math.min(15, volume + steps)
end


local function envelopeRingSamples(volume, fade)
  if not fade or fade <= 0 or not volume or volume <= 0 then return 0 end
  return math.floor(volume * (fade / 64) * SAMPLE_RATE + 0.5)
end

local function extendDrumEnvelope(segments)
  local last = segments and segments[#segments]
  if not last then return segments end
  local ringEnd = last.startSample + envelopeRingSamples(last.volume, last.fade)
  if ringEnd > last.endSample then last.endSample = ringEnd end
  return segments
end

local function drumAudioEnd(drum)
  local last = drum and drum[#drum]
  return last and last.endSample or 0
end

-- ../pokecrystal/audio/engine.asm:1348
local function ringingRow(tail)
  local current = tail.drum[1]
  for _, segment in ipairs(tail.drum) do
    if tail.sample > segment.startSample then current = segment end
  end
  if not current then return nil end
  return {
    drum = extendDrumEnvelope({ {
      startSample = current.startSample,
      endSample = current.endSample,
      volume = current.volume,
      fade = current.fade,
      parameter = current.parameter,
    } }),
    sample = tail.sample,
    drumSegmentIndex = 1,
  }
end

function Channel:resetNoise()
  self.noiseLfsr = 0x7FFF
  self.noiseClock = 0
end

function Channel:noiseMoments(parameter)
  parameter = parameter or 0
  local lfsr = self.noiseLfsr
  local level = 1 - bit.band(lfsr, 1)
  local shift = bit.rshift(parameter, 4)
  local pitch = channelPitch[self.hardware] or 1
  local cycles = GB_CLOCK / NOISE_DIVISORS[bit.band(parameter, 7)]
    / (2 ^ shift) / SAMPLE_RATE * pitch
  if shift >= 14 or cycles <= 0 then return level * 0.5, level * 0.5 end
  local keep, inject = 0x3FFF, 0x4000
  if bit.band(parameter, 8) ~= 0 then keep, inject = 0x3FBF, 0x4040 end
  local step = 1 / cycles
  local at = 0
  local nextAt = (1 - self.noiseClock) * step
  local mean, moment = 0, 0
  while nextAt <= 1 do
    mean = mean + level * (nextAt - at)
    moment = moment + level * (nextAt * nextAt - at * at)
    local feedback = bit.band(bit.bxor(lfsr, bit.rshift(lfsr, 1)), 1)
    lfsr = bit.bor(bit.band(bit.rshift(lfsr, 1), keep),
      bit.band(-feedback, inject))
    level = 1 - bit.band(lfsr, 1)
    at = nextAt
    nextAt = nextAt + step
  end
  mean = mean + level * (1 - at)
  moment = (moment + level * (1 - at * at)) * 0.5
  self.noiseClock = 1 - (nextAt - 1) * cycles
  self.noiseLfsr = lfsr
  return mean - moment, moment
end

local function sweepCalculation(register, sweep)
  local delta = math.floor(register / (2 ^ sweep.shift))
  if sweep.subtract then return register - delta end
  return register + delta
end

local function sweptRegister(register, sweep, elapsed)
  if not sweep or sweep.shift == 0 then return register end
  local nextRegister = sweepCalculation(register, sweep)
  if nextRegister > 0x7FF or nextRegister < 0 then return nil end
  if sweep.pace == 0 then return register end

  local iterations = math.floor(elapsed * 128 / sweep.pace)
  for _ = 1, iterations do
    register = nextRegister
    nextRegister = sweepCalculation(register, sweep)
    if nextRegister > 0x7FF or nextRegister < 0 then return nil end
  end
  return register
end

function Channel:drumMoments(event, sampleIndex)
  local index = event.drumSegmentIndex or 1
  local segment = event.drum[index]
  while segment and sampleIndex >= segment.endSample do
    index = index + 1
    segment = event.drum[index]
  end
  if not segment or sampleIndex < segment.startSample then return 0, 0 end
  if event.drumSegmentIndex ~= index then
    event.drumSegmentIndex = index
    self:resetNoise()
  end
  local elapsed = (sampleIndex - segment.startSample) / SAMPLE_RATE
  local scale = envelopeVolume(segment.volume, segment.fade, elapsed) / 15
  local lead, lag = self:noiseMoments(segment.parameter)
  return lead * scale, lag * scale
end

function Channel:moments()
  while not self.ended
      and (not self.event or self.event.sample >= self.event.samples) do
    local prev = self.event
    -- ../pokecrystal/audio/engine.asm:112
    if self.vibrato then self.vibratoDelayCount = self.vibrato.delay end
    self.event = self:nextEvent()
    self.phase = 0
    if self.event and self.event.drum then
      self.drumTail = nil
      self:resetNoise()
    elseif prev and prev.drum and prev.sample < drumAudioEnd(prev.drum) then
      -- ..(audio/engine_1.asm ln 197)
      self.drumTail = prev
    elseif not (self.event and self.event.silence and self.drumTail) then
      self.drumTail = nil
      self:resetNoise()
    end
    if self.drumTail and self.event and self.event.dropDrumRows then
      self.drumTail = ringingRow(self.drumTail)
    end
  end
  local event = self.event
  local gain = channelVolume[self.hardware] or 1
  if not event then
    local tail = self.drumTail
    if not tail then return 0, 0 end
    local sampleIndex = tail.sample
    tail.sample = sampleIndex + 1
    if sampleIndex >= drumAudioEnd(tail.drum) then
      self.drumTail = nil
      return 0, 0
    end
    local lead, lag = self:drumMoments(tail, sampleIndex)
    return lead * gain, lag * gain
  end
  local sampleIndex = event.sample
  event.elapsed = sampleIndex / SAMPLE_RATE
  event.sample = sampleIndex + 1
  if sampleIndex >= event.vibratoSample then
    local frame = event.vibratoFrame
    if frame < event.frames - 1 and frame < math.floor((event.frameTicks
        + sampleIndex * TICKS_PER_SECOND / SAMPLE_RATE) / FRAME_TICKS) then
      frame = frame + 1
      event.vibratoFrame = frame
      self:stepVibrato(event, frame)
    end
    event.vibratoSample = math.floor(((frame + 1) * FRAME_TICKS
      - event.frameTicks) * SAMPLE_RATE / TICKS_PER_SECOND)
  end
  if event.silence then
    local tail = self.drumTail
    if not tail then return 0, 0 end
    local tailIndex = tail.sample
    tail.sample = tailIndex + 1
    if tailIndex >= drumAudioEnd(tail.drum) then
      self.drumTail = nil
      return 0, 0
    end
    local lead, lag = self:drumMoments(tail, tailIndex)
    return lead * gain, lag * gain
  end
  if event.drum then
    local lead, lag = self:drumMoments(event, sampleIndex)
    return lead * gain, lag * gain
  end
  self.drumTail = nil
  local volume = envelopeVolume(
    event.volume or 0, event.fade or 0, event.elapsed)
  if event.noise then
    local scale = volume / 15 * gain
    local lead, lag = self:noiseMoments(event.noiseParameter)
    return lead * scale, lag * scale
  end

  local register = event.register
  local frame = math.floor(event.elapsed * 60)
  if event.sweep then
    register = sweptRegister(register, event.sweep, event.elapsed)
    if not register then return 0, 0 end
  elseif event.slide then
    local slide = event.slide
    local value = slide.registers[math.min(frame + 1, #slide.registers)]
    value = bit.band(value + slide.offset, 0xFFFF)
    -- ../pokecrystal/audio/engine.asm:270
    if value > 0x7FFF then return 0, 0 end
    register = bit.band(value, 0x7FF)
  elseif event.vibratoRegister then
    register = event.vibratoRegister
  end
  local pitch = channelPitch[self.hardware] or 1
  local frequency = 131072 / (2048 - math.min(register, 2047)) * pitch
  if event.wave then frequency = frequency * 0.5 end
  local delta = frequency / SAMPLE_RATE
  local phase = self.phase
  self.phase = (phase + delta) % 1
  local shape, scale
  if event.wave then
    shape = self.engine:waveShape(event.waveInstrument)
    -- a def-local program may omit its wave table entirely
    if not shape then return 0, 0 end
    scale = event.waveLevel * gain
  else
    local duty = event.duty
    if type(duty) == "table" then
      duty = duty[frame % 4 + 1]
    end
    shape = PULSE_SHAPES[duty or 2] or PULSE_SHAPES[2]
    scale = volume / 15 * gain
  end
  local lead, lag = shapeMoments(shape, phase, delta)
  return lead * scale, lag * scale
end

function Channel:sample()
  local lead, lag = self:moments()
  local value = self.lag + lead
  self.lag = lag
  return value
end

local Engine = {}
Engine.__index = Engine

function Engine:waveShape(instrument)
  local index = math.min(instrument + 1, #self.waves)
  local shape = self.waveShapes[index]
  if shape == nil then
    local wave = self.waves[index]
    if wave then
      local levels = {}
      for position = 1, 32 do
        levels[position] = math.max(0, math.min(15, wave[position] * 8 + 8)) / 15
      end
      shape = buildShape(levels, 32)
    else
      shape = false
    end
    self.waveShapes[index] = shape
  end
  return shape
end

function Engine:noiseInstrument(number)
  -- a def-local drum wins over the ROM engine's table for that id
  local custom = self.customDrums and self.customDrums[number]
  if custom then return extendDrumEnvelope(custom) end
  local cached = self.noiseInstruments[number]
  if cached then return cached end

  local header = self.noiseHeaders[tostring(number)]
  local segments = {}
  if header then
    local spec = headerChannels(self.banks, header)[1]
    local address = spec and spec.address
    local ticks = 0
    for _ = 1, 64 do
      local command = romByte(self.banks, header.bank, address)
      address = address + 1
      if command == 0xFF then break end
      if command < 0x20 or command >= 0x30 then
        error(("unsupported drum command %02X at %02X:%04X")
          :format(command, header.bank, address - 1))
      end
      local packed = romByte(self.banks, header.bank, address)
      local parameter = romByte(self.banks, header.bank, address + 1)
      address = address + 2
      local duration = (bit.band(command, 0x0F) + 1) * FRAME_TICKS
      segments[#segments + 1] = {
        startSample = snapTicks(ticks),
        endSample = snapTicks(ticks + duration),
        volume = bit.rshift(packed, 4),
        fade = fadeValue(bit.band(packed, 0x0F)),
        parameter = parameter,
      }
      ticks = ticks + duration
    end
  end

  extendDrumEnvelope(segments)
  self.noiseInstruments[number] = segments
  return segments
end

-- Gen 2 Drumkits → kit pointer → instrument noise_note script (ReadNoiseSample).
function Engine:drumInstrumentGen2(kit, pitch)
  local key = kit * 256 + pitch
  local cached = self.noiseInstruments[key]
  if cached then return cached end
  local segments = {}
  local spec = self.drumkits
  if spec and pitch and pitch > 0 then
    local kitAddr = romWord(self.banks, spec.bank, spec.address + kit * 2)
    local instrAddr = romWord(self.banks, spec.bank, kitAddr + pitch * 2)
    local address = instrAddr
    local ticks = 0
    for _ = 1, 64 do
      local command = romByte(self.banks, spec.bank, address)
      address = address + 1
      if command == 0xFF then break end
      local packed = romByte(self.banks, spec.bank, address)
      local parameter = romByte(self.banks, spec.bank, address + 1)
      address = address + 2
      -- ../pokecrystal/audio/engine.asm:1087
      local duration = (bit.band(command, 0x0F) + 2) * FRAME_TICKS
      segments[#segments + 1] = {
        startSample = snapTicks(ticks),
        endSample = snapTicks(ticks + duration),
        volume = bit.rshift(packed, 4),
        fade = fadeValue(bit.band(packed, 0x0F)),
        parameter = parameter,
      }
      ticks = ticks + duration
    end
  end
  extendDrumEnvelope(segments)
  self.noiseInstruments[key] = segments
  return segments
end

local function readWaves(banks, audio, engineNumber)
  local spec = audio.waveBanks[tostring(engineNumber)]
  local waves = {}
  for wave = 0, 4 do
    local values = {}
    for byteIndex = 0, 15 do
      local packed = romByte(
        banks, spec.bank, spec.address + wave * 16 + byteIndex)
      values[#values + 1] = (bit.rshift(packed, 4) - 8) / 8
      values[#values + 1] = (bit.band(packed, 0x0F) - 8) / 8
    end
    waves[#waves + 1] = values
  end
  local values = {}
  for byteIndex = 0, 15 do
    local packed = romByte(
      banks, spec.bank, spec.address + 5 * 16 + byteIndex)
    values[#values + 1] = (bit.rshift(packed, 4) - 8) / 8
    values[#values + 1] = (bit.band(packed, 0x0F) - 8) / 8
  end
  for _ = 1, 4 do waves[#waves + 1] = values end
  return waves
end

-- Gen 2 WaveSamples: 10 patterns × 16 bytes (instruments 0-9).
local function readWavesGen2(banks, audio)
  local spec = audio.waveBanks and audio.waveBanks["1"]
  if not spec then return {} end
  local waves = {}
  for wave = 0, 9 do
    local values = {}
    for byteIndex = 0, 15 do
      local packed = romByte(
        banks, spec.bank, spec.address + wave * 16 + byteIndex)
      values[#values + 1] = (bit.rshift(packed, 4) - 8) / 8
      values[#values + 1] = (bit.band(packed, 0x0F) - 8) / 8
    end
    waves[#waves + 1] = values
  end
  return waves
end

-- def-local waves are authored either as raw 0-15 nibbles (the ROM's own
-- units) or as the -1..1 samples readWaves produces; the synth wants the
-- latter (LuaGB: (nibble - 8) / 8)
local function normalizeWaves(source)
  local waves = {}
  for index, values in ipairs(source) do
    local nibbles = false
    for _, value in ipairs(values) do
      if value > 1 or value < -1 then nibbles = true break end
    end
    local wave = {}
    for position, value in ipairs(values) do
      wave[position] = nibbles and (value - 8) / 8 or value
    end
    waves[index] = wave
  end
  return waves
end

function Engine.new(data, header, options)
  options = options or {}
  local audio = data.audio or {}
  -- shape dispatch: a def-local chip program supplies its own channels and
  -- may supply its own waves/drums, falling back to a ROM engine's tables
  local chip = header.chip
  local banks = engineBanks(data, chip)
  local generation = header.generation or audio.generation or 1
  local engineNumber = chip and (chip.engine or 1) or header.engine or 1
  local waves
  if chip and chip.waves then
    waves = normalizeWaves(chip.waves)
  elseif generation == 2 then
    if chip then
      local ok, romWaves = pcall(readWavesGen2, banks, audio)
      waves = ok and romWaves or {}
    else
      waves = readWavesGen2(banks, audio)
    end
  elseif chip then
    local ok, romWaves = pcall(readWaves, banks, audio, engineNumber)
    waves = ok and romWaves or {}
  else
    waves = readWaves(banks, audio, engineNumber)
  end
  local engine = setmetatable({
    banks = banks,
    generation = generation,
    tempo = 0x100,
    pan = 0xFF,
    waves = waves,
    noiseHeaders = audio.noiseHeaders
      and audio.noiseHeaders[tostring(engineNumber)] or {},
    drumkits = audio.drumkits,
    customDrums = chip and chip.drums or nil,
    noiseInstruments = {},
    waveShapes = {},
    channels = {},
    hpfCap = 0, hpfCapLeft = 0, hpfCapRight = 0,
    lpf = 0, lpfLeft = 0, lpfRight = 0,
  }, Engine)
  -- header.tempo: the Music_*AlternateTempo override Music.play stamps onto
  -- a copy of the song def (audio/alternate_tempo.asm) (#847)
  if header.tempo then
    engine.tempo = header.tempo
    engine.tempoLocked = true
  end
  local channels = chip and chip.channels or headerChannels(banks, header)
  if header.startChannels then
    local byNumber = {}
    for _, start in ipairs(header.startChannels) do
      byNumber[start.number] = start.address
    end
    for _, spec in ipairs(channels) do
      spec.address = byNumber[spec.number] or spec.address
    end
  end
  for _, spec in ipairs(channels) do
    local frameTicks = options.frameTicks
    local hardware = (spec.number - 1) % 4 + 1
    if hardware == 4 then
      frameTicks = FRAME_TICKS
    elseif options.cryLength then
      -- Gen 1: Audio_SetSfxTempo builds a 9-bit tempo out of $80 plus the
      -- cry's length BYTE.  Gen 2: _PlayCry writes wCryLength -- a full word,
      -- and its own comment says "Tempo is effectively length" -- straight
      -- into CHANNEL_TEMPO, with no $80 base.  Adding one anyway stretched
      -- every Gold cry by a third on top of the parse bug above.
      frameTicks = generation == 2 and options.cryLength
        or (0x80 + options.cryLength)
    end
    engine.channels[#engine.channels + 1] = Channel.new(engine, spec, {
      bank = chip and 0 or header.bank,
      sfx = options.sfx,
      allowLoops = options.allowLoops,
      frequencyOffset = options.frequencyOffset,
      frameTicks = frameTicks,
      plainFrames = options.plainFrames,
    })
  end
  engine:refreshMonoMix()
  return engine
end

function Engine:refreshMonoMix()
  if self.generation ~= 2 or stereoEnabled then
    self.monoMix = false
    return
  end
  for _, channel in ipairs(self.channels) do
    local mask = bit.lshift(1, channel.hardware - 1)
    if channel.tracks ~= nil
       and channel.tracks ~= bit.bor(bit.lshift(mask, 4), mask) then
      self.monoMix = false
      return
    end
  end
  self.monoMix = true
end

function Engine:finished()
  for _, channel in ipairs(self.channels) do
    if not channel.ended or channel.event then return false end
  end
  return true
end

local function analogOut(engine, input, hpfField, lpfField)
  local cap = engine[hpfField]
  local hp = input - cap
  engine[hpfField] = input - hp * HPF_CHARGE
  local prev = engine[lpfField]
  local lp = prev + LPF_ALPHA * (hp - prev)
  engine[lpfField] = lp
  return math.max(-1, math.min(1, lp * MIX_SCALE))
end

function Engine:sample()
  local value = 0
  for _, channel in ipairs(self.channels) do value = value + channel:sample() end
  return analogOut(self, value, "hpfCap", "lpf")
end

function Engine:sampleStereo()
  if monoFastPath and self.monoMix and not stereoEnabled then
    local value = 0
    local channels = self.channels
    for index = 1, #channels do value = value + channels[index]:sample() end
    local out = analogOut(self, value, "hpfCapLeft", "lpfLeft")
    self.hpfCapRight, self.lpfRight = self.hpfCapLeft, self.lpfLeft
    return out, out
  end
  local left, right = 0, 0
  for _, channel in ipairs(self.channels) do
    local value = channel:sample()
    local panLeft, panRight
    if self.generation == 2 then
      -- live CHANNEL_TRACKS, not the pan baked into the current note, so a
      -- SOUND toggle reaches the next synthesized sample (#1471)
      panLeft, panRight = channel:pan()
    else
      local event = channel.event
      panLeft = not event or event.panLeft ~= false
      panRight = not event or event.panRight ~= false
    end
    if panLeft then left = left + value end
    if panRight then right = right + value end
  end
  return analogOut(self, left, "hpfCapLeft", "lpfLeft"),
    analogOut(self, right, "hpfCapRight", "lpfRight")
end

function Engine:applyStereo()
  if self.generation ~= 2 then return end
  for _, channel in ipairs(self.channels) do
    channel:applyStereoMix()
  end
  self:refreshMonoMix()
end

function Engine:sampleChannel(number)
  local selected = 0
  for _, channel in ipairs(self.channels) do
    local value = channel:sample()
    if channel.number == number then selected = value end
  end
  return analogOut(self, selected, "hpfCap", "lpf")
end

-- Bulk PCM writes.  SoundData:setSample is a C call per sample (two per
-- stereo frame); at 44100 Hz that was a large slice of every rendered buffer.
-- Where LuaJIT's ffi and Data:getFFIPointer exist, samples go straight into
-- the SoundData's int16 storage instead.  LOVE 11.5's 16-bit setSample stores
-- (int16)(value * 32767) in double precision (truncating, no clamp), which is
-- exactly what an ffi int16 store of `value * 32767` does, so the PCM is
-- bit-identical to the setSample path (tests/chip_synth_bulk_pcm_test.lua,
-- plus a real-LOVE comparison over 2M values incl. out-of-range and NaN).
-- The setSample path stays as the fallback (headless stub, no ffi).
local ffiOk, ffi = pcall(require, "ffi")
local bulkWrites = true

function ChipSynth._setBulkWritesForTest(enabled)
  bulkWrites = not not enabled
end

local function int16Pointer(sd)
  if not (bulkWrites and ffiOk and ffi and sd.getFFIPointer) then return nil end
  if sd.getBitDepth then
    local okDepth, depth = pcall(sd.getBitDepth, sd)
    if not okDepth or depth ~= 16 then return nil end
  end
  local ok, pointer = pcall(sd.getFFIPointer, sd)
  if not ok or pointer == nil then return nil end
  return ffi.cast("int16_t *", pointer)
end
ChipSynth._int16Pointer = int16Pointer

-- does this runtime's SoundData expose writable int16 storage?  Probed once
-- (a 1-frame buffer) so renderEffectData can pick its path before rendering.
local pointerSupport

local function bulkAvailable()
  if not (bulkWrites and ffiOk and ffi) then return false end
  if pointerSupport == nil then
    local ok, probe = pcall(love.sound.newSoundData, 1, SAMPLE_RATE, 16, 2)
    pointerSupport = (ok and probe and int16Pointer(probe)) and true or false
  end
  return pointerSupport
end

-- render `count` frames from `engine` into an existing SoundData starting at
-- frame `offset`.  The synchronous music fallback fills one buffer a slice at
-- a time across frames (ChipAudio fillSync) so its per-frame cost is flat.
local function renderInto(engine, result, offset, count, channels)
  local last = offset + count - 1
  local pointer = int16Pointer(result)
  if pointer then
    if channels == 2 then
      for index = offset, last do
        local left, right = engine:sampleStereo()
        pointer[index * 2] = left * 32767
        pointer[index * 2 + 1] = right * 32767
      end
    else
      for index = offset, last do
        pointer[index] = engine:sample() * 32767
      end
    end
    return result
  end
  for index = offset, last do
    if channels == 2 then
      local left, right = engine:sampleStereo()
      result:setSample(index, 1, left)
      result:setSample(index, 2, right)
    else
      result:setSample(index, engine:sample())
    end
  end
  return result
end

local function newBuffer(samples, channels)
  return love.sound.newSoundData(samples, SAMPLE_RATE, 16, channels)
end

-- render `samples` frames into a fresh SoundData (mono or stereo).  love.sound
-- is available on worker threads, so this is the hand-off unit the worker
-- produces and the main thread queues.
local function soundData(engine, samples, channels)
  local result = newBuffer(samples, channels)
  return renderInto(engine, result, 0, samples, channels)
end

-- reusable int16 scratch for renderEffectData's bulk path: the effect length
-- is only known once the engine finishes, so samples are converted as they
-- are produced and copied (duplicated to both channels) at the end, instead
-- of growing a Lua table of doubles per render
local scratch, scratchSize = nil, 0

local function ensureScratch(size)
  if scratchSize >= size then return scratch end
  local grown = math.max(size, scratchSize * 2, 4096)
  local fresh = ffi.new("int16_t[?]", grown)
  if scratch and scratchSize > 0 then
    ffi.copy(fresh, scratch, scratchSize * 2)
  end
  scratch, scratchSize = fresh, grown
  return scratch
end

local function renderEffectData(data, header, options)
  if not header then return nil end
  options = options or {}
  options.sfx = true
  options.allowLoops = false
  local engine = Engine.new(data, header, options)
  -- audio/sfx/pokeflute.asm:20
  local maximum = SAMPLE_RATE * (options.maxSeconds or 12)
  local minimum = math.floor(SAMPLE_RATE / 100)
  if bulkAvailable() then
    local values = ensureScratch(SAMPLE_RATE)
    local count = 0
    while count < maximum and not engine:finished() do
      if count >= scratchSize then values = ensureScratch(count + 1) end
      values[count] = engine:sample() * 32767
      count = count + 1
    end
    if count < minimum then return nil end
    local result = newBuffer(count, 2)
    local pointer = int16Pointer(result)
    if pointer then
      for index = 0, count - 1 do
        local value = values[index]
        pointer[index * 2] = value
        pointer[index * 2 + 1] = value
      end
      return result
    end
    -- the probe said yes but this buffer has no pointer: re-render through
    -- setSample below (truncated int16s cannot be turned back into floats)
    engine = Engine.new(data, header, options)
  end
  local values = {}
  local count = 0
  while count < maximum and not engine:finished() do
    count = count + 1
    values[count] = engine:sample()
  end
  if count < minimum then return nil end
  local result = newBuffer(count, 2)
  for index = 1, count do
    local value = values[index]
    result:setSample(index - 1, 1, value)
    result:setSample(index - 1, 2, value)
  end
  return result
end

-- audio/engine_2.asm:259
local function effectChannelFrames(data, header, options)
  if not header then return nil end
  options = options or {}
  options.sfx = true
  options.allowLoops = false
  local engine = Engine.new(data, header, options)
  local frames = {}
  for _, channel in ipairs(engine.channels) do
    for _ = 1, 100000 do
      if channel.ended or not channel:nextEvent() then break end
    end
    frames[channel.number] = channel.timeTicks / FRAME_TICKS
  end
  return frames
end

ChipSynth.newEngine = Engine.new
ChipSynth.effectChannelFrames = effectChannelFrames
ChipSynth.soundData = soundData
ChipSynth.renderInto = renderInto
ChipSynth.newBuffer = newBuffer
ChipSynth.renderEffectData = renderEffectData

function ChipSynth.applyStereo(engine)
  if type(engine) == "table" and engine.applyStereo then
    engine:applyStereo()
  end
end

return ChipSynth
