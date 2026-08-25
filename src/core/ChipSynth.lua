-- Pure Game Boy audio synthesis (the DMG/GBC channel-program interpreter and
-- PCM renderer), factored out of ChipAudio so it can run on EITHER the main
-- thread (SFX/cries, and the synchronous music fallback) or the ChipAudio
-- worker thread (src/core/chip_worker.lua), which is where map/battle music is
-- synthesized so a song change never stutters the render thread.
--
-- Deliberately depends ONLY on `bit`, love.sound and love.filesystem: no
-- love.audio (Sources are a playback concern the caller owns) and no
-- src.render.Assets (hot-reload registration stays in ChipAudio).  Both of
-- those are unavailable or main-thread-only inside a love.thread worker, so
-- keeping them out is what lets the same synth code run in the worker.

local bit = require("bit")

local ChipSynth = {}

local SAMPLE_RATE = 44100
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

local function snapTicks(ticks)
  return math.floor((ticks * 1470 + 256) / 512)
end

local cachedProgramFile
local cachedBanks

local function loadBanks(data)
  local audio = data.audio
  if cachedProgramFile == audio.programFile and cachedBanks then
    return cachedBanks
  end
  local raw, readError
  -- The chip worker runs in a separate Lua state without the NX overlay;
  -- ChipAudio hands it the versioned cache prefix explicitly.  On the main
  -- thread the NX overlay (or desktop mountVersion) makes the plain read
  -- resolve, so no platform branching belongs here.
  local prefix = audio.programPrefix
  if prefix and prefix ~= "" then
    raw, readError = love.filesystem.read(prefix .. audio.programFile)
  end
  if not raw then
    raw, readError = love.filesystem.read(audio.programFile)
  end
  if not raw then error("could not read sound programs: " .. tostring(readError)) end
  local banks = {}
  for index, bank in ipairs(audio.bankOrder) do
    local first = (index - 1) * 0x4000 + 1
    banks[bank] = raw:sub(first, first + 0x3FFF)
  end
  cachedProgramFile, cachedBanks = audio.programFile, banks
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
    octave = 4,
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
    pendingSlide = nil,
    sweep = nil,
    callStack = {},
    loopCounts = {},
    event = nil,
    ended = false,
    phase = 0,
    noiseLfsr = 0x7FFF,
    noiseClock = 0,
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

function Channel:frequency(note, octave)
  local signed = PITCHES[note + 1] - 0x10000
  local register = bit.band(
    bit.arshift(signed, math.max(0, (octave or self.octave) - 1)), 0x7FF)
  if self.perfectPitch then register = bit.band(register + 1, 0x7FF) end
  return bit.band(register + self.frequencyOffset, 0x7FF)
end

-- pokegold GetFrequency: FrequencyTable[pitch+transpose] with asr while
-- CHANNEL_OCTAVE (+ transpose hi) < 7, then optional pitch_offset.
function Channel:frequencyGen2(note, octave)
  local trans = self.transposition or 0
  local pitch = note + bit.band(trans, 0x0F)
  local oct = (octave or self.octave) + bit.rshift(trans, 4)
  local tableVal = GEN2_FREQUENCY[pitch + 1] or 0
  local signed = tableVal - 0x10000
  local shifts = 0
  while oct < 7 do
    shifts = shifts + 1
    oct = oct + 1
  end
  local register = bit.band(bit.arshift(signed, shifts), 0x7FF)
  register = bit.band(register + (self.pitchOffset or 0), 0x7FF)
  return bit.band(register + self.frequencyOffset, 0x7FF)
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
  local frames = math.floor(product / 256)
  return frames * FRAME_TICKS
end

function Channel:timedEvent(event, ticks)
  local first = snapTicks(self.timeTicks)
  self.timeTicks = self.timeTicks + ticks
  event.duration = ticks / TICKS_PER_SECOND
  event.samples = snapTicks(self.timeTicks) - first
  event.sample = 0
  event.elapsed = 0
  return event
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
  local duration = ticks / TICKS_PER_SECOND
  local panLeft, panRight = self:pan()
  local slide
  if self.pendingSlide then
    slide = {
      target = self.pendingSlide.target,
      frames = math.max(1, duration * 60 - self.pendingSlide.length),
    }
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
    vibrato = slide and nil or self.vibrato,
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
      return self:tone(self:durationTicks(length), self:frequency(note))
    elseif command >= 0xC0 and command < 0xD0 then
      local length = bit.band(command, 0x0F) + 1
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
      if depth == 0 then
        self.vibrato = nil
      else
        self.vibrato = {
          delay = delay,
          above = bit.rshift(depth, 1) + bit.band(depth, 1),
          below = bit.rshift(depth, 1),
          rate = bit.band(packed, 0x0F),
        }
      end
    elseif command == 0xEB then
      local length, packed = self:byte(), self:byte()
      local octave = 8 - bit.rshift(packed, 4)
      self.pendingSlide = {
        length = length,
        target = self:frequency(bit.band(packed, 0x0F), octave),
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
      return self:tone(ticks, register, volume, fade)
    elseif command < 0xD0 then
      local note = bit.rshift(command, 4)
      local length = bit.band(command, 0x0F)
      local ticks = self:durationTicksGen2(length)
      if note == 0 then
        return self:silenceEvent(ticks)
      end
      if self.noise and self.noiseSampling then
        return self:drumEvent(ticks, note)
      end
      if self.noise then
        return self:silenceEvent(ticks)
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
        target = self:frequencyGen2(bit.band(packed, 0x0F), octave),
      }
    elseif command == 0xE1 then -- vibrato
      local delay, packed = self:byte(), self:byte()
      local depth = bit.rshift(packed, 4)
      if depth == 0 then
        self.vibrato = nil
      else
        self.vibrato = {
          delay = delay,
          above = bit.rshift(depth, 1) + bit.band(depth, 1),
          below = bit.rshift(depth, 1),
          rate = bit.band(packed, 0x0F),
        }
      end
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

function Channel:resetNoise()
  self.noiseLfsr = 0x7FFF
  self.noiseClock = 0
end

function Channel:clockNoise(width7)
  local feedback = bit.bxor(
    bit.band(self.noiseLfsr, 1),
    bit.band(bit.rshift(self.noiseLfsr, 1), 1))
  self.noiseLfsr = bit.bor(
    bit.rshift(self.noiseLfsr, 1),
    bit.lshift(feedback, 14))
  if width7 then
    self.noiseLfsr = bit.bor(
      bit.band(self.noiseLfsr, bit.bnot(0x40)),
      bit.lshift(feedback, 6))
  end
end

function Channel:sampleNoise(parameter)
  parameter = parameter or 0
  local divisor = NOISE_DIVISORS[bit.band(parameter, 7)]
  local shift = bit.rshift(parameter, 4)
  if shift < 14 then
    local pitch = channelPitch[self.hardware] or 1
    local cycles = GB_CLOCK / divisor / (2 ^ shift) / SAMPLE_RATE * pitch
    local width7 = bit.band(parameter, 8) ~= 0
    local remaining = cycles
    while remaining > 0 do
      local untilClock = 1 - self.noiseClock
      local span = math.min(remaining, untilClock)
      self.noiseClock = self.noiseClock + span
      remaining = remaining - span
      if self.noiseClock >= 1 - 1e-12 then
        self.noiseClock = 0
        self:clockNoise(width7)
      end
    end
  end
  return bit.band(self.noiseLfsr, 1) == 0 and 1 or 0
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

function Channel:sampleDrum(event, sampleIndex)
  local index = event.drumSegmentIndex or 1
  local segment = event.drum[index]
  while segment and sampleIndex >= segment.endSample do
    index = index + 1
    segment = event.drum[index]
  end
  if not segment or sampleIndex < segment.startSample then return 0 end
  if event.drumSegmentIndex ~= index then
    event.drumSegmentIndex = index
    self:resetNoise()
  end
  local elapsed = (sampleIndex - segment.startSample) / SAMPLE_RATE
  local volume = envelopeVolume(segment.volume, segment.fade, elapsed)
  return self:sampleNoise(segment.parameter) * volume / 15
end

function Channel:sample()
  while not self.ended
      and (not self.event or self.event.sample >= self.event.samples) do
    local prev = self.event
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
  end
  local event = self.event
  local gain = channelVolume[self.hardware] or 1
  if not event then
    local tail = self.drumTail
    if not tail then return 0 end
    local sampleIndex = tail.sample
    tail.sample = sampleIndex + 1
    if sampleIndex >= drumAudioEnd(tail.drum) then
      self.drumTail = nil
      return 0
    end
    return self:sampleDrum(tail, sampleIndex) * gain
  end
  local sampleIndex = event.sample
  event.elapsed = sampleIndex / SAMPLE_RATE
  event.sample = sampleIndex + 1
  if event.silence then
    local tail = self.drumTail
    if not tail then return 0 end
    local tailIndex = tail.sample
    tail.sample = tailIndex + 1
    if tailIndex >= drumAudioEnd(tail.drum) then
      self.drumTail = nil
      return 0
    end
    return self:sampleDrum(tail, tailIndex) * gain
  end
  if event.drum then
    return self:sampleDrum(event, sampleIndex) * gain
  end
  self.drumTail = nil
  local volume = envelopeVolume(
    event.volume or 0, event.fade or 0, event.elapsed)
  if event.noise then
    return self:sampleNoise(event.noiseParameter) * volume / 15 * gain
  end

  local register = event.register
  local frame = math.floor(event.elapsed * 60)
  if event.sweep then
    register = sweptRegister(register, event.sweep, event.elapsed)
    if not register then return 0 end
  elseif event.slide then
    local amount = math.min(1, frame / event.slide.frames)
    register = register + (event.slide.target - register) * amount
  elseif event.vibrato and frame >= event.vibrato.delay then
    local vibrato = event.vibrato
    local toggles = math.floor(
      (frame - vibrato.delay + 1) / (vibrato.rate + 1))
    if toggles > 0 then
      local low = bit.band(register, 0xFF)
      local high = bit.band(register, 0x700)
      if bit.band(toggles, 1) ~= 0 then
        register = high + math.min(0xFF, low + vibrato.above)
      else
        register = high + math.max(0, low - vibrato.below)
      end
    end
  end
  local pitch = channelPitch[self.hardware] or 1
  local frequency = 131072 / (2048 - math.min(register, 2047)) * pitch
  if event.wave then frequency = frequency * 0.5 end
  local phase = self.phase
  self.phase = (phase + frequency / SAMPLE_RATE) % 1
  if event.wave then
    local wave = self.engine.waves[
      math.min(event.waveInstrument + 1, #self.engine.waves)]
    -- a def-local program may omit its wave table entirely
    if not wave then return 0 end
    local index = math.min(32, math.floor(phase * 32) + 1)
    local nibble = math.max(0, math.min(15, wave[index] * 8 + 8))
    return (nibble / 15) * event.waveLevel * gain
  end
  local duty = event.duty
  if type(duty) == "table" then
    duty = duty[frame % 4 + 1]
  end
  local pattern = WAVE_PATTERN_TABLES[duty or 2] or WAVE_PATTERN_TABLES[2]
  local step = math.floor(phase * 8) % 8
  if pattern[step + 1] == 0 then
    return 0
  end
  return volume / 15 * gain
end

local Engine = {}
Engine.__index = Engine

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
      -- ReadNoiseSample: delay = (length & $f) + 1 frames
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
  return engine
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
end

function Engine:sampleChannel(number)
  local selected = 0
  for _, channel in ipairs(self.channels) do
    local value = channel:sample()
    if channel.number == number then selected = value end
  end
  return analogOut(self, selected, "hpfCap", "lpf")
end

-- render `samples` frames into a fresh SoundData (mono or stereo).  love.sound
-- is available on worker threads, so this is the hand-off unit the worker
-- produces and the main thread queues.
local function soundData(engine, samples, channels)
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, channels)
  for index = 0, samples - 1 do
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


local function renderEffectData(data, header, options)
  if not header then return nil end
  options = options or {}
  options.sfx = true
  options.allowLoops = false
  local engine = Engine.new(data, header, options)
  local maximum = SAMPLE_RATE * 5
  local values = {}
  local count = 0
  while count < maximum and not engine:finished() do
    count = count + 1
    values[count] = engine:sample()
  end
  if count < math.floor(SAMPLE_RATE / 100) then return nil end
  local result = love.sound.newSoundData(count, SAMPLE_RATE, 16, 2)
  for index = 1, count do
    local value = values[index]
    result:setSample(index - 1, 1, value)
    result:setSample(index - 1, 2, value)
  end
  return result
end

ChipSynth.newEngine = Engine.new
ChipSynth.soundData = soundData
ChipSynth.renderEffectData = renderEffectData

function ChipSynth.applyStereo(engine)
  if type(engine) == "table" and engine.applyStereo then
    engine:applyStereo()
  end
end

return ChipSynth
