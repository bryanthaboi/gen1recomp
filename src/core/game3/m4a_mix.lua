-- DirectSound + lightweight CGB mix for game3 M4A.
-- Output rate matches ChipSynth / QueueableSource; sequencer paced in GBA vblanks.

local Mix = {}

-- FireRed SampleFreqSet: timer 0 advances every 1254 CPU cycles.
Mix.GBA_CLOCK = 16777216
Mix.GBA_FRAME_CYCLES = 280896
Mix.GBA_SAMPLES_PER_VBLANK = 224
Mix.GBA_VBLANK_HZ = Mix.GBA_CLOCK / Mix.GBA_FRAME_CYCLES
Mix.GBA_MIX_RATE = Mix.GBA_VBLANK_HZ * Mix.GBA_SAMPLES_PER_VBLANK

local function load_chip_synth()
  -- love.thread workers often cannot resolve package.path requires; mirror chip_worker.
  if love and love.filesystem and love.filesystem.load then
    local ok, mod = pcall(function()
      return assert(love.filesystem.load("src/core/ChipSynth.lua"))()
    end)
    if ok and type(mod) == "table" then return mod end
  end
  local ok, mod = pcall(require, "src.core.ChipSynth")
  if ok and type(mod) == "table" then return mod end
  return nil
end

local ChipSynth = load_chip_synth()

-- Never fall back to a random rate (old 32768) — that desyncs QueueableSource vs SoundData.
Mix.SAMPLE_RATE = (ChipSynth and ChipSynth.SAMPLE_RATE) or 44100

function Mix.setSampleRate(rate)
  rate = tonumber(rate)
  if not rate or rate < 8000 or rate > 48000 then return Mix.SAMPLE_RATE end
  Mix.SAMPLE_RATE = math.floor(rate)
  return Mix.SAMPLE_RATE
end

--- How many output samples equal one GBA VBlank (one MPlayMain call).
function Mix.samplesPerVBlank()
  return Mix.SAMPLE_RATE * Mix.GBA_SAMPLES_PER_VBLANK / Mix.GBA_MIX_RATE
end

--- Convert an output PCM length into GBA VBlank units for the sequencer.
function Mix.vblanksForSamples(n)
  n = tonumber(n) or 0
  if n <= 0 then return 0 end
  return n / Mix.samplesPerVBlank()
end

local DUTY = {
  [0] = { 0.125, 1, -1 },
  [1] = { 0.25, 1, -1 },
  [2] = { 0.5, 1, -1 },
  [3] = { 0.75, 1, -1 },
}

-- pret gCgbScaleTable / gCgbFreqTable / gNoiseTable (m4a_tables.c)
local CGB_SCALE = {
  [0]=0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
  0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,
  0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,
  0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,
  0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,
  0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,
  0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xAB,
}

local CGB_FREQ = {
  [0]=-2004,-1891,-1785,-1685,-1591,-1501,-1417,-1337,-1262,-1192,-1125,-1062,
}

local NOISE_TABLE = {
  [0]=0xD7,0xD6,0xD5,0xD4,0xC7,0xC6,0xC5,0xC4,
  0xB7,0xB6,0xB5,0xB4,0xA7,0xA6,0xA5,0xA4,
  0x97,0x96,0x95,0x94,0x87,0x86,0x85,0x84,
  0x77,0x76,0x75,0x74,0x67,0x66,0x65,0x64,
  0x57,0x56,0x55,0x54,0x47,0x46,0x45,0x44,
  0x37,0x36,0x35,0x34,0x27,0x26,0x25,0x24,
  0x17,0x16,0x15,0x14,0x07,0x06,0x05,0x04,
  0x03,0x02,0x01,0x00,
}

local NOISE_DIV = { [0]=8, 16, 32, 48, 64, 80, 96, 112 }

-- pret gScaleTable / gFreqTable for MidiKeyToFreq (DirectSound)
local DS_SCALE = {
  [0]=0xE0,0xE1,0xE2,0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xEB,
  0xD0,0xD1,0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xDB,
  0xC0,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,0xCB,
  0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA,0xBB,
  0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xAB,
  0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,
  0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,
  0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,
  0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,
  0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,
  0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
}

local DS_FREQ = {
  [0]=2147483648, 2275179671, 2410468894, 2553802834,
  2705659852, 2866546760, 3037000500, 3217589947,
  3408917802, 3611622603, 3826380858, 4053909305,
}

-- Remove DC from the unipolar GBA PSG without the DMG capacitor's bass loss.
local GB_CLOCK = 4194304
local function hpf_charge()
  return math.exp(-2 * math.pi * 5 / Mix.SAMPLE_RATE)
end

local function midi_to_hz(key)
  key = tonumber(key) or 60
  return 440 * (2 ^ ((key - 69) / 12))
end

local function umul_hi32(a, b)
  -- high 32 bits of a*b for unsigned 32-bit operands (Lua number).
  a = tonumber(a) or 0
  b = tonumber(b) or 0
  if a < 0 then a = a + 4294967296 end
  if b < 0 then b = b + 4294967296 end
  return math.floor(a * b / 4294967296)
end

local function ds_scale_freq(key)
  key = math.floor(tonumber(key) or 60)
  if key < 0 then key = 0 end
  if key > 179 then key = 179 end
  local s = DS_SCALE[key] or 0
  return math.floor((DS_FREQ[s % 16] or 0) / (2 ^ math.floor(s / 16)))
end

--- pret MidiKeyToFreq returns playback Hz; only WaveData.freq is Q10.
function Mix.midiKeyToFreq(wavFreq, key, fine)
  wavFreq = tonumber(wavFreq) or 0
  key = math.floor(tonumber(key) or 60)
  fine = math.floor(tonumber(fine) or 0)
  if fine < 0 then fine = 0 end
  if fine > 255 then fine = 255 end
  if key > 178 then
    key = 178
    fine = 255
  end
  if key < 0 then key = 0 end
  local val1 = ds_scale_freq(key)
  local val2 = ds_scale_freq(key + 1)
  local delta = val2 - val1
  -- pret: umul3232H32(delta, fine<<24); fine<<24 = fine * 2^24
  local interp = umul_hi32(delta, fine * 16777216)
  return umul_hi32(wavFreq, val1 + interp)
end

--- pret MidiKeyToCgbFreq for pulse/wave → 11-bit-ish period register.
function Mix.cgbPeriod(key, fine, fixed)
  key = tonumber(key) or 60
  fine = math.floor(tonumber(fine) or 0)
  if fine < 0 then fine = 0 end
  if fine > 255 then fine = 255 end
  if key <= 35 then
    fine = 0
    key = 0
  else
    key = key - 36
    if key > 130 then
      key = 130
      fine = 255
    end
  end
  local s1 = CGB_SCALE[key] or 0
  local val1 = math.floor((CGB_FREQ[s1 % 16] or 0) / (2 ^ math.floor(s1 / 16)))
  local s2 = CGB_SCALE[key + 1] or s1
  local val2 = math.floor((CGB_FREQ[s2 % 16] or 0) / (2 ^ math.floor(s2 / 16)))
  local period = val1 + math.floor((fine * (val2 - val1)) / 256) + 2048
  -- CgbSound quantizes FIX tones to the 65536 Hz PWM grid in FireRed's mode.
  if fixed then period = math.floor((period + 1) / 2) * 2 % 2048 end
  return period
end

function Mix.cgbPulseHz(key, fine, fixed)
  local p = Mix.cgbPeriod(key, fine, fixed)
  local denom = 2048 - p
  if denom < 1 then denom = 1 end
  return 131072 / denom
end

-- Hardware wave clock is half of pulse → one octave lower for same period.
function Mix.cgbWaveHz(key, fine, fixed)
  return Mix.cgbPulseHz(key, fine, fixed) * 0.5
end

function Mix.periodToPulseHz(periodReg)
  local denom = 2048 - (tonumber(periodReg) or 0)
  if denom < 1 then denom = 1 end
  return 131072 / denom
end

function Mix.cgbNoiseNr43(key)
  key = tonumber(key) or 60
  if key <= 20 then
    key = 0
  else
    key = key - 21
    if key > 59 then key = 59 end
  end
  return NOISE_TABLE[key] or 0
end

--- Convert NR43-style noise control into LFSR step period at Mix.SAMPLE_RATE.
function Mix.cgbNoisePeriod(key)
  local nr43 = Mix.cgbNoiseNr43(key)
  local shift = math.floor(nr43 / 16) % 16
  local div = NOISE_DIV[nr43 % 8] or 8
  -- mGBA GB audio: divisor is already in 4 MHz clocks, not 524288 Hz units.
  return Mix.SAMPLE_RATE * div * (2 ^ shift) / GB_CLOCK
end

--- Attach MP2K ADSR. CGB uses 0..15 sustain; DS uses 0..255.
function Mix.attachAdsr(voice, tone, isCgb, opts)
  if not voice then return voice end
  tone = tone or {}
  opts = opts or {}
  voice.adsr = {
    attack = tonumber(tone.attack) or (isCgb and 0 or 255),
    decay = tonumber(tone.decay) or 0,
    sustain = tonumber(tone.sustain) or (isCgb and 15 or 255),
    release = tonumber(tone.release) or 0,
    isCgb = isCgb and true or false,
    pseudoEchoVolume = tonumber(opts.pseudoEchoVolume or tone.pseudoEchoVolume or 0) or 0,
    pseudoEchoLength = tonumber(opts.pseudoEchoLength or tone.pseudoEchoLength or 0) or 0,
  }
  voice.envPhase = "attack"
  voice.envVol = 0
  voice.env = 0
  return voice
end

local function finish_envelope(v, cgb)
  local a = v.adsr
  local echo = a.pseudoEchoVolume or 0
  if cgb then echo = math.floor(((v.envGoal or 0) * echo + 255) / 256) end
  v.envVol = echo
  if echo > 0 then
    v.envPhase = "echo"
  else
    v.alive = false
  end
end

-- pokefirered CgbModVol: PSG has routing bits and a 4-bit envelope, not
-- independent continuous left/right gains. Wave volume is quantized further.
function Mix.cgbVolume(v)
  local l = math.floor((v.volL or 0) * 256)
  local r = math.floor((v.volR or 0) * 256)
  v.routeL, v.routeR = true, true
  if r >= l and math.floor(r / 2) >= l then
    v.routeL = false
  elseif l > r and math.floor(l / 2) >= r then
    v.routeR = false
  end
  v.envGoal = math.min(15, math.floor((l + r) / 16))
  v.sustainGoal = math.floor((v.envGoal * v.adsr.sustain + 15) / 16)
end

local function cgb_decay(v)
  local a = v.adsr
  v.envVol = v.envGoal
  v.envPhase = "decay"
  v.envCounter = a.decay
  if a.decay == 0 then
    v.envVol = v.sustainGoal
    v.envPhase = "sustain"
    v.envCounter = 7
    if a.sustain == 0 then finish_envelope(v, true) end
  end
end

local function tick_cgb_envelope(v, extraClock)
  local a = v.adsr
  Mix.cgbVolume(v)
  if not v.envStarted then
    v.envStarted = true
    if v.released then v.alive = false; return end
    v.envCounter = a.attack
    if a.attack == 0 then cgb_decay(v) end
  elseif v.envPhase == "echo" then
    a.pseudoEchoLength = a.pseudoEchoLength - 1
    if a.pseudoEchoLength <= 0 then v.alive = false end
    return
  elseif v.released and v.envPhase ~= "release" then
    v.envPhase = "release"
    v.envCounter = a.release
    if a.release == 0 then finish_envelope(v, true) end
  else
    -- CgbSound counts down once per VBlank and twice every fifteenth frame.
    if (v.envCounter or 0) == 0 then
      if v.envPhase == "attack" then
        v.envVol = v.envVol + 1
        v.envCounter = a.attack
        if v.envVol >= v.envGoal then cgb_decay(v) end
      elseif v.envPhase == "decay" then
        v.envVol = v.envVol - 1
        v.envCounter = a.decay
        if v.envVol <= v.sustainGoal then
          v.envVol = v.sustainGoal
          v.envPhase = "sustain"
          v.envCounter = 7
          if a.sustain == 0 then finish_envelope(v, true) end
        end
      elseif v.envPhase == "sustain" then
        v.envVol = v.sustainGoal
        v.envCounter = 7
      elseif v.envPhase == "release" then
        v.envVol = v.envVol - 1
        v.envCounter = a.release
        if v.envVol <= 0 then finish_envelope(v, true) end
      end
    end
  end
  if v.alive and v.envPhase ~= "echo" then
    v.envCounter = math.max(0, (v.envCounter or 0) - 1)
    if extraClock then tick_cgb_envelope(v, false) end
  end
end

--- SoundMain envelope step, once per GBA frame regardless of song tempo.
function Mix.tickEnvelope(v, extraCgbClock)
  if not v or not v.alive then return end
  local a = v.adsr
  if not a then v.env = 1; return end
  if a.isCgb then
    tick_cgb_envelope(v, extraCgbClock)
    v.env = (v.envVol or 0) / 15
    return
  end
  if not v.envStarted then
    v.envStarted = true
    if v.released then v.alive = false; return end
  end
  local phase = v.envPhase
  if phase == "echo" then
    a.pseudoEchoLength = a.pseudoEchoLength - 1
    if a.pseudoEchoLength <= 0 then v.alive = false end
  elseif v.released then
    v.envPhase = "release"
    v.envVol = math.floor(v.envVol * a.release / 256)
    if v.envVol <= a.pseudoEchoVolume then finish_envelope(v, false) end
  elseif phase == "attack" then
    v.envVol = math.min(255, v.envVol + a.attack)
    if v.envVol == 255 then v.envPhase = "decay" end
  elseif phase == "decay" then
    v.envVol = math.floor(v.envVol * a.decay / 256)
    if v.envVol <= a.sustain then
      v.envVol = a.sustain
      v.envPhase = "sustain"
      if a.sustain == 0 then finish_envelope(v, false) end
    end
  end
  v.env = v.envVol / 255
end

function Mix.releaseVoice(v)
  if not v or v.released then return end
  v.released = true
  v.gateTicks = nil
  if not v.adsr then v.alive = false end
end

function Mix.newDsVoice(pcm, meta, opts)
  opts = opts or {}
  local rate = opts.rate or Mix.waveRate(meta and meta.freq)
  local v = {
    kind = "ds",
    pcm = pcm,
    pos = 0,
    size = meta and meta.size or #pcm,
    loopStart = (meta and meta.loopStart) or 0,
    loop = opts.loop and true or false,
    step = rate / Mix.SAMPLE_RATE,
    volL = opts.volL or 0.5,
    volR = opts.volR or 0.5,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, false) end
  return v
end

function Mix.waveRate(freqField)
  freqField = tonumber(freqField) or 0
  if freqField <= 0 then return Mix.GBA_MIX_RATE end
  local rate = math.floor(freqField / 1024 + 0.5)
  if rate < 500 then rate = Mix.GBA_MIX_RATE end
  if rate > 48000 then rate = 48000 end
  return rate
end

-- Hardware: 4 exclusive CGB channels (pulse1, pulse2, wave, noise).
Mix.MAX_DS_CHANNELS = 5

function Mix.newCgbPulse(opts)
  opts = opts or {}
  local key = opts.key or 60
  local fine = opts.fine or 0
  local fixed = opts.tone and math.floor((opts.tone.type or 0) / 8) % 2 == 1
  local periodReg = opts.periodReg or Mix.cgbPeriod(key, fine, fixed)
  local v = {
    kind = "cgb_pulse",
    cgbChan = opts.cgbChan or 1, -- 1 or 2
    cgbFixed = fixed,
    duty = opts.duty or 2,
    phase = 0,
    periodReg = periodReg,
    freq = opts.freq or Mix.periodToPulseHz(periodReg),
    volL = opts.volL or 0.4,
    volR = opts.volR or 0.4,
    env = opts.env or 1,
    alive = true,
  }
  -- Channel 1 only: ToneData.pan_sweep is NR10 when bit7 clear (pret ply_note).
  local panSweep = opts.tone and tonumber(opts.tone.pan) or 0
  if v.cgbChan == 1 and panSweep > 0 and math.floor(panSweep / 128) % 2 == 0 then
    local time = math.floor(panSweep / 16) % 8
    local shift = panSweep % 8
    if time > 0 or shift > 0 then
      v.sweepNr10 = panSweep % 128
      v.sweepShadow = periodReg
      v.sweepTimer = (time == 0) and 8 or time
      v.sweepAcc = 0
      v.sweepEnabled = true
    end
  end
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

function Mix.newCgbWave(opts)
  opts = opts or {}
  local wave = opts.wave or {}
  local key = opts.key or 60
  local fine = opts.fine or 0
  local fixed = opts.tone and math.floor((opts.tone.type or 0) / 8) % 2 == 1
  local v = {
    kind = "cgb_wave",
    cgbChan = 3,
    cgbFixed = fixed,
    wave = wave,
    phase = 0,
    freq = opts.freq or Mix.cgbWaveHz(key, fine, fixed),
    volL = opts.volL or 0.35,
    volR = opts.volR or 0.35,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

function Mix.newCgbNoise(opts)
  opts = opts or {}
  local v = {
    kind = "cgb_noise",
    cgbChan = 4,
    lfsr = 0x7FFF,
    shortNoise = opts.tone and (tonumber(opts.tone.wavParam) or 0) % 2 == 1,
    clock = 0,
    period = opts.period or Mix.cgbNoisePeriod(opts.key or 60),
    volL = opts.volL or 0.3,
    volR = opts.volR or 0.3,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

local function clip1(x)
  if x > 1 then return 1 end
  if x < -1 then return -1 end
  return x
end

local function s8_at(pcm, idx)
  local i = math.floor(idx)
  if i < 0 or i >= #pcm then return 0 end
  local b = pcm:byte(i + 1)
  return (b >= 128 and (b - 256) or b) / 128
end

--- Linear interpolate s8 PCM (reduces stair-step harshness on upsample).
local function s8_lerp(pcm, pos, size, loop, loopStart)
  if pos < 0 then return 0 end
  local i0 = math.floor(pos)
  if i0 >= size then return 0 end
  local frac = pos - i0
  local s0 = s8_at(pcm, i0)
  if frac < 1e-6 then return s0 end
  local i1 = i0 + 1
  if i1 >= size then
    if loop and loopStart and loopStart < size then
      i1 = loopStart
    else
      return s0
    end
  end
  local s1 = s8_at(pcm, i1)
  return s0 + (s1 - s0) * frac
end

-- GB channel-1 hardware sweep (~128 Hz clock).
local function tick_sweep_sample(v)
  if not v.sweepEnabled then return end
  local clocksPerSec = 128
  v.sweepAcc = (v.sweepAcc or 0) + clocksPerSec / Mix.SAMPLE_RATE
  while v.sweepAcc >= 1 do
    v.sweepAcc = v.sweepAcc - 1
    local nr10 = v.sweepNr10 or 0
    local time = math.floor(nr10 / 16) % 8
    if time == 0 then return end
    v.sweepTimer = (v.sweepTimer or time) - 1
    if v.sweepTimer > 0 then
      -- wait
    else
      v.sweepTimer = time
      local shift = nr10 % 8
      if shift == 0 then return end
      local shadow = v.sweepShadow or 0
      local delta = math.floor(shadow / (2 ^ shift))
      local negate = math.floor(nr10 / 8) % 2
      local newf = (negate == 1) and (shadow - delta) or (shadow + delta)
      if newf > 2047 or newf < 0 then
        v.alive = false
        return
      end
      v.sweepShadow = newf
      v.periodReg = newf
      v.freq = Mix.periodToPulseHz(newf)
    end
  end
end

local function render_voice(v, n, outL, outR)
  if not v or not v.alive then return end
  if v.lengthRemaining then
    n = math.min(n, math.max(0, math.ceil(v.lengthRemaining)))
    v.lengthRemaining = v.lengthRemaining - n
  end
  if v.kind == "ds" then
    local pcm = v.pcm
    local size = v.size or #pcm
    local loop = v.loop and true or false
    local loopStart = (v.loopStart and v.loopStart >= 0 and v.loopStart < size) and v.loopStart or 0
    local loopLen = size - loopStart
    local step = v.step or 1
    local pos = v.pos or 0
    -- SoundMain: masterVolume = 12, envelope gain = ((12 + 1) * env) >> 4.
    local e = math.floor(13 * (v.envVol or 255) / 16)
    local volL = math.floor((v.volL or 0.5) * e) / 256
    local volR = math.floor((v.volR or 0.5) * e) / 256
    for i = 1, n do
      if pos >= size then
        if loop and loopLen > 0 then
          pos = loopStart + ((pos - loopStart) % loopLen)
        else
          v.alive = false
          break
        end
      end
      local s = s8_lerp(pcm, pos, size, loop, loopStart)
      outL[i] = outL[i] + s * volL
      outR[i] = outR[i] + s * volR
      pos = pos + step
    end
    v.pos = pos
  elseif v.kind == "cgb_pulse" then
    local duty = DUTY[v.duty] or DUTY[2]
    local thresh, hi, lo = duty[1], duty[2], duty[3]
    for i = 1, n do
      tick_sweep_sample(v)
      if not v.alive then break end
      local inc = v.freq / Mix.SAMPLE_RATE
      local s = (v.phase < thresh) and hi or lo
      -- SOUNDCNT_L=0x77, PSG ratio=100%: one envelope unit is 16/512.
      s = (s + 1) * (v.envVol or 15) / 64
      if v.routeL ~= false then outL[i] = outL[i] + s end
      if v.routeR ~= false then outR[i] = outR[i] + s end
      v.phase = v.phase + inc
      v.phase = v.phase % 1
    end
  elseif v.kind == "cgb_wave" then
    local wave = v.wave
    local inc = v.freq / Mix.SAMPLE_RATE
    for i = 1, n do
      local idx = math.floor(v.phase * 32) % 32
      local nibble = wave[idx + 1] or 8
      -- gCgb3Vol: mute, 25%, 50%, 75%, 100% (hardware truncates nibbles).
      local level = v.envVol or 15
      local sample = 0
      if level >= 14 then sample = nibble
      elseif level >= 10 then sample = math.floor(nibble * 3 / 4)
      elseif level >= 6 then sample = math.floor(nibble / 2)
      elseif level >= 2 then sample = math.floor(nibble / 4) end
      local s = sample / 32
      if v.routeL ~= false then outL[i] = outL[i] + s end
      if v.routeR ~= false then outR[i] = outR[i] + s end
      v.phase = v.phase + inc
      v.phase = v.phase % 1
    end
  elseif v.kind == "cgb_noise" then
    for i = 1, n do
      v.clock = v.clock + 1
      while v.clock >= v.period do
        v.clock = v.clock - v.period
        local lo = v.lfsr % 2
        local hi = math.floor(v.lfsr / 2) % 2
        local bit = (lo == hi) and 0 or 1
        v.lfsr = math.floor(v.lfsr / 2) + bit * 0x4000
        if v.shortNoise then
          v.lfsr = v.lfsr - (math.floor(v.lfsr / 64) % 2) * 64 + bit * 64
        end
      end
      local s = ((v.lfsr % 2) == 0) and (v.envVol or 15) / 32 or 0
      if v.routeL ~= false then outL[i] = outL[i] + s end
      if v.routeR ~= false then outR[i] = outR[i] + s end
    end
  end
  if v.lengthRemaining and v.lengthRemaining <= 0 then v.alive = false end
end

-- SoundMainRAM feeds the sum of both PCM sides, from six and seven frames
-- ago, back into both sides at reverb/512. PSG never enters this buffer.
-- The delay is resampled to the host clock; native s8 wrapping is not modeled.
function Mix.newReverb(level, rate)
  local frame = (rate or Mix.SAMPLE_RATE) / Mix.GBA_VBLANK_HZ
  return {
    level = math.max(0, math.min(127, tonumber(level) or 0)),
    shortDelay = frame * 6,
    longDelay = frame * 7,
    size = math.ceil(frame * 7) + 1,
    cursor = 0, left = {}, right = {}, energy = 0,
  }
end

function Mix.reverbActive(state)
  return state and state.level > 0 and state.energy > 1e-8
end

local function reverb_tap(state, delay)
  local at = (state.cursor - delay) % state.size
  local i = math.floor(at)
  local frac = at - i
  local j = (i + 1) % state.size
  local a = (state.left[i] or 0) + (state.right[i] or 0)
  local b = (state.left[j] or 0) + (state.right[j] or 0)
  return a + (b - a) * frac
end

local function apply_reverb(state, left, right, n)
  if not state or state.level <= 0 then return end
  local gain = state.level / 512
  for i = 1, n do
    local echo = (reverb_tap(state, state.shortDelay)
      + reverb_tap(state, state.longDelay)) * gain
    local l, r = left[i] + echo, right[i] + echo
    local at = state.cursor
    local oldL, oldR = state.left[at] or 0, state.right[at] or 0
    state.energy = math.max(0, state.energy + l * l + r * r - oldL * oldL - oldR * oldR)
    state.left[at], state.right[at] = l, r
    state.cursor = (at + 1) % state.size
    left[i], right[i] = l, r
  end
end

function Mix.render(voices, n, opts)
  opts = opts or {}
  n = n or 1024
  local outL, outR = {}, {}
  for i = 1, n do outL[i] = 0; outR[i] = 0 end
  for _, v in ipairs(voices) do
    if v.kind == "ds" then render_voice(v, n, outL, outR) end
  end
  apply_reverb(opts.reverbState, outL, outR, n)
  for _, v in ipairs(voices) do
    if v.kind ~= "ds" then render_voice(v, n, outL, outR) end
  end
  local alive = {}
  for _, v in ipairs(voices) do
    if v.alive then alive[#alive + 1] = v end
  end

  -- DC blocker; state belongs to the rendered player slot.
  local master = opts.master or 1
  local charge = hpf_charge()
  local capL = opts.hpfCapL
  local capR = opts.hpfCapR
  if capL == nil then capL = Mix._hpfCapL or 0 end
  if capR == nil then capR = Mix._hpfCapR or 0 end
  for i = 1, n do
    local inl = outL[i] * master
    local inr = outR[i] * master
    local hpL = inl - capL
    capL = inl - hpL * charge
    local hpR = inr - capR
    capR = inr - hpR * charge
    outL[i] = hpL
    outR[i] = hpR
  end
  Mix._hpfCapL = capL
  Mix._hpfCapR = capR
  if opts.hpfState then
    opts.hpfState.l = capL
    opts.hpfState.r = capR
  end

  if opts.raw then
    return outL, outR, alive
  end
  if not (love and love.sound and love.sound.newSoundData) then
    return outL, alive
  end
  local ch = opts.mono and 1 or 2
  local rate = opts.sampleRate or Mix.SAMPLE_RATE
  local sd = love.sound.newSoundData(n, rate, 16, ch)
  -- Hard clip only. Soft clip (tanh) ducks every other voice whenever
  -- a loud hit (noise / stacked CGB) pushes the bus — sounds like channel dimming.
  for i = 1, n do
    local l = clip1(outL[i])
    local r = clip1(outR[i])
    if ch == 1 then
      sd:setSample(i - 1, (l + r) * 0.5)
    else
      sd:setSample(i - 1, 1, l)
      sd:setSample(i - 1, 2, r)
    end
  end
  return sd, alive
end

function Mix.midiToHz(key)
  return midi_to_hz(key)
end

return Mix
