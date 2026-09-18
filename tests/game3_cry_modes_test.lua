package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end

local function new_sd(n, rate, bits, ch)
  local sd = { n = n, rate = rate, ch = ch or 1, data = {} }
  function sd:setSample(i, a, b)
    if b == nil then self.data[i * self.ch + 1] = a else self.data[i * self.ch + a] = b end
  end
  function sd:getSample(i, c)
    return self.data[i * self.ch + (c or 1)] or 0
  end
  function sd:getSampleCount() return self.n end
  function sd:getChannelCount() return self.ch end
  return sd
end

local sources = {}
local function new_source(sd)
  local s = { sd = sd, volume = 1, playing = false, pos = 0, looping = false }
  function s:play() self.playing = true end
  function s:stop() self.playing = false end
  function s:isPlaying() return self.playing end
  function s:setVolume(v) self.volume = v end
  function s:getVolume() return self.volume end
  function s:setLooping(v) self.looping = v end
  function s:tell() return self.pos end
  function s:seek(p) self.pos = p end
  sources[#sources + 1] = s
  return s
end

love = {
  sound = { newSoundData = new_sd },
  audio = { newSource = new_source },
}

local Sample = require("src.core.game3.m4a_sample")
local Mix = require("src.core.game3.m4a_mix")
local Audio = require("src.core.game3.audio")

-- pokefirered/src/sound.c:374
local pret = {
  [0] = { 140, 0, 15360, 0, false, 120 },
  [1] = { 20, 225, 15360, 0, false, 120 },
  [2] = { 140, 225, 15600, 20, false, 90 },
  [3] = { 50, 200, 15800, 20, false, 90 },
  [4] = { 25, 100, 15600, 192, true, 90 },
  [5] = { 140, 200, 14440, 0, false, 120 },
  [6] = { 140, 220, 15555, 192, false, 90 },
  [7] = { 10, 100, 14848, 0, false, 120 },
  [8] = { 60, 225, 15616, 0, false, 120 },
  [9] = { 15, 125, 15200, 0, true, 120 },
  [10] = { 100, 225, 15200, 0, false, 120 },
  [11] = { 140, 0, 15000, 0, false, 120 },
  [12] = { 20, 225, 15000, 0, false, 120 },
}
for mode = 0, 12 do
  local p = Sample.cryParams(mode)
  local e = pret[mode]
  check(p.mode == mode, "mode " .. mode .. " id")
  check(p.length == e[1], "mode " .. mode .. " length")
  check(p.release == e[2], "mode " .. mode .. " release")
  check(p.pitch == e[3], "mode " .. mode .. " pitch")
  check(p.chorus == e[4], "mode " .. mode .. " chorus")
  check(p.reverse == e[5], "mode " .. mode .. " reverse")
  check(p.volume == e[6], "mode " .. mode .. " volume")
end
check(Sample.cryParams(99).mode == 0, "unknown mode falls back to normal")
check(Sample.cryParams(0, 125).volume == 125, "caller volume for normal")
check(Sample.cryParams(3, 125).volume == 90, "mode volume overrides caller")

do
  local k, t = Sample.cryKeyTune(15360)
  check(k == 60 and t == 64, "15360 key/tune")
  check(near(Sample.cryRateMul(k, t), 1.0), "15360 rate 1.0")
  k, t = Sample.cryKeyTune(15800)
  check(k == 62 and t == 28, "15800 key/tune")
  check(near(Sample.cryRateMul(k, t), 2 ^ (92 / 768)), "15800 rate")
  k, t = Sample.cryKeyTune(14440)
  check(k == 56 and t == 116, "14440 key/tune")
  check(near(Sample.cryRateMul(k, t), 2 ^ (-204 / 768)), "14440 rate")
  check(Sample.cryChorusTune(20, 28) == 48, "chorus +20")
  check(Sample.cryChorusTune(192, 56) == 120, "chorus 192 wraps as s8 -64")
end

do
  local env = Sample.cryEnvelope(20, 225)
  check(env.gain(0) == 1 and env.gain(19) == 1, "held for length")
  check(near(env.gain(20), math.floor(255 * 225 / 256) / 255), "first release step")
  local prev = 1
  local mono = true
  for f = 20, env.endFrame - 1 do
    local g = env.gain(f)
    if not (g < prev and g > 0) then mono = false end
    prev = g
  end
  check(mono, "release decays monotonically")
  check(env.gain(env.endFrame) == 0, "release reaches zero")
  check(env.endFrame > 20 and env.endFrame < 80, "release tail length")
  local cut = Sample.cryEnvelope(140, 0)
  check(cut.endFrame == 140 and cut.gain(140) == 0, "release 0 cuts at length")
end

for mode = 0, 12 do
  local v = Sample.cryVoices(Sample.cryParams(mode))
  local want = (mode == 2 or mode == 3 or mode == 4 or mode == 6) and 2 or 1
  check(#v == want, "mode " .. mode .. " voice count")
end

local ramp = {}
for i = 0, 99 do ramp[#ramp + 1] = string.char(i) end
ramp = table.concat(ramp)

do
  local base = { length = 140, release = 0, pitch = 15360, chorus = 0, reverse = false, volume = 127 }
  local fwd = Sample.renderCryMix(ramp, 1000, base, { outRate = 1000 })
  local rp = { length = 140, release = 0, pitch = 15360, chorus = 0, reverse = true, volume = 127 }
  local rev = Sample.renderCryMix(ramp, 1000, rp, { outRate = 1000 })
  check(#fwd == 100 and #rev == 100, "render length at native rate")
  check(near(fwd[1], 0) and near(fwd[100], 99 / 128), "forward order")
  check(near(rev[1], 99 / 128) and near(rev[100], 0), "reverse order")
  local vp = { length = 140, release = 0, pitch = 15360, chorus = 0, reverse = false, volume = 90 }
  local vol = Sample.renderCryMix(ramp, 1000, vp, { outRate = 1000 })
  check(near(vol[51], (50 / 128) * 90 / 127), "volume scales by vol/127")
end

do
  local long = string.rep(string.char(64), 30000)
  local p = { length = 20, release = 225, pitch = 15360, chorus = 0, reverse = false, volume = 127 }
  local out, info = Sample.renderCryMix(long, 10000, p, { outRate = 10000 })
  local env = Sample.cryEnvelope(20, 225)
  check(info.frames == env.endFrame, "doubles length is envelope-bound")
  local fr = Sample.GBA_FRAME_RATE
  local s19 = math.floor(19.5 * 10000 / fr)
  local s25 = math.floor(25.5 * 10000 / fr)
  check(near(out[s19 + 1], 0.5), "held at full before length")
  check(near(out[s25 + 1], 0.5 * env.gain(25)), "release gain applied")
  check(#out <= math.ceil(env.endFrame * 10000 / fr), "buffer ends with the tail")
  local short = string.rep(string.char(64), 1000)
  local n = { length = 140, release = 0, pitch = 15360, chorus = 0, reverse = false, volume = 127 }
  local _, i2 = Sample.renderCryMix(short, 10000, n, { outRate = 10000 })
  check(i2.frames == math.ceil(1000 / 10000 * fr), "short cry ends at sample end")
end

do
  local p = Sample.cryParams(3)
  local one = Sample.renderCryMix(string.rep(string.char(32), 4000), 8000,
    { length = p.length, release = p.release, pitch = p.pitch, chorus = 0, reverse = false, volume = 90 },
    { outRate = 8000 })
  local two = Sample.renderCryMix(string.rep(string.char(32), 4000), 8000, p, { outRate = 8000 })
  check(near(two[10], one[10] * 2, 1e-9), "chorus mixes a second voice at the same volume")
end

do
  local pcm = string.rep(string.char(40), 20000)
  Audio._pack = {
    index = { cryIds = { [25] = 0 }, cries = { [0] = { sampleId = 1 } } },
    samples = { [1] = { offset = 0, size = #pcm, freq = 10000 * 1024 } },
    samplesBin = pcm,
  }
  Audio._ready = true
  Audio._cryClock = 0
  sources = {}
  Audio.playCry(25, 1, 0x3F)
  local src = sources[#sources]
  check(src and src.playing, "cry source plays")
  check(src and src.sd.ch == 2, "panned cry is stereo")
  check(Audio._duck == 1, "doubles does not duck")
  check(Audio._cryUntil == Sample.cryEnvelope(20, 225).endFrame, "cryUntil = length + release")
  Audio.stopCry()
  Audio.playCry(25, { mode = 3, pan = -64 })
  check(Audio._cryParams.mode == 3 and Audio._cryParams.pitch == 15800, "table-form mode")
  check(Audio._duck < 1, "non-doubles ducks BGM")
  check(sources[#sources].sd.ch == 2, "table-form pan")
  Audio._cryClock = Audio._cryUntil
  check(Audio.isCryFinished(), "cry finishes on the rendered length")
  Audio.stopCry()
  Audio._pack = nil
  Audio._ready = false
end

do
  sources = {}
  local L, R = {}, {}
  for i = 1, 100 do L[i] = 0.5; R[i] = 0.5 end
  local sd = Audio._buildSeSoundData(L, R, 1, 0, false)
  local old = new_source(sd)
  old:play()
  old.pos = 40
  Audio._seSources = { old }
  Audio._seByPlayer = { [1] = old }
  Audio._seMeta = { [old] = { id = 5, player = 1, rawL = L, rawR = R, master = 1, pan = 0, mono = false, loop = false } }
  Audio.setSePan(63)
  local src = Audio._seByPlayer[1]
  check(src ~= old and not old.playing and src.playing, "setSePan swaps the playing SE")
  check(src.pos == 40, "setSePan keeps playback position")
  check(Audio._seSources[1] == src and Audio._seMeta[src].pan == 63, "setSePan updates bookkeeping")
  check(near(src.sd:getSample(10, 1), 0.5 / 64) and near(src.sd:getSample(10, 2), 0.5), "pan 63 attenuates left")
  Audio.setSePan(-64)
  src = Audio._seByPlayer[1]
  check(near(src.sd:getSample(10, 1), 0.5) and near(src.sd:getSample(10, 2), 0), "pan -64 silences right")
  check(Audio._seMeta[src].pan == -64, "pan recorded")
  Audio._seSources, Audio._seByPlayer, Audio._seMeta = {}, {}, {}
end

print(string.format("game3_cry_modes_test: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
