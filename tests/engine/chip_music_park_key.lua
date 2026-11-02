package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")
local ffi = require("ffi")

local SoundData = {}
SoundData.__index = SoundData
function SoundData:setSample(index, a, b)
  if b == nil then self.buf[index * self.channels] = a * 32767
  else self.buf[index * self.channels + (a - 1)] = b * 32767 end
end
function SoundData:getFFIPointer() return self.buf end
function SoundData:getBitDepth() return 16 end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getChannelCount() return self.channels end
function SoundData:bytes()
  return ffi.string(self.buf, self.samples * self.channels * 2)
end
love.sound.newSoundData = function(samples, rate, _, channels)
  return setmetatable({ samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels) }, SoundData)
end

local ChipSynth = require("src.core.ChipSynth")
local BUFFERS = ChipSynth.MUSIC_BUFFER_COUNT

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setVolume() end
function Source:setPitch() end
function Source:setLooping() end
function Source:setFilter() end
function Source:getDuration() return 1 end
function Source:getFreeBufferCount() return BUFFERS - #self.queued end
function Source:queue(sd)
  if #self.queued >= BUFFERS then error("source full") end
  self.queued[#self.queued + 1] = sd
  self.log[#self.log + 1] = sd
end
function Source:consume(n)
  for _ = 1, math.min(n, #self.queued) do table.remove(self.queued, 1) end
end

local sources = {}
love.audio = {
  newSource = function(sd) return setmetatable({ sd = sd }, Source) end,
  newQueueableSource = function()
    local src = setmetatable({ queued = {}, log = {}, playing = false },
                             Source)
    sources[#sources + 1] = src
    return src
  end,
}

local channels = {}
local sent = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  local items = {}
  ch = {}
  function ch:push(v)
    if name == "chipaudio_cmd" and type(v) == "table" then
      sent[#sent + 1] = v
    end
    items[#items + 1] = v
  end
  function ch:pop() return table.remove(items, 1) end
  function ch:demand()
    if #items == 0 then coroutine.yield("idle") end
    return table.remove(items, 1)
  end
  function ch:clear() for i = #items, 1, -1 do items[i] = nil end end
  function ch:getCount() return #items end
  channels[name] = ch
  return ch
end

love.timer.sleep = function(seconds) coroutine.yield(seconds) end
for _, mod in ipairs({ "love.thread", "love.timer", "love.sound",
                       "love.filesystem" }) do
  package.preload[mod] = function() return true end
end
local realLoad = love.filesystem.load
love.filesystem.load = function(path)
  if path == "src/core/ChipSynth.lua" or path == "src/core/WorkerFs.lua" then
    return loadfile(path)
  end
  return realLoad(path)
end

local co, workerError
love.thread = {
  newThread = function(path)
    return {
      start = function() co = coroutine.create(assert(loadfile(path))) end,
      getError = function() return workerError end,
      wait = function() end,
    }
  end,
  getChannel = channel,
}

local function runWorker()
  if not co or coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then workerError = err end
end

local ChipAudio = require("src.core.ChipAudio")
local ChipAsm = require("src.audio.ChipAsm")

local function song(octave, note2)
  return ChipAsm.song{ channels = {
    { hw = 1, program = {
      { notetype = { speed = 12, volume = 12, fade = 0 } },
      { octave = octave },
      { note = "C", len = 4 }, { note = "E", len = 4 }, { note = "G", len = 8 },
      { loop = { count = 0, to = 1 } },
    } },
    { hw = 2, program = {
      { notetype = { speed = 6, volume = 10, fade = 2 } },
      { octave = octave - 1 },
      { note = note2, len = 6 }, { note = "A", len = 2 },
      { loop = { count = 0, to = 1 } },
    } },
  } }
end

local data = { audio = {} }
local route = song(3, "D")
local theme = song(4, "F")

local function settle(frames)
  for _ = 1, frames or 4 do
    runWorker()
    ChipAudio.update()
  end
end

local function current() return sources[#sources] end

local function startRoute()
  check(ChipAudio.playMusic(data, route, true) ~= nil, "route song plays")
  for _ = 1, 20 do
    settle(1)
    current():consume(2)
  end
  settle(4)
end

local function lastSent(cmd)
  for i = #sent, 1, -1 do
    if sent[i].cmd == cmd then return sent[i] end
  end
end

local function reference(header, count)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  local out = {}
  for i = 1, count do
    out[i] = ChipSynth.soundData(engine, ChipSynth.MUSIC_BUFFER_SAMPLES, 2)
      :bytes()
  end
  return out
end

local function sameStream(src, header, count, label)
  local ref = reference(header, count)
  local same = #src.log >= count
  for i = 1, count do
    if not (src.log[i] and src.log[i]:bytes() == ref[i]) then
      same = false
    end
  end
  check(same, label)
end

local PREROLL = ChipAudio.MUSIC_PREROLL

startRoute()
check(ChipAudio.prepareMusic(data, theme, true),
  "prepareMusic accepts a looping chip song")
settle(4)
local ps = ChipAudio.parkState()
check(ps ~= nil and ps.ready and ps.buffers == PREROLL,
  "the worker parks the theme's first " .. PREROLL .. " buffers")
check(ChipAudio.prepareMusic(data, theme, true),
  "a second hint for the same song is accepted")
eq(ChipAudio.parkState().serial, ps.serial, "and does not re-render it")
for _ = 1, 6 do
  current():consume(3)
  settle(1)
end
local hits = ChipAudio.stats().parkHits
check(ChipAudio.playMusic(data, theme, true) ~= nil, "battle theme cued")
local battle = current()
eq(#battle.log, PREROLL, "the cue queues the parked preroll on the spot")
eq(ChipAudio.stats().parkHits, hits + 1, "and counts a park hit")
eq(lastSent("play").parkSkip, PREROLL, "the worker is told to adopt the park")
check(ChipAudio.parkState() == nil, "a used park is gone")
for _ = 1, 4 do
  settle(1)
  battle:consume(2)
end
check(battle.playing, "the parked theme is playing")
sameStream(battle, theme, PREROLL * 3,
  "parked preroll plus the adopted engine's stream equals a fresh render")

startRoute()
ChipAudio.prepareMusic(data, theme, true)
settle(4)
check(ChipAudio.parkState().ready, "re-hint parks again")
channel("chipaudio_cmd"):push({ cmd = "unpark" })
settle(2)
hits = ChipAudio.stats().parkHits
ChipAudio.playMusic(data, theme, true)
eq(ChipAudio.stats().parkHits, hits + 1,
  "the main thread still hands over its parked buffers")
for _ = 1, 4 do
  settle(1)
  current():consume(2)
end
sameStream(current(), theme, PREROLL * 3,
  "a worker that lost its park fast-forwards and the stream stays seamless")

local function parkReady()
  ChipAudio.prepareMusic(data, theme, true)
  settle(4)
  local state = ChipAudio.parkState()
  return state ~= nil and state.ready
end

local function missesAfter(label, mutate, restore)
  startRoute()
  check(parkReady(), "parked before " .. label)
  mutate()
  local dropped = ChipAudio.parkState() == nil
  hits = ChipAudio.stats().parkHits
  ChipAudio.playMusic(data, theme, true)
  check(dropped, label .. " drops the park")
  eq(ChipAudio.stats().parkHits, hits, label .. ": the cue does not use it")
  eq(lastSent("play").parkSkip, nil,
    label .. ": the worker builds a fresh engine")
  if restore then restore() end
end

missesAfter("a channel volume change", function()
  ChipAudio.setChannelVolume(2, 0.5)
end, function() ChipAudio.setChannelVolume(2, 1) end)
missesAfter("a channel pitch change", function()
  ChipAudio.setChannelPitch(1, 2)
end, function() ChipAudio.setChannelPitch(1, 1) end)
missesAfter("a SOUND toggle", function()
  ChipAudio.setStereo(true)
end, function() ChipAudio.setStereo(false) end)
missesAfter("a sample rate change", function()
  ChipAudio.setSampleRate(22050)
end, function() ChipAudio.setSampleRate(44100) end)
missesAfter("a hot reload", function()
  ChipAudio.invalidate()
end)

startRoute()
check(parkReady(), "parked before a tempo variant")
local slowed = {}
for key, value in pairs(theme) do slowed[key] = value end
slowed.tempo = 0x200
hits = ChipAudio.stats().parkHits
ChipAudio.playMusic(data, slowed, true)
eq(ChipAudio.stats().parkHits, hits, "a tempo variant never takes the park")
check(ChipAudio.parkState() ~= nil, "and leaves it for the real cue")

ChipAudio.stopMusic()
check(ChipAudio.parkState() ~= nil, "stopMusic keeps the park")
hits = ChipAudio.stats().parkHits
ChipAudio.playMusic(data, theme, true)
eq(ChipAudio.stats().parkHits, hits + 1,
  "so a stop before the cue still finds it")

startRoute()
check(not ChipAudio.prepareMusic(data, theme, false),
  "a one-shot song is never parked")
eq(lastSent("park") and lastSent("park").allowLoops, true,
  "every park request is for a looping song")

local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local gen1 = { audio = {
  songs = { Music_Routes1 = route, Music_WildBattle = theme },
  mapSongs = { ROUTE_1 = "Music_Routes1" },
  battle = { wild = "Music_WildBattle" },
} }
local function walkMusic()
  for _ = 1, 20 do
    settle(1)
    current():consume(2)
  end
  settle(4)
end
local parks = #sent
Music.playMap(gen1, "ROUTE_1")
walkMusic()
ps = ChipAudio.parkState()
check(ps ~= nil and ps.ready, "a Gen 1 map theme parks the wild battle theme")
check(#sent > parks and lastSent("park").header == theme,
  "the park is the kind default Music.playBattle would cue")
hits = ChipAudio.stats().parkHits
Music.playBattle(gen1, "wild")
eq(ChipAudio.stats().parkHits, hits + 1, "the wild battle cue takes it")
eq(#current().log, PREROLL, "with its preroll queued on the cue frame")
walkMusic()
Music.restoreMap(gen1)
walkMusic()
check(ChipAudio.parkState() ~= nil and ChipAudio.parkState().ready,
  "the map restore after a battle parks the theme again")

local OW = require("src.world.OverworldController")
local BattleState = require("src.battle.BattleState")
local themes = { trainer = song(4, "G"), gym = song(5, "A"),
  final = song(5, "C"), mod = song(2, "B") }
gen1.audio.songs.Music_TrainerBattle = themes.trainer
gen1.audio.songs.Music_GymLeaderBattle = themes.gym
gen1.audio.songs.Music_FinalBattle = themes.final
gen1.audio.songs.Music_ModTheme = themes.mod
gen1.audio.songs.Music_MeetMaleTrainer = song(3, "E")
gen1.audio.battle.trainer = "Music_TrainerBattle"
gen1.audio.battle.gym = "Music_GymLeaderBattle"
gen1.audio.battle.final = "Music_FinalBattle"
gen1.trainers = {}
for _, cls in ipairs({ "OPP_YOUNGSTER", "OPP_BROCK", "OPP_LANCE",
    "OPP_RIVAL3", "OPP_GIOVANNI" }) do
  gen1.trainers[cls] = { id = cls }
end
gen1.trainers.OPP_BUG_CATCHER = { id = "OPP_BUG_CATCHER",
  battleTheme = "Music_ModTheme" }

local function trainerCase(cls, partyIndex, want, label)
  Music.stop()
  Music.playMap(gen1, "ROUTE_1")
  walkMusic()
  Music.play(gen1, "Music_MeetMaleTrainer")
  walkMusic()
  local ok = OW.prepareTrainerBattleMusic
    and OW.prepareTrainerBattleMusic(gen1, cls, partyIndex)
  walkMusic()
  check(ok, label .. ": the sighting parks a battle theme")
  local state = ChipAudio.parkState()
  check(state ~= nil and state.ready, label .. ": the park is ready")
  check(lastSent("park") and lastSent("park").header == themes[want],
    label .. ": the park is the " .. want .. " theme")
  local before = ChipAudio.stats().parkHits
  local battle = setmetatable({ data = gen1, kind = "trainer",
    oppClass = cls, partyIndex = partyIndex,
    trainer = gen1.trainers[cls] }, BattleState)
  battle:playBattleTheme()
  eq(ChipAudio.stats().parkHits, before + 1,
    label .. ": the battle cue takes the park")
  eq(#current().log, PREROLL, label .. ": with its preroll queued on the cue")
  walkMusic()
end

trainerCase("OPP_YOUNGSTER", 1, "trainer", "a Youngster")
trainerCase("OPP_BROCK", 1, "gym", "Brock")
trainerCase("OPP_LANCE", 1, "gym", "Lance")
trainerCase("OPP_RIVAL3", 1, "final", "the Champion")
trainerCase("OPP_GIOVANNI", 2, "trainer", "Giovanni in Silph Co")
trainerCase("OPP_GIOVANNI", 3, "gym", "Giovanni in his gym")
trainerCase("OPP_BUG_CATCHER", 1, "mod", "a mod-set trainer theme")

Music.stop()
Music.playMap(gen1, "ROUTE_1")
walkMusic()
OW.prepareTrainerBattleMusic(gen1, "OPP_YOUNGSTER", 1)
hits = ChipAudio.stats().parkHits
Music.playBattle(gen1, "gym")
eq(ChipAudio.stats().parkHits, hits, "a gym cue never takes a trainer park")
eq(#current().log, 0, "and starts from a fresh engine")
check(ChipAudio.parkState() ~= nil,
  "the unmatched trainer park stays for its own cue")
walkMusic()
Music.stop()
Music.playMap(gen1, "ROUTE_1")
OW.prepareTrainerBattleMusic(gen1, "OPP_YOUNGSTER", 1)
Music.playBattle(gen1, "trainer")
check(ChipAudio.parkState() == nil,
  "a cue that beats its own park to the worker drops it")
walkMusic()

local realWants = Runtime.wantsHook
Runtime.wantsHook = function(name) return name == "music.select" end
ChipAudio.invalidate()
Music.stop()
Music.playMap(gen1, "ROUTE_1")
walkMusic()
check(ChipAudio.parkState() == nil, "a music.select hook disables parking")
Runtime.wantsHook = realWants

local gen2 = { audio = {
  generation = 2,
  songs = { Music_JohtoWildBattle = theme },
  mapSongs = {},
  battle = { wild = "Music_JohtoWildBattle" },
} }
ChipAudio.invalidate()
Music.stop()
startRoute()
local before = lastSent("park")
Music.playMap(gen2, "ROUTE_29")
settle(4)
check(ChipAudio.parkState() == nil and lastSent("park") == before,
  "Gen 2 leaves the hint to the world's own battle-song choice")
check(Music.prepare(gen2, "Music_JohtoWildBattle"),
  "Music.prepare parks a label the caller picked")

check(workerError == nil, "worker ran clean: " .. tostring(workerError))
ChipAudio.shutdown()
T.finish("chip music park key")
