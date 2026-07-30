-- A song cued while a fanfare is sounding stays silent until the jingle
-- ends (#398), on both chip playback paths.  On the Game Boy a fanfare's
-- sfx header claims the music channels and Audio1_PlaySound's .playMusic
-- only rewrites the NUM_MUSIC_CHANS state, so the new song is muted until
-- the jingle finishes (audio/engine_1.asm:39-56 Audio1_ApplyMusicAffects,
-- :1343-1357 .playMusic).  ChipAudio is what calls Source:play for a chip
-- song, so Music pausing its own Source cannot cover a song that starts
-- mid-jingle: the hold lives in ChipAudio and Music releases it.
-- ROM-free: ChipAsm blobs, no data/generated/.
--   luajit tests/engine/fanfare_music_hold.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

-- ------- audio stub: records which sources exist and which are sounding

local sources = {}

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

local function track(src)
  sources[#sources + 1] = src
  return src
end

love.audio = {
  newSource = function(what, mode)
    if what ~= "assets/beep.wav" then error("could not open " .. tostring(what), 0) end
    return track(setmetatable({ file = what, mode = mode, free = 0 }, Source))
  end,
  newQueueableSource = function()
    return track(setmetatable({ queueable = true, free = BUFFERS }, Source))
  end,
}

-- ------- worker stub for the threaded path
-- The real worker synthesizes on another thread; here the test hands the
-- buffers over itself so it controls the frame the first one lands on.

local channels = {}
local lastGen = 0

local Channel = {}
Channel.__index = Channel
function Channel:push(msg)
  if type(msg) == "table" and msg.cmd == "play" then lastGen = msg.gen end
  self.queue[#self.queue + 1] = msg
end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end

local function channel(name)
  channels[name] = channels[name] or setmetatable({ queue = {} }, Channel)
  return channels[name]
end

local threadStub = {
  newThread = function()
    return {
      start = function() end,
      getError = function() return nil end,
      wait = function() end,
    }
  end,
  getChannel = channel,
}

local function deliverBuffer()
  channel("chipaudio_out"):push({ gen = lastGen, sd = true })
end

-- ------- fixture dataset

local ChipAsm = require("src.audio.ChipAsm")

local function chipSong(octave)
  return ChipAsm.song{
    channels = { { hw = 1, program = {
      { notetype = { speed = 12, volume = 12, fade = 0 } },
      { octave = octave },
      { note = "C", len = 8 },
      { loop = { count = 0, to = 1 } },
    } } },
  }
end

local function fixtureData()
  return {
    audio = {
      songs = { Music_PalletTown = chipSong(4), Music_Routes1 = chipSong(5) },
      -- Level_Up rides Sound.lua's FANFARES fallback, which is what runs
      -- when a cache carries no data.audio.fanfares table
      sfx = { Level_Up = "assets/beep.wav" },
      cries = {},
      mapSongs = { PALLET_TOWN = "Music_PalletTown" },
    },
  }
end

local Music = require("src.core.Music")
local Sound = require("src.core.Sound")

-- ChipAudio decides sync vs threaded once per process (workerReady), so each
-- path gets its own copy of the module; Music resolves it through require on
-- every call and picks the new one up.
local function freshChipAudio(threaded)
  love.thread = threaded and threadStub or nil
  package.loaded["src.core.ChipAudio"] = nil
  return require("src.core.ChipAudio")
end

local function lastSource() return sources[#sources] end

local function scenario(label, threaded)
  local ChipAudio = freshChipAudio(threaded)
  local data = fixtureData()
  Sound.invalidate()
  Music.reload()
  for i = #sources, 1, -1 do sources[i] = nil end

  Music.playMap(data, "PALLET_TOWN", false, false)
  local mapSrc = lastSource()
  if threaded then deliverBuffer() ChipAudio.update() end
  check(mapSrc and mapSrc.queueable, label .. ": map theme streams through ChipAudio")
  check(mapSrc.playing, label .. ": map theme is sounding before the jingle")

  local fanfare = Sound.play(data, "Level_Up")
  check(fanfare ~= nil and fanfare.playing, label .. ": Level_Up started")
  check(not mapSrc.playing, label .. ": the playing song ducked under the jingle")

  -- BattleState:finish -> Music.restoreMap while the jingle still sounds;
  -- restoreMap clears state.current, so even the same theme rebuilds
  Music.restoreMap(data)
  local held = lastSource()
  check(held ~= mapSrc, label .. ": restoreMap built a new source mid-jingle")
  if threaded then deliverBuffer() ChipAudio.update() end
  ChipAudio.ensureMusicPlaying()
  Music.update(data)
  check(not held.playing, label .. ": a song cued during the jingle stays silent")
  check(fanfare.playing, label .. ": the jingle is still the only thing sounding")

  fanfare:stop()
  Music.update(data)
  if threaded then ChipAudio.update() end
  check(held.playing, label .. ": the held song starts once the jingle ends")

  -- a later song change is unaffected: the hold is released, not sticky
  Music.play(data, "Music_Routes1")
  local next_ = lastSource()
  if threaded then deliverBuffer() ChipAudio.update() end
  check(next_ ~= held and next_.playing, label .. ": later songs start normally")
end

scenario("sync", false)
scenario("threaded", true)

T.finish("fanfare music hold")
