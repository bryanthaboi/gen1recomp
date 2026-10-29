package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("chip music start vs prewarm 3065")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
local ffi = require("ffi")

local SCALE = 10
local MUSIC_MS = 12.9
local FRAME = 1 / 60

local now, wnow, inWorker = 0, 0, false
love.timer.getTime = function() return inWorker and wnow or now end
love.timer.sleep = function(seconds) coroutine.yield(seconds) end

local SoundData = {}
SoundData.__index = SoundData
function SoundData:setSample(index, a, b)
  if b == nil then self.buf[index * self.channels] = a * 32767
  else self.buf[index * self.channels + (a - 1)] = b * 32767 end
end
function SoundData:getFFIPointer() return self.buf end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getChannelCount() return self.channels end
love.sound.newSoundData = function(samples, rate, _, channels)
  return setmetatable({ samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels) }, SoundData)
end

local ChipSynth = require("src.core.ChipSynth")
local BUFFERS = ChipSynth.MUSIC_BUFFER_COUNT
local BUF_SECONDS = ChipSynth.MUSIC_BUFFER_SAMPLES / ChipSynth.SAMPLE_RATE

local queueables = {}
local Source = {}
Source.__index = Source
function Source:play()
  if not self.playing and not self.firstPlay then self.firstPlay = now end
  self.playing = true
end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setVolume() end
function Source:setPitch() end
function Source:getPitch() return 1 end
function Source:setLooping() end
function Source:getDuration() return 1 end
function Source:getFreeBufferCount() return BUFFERS - self.queued end
function Source:queue()
  if self.queued >= BUFFERS then error("source full") end
  self.queued = self.queued + 1
  if not self.firstQueue then self.firstQueue = now end
end
function Source:advance(dt)
  while self.playing and dt > 0 do
    if self.queued == 0 then
      self.playing = false
      self.underruns[#self.underruns + 1] = now
      return
    end
    if self.head <= 0 then self.head = BUF_SECONDS end
    local take = math.min(dt, self.head)
    self.head = self.head - take
    dt = dt - take
    if self.head <= 0 then self.queued = self.queued - 1 end
  end
end

love.audio = {
  newSource = function(sd) return setmetatable({ sd = sd }, Source) end,
  newQueueableSource = function()
    local src = setmetatable({ queued = 0, head = 0, playing = false,
      underruns = {} }, Source)
    queueables[#queueables + 1] = src
    return src
  end,
}

local costOf = {}
local leadHeaders = {}
local pushes = {}
local renders = {}
local workerMusic = 0
local workerSongs = 0
local playsPushed = 0

local channels = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  local items = {}
  ch = { items = items }
  function ch:push(v)
    if name == "chipaudio_cmd" and type(v) == "table" then
      if v.cmd == "play" then playsPushed = playsPushed + 1 end
      if v.cmd == "effect" then
        pushes[#pushes + 1] = { t = now, lead = leadHeaders[v.header] or false,
                                plays = playsPushed }
      end
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

local function noop() end
local WorkerSynth = {
  MUSIC_BUFFER_SAMPLES = ChipSynth.MUSIC_BUFFER_SAMPLES,
  SAMPLE_RATE = ChipSynth.SAMPLE_RATE,
  setSampleRate = function() return ChipSynth.SAMPLE_RATE end,
  setChannelVolumes = noop, setChannelPitches = noop, setStereo = noop,
  applyStereo = noop, invalidateBanks = noop,
  newEngine = function()
    workerMusic = 0
    workerSongs = workerSongs + 1
    return { finished = function() return false end }
  end,
  soundData = function()
    coroutine.yield(MUSIC_MS * SCALE / 1000)
    workerMusic = workerMusic + 1
    return { music = true }
  end,
  renderEffectData = function(_, header)
    renders[#renders + 1] = { lead = leadHeaders[header] or false,
                              musicBefore = workerMusic, song = workerSongs }
    coroutine.yield((costOf[header] or 5) * SCALE / 1000)
    return { fx = true }
  end,
}

local realLoad = love.filesystem.load
love.filesystem.load = function(path)
  if path == "src/core/ChipSynth.lua" then
    return function() return WorkerSynth end
  end
  if path == "src/core/WorkerFs.lua" then return loadfile(path) end
  return realLoad(path)
end
for _, mod in ipairs({ "love.thread", "love.timer", "love.sound",
                       "love.filesystem" }) do
  package.preload[mod] = function() return true end
end

local co, workerError
love.thread = {
  newThread = function(path)
    return {
      start = function()
        co = coroutine.create(assert(loadfile(path)))
      end,
      getError = function() return workerError end,
      wait = noop,
    }
  end,
  getChannel = channel,
}

local function runWorker(untilT)
  while co and coroutine.status(co) ~= "dead" and wnow < untilT do
    inWorker = true
    local ok, y = coroutine.resume(co)
    inWorker = false
    if not ok then
      workerError = y
      return
    end
    if type(y) == "number" then
      wnow = wnow + y
    else
      wnow = untilT
    end
  end
end

local ChipAsm = require("src.audio.ChipAsm")
local ChipAudio = require("src.core.ChipAudio")
require("src.core.Sound")
local BattleState = require("src.battle.BattleState")

local serial = 0
local function def(ms)
  serial = serial + 1
  local d = ChipAsm.sfx{ channels = { { hw = 1, program = {
    { squareNote = { len = 4, volume = 15, fade = 1,
                     frequency = 0x300 + serial % 0x400 } },
  } } } }
  costOf[d] = ms
  return d
end

local function song(octave)
  return ChipAsm.song{ channels = { { hw = 1, program = {
    { notetype = { speed = 12, volume = 12, fade = 0 } },
    { octave = octave },
    { note = "C", len = 8 },
    { loop = { count = 0, to = 1 } },
  } } } }
end

local function newBattle()
  local data = {
    audio = {
      sfx = {
        Damage = def(1.5), Super_Effective = def(1.5),
        Not_Very_Effective = def(2.3),
        Faint_Fall = def(5.6), Faint_Thud = def(3.3), Ball_Toss = def(7),
        Ball_Poof = def(3.9), Run = def(5.4),
        Level_Up = def(139), Caught_Mon = def(135),
      },
      cries = {},
    },
    moves = {},
  }
  for i, ms in ipairs({ 11, 1, 3, 5, 6, 2 }) do
    data.audio.sfx["Move" .. i] = def(ms)
    data.moves["MOVE" .. i] = { anim = { sound = "Move" .. i } }
  end
  local function mon(species, ms, ...)
    data.audio.cries[species] = data.audio.cries[species] or def(ms)
    local moves = {}
    for _, id in ipairs({ ... }) do moves[#moves + 1] = { id = id } end
    return { species = species, moves = moves }
  end
  local enemy = mon("PIDGEY", 41, "MOVE1", "MOVE2")
  local player = mon("PIKA", 42, "MOVE3", "MOVE4", "MOVE5", "MOVE6")
  leadHeaders[data.audio.cries.PIDGEY] = true
  leadHeaders[data.audio.cries.PIKA] = true
  local party = { player, mon("SPEAROW", 5.4, "MOVE1"),
    mon("RATTATA", 4.5, "MOVE2"), mon("CATERPIE", 4.3, "MOVE3"),
    mon("WEEDLE", 3.1, "MOVE4"), mon("NIDORAN", 5.8, "MOVE5") }
  return data, {
    data = data, enemy = { mon = enemy }, player = { mon = player },
    enemyParty = { enemy },
    playerPartyView = function() return party end,
  }
end

local function step(frames)
  for _ = 1, frames do
    now = now + FRAME
    runWorker(now)
    for _, src in ipairs(queueables) do src:advance(FRAME) end
    ChipAudio.update()
    ChipAudio.ensureMusicPlaying()
  end
end

local preroll2 = ChipAudio.MUSIC_PREROLL * 2

local function battleStart(phase, gapMs)
  local tag = (" (phase %d, gap %d ms)"):format(phase, gapMs)
  check(ChipAudio.playMusic({ audio = {} }, song(3), true) ~= nil,
    "route song plays" .. tag)
  local routeSource = queueables[#queueables]
  step(600 + phase)
  check(routeSource.playing and #routeSource.underruns == 0,
    "route music is streaming before the battle starts" .. tag)

  local data, battle = newBattle()
  local total = 0
  for _, h in pairs(data.audio.sfx) do if costOf[h] then total = total + 1 end end
  for _ in pairs(data.audio.cries) do total = total + 1 end
  pushes, renders = {}, {}
  local battleSong = workerSongs + 1
  local playsBefore = playsPushed
  BattleState.prewarmCries(battle)
  local requested = ChipAudio._effectStateForTest()
  check(requested.queued + requested.inFlight >= 20,
    "the battle prewarm queues the whole battle set ("
      .. (requested.queued + requested.inFlight) .. ")" .. tag)
  now = now + gapMs / 1000
  runWorker(now)
  local t0 = now
  check(ChipAudio.playMusic(data, song(4), true) ~= nil,
    "battle theme cued" .. tag)
  local music = queueables[#queueables]

  step(math.floor(3 / FRAME))

  local leadsAfterPlay = 0
  for _, p in ipairs(pushes) do
    if p.lead and p.plays > playsBefore then
      leadsAfterPlay = leadsAfterPlay + 1
    end
  end
  eq(leadsAfterPlay, 2,
    "both lead cries reach the worker after the battle theme's play" .. tag)
  check(music.firstPlay ~= nil and music.firstPlay - t0 <= 0.7,
    ("battle theme starts within 0.7 s (%s s)"):format(
      music.firstPlay and ("%.2f"):format(music.firstPlay - t0) or "never")
      .. tag)
  local firstBackground
  for _, p in ipairs(pushes) do
    if not p.lead then firstBackground = p.t break end
  end
  check(firstBackground == nil
      or (music.firstPlay ~= nil and firstBackground > music.firstPlay),
    "no non-lead prewarm is pushed while the theme awaits its preroll" .. tag)
  local early = 0
  for _, r in ipairs(renders) do
    if r.song ~= battleSong or r.musicBefore < preroll2 then
      early = early + 1
    end
  end
  eq(early, 0, "the worker renders " .. preroll2
    .. " battle buffers before any effect" .. tag)
  eq(#music.underruns, 0, ("no underrun in the first 3 s of the battle (%s)")
    :format(table.concat(music.underruns, ", ")) .. tag)

  step(math.floor(57 / FRAME))
  local st = ChipAudio._effectStateForTest()
  eq(st.queued + st.inFlight, 0,
    "the background prewarm drains within a minute" .. tag)
  check(st.ready >= total, "every battle sound is prewarmed (" .. st.ready
    .. "/" .. total .. ")" .. tag)
end

battleStart(0, 0)
for phase = 0, 11 do battleStart(phase, 26) end
check(workerError == nil, "worker ran clean: " .. tostring(workerError))

local data2, battle2 = newBattle()
BattleState.prewarmCries(battle2)
ChipAudio.playMusic(data2, song(5), true)
step(2)
ChipAudio.resetSyncStats()
local before = ChipAudio._effectStateForTest()
check(ChipAudio.newSfx(data2, "Caught_Mon") ~= nil,
  "a background sound played before its prewarm still plays")
eq(ChipAudio.stats().syncRenders, 1, "it renders on demand")
eq(ChipAudio._effectStateForTest().queued, before.queued - 1,
  "and leaves the prewarm queue")
check(ChipAudio.newCry(data2, "PIDGEY", data2.audio.cries.PIDGEY) ~= nil,
  "a lead cry played before its prewarm lands still plays")
step(math.floor(60 / FRAME))
st = ChipAudio._effectStateForTest()
eq(st.queued + st.inFlight, 0, "the rest of the second battle drains")

ChipAudio.shutdown()
S.finish()
