package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local rates = {}

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setLooping(v) self.looping = v end
function Source:setVolume(v) self.volume = v end
function Source:setPitch(v) self.pitch = v end
function Source:setFilter() end
function Source:getDuration() return 1 end
function Source:getFreeBufferCount() return self.free end
function Source:queue() self.free = math.max(0, self.free - 1) end

local ChipSynth = require("src.core.ChipSynth")
local BUFFERS = ChipSynth.MUSIC_BUFFER_COUNT

love.audio = {
  newSource = function(what, mode)
    return setmetatable({ file = what, mode = mode, free = 0 }, Source)
  end,
  newQueueableSource = function(rate)
    rates[#rates + 1] = rate
    return setmetatable({ queueable = true, rate = rate, free = BUFFERS },
                        Source)
  end,
}

local channels = {}
local Channel = {}
Channel.__index = Channel
function Channel:push(msg) self.queue[#self.queue + 1] = msg end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end
function Channel:getCount() return #self.queue end

local function channel(name)
  channels[name] = channels[name] or setmetatable({ queue = {} }, Channel)
  return channels[name]
end

love.thread = {
  newThread = function()
    return { start = function() end, getError = function() return nil end,
             wait = function() end }
  end,
  getChannel = channel,
}

local ChipAudio = require("src.core.ChipAudio")

local BASE = ChipSynth.SAMPLE_RATE
eq(BASE, 44100, "the default synth rate is 44100")

eq(ChipSynth.setSampleRate(22050), 22050, "setSampleRate returns the new rate")
eq(ChipSynth.SAMPLE_RATE, 22050, "and republishes it on the module")
eq(ChipSynth.setSampleRate(100), 8000, "a silly low rate clamps to 8000")
eq(ChipSynth.setSampleRate(192000), 48000, "and a silly high one to 48000")
eq(ChipSynth.setSampleRate("not a number"), 48000,
   "garbage leaves the live rate alone")

local ChipAsm = require("src.audio.ChipAsm")
local song = ChipAsm.song{
  channels = { { hw = 1, program = {
    { notetype = { speed = 12, volume = 12, fade = 0 } },
    { octave = 4 },
    { note = "C", len = 8 },
    { loop = { count = 0, to = 1 } },
  } } },
}
local data = { audio = { songs = { Music_PalletTown = song } } }

local function firstEventSamples()
  local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
  engine.channels[1]:sample()
  return engine.channels[1].event.samples
end

ChipSynth.setSampleRate(44100)
local full = firstEventSamples()
ChipSynth.setSampleRate(22050)
local half = firstEventSamples()
check(full > 0, "the fixture note occupies real samples at 44100")
eq(half, math.floor(full / 2),
   "halving the rate halves the note's sample budget")

rates = {}
ChipSynth.setSampleRate(22050)
check(ChipAudio.playMusic(data, song, true) ~= nil,
      "threaded playMusic built a source")
eq(rates[#rates], 22050, "the QueueableSource is built at the live rate")

local pushed
for _, msg in ipairs(channel("chipaudio_cmd").queue) do
  if type(msg) == "table" and msg.cmd == "play" then pushed = msg end
end
check(pushed ~= nil, "the worker got a play command")
eq(pushed.sampleRate, 22050,
   "and it carries the rate, so the worker's own Lua state matches")

rates = {}
check(ChipAudio.rebuildPlayback(), "rebuildPlayback rebuilt the source")
eq(rates[#rates], 22050, "a device-reset rebuild uses the live rate too")

rates = {}
ChipAudio.setStereo(true)
eq(rates[#rates], 22050, "and so does the SOUND-toggle source swap")
ChipAudio.setStereo(false)

ChipAudio.stopMusic()

local realOS = love.system.getOS
local function withOS(name, fn)
  love.system.getOS = function() return name end
  local ok, err = pcall(fn)
  love.system.getOS = realOS
  if not ok then error(err, 0) end
end

ChipAudio._setEnvRateForTest(nil)
withOS("OS X", function()
  eq(ChipAudio.selectSampleRate({ performance = "high" }), 44100,
     "a HIGH desktop keeps the full rate")
  eq(ChipAudio.selectSampleRate({ performance = "low" }), 22050,
     "the LOW tier halves it on any platform")
end)
withOS("Android", function()
  eq(ChipAudio.selectSampleRate({ performance = "balanced" }), 22050,
     "Android at its default BALANCED tier halves it")
  eq(ChipAudio.selectSampleRate({ performance = "high" }), 44100,
     "an Android user who picked HIGH gets the full rate back")
end)
withOS("NX", function()
  eq(ChipAudio.selectSampleRate({ performance = "auto" }), 22050,
     "a Switch at AUTO halves it")
  eq(ChipAudio.selectSampleRate({}), 22050,
     "and so does a Switch with no stored tier")
  eq(ChipAudio.selectSampleRate({ performance = "balanced" }), 22050,
     "and at BALANCED")
  eq(ChipAudio.selectSampleRate({ performance = "high" }), 44100,
     "a Switch user who picked HIGH gets the full rate back")
end)

ChipAudio._setEnvRateForTest("32000")
withOS("Android", function()
  eq(ChipAudio.selectSampleRate({ performance = "balanced" }), 32000,
     "POKEPORT_AUDIO_RATE wins over the platform default")
end)
ChipAudio._setEnvRateForTest("nonsense")
withOS("Android", function()
  eq(ChipAudio.selectSampleRate({ performance = "balanced" }), 22050,
     "an unparseable POKEPORT_AUDIO_RATE is ignored")
end)
ChipAudio._setEnvRateForTest(nil)

ChipSynth.setSampleRate(44100)
withOS("Android", function()
  check(ChipAudio.applyOptions({ performance = "balanced" }),
        "applyOptions reports the rate moved")
  eq(ChipSynth.SAMPLE_RATE, 22050, "and applied it")
  check(not ChipAudio.applyOptions({ performance = "balanced" }),
        "a second pass with the same options is a no-op")
end)

ChipSynth.setSampleRate(BASE)

T.finish("chip sample rate")
