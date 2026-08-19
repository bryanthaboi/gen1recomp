package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

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
function Source:setFilter() self.filters = (self.filters or 0) + 1 end
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
    return track(setmetatable({ file = what, mode = mode, free = 0 }, Source))
  end,
  newQueueableSource = function()
    return track(setmetatable({ queueable = true, free = BUFFERS }, Source))
  end,
}

local channels = {}
local lastGen, lastEpoch = 0, 0

local Channel = {}
Channel.__index = Channel
function Channel:push(msg)
  if type(msg) == "table" and msg.cmd == "play" then
    lastGen, lastEpoch = msg.gen, msg.stereoEpoch or 0
  end
  self.queue[#self.queue + 1] = msg
end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end
function Channel:getCount() return #self.queue end

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

local function deliverBuffer(epoch)
  channel("chipaudio_out"):push({
    gen = lastGen, sd = true, stereoEpoch = epoch or lastEpoch })
end

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
      songs = {
        Music_PalletTown = chipSong(4),
        Music_Streamed = { file = "assets/song.ogg",
                           loopFile = "assets/song_loop.ogg" },
      },
      sfx = { Press_AB = "assets/beep.wav" },
      cries = {},
      mapSongs = { PALLET_TOWN = "Music_PalletTown" },
    },
  }
end

local Music = require("src.core.Music")
local Sound = require("src.core.Sound")

local function freshChipAudio(threaded)
  love.thread = threaded and threadStub or nil
  package.loaded["src.core.ChipAudio"] = nil
  return require("src.core.ChipAudio")
end

local function lastSource() return sources[#sources] end

local function clearSources()
  for i = #sources, 1, -1 do sources[i] = nil end
end

local function audioSuspend()
  require("src.core.ChipAudio").setSuspended(true)
end

local function audioReset()
  local ChipAudio = require("src.core.ChipAudio")
  ChipAudio.setSuspended(false)
  ChipAudio.rebuildPlayback()
  Music.onDeviceReset()
  Sound.onDeviceReset()
end

local ChipAudio = freshChipAudio(true)
local data = fixtureData()
Sound.invalidate()
Music.reload()
clearSources()
channel("chipaudio_out"):clear()

Music.playMap(data, "PALLET_TOWN", false, false)
local src = lastSource()
check(src and src.queueable, "the map theme streams through ChipAudio")
src.playing = false

audioSuspend()
deliverBuffer()
ChipAudio.update()
eq(src.free, BUFFERS, "a suspended update queues nothing onto the dead source")
check(not src.playing, "a suspended update does not start playback")
eq(channel("chipaudio_out"):getCount(), 1,
   "the worker buffer waits in the channel instead of being dropped")

ChipAudio.setSuspended(true)
ChipAudio.setSuspended(false)
ChipAudio.setSuspended(false)
check(not ChipAudio.isSuspended(), "the suspend flag is idempotent both ways")

ChipAudio.update()
eq(src.free, BUFFERS - 1, "the resumed update queues the waiting buffer")
check(src.playing, "the resumed update starts playback")

src.playing = false
audioSuspend()
ChipAudio.ensureMusicPlaying()
check(not src.playing, "ensureMusicPlaying stays silent while suspended")
ChipAudio.setSuspended(false)
ChipAudio.ensureMusicPlaying()
check(src.playing, "ensureMusicPlaying recovers again once output is back")

Music.setVolumeLevel(7)
Music.setFilterLevel(0)
local before = #sources
audioSuspend()
audioReset()
eq(#sources, before + 1, "the reset built exactly one replacement source")
local fresh = ChipAudio.currentSource()
check(fresh ~= nil and fresh ~= src, "rebuildPlayback swapped in a fresh source")
check(not src.playing, "the source from the dead device was stopped")
eq(fresh.free, BUFFERS, "the replacement source starts empty")

deliverBuffer()
ChipAudio.update()
eq(fresh.free, BUFFERS - 1,
   "worker PCM tagged with the pre-reset gen and stereo epoch still queues")
check(fresh.playing, "playback resumes on the first requeued buffer")

deliverBuffer(lastEpoch + 1)
ChipAudio.update()
eq(fresh.free, BUFFERS - 1,
   "a buffer from another stereo epoch is still dropped after the reset")

check(fresh.volume ~= nil, "Music re-applied volume to the replacement source")
check((fresh.filters or 0) > 0, "Music re-applied the filter to it as well")
Music.setVolumeLevel(0)
eq(fresh.volume, 0, "the replacement source is what Music now drives")
check(src.volume ~= 0, "the dead source is no longer Music's source")
Music.setVolumeLevel(7)

local first = Sound.play(data, "Press_AB")
check(first ~= nil and first.playing, "the sfx played")
Sound.onDeviceReset()
local second = Sound.play(data, "Press_AB")
check(second ~= nil and second ~= first,
      "the sfx cache is empty after onDeviceReset; the next play re-renders")

Music.stop()
before = #sources
audioReset()
audioReset()
eq(#sources, before, "an audioreset with no music playing builds nothing")
check(ChipAudio.currentSource() == nil, "and leaves no music behind")

Music.play(data, "Music_Streamed")
local intro, loop = sources[#sources - 1], sources[#sources]
check(intro ~= nil and intro.playing, "the streamed intro is sounding")
check(loop ~= nil and not loop.playing, "its loop body waits its turn")
before = #sources
audioSuspend()
audioReset()
eq(#sources, before + 2, "the reset rebuilt both file sources")
local newIntro, newLoop = sources[#sources - 1], sources[#sources]
check(newIntro ~= intro and newIntro.playing,
      "the streamed song plays again from the top")
check(newLoop ~= loop and not newLoop.playing,
      "its rebuilt loop body still waits its turn")
check(not intro.playing, "the streamed source from the dead device was stopped")
eq(Music.current(), "Music_Streamed", "and the song label is unchanged")

ChipAudio = freshChipAudio(false)
Music.reload()
clearSources()
Music.playMap(data, "PALLET_TOWN", false, false)
local syncSrc = lastSource()
check(syncSrc and syncSrc.queueable and syncSrc.free < BUFFERS,
      "the sync path fills its queue on the frame the song starts")
local filled = syncSrc.free
audioSuspend()
ChipAudio.update()
eq(syncSrc.free, filled, "a suspended update fills nothing on the sync path")

audioReset()
local syncFresh = ChipAudio.currentSource()
check(syncFresh ~= syncSrc, "the sync path swaps in a fresh source too")
check(syncFresh.free < BUFFERS and syncFresh.playing,
      "and refills and starts it right away")
check(not syncSrc.playing, "the sync source from the dead device was stopped")

local function source(path)
  local f = io.open(path, "rb")
  check(f ~= nil, path .. " is readable")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  return text
end

local mainSrc = source("main.lua")
local suspendHook =
  mainSrc:match("\nfunction love%.handlers%.audiosuspend%(%).-\nend\n")
check(suspendHook ~= nil, "main.lua defines love.handlers.audiosuspend")
suspendHook = suspendHook or ""
check(suspendHook:find("setSuspended, true", 1, true) ~= nil,
      "the suspend handler gates ChipAudio")

local resetHook =
  mainSrc:match("\nfunction love%.handlers%.audioreset%(%).-\nend\n")
check(resetHook ~= nil, "main.lua defines love.handlers.audioreset")
resetHook = resetHook or ""
local unGate = resetHook:find("setSuspended, false", 1, true)
local rebuild = resetHook:find("rebuildPlayback", 1, true)
local music = resetHook:find("Music.onDeviceReset", 1, true)
local sound = resetHook:find("Sound.onDeviceReset", 1, true)
check(unGate and rebuild and unGate < rebuild,
      "the reset handler lifts the gate before rebuilding playback")
check(rebuild and music and rebuild < music,
      "Music re-binds after ChipAudio swapped the source in")
check(music and sound and music < sound, "and the sfx cache is flushed last")
check(resetHook:find('package.loaded["src.core.ChipAudio"]', 1, true) ~= nil,
      "the handlers cost a session that never touched audio nothing")

local workerSrc = source("src/core/chip_worker.lua")
check(workerSrc:find("outCh:getCount() < LOOKAHEAD", 1, true) ~= nil,
      "the chip worker bounds its look-ahead instead of free-running")

T.finish("audio device reset")
