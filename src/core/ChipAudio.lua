-- Playback front end for the Game Boy audio synth (src/core/ChipSynth.lua).
--
-- Map/battle MUSIC is streamed from a background worker thread
-- (src/core/chip_worker.lua): the worker synthesizes the PCM buffers and this
-- module only queues finished SoundData onto a QueueableSource.  That is the
-- fix for the map-transition stutter -- filling the deep (~6s) playback queue
-- from scratch when a song changes is ~200ms of Lua synthesis, and doing it on
-- the render thread dropped frames for the ~10 frames after every seam
-- crossing.  Off-thread, a song change costs the main loop essentially
-- nothing.
--
-- When love.thread is unavailable (the headless test stub) or a worker fails
-- to start, music falls back to the original synchronous, amortized queue fill
-- so behavior is unchanged -- see the `threaded` branch in each entry point.
--
-- SFX and cries stay synchronous: they are short one-shots rendered once into
-- a static Source, not a per-frame streaming cost.

local Assets = require("src.render.Assets")
local ChipSynth = require("src.core.ChipSynth")

local ChipAudio = {}

local function sampleRate()
  return ChipSynth.SAMPLE_RATE
end
local MUSIC_BUFFER_SAMPLES = ChipSynth.MUSIC_BUFFER_SAMPLES
local MUSIC_BUFFER_COUNT = ChipSynth.MUSIC_BUFFER_COUNT

-- ---------------------------------------------------------------------------
-- Per-channel mix (edit these)
-- Applied on load and whenever this file hot-reloads.
-- Runtime: ChipAudio.setChannelVolume / setChannelPitch.
--   [1] pulse 1   [2] pulse 2   [3] wave   [4] noise / drums
-- Volume: 1 = authentic, 0 = mute, >1 boosts
-- Pitch:  1 = authentic, 2 = +1 octave, 0.5 = -1 octave
-- The shipped values stay at 1: 0.25 / 0.5 on the wave channel buried the Ch3
-- countermelodies an octave low (#429), and ChipSynth already applies the
-- wave channel's own hardware octave (frequency * 0.5).
-- ---------------------------------------------------------------------------
local CHANNEL_VOLUME = {
  [1] = 1, -- pulse 1
  [2] = 1, -- pulse 2
  [3] = 1, -- wave
  [4] = 1, -- noise / drums
}
local CHANNEL_PITCH = {
  [1] = 1, -- pulse 1
  [2] = 1, -- pulse 2
  [3] = 1, -- wave
  [4] = 1, -- noise / drums
}
ChipSynth.setChannelVolumes(CHANNEL_VOLUME)
ChipSynth.setChannelPitches(CHANNEL_PITCH)

-- currentMusic: { source, gen, threaded, started, finished, engine }
--   threaded songs stream from the worker (engine is nil here);
--   the fallback path owns a local engine and fills the source itself.
local currentMusic
local pendingBuf -- a current-gen buffer popped from the worker but not yet
                 -- queued because the Source was momentarily full

-- Music holds playback while a fanfare owns the music channels (#398).
-- Pausing the Source is not enough on its own: this module is what starts a
-- chip song (immediately on the sync path, on the first worker buffer on the
-- threaded one), so a song that begins during a jingle would come up
-- underneath it.  Music.duckForFanfare sets the hold, Music releases it when
-- the jingle ends.
local musicHeld = false

local suspended = false

local STATS = os.getenv("POKEPORT_AUDIO_STATS") == "1"
local statFrames, statUnderruns, statRestarts = 0, 0, 0
local statDepthMin, statDepthSum, statDepthFrames = nil, 0, 0
local statWorkerJit, statWorkerXrt = nil, nil
local statXrtSum, statXrtCount, statXrtMax = 0, 0, nil
local statSyncRenders, statSyncMs, statSyncMsMax = 0, 0, 0
local statSyncLast
local statPrewarmHits = 0
local lastCosted

-- ---------------------------------------------------------------------------
-- worker management
-- ---------------------------------------------------------------------------

local worker, cmdCh, outCh
local workerReady -- nil = untried, true = running, false = unavailable

-- SFX/cry prewarm state (see "one-shot effects" below): results come back on
-- their own channel so a music stop/clear never drops them
local fxCh
local fxEpoch = 0 -- bumped by invalidate: drops results from a stale def
local fxReady = {}    -- key -> SoundData | false (renders to nothing)
local fxPending = {}  -- key -> true while a request is in flight
local fxReadyCount = 0
local fxReadyOrder = {}
local fxOrderCount = 0
local FX_READY_MAX = 64
local fxPinned = {}
local fxPinnedCount = 0
local FX_PINNED_MAX = 24
local pinRequests = false
local frontRequests = false
local pushHeld = false
local fxQueue = {}
local fxInFlight = {}
local fxInFlightCount = 0
local FX_IN_FLIGHT_MAX = 2
local drainEffects, dropEffects, pumpEffects

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
  if not (love.thread and love.thread.newThread and love.audio) then
    workerReady = false
    return false
  end
  local ok, thread = pcall(love.thread.newThread, "src/core/chip_worker.lua")
  if not ok or not thread then
    workerReady = false
    return false
  end
  cmdCh = love.thread.getChannel("chipaudio_cmd")
  outCh = love.thread.getChannel("chipaudio_out")
  local started = pcall(function() thread:start() end)
  if not started then
    workerReady = false
    return false
  end
  worker = thread
  workerReady = true
  return true
end

-- only the tables ChipSynth.newEngine reads for ROM songs; sent with every
-- play so a hot-reloaded dataset (or a mod's audio) always reaches the worker
local function slimAudio(data)
  local audio = data.audio or {}
  return {
    programFile = audio.programFile,
    programPrefix = require("src.core.WorkerFs").prefix(),
    bankOrder = audio.bankOrder,
    waveBanks = audio.waveBanks,
    noiseHeaders = audio.noiseHeaders,
    generation = audio.generation,
    drumkits = audio.drumkits,
  }
end

-- test-only: expose slimAudio so the NX prefix hand-off is verifiable
function ChipAudio._slimAudioForTest(data)
  return slimAudio(data)
end

-- If the worker died (a malformed def that errors mid-synth), fall back to the
-- synchronous path for the rest of the session instead of going silent.
local function workerAlive()
  if not worker then return false end
  local err = worker:getError()
  if err then
    require("src.core.Logger").warn("chip audio worker died: %s", tostring(err))
    workerReady = false
    worker = nil
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- synchronous fallback (no love.thread): the original amortized queue fill
-- ---------------------------------------------------------------------------

-- The queue is deep (MUSIC_BUFFER_COUNT, ~6s) for stall tolerance, but
-- synthesizing all of it on the frame a song starts renders ~6s of audio at
-- once.  A (re)start renders MUSIC_FILL_INITIAL whole buffers so playback has
-- lookahead; after that each update() renders a flat slice of samples into a
-- staging buffer and queues it once all MUSIC_BUFFER_SAMPLES are in.  Whole
-- 8192-sample buffers rendered on the frame a queue slot freed (every ~11
-- frames) read as a periodic stutter; ~1024 samples per 60 Hz tick
-- (playback drains ~735) keeps the per-frame cost flat while the queue still
-- creeps up to full.  Below MUSIC_FILL_LOW_WATER queued buffers (a long
-- stall, or update() called well under 60 Hz) a tick renders a whole buffer's
-- worth so the queue cannot run dry.  The sample stream is unchanged: every
-- buffer is still MUSIC_BUFFER_SAMPLES consecutive engine samples, and a
-- buffer begun before the song ended is completed exactly as before.
local MUSIC_FILL_INITIAL = 4
local MUSIC_FILL_TICK_SAMPLES = 1024 -- at 44100 Hz; scaled with the rate
local MUSIC_FILL_LOW_WATER = 2

local function tickSamples()
  return math.max(256,
    math.floor(MUSIC_FILL_TICK_SAMPLES * sampleRate() / 44100 + 0.5))
end

-- render up to `budget` samples of the fallback song, queueing each staging
-- buffer as it fills.  A new buffer is only begun while the Source has a free
-- slot and the song has not finished (the old whole-buffer loop's gates).
local function renderSync(music, budget)
  while budget > 0 do
    if not music.staging then
      if music.engine:finished() then return end
      local ok, free = pcall(music.source.getFreeBufferCount, music.source)
      if not ok or type(free) ~= "number" or free <= 0 then return end
      music.staging = ChipSynth.newBuffer(MUSIC_BUFFER_SAMPLES, 2)
      music.stagingFill = 0
    end
    local count = math.min(budget, MUSIC_BUFFER_SAMPLES - music.stagingFill)
    ChipSynth.renderInto(music.engine, music.staging, music.stagingFill,
                         count, 2)
    music.stagingFill = music.stagingFill + count
    budget = budget - count
    if music.stagingFill >= MUSIC_BUFFER_SAMPLES then
      local sd = music.staging
      music.staging, music.stagingFill = nil, 0
      if not pcall(music.source.queue, music.source, sd) then return end
    end
  end
end

-- `buffers`: render that many whole buffers now (song start / restart);
-- omitted: one per-frame tick
local function fillSync(buffers)
  if suspended then return end
  local music = currentMusic
  if not music or not music.engine then return end
  if not music.staging and music.engine:finished() then return end
  local budget
  if buffers then
    budget = buffers * MUSIC_BUFFER_SAMPLES - (music.stagingFill or 0)
  else
    budget = tickSamples()
    local ok, free = pcall(music.source.getFreeBufferCount, music.source)
    if ok and type(free) == "number"
        and MUSIC_BUFFER_COUNT - free < MUSIC_FILL_LOW_WATER then
      budget = MUSIC_BUFFER_SAMPLES
    end
  end
  renderSync(music, budget)
end

local function playMusicSync(data, header, allowLoops)
  -- build before tearing down: a def that fails to compile must leave the
  -- outgoing song sounding
  local ok, engine = pcall(ChipSynth.newEngine, data, header,
                           { allowLoops = allowLoops })
  if not ok then return nil, engine end
  local ok2, source = pcall(
    love.audio.newQueueableSource, sampleRate(), 16, 2, MUSIC_BUFFER_COUNT)
  if not ok2 then return nil, source end
  ChipAudio.stopMusic()
  currentMusic = { source = source, engine = engine, threaded = false,
                   started = true, finished = false }
  fillSync(MUSIC_FILL_INITIAL)
  if not musicHeld then pcall(source.play, source) end
  return source
end

-- ---------------------------------------------------------------------------
-- threaded music
-- ---------------------------------------------------------------------------

local musicGen = 0
-- bumps when SOUND flips so already-queued PCM (old pan) is dropped rather
-- than playing out the ~6s stall-tolerance queue (#1471)
local stereoEpoch = 0

local MUSIC_PREROLL = 4
ChipAudio.MUSIC_PREROLL = MUSIC_PREROLL

local function queuedBuffers(source)
  local ok, free = pcall(source.getFreeBufferCount, source)
  if not ok or type(free) ~= "number" then return nil end
  return MUSIC_BUFFER_COUNT - free
end

local function readyToStart(m)
  local queued = queuedBuffers(m.source)
  if not queued then return false end
  return queued >= (m.preroll or 1) or (m.finished and queued > 0)
end

function ChipAudio.playMusic(data, header, allowLoops)
  if not ensureWorker() then
    return playMusicSync(data, header, allowLoops)
  end
  -- validate the def on this thread (cheap: engine construction, no synthesis)
  -- so a broken def costs nothing but a log line and keeps the old song
  local ok, engine = pcall(ChipSynth.newEngine, data, header,
                           { allowLoops = allowLoops })
  if not ok then return nil, engine end
  -- build the new source before tearing the old song down
  local ok2, source = pcall(
    love.audio.newQueueableSource, sampleRate(), 16, 2, MUSIC_BUFFER_COUNT)
  if not ok2 then return nil, source end
  ChipAudio.stopMusic()
  musicGen = musicGen + 1
  local gen = musicGen
  cmdCh:push({ cmd = "play", gen = gen, header = header,
               allowLoops = allowLoops, audio = slimAudio(data),
               channelVolumes = ChipSynth.getChannelVolumes(),
               channelPitches = ChipSynth.getChannelPitches(),
               stereo = ChipSynth.getStereo(),
               sampleRate = sampleRate(),
               stereoEpoch = stereoEpoch })
  currentMusic = { source = source, gen = gen, threaded = true,
                   started = false, finished = false,
                   stereoEpoch = stereoEpoch,
                   preroll = (allowLoops ~= false) and MUSIC_PREROLL or 1 }
  return source
end

local function pushChannelMix()
  if workerReady and cmdCh then
    cmdCh:push({ cmd = "channelMix",
                 volumes = ChipSynth.getChannelVolumes(),
                 pitches = ChipSynth.getChannelPitches(),
                 stereo = ChipSynth.getStereo() })
  end
end

-- move finished buffers from the worker into the Source; start playback once
-- the first one lands
local function updateThreaded()
  local m = currentMusic
  if not m then return end
  if not workerAlive() then
    -- worker gone: nothing more will arrive; leave whatever is queued playing
    return
  end
  while true do
    local okFree, free = pcall(m.source.getFreeBufferCount, m.source)
    if not okFree or type(free) ~= "number" then return end
    local buf = pendingBuf
    if buf then pendingBuf = nil else buf = outCh:pop() end
    if not buf then break end
    if buf.gen ~= m.gen then
      -- stale buffer from a superseded song: drop it
    elseif buf.stereoEpoch ~= nil and m.stereoEpoch ~= nil
        and buf.stereoEpoch ~= m.stereoEpoch then
      -- stale pan mix from before a live SOUND toggle (#1471)
    elseif buf.done then
      m.finished = true
    elseif buf.error then
      require("src.core.Logger").warn("chip audio: %s", tostring(buf.error))
      m.finished = true
    elseif buf.sd then
      if buf.jit ~= nil then statWorkerJit = buf.jit end
      if type(buf.xrt) == "number" and buf ~= lastCosted then
        lastCosted = buf
        statWorkerXrt = buf.xrt
        statXrtSum = statXrtSum + buf.xrt
        statXrtCount = statXrtCount + 1
        if statXrtMax == nil or buf.xrt > statXrtMax then
          statXrtMax = buf.xrt
        end
      end
      if free > 0 then
        if not pcall(m.source.queue, m.source, buf.sd) then return end
      else
        pendingBuf = buf -- Source full; hold this one for next frame
        break
      end
    end
  end
  if not m.started and not musicHeld and readyToStart(m) then
    pcall(function() m.source:play() end)
    m.started = true
  end
end

local function noteStats(m)
  if not m.started or m.finished then return end
  statFrames = statFrames + 1
  local depth = m.source and queuedBuffers(m.source) or nil
  if depth then
    statDepthSum = statDepthSum + depth
    statDepthFrames = statDepthFrames + 1
    if statDepthMin == nil or depth < statDepthMin then statDepthMin = depth end
  end
  if depth == 0 then statUnderruns = statUnderruns + 1 end
  if STATS and statFrames % 60 == 0 then
    require("src.core.Logger").info(
      "chipaudio: depth=%d/%d out=%d underruns=%d restarts=%d rate=%d",
      depth or -1, MUSIC_BUFFER_COUNT,
      (m.threaded and outCh) and outCh:getCount() or -1,
      statUnderruns, statRestarts, sampleRate())
  end
end

function ChipAudio.stats()
  local m = currentMusic
  local depth = (m and m.source) and queuedBuffers(m.source) or nil
  local worker
  if workerReady == nil then worker = "none"
  elseif workerReady == false then worker = "sync"
  elseif statWorkerJit == true then worker = "jit"
  elseif statWorkerJit == false then worker = "interp"
  else worker = "starting" end
  local average = statDepthFrames > 0
    and (statDepthSum / statDepthFrames) or nil
  local stats = {
    rate = sampleRate(),
    worker = worker,
    depth = depth,
    depthMax = MUSIC_BUFFER_COUNT,
    depthMin = statDepthMin,
    depthAvg = average,
    frames = statFrames,
    underruns = statUnderruns,
    restarts = statRestarts,
    xrt = statWorkerXrt,
    xrtAvg = statXrtCount > 0 and (statXrtSum / statXrtCount) or nil,
    xrtMax = statXrtMax,
    buffers = statXrtCount,
    syncRenders = statSyncRenders,
    syncRenderMs = statSyncMs,
    syncRenderMsMax = statSyncMsMax,
    syncRenderLast = statSyncLast,
    prewarmHits = statPrewarmHits,
    prewarmQueued = #fxQueue,
    prewarmInFlight = fxInFlightCount,
    prewarmReady = fxReadyCount,
  }
  local function num(value, places)
    if type(value) ~= "number" then return "-" end
    return string.format("%." .. places .. "f", value)
  end
  stats.line = string.format(
    "rate=%d worker=%s depth=%s/%d min=%s avg=%s underruns=%d restarts=%d "
      .. "xrt=%s/%s/%s n=%d sync=%d/%sms max=%sms last=%s prewarm=%d q=%d",
    stats.rate, worker, depth and tostring(depth) or "-", MUSIC_BUFFER_COUNT,
    statDepthMin and tostring(statDepthMin) or "-", num(average, 1),
    statUnderruns, statRestarts,
    num(statWorkerXrt, 3), num(stats.xrtAvg, 3), num(statXrtMax, 3),
    statXrtCount, statSyncRenders, num(statSyncMs, 1), num(statSyncMsMax, 1),
    tostring(statSyncLast or "-"), statPrewarmHits, #fxQueue + fxInFlightCount)
  return stats
end

function ChipAudio.resetSyncStats()
  statSyncRenders, statSyncMs, statSyncMsMax = 0, 0, 0
  statSyncLast = nil
  statPrewarmHits = 0
end

function ChipAudio.update()
  if suspended then return end
  pushHeld = false
  if fxCh then pumpEffects() end
  local m = currentMusic
  if not m then return end
  if m.threaded then
    updateThreaded()
  else
    fillSync()
  end
  noteStats(m)
end

-- Recover from a queue underrun caused by a long render stall.  Called after
-- Music has handled intentional fanfare pauses, so it never fights the normal
-- pause/resume behavior.
function ChipAudio.ensureMusicPlaying()
  if suspended then return end
  local m = currentMusic
  if not m or m.finished or musicHeld then return end
  if m.threaded then
    if not m.started then return end
    local ok, playing = pcall(function() return m.source:isPlaying() end)
    if not ok or playing then return end
    if readyToStart(m) then
      pcall(function() m.source:play() end)
      statRestarts = statRestarts + 1
    end
  else
    if not m.engine or m.engine:finished() then return end
    local ok, playing = pcall(m.source.isPlaying, m.source)
    if ok and not playing then
      fillSync(MUSIC_FILL_INITIAL)
      pcall(m.source.play, m.source)
      statRestarts = statRestarts + 1
    end
  end
end

-- Silence the song for the length of a fanfare and start whatever was held
-- back once it ends.  Held state outlives a song change: Music.play may swap
-- songs while the jingle is still sounding.
function ChipAudio.holdMusic(held)
  held = not not held
  if held == musicHeld then return end
  musicHeld = held
  if held then return end
  ChipAudio.update()
  ChipAudio.ensureMusicPlaying()
end

-- Threaded playMusic returns an empty QueueableSource and only calls
-- Source:play once the first worker buffer lands (~1 frame later).  Until
-- then Source:isPlaying is false -- callers that treat that as "song over"
-- (Music.oneShotPlaying / pendingRestore) must wait here instead, or a
-- playOnce jingle like Music_PkmnHealed is cut off before it starts.
local forceAwaitingFirstBuffer -- test-only override (see _simulate*)

function ChipAudio.awaitingFirstBuffer()
  if suspended then return false end
  if forceAwaitingFirstBuffer then return true end
  local m = currentMusic
  if not (m and m.threaded and not m.started and not m.finished) then
    return false
  end
  -- a dead worker will never deliver the first buffer
  if workerReady == false then return false end
  if worker and worker.getError and worker:getError() then return false end
  return true
end

function ChipAudio.stopMusic()
  if currentMusic and currentMusic.source then
    pcall(currentMusic.source.stop, currentMusic.source)
  end
  if workerReady and cmdCh then
    cmdCh:push({ cmd = "stop" })
    if outCh then outCh:clear() end
  end
  pendingBuf = nil
  currentMusic = nil
  forceAwaitingFirstBuffer = nil
end

-- hot reload: the next play re-reads programs.bin (a mod may have swapped the
-- file out from under the single-slot bank cache), on both threads
function ChipAudio.invalidate()
  ChipAudio.stopMusic()
  ChipSynth.invalidateBanks()
  dropEffects()
  if workerReady and cmdCh then cmdCh:push({ cmd = "invalidate" }) end
end

-- End the worker thread.  LOVE waits for every live love.thread before the
-- process exits and the worker's command loop only returns on "quit", so
-- skipping this leaves the process running after the window is gone (#339).
function ChipAudio.shutdown()
  ChipAudio.stopMusic()
  if workerReady and cmdCh then cmdCh:push({ cmd = "quit" }) end
  if worker then pcall(function() worker:wait() end) end
  worker, cmdCh, outCh = nil, nil, nil
  workerReady = nil
  dropEffects()
  fxCh = nil
end

function ChipAudio.currentSource()
  return currentMusic and currentMusic.source
end

function ChipAudio.setSuspended(flag)
  suspended = not not flag
end

function ChipAudio.isSuspended()
  return suspended
end

function ChipAudio.rebuildPlayback()
  local m = currentMusic
  if not m then return true end
  if not (love.audio and love.audio.newQueueableSource) then return false end
  local ok, source = pcall(
    love.audio.newQueueableSource, sampleRate(), 16, 2, MUSIC_BUFFER_COUNT)
  if not ok or not source then return false end
  pendingBuf = nil
  local old = m.source
  m.source = source
  m.started = false
  if old then pcall(old.stop, old) end
  if not m.threaded then
    fillSync(MUSIC_FILL_INITIAL)
    if not musicHeld then pcall(source.play, source) end
    m.started = true
  end
  return true
end

function ChipAudio.setStereo(enabled)
  enabled = not not enabled
  if ChipSynth.getStereo() == enabled then return end
  ChipSynth.setStereo(enabled)
  stereoEpoch = stereoEpoch + 1
  local m = currentMusic
  if m and m.engine then
    ChipSynth.applyStereo(m.engine)
    -- a half-rendered fallback buffer holds the previous pan mix (#1471)
    m.staging, m.stagingFill = nil, 0
  end
  if workerReady and cmdCh then
    cmdCh:push({ cmd = "channelMix",
                 volumes = ChipSynth.getChannelVolumes(),
                 pitches = ChipSynth.getChannelPitches(),
                 stereo = enabled,
                 stereoEpoch = stereoEpoch })
  end
  if not m then return end
  pendingBuf = nil
  if outCh then outCh:clear() end
  m.stereoEpoch = stereoEpoch
  -- QueueableSource cannot unqueue; swap so the ~6s stall-tolerance buffers
  -- (mixed under the previous pan) do not have to play out first (#1471)
  if not love.audio then return end
  local ok, source = pcall(
    love.audio.newQueueableSource, sampleRate(), 16, 2, MUSIC_BUFFER_COUNT)
  if not ok or not source then return end
  local old = m.source
  m.source = source
  m.started = false
  if old then pcall(old.stop, old) end
  if not m.threaded then
    fillSync(MUSIC_FILL_INITIAL)
    if not musicHeld then pcall(source.play, source) end
    m.started = true
  end
end

function ChipAudio.getStereo()
  return ChipSynth.getStereo()
end

local envRate = os.getenv("POKEPORT_AUDIO_RATE")

function ChipAudio._setEnvRateForTest(value)
  envRate = value
end

function ChipAudio.selectSampleRate(options)
  local forced = tonumber(envRate)
  if forced and forced >= 8000 and forced <= 48000 then
    return math.floor(forced)
  end
  local tier = require("src.core.Performance")
    .resolve(options and options.performance)
  if tier == "low" then return 22050 end
  local osName = love and love.system and love.system.getOS
    and love.system.getOS() or nil
  if osName == "Android" and tier ~= "high" then return 22050 end
  return 44100
end

function ChipAudio.setSampleRate(rate)
  local before = sampleRate()
  if ChipSynth.setSampleRate(rate) == before then return false end
  ChipAudio.stopMusic()
  return true
end

function ChipAudio.applyOptions(options)
  return ChipAudio.setSampleRate(ChipAudio.selectSampleRate(options))
end

-- Runtime mix for one hardware channel (1..4).  Takes effect on the next
-- synthesized buffer (live music) and on any SFX/cry rendered after the call.
function ChipAudio.setChannelVolume(hw, scale)
  ChipSynth.setChannelVolume(hw, scale)
  pushChannelMix()
end

function ChipAudio.getChannelVolume(hw)
  return ChipSynth.getChannelVolume(hw)
end

function ChipAudio.setChannelVolumes(volumes)
  ChipSynth.setChannelVolumes(volumes)
  pushChannelMix()
end

function ChipAudio.getChannelVolumes()
  return ChipSynth.getChannelVolumes()
end

function ChipAudio.setChannelPitch(hw, scale)
  ChipSynth.setChannelPitch(hw, scale)
  pushChannelMix()
end

function ChipAudio.getChannelPitch(hw)
  return ChipSynth.getChannelPitch(hw)
end

function ChipAudio.setChannelPitches(pitches)
  ChipSynth.setChannelPitches(pitches)
  pushChannelMix()
end

function ChipAudio.getChannelPitches()
  return ChipSynth.getChannelPitches()
end

-- aliases for channel 4 (noise / drums)
function ChipAudio.setNoiseVolume(scale)
  ChipAudio.setChannelVolume(4, scale)
end

function ChipAudio.getNoiseVolume()
  return ChipAudio.getChannelVolume(4)
end

-- a stale song must not keep sounding past the flush that replaced its
-- program (20 §2 cache contract, chip music row)
Assets.register(ChipAudio.invalidate)

-- ---------------------------------------------------------------------------
-- one-shot effects (SFX, cries, low-health alarm): synchronous static Sources
-- ---------------------------------------------------------------------------

-- Prewarm (#first-cry hitch): the first play of an SFX/cry synthesizes its
-- whole PCM on the main thread (a cry is ~10-25 ms of Lua synthesis, a long
-- jingle 150-350 ms).  ChipAudio.prewarmSfx / prewarmCry hand that render to
-- the music worker ahead of time -- e.g. while a battle transition runs, for
-- the two species about to cry -- and the next newSfx/newCry with the same
-- def, modifiers and channel mix takes the finished SoundData instead of
-- rendering.  Playback timing is unchanged: a play never waits on the worker
-- (a request still in flight is rendered synchronously as before and its
-- late result dropped), and the worker runs the same ChipSynth code with the
-- same rate/mix, so the PCM is identical.  No worker (headless, love.thread
-- unavailable or dead): prewarm is a no-op and plays render as before.

local function effectKey(data, header, options)
  if type(header) ~= "table" then return nil end
  local volumes = ChipSynth.getChannelVolumes()
  local pitches = ChipSynth.getChannelPitches()
  -- table identities: a reloaded def (or dataset) is a new table
  return table.concat({
    tostring(data and data.audio), tostring(header.chip or header),
    tostring(options.frequencyOffset), tostring(options.frameTicks),
    tostring(options.plainFrames), tostring(options.cryLength),
    tostring(options.maxSeconds),
    sampleRate(), ChipSynth.getStereo() and 1 or 0,
    volumes[1], volumes[2], volumes[3], volumes[4],
    pitches[1], pitches[2], pitches[3], pitches[4], fxEpoch,
  }, "|")
end

local function storeReady(key, sd)
  if fxReady[key] ~= nil then return end
  if fxPinned[key] then
    fxReady[key] = sd
    fxReadyCount = fxReadyCount + 1
    return
  end
  while fxOrderCount >= FX_READY_MAX and #fxReadyOrder > 0 do
    local oldest = table.remove(fxReadyOrder, 1)
    if fxReady[oldest] ~= nil and not fxPinned[oldest] then
      fxReady[oldest] = nil
      fxReadyCount = fxReadyCount - 1
      fxOrderCount = fxOrderCount - 1
    end
  end
  if #fxReadyOrder > FX_READY_MAX * 2 then
    local live = {}
    for _, k in ipairs(fxReadyOrder) do
      if fxReady[k] ~= nil and not fxPinned[k] then live[#live + 1] = k end
    end
    fxReadyOrder = live
  end
  fxReady[key] = sd
  fxReadyCount = fxReadyCount + 1
  fxOrderCount = fxOrderCount + 1
  fxReadyOrder[#fxReadyOrder + 1] = key
end

local function pinEffect(key)
  if fxPinned[key] or fxPinnedCount >= FX_PINNED_MAX then return end
  fxPinned[key] = true
  fxPinnedCount = fxPinnedCount + 1
  if fxReady[key] ~= nil then fxOrderCount = fxOrderCount - 1 end
end

function drainEffects()
  if not fxCh then return end
  while true do
    local result = fxCh:pop()
    if not result then return end
    if result.epoch == fxEpoch then
      if fxInFlight[result.key] then
        fxInFlight[result.key] = nil
        fxInFlightCount = fxInFlightCount - 1
      end
      if fxPending[result.key] then
        fxPending[result.key] = nil
        if result.error then
          require("src.core.Logger").warn("chip audio prewarm: %s",
            tostring(result.error))
        else
          storeReady(result.key, result.sd or false)
        end
      end
    end
  end
end

function dropEffects()
  fxEpoch = fxEpoch + 1
  fxReady, fxPending, fxReadyCount = {}, {}, 0
  fxReadyOrder, fxQueue, fxInFlight, fxInFlightCount = {}, {}, {}, 0
  fxOrderCount, fxPinned, fxPinnedCount = 0, {}, 0
  pushHeld = false
  if fxCh then fxCh:clear() end
end

local function musicHasHeadroom()
  local m = currentMusic
  if not (m and m.threaded) or m.finished or musicHeld then return true end
  if not m.started then return false end
  local depth = queuedBuffers(m.source)
  if not depth then return true end
  if outCh then depth = depth + outCh:getCount() end
  return depth >= MUSIC_PREROLL * 4 * (fxInFlightCount + 1)
end

local function frontSlot()
  local slot = 1
  while fxQueue[slot] and fxQueue[slot].front do slot = slot + 1 end
  return slot
end

local function promoteEffect(key)
  for i, entry in ipairs(fxQueue) do
    if entry.key == key then
      if entry.front then return end
      table.remove(fxQueue, i)
      entry.front = true
      table.insert(fxQueue, frontSlot(), entry)
      return
    end
  end
end

function pumpEffects()
  drainEffects()
  while not pushHeld and #fxQueue > 0
      and fxInFlightCount < FX_IN_FLIGHT_MAX do
    if not workerAlive() then
      fxQueue = {}
      return
    end
    if not fxQueue[1].front and not musicHasHeadroom() then return end
    local entry = table.remove(fxQueue, 1)
    if fxPending[entry.key] then
      local pushed = pcall(cmdCh.push, cmdCh, entry.request)
      if pushed then
        fxInFlight[entry.key] = true
        fxInFlightCount = fxInFlightCount + 1
      else
        fxPending[entry.key] = nil
      end
    end
  end
end

local function requestEffect(data, header, options)
  if not ensureWorker() or not workerAlive() then return false end
  local key = effectKey(data, header, options)
  if not key then return false end
  fxCh = fxCh or love.thread.getChannel("chipaudio_fx")
  drainEffects()
  if pinRequests then pinEffect(key) end
  if fxReady[key] ~= nil then return true end
  if fxPending[key] then
    if frontRequests and not fxInFlight[key] then
      promoteEffect(key)
      pumpEffects()
    end
    return true
  end
  fxPending[key] = true
  local slot = frontRequests and frontSlot() or #fxQueue + 1
  table.insert(fxQueue, slot, { key = key, front = frontRequests, request = {
    cmd = "effect", key = key, epoch = fxEpoch, header = header,
    options = {
      frequencyOffset = options.frequencyOffset,
      frameTicks = options.frameTicks,
      plainFrames = options.plainFrames,
      cryLength = options.cryLength,
      maxSeconds = options.maxSeconds,
    },
    audio = slimAudio(data),
    channelVolumes = ChipSynth.getChannelVolumes(),
    channelPitches = ChipSynth.getChannelPitches(),
    stereo = ChipSynth.getStereo(),
    sampleRate = sampleRate(),
  } })
  pumpEffects()
  return true
end

-- a finished prewarm for exactly this render, or nil
local function takeEffect(data, header, options)
  if not fxCh then return nil end
  local key = effectKey(data, header, options)
  if not key then return nil end
  drainEffects()
  local sd = fxReady[key]
  if sd ~= nil then
    fxReady[key] = nil
    fxReadyCount = fxReadyCount - 1
    if not fxPinned[key] then fxOrderCount = fxOrderCount - 1 end
    return sd
  end
  if fxPending[key] then
    fxPending[key] = nil
    for i, entry in ipairs(fxQueue) do
      if entry.key == key then
        table.remove(fxQueue, i)
        break
      end
    end
  end
  return nil
end

local function nowMs()
  local timer = love and love.timer
  if timer and timer.getTime then return timer.getTime() * 1000 end
  return os.clock() * 1000
end

local function renderEffect(data, header, options, label)
  local sd = takeEffect(data, header, options)
  if sd == nil then
    local began = nowMs()
    sd = ChipSynth.renderEffectData(data, header, options)
    local ms = nowMs() - began
    statSyncRenders = statSyncRenders + 1
    statSyncMs = statSyncMs + ms
    if ms > statSyncMsMax then statSyncMsMax = ms end
    statSyncLast = label
    if STATS then
      require("src.core.Logger").info("chipaudio: sync render %s %.1fms",
        tostring(label), ms)
    end
    local FixedStep = require("src.core.FixedStep")
    if ms >= FixedStep.STEP * 1000 then FixedStep:discardCatchup() end
  else
    statPrewarmHits = statPrewarmHits + 1
  end
  if not sd then return nil end
  return love.audio.newSource(sd, "static")
end

local function sfxOptions(pitch, tempo, plainFrames)
  return {
    frequencyOffset = pitch or 0,
    frameTicks = 0x80 + (tempo or 0x80),
    plainFrames = plainFrames,
  }
end

local function cryDef(data, species, resolved)
  return resolved or (data.audio.cries and data.audio.cries[species])
end

local function cryOptions(cry)
  return { frequencyOffset = cry.pitch, cryLength = cry.length }
end

function ChipAudio.newSfx(data, name, pitch, tempo, header, plainFrames)
  header = header or data.audio.sfx[name]
  return renderEffect(data, header, sfxOptions(pitch, tempo, plainFrames),
    name)
end

-- `resolved` is a {header|chip, pitch, length} def the caller already worked
-- out -- a derived cry borrowing another species' header with its own
-- modifiers, which no registry lookup under `species` could find
function ChipAudio.newCry(data, species, resolved)
  local cry = cryDef(data, species, resolved)
  if not cry then return nil end
  return renderEffect(data, cry.chip and cry or cry.header, cryOptions(cry),
    "cry:" .. tostring(species))
end

-- Same arguments as newSfx / newCry; returns true when a render was queued
-- on the worker (or is already queued / done), false when there is no worker
-- to do it.  Never renders on the calling thread.
function ChipAudio.prewarmSfx(data, name, pitch, tempo, header, plainFrames)
  header = header or (data.audio and data.audio.sfx and data.audio.sfx[name])
  if not header then return false end
  return requestEffect(data, header, sfxOptions(pitch, tempo, plainFrames))
end

function ChipAudio.prewarmCry(data, species, resolved)
  local cry = data.audio and cryDef(data, species, resolved)
  if not cry then return false end
  local header = cry.chip and cry or cry.header
  if not header then return false end
  return requestEffect(data, header, cryOptions(cry))
end

function ChipAudio.pumpEffects()
  if suspended then return end
  pushHeld = false
  if fxCh then pumpEffects() end
end

function ChipAudio.prewarmPinned(fn, ...)
  local was = pinRequests
  pinRequests = true
  local ok, err = pcall(fn, ...)
  pinRequests = was
  if not ok then error(err, 0) end
end

function ChipAudio.prewarmFront(fn, ...)
  local was = frontRequests
  frontRequests = true
  pushHeld = true
  local ok, err = pcall(fn, ...)
  frontRequests = was
  if not ok then error(err, 0) end
end

-- test hook: prewarm bookkeeping
function ChipAudio._effectStateForTest()
  local pending = 0
  for _ in pairs(fxPending) do pending = pending + 1 end
  return { ready = fxReadyCount, pending = pending, epoch = fxEpoch,
           queued = #fxQueue, inFlight = fxInFlightCount,
           pinned = fxPinnedCount, unpinnedReady = fxOrderCount }
end

-- Two channels for the same reason ChipSynth.renderEffectData renders stereo:
-- a mono Source is spatialized by OpenAL at the listener position and spreads
-- over every output an interface has (#626).  The siren itself is unchanged,
-- both channels carry the same sample.
-- PlayDanger (audio/engine.asm:531) counts one frame per call and resets with
-- `cp 30 / jr c, .noreset`, so the cycle is frames 0..29 and the buffer holds
-- exactly two of them.  DangerSoundHigh goes in on the `and a / jr z, .begin`
-- frame 0 and DangerSoundLow on the `cp 16 / jr z, .halfway` frame 16, so the
-- high tone owns 0..15 and the low tone 16..29.
function ChipAudio.newLowHealthAlarm()
  local SAMPLE_RATE = sampleRate()
  local samples = math.floor(SAMPLE_RATE * 60 / 60)
  local data = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 2)
  local pointer = ChipSynth._int16Pointer(data)
  local phase = 0
  for index = 0, samples - 1 do
    local frame = math.floor(index * 60 / SAMPLE_RATE) % 30
    local register = frame < 16 and 0x750 or 0x6EE
    local frequency = 131072 / (2048 - register)
    phase = (phase + frequency / SAMPLE_RATE) % 1
    local value = (phase < 0.5 and 1 or -1) * 0.25
    if pointer then
      -- same int16 setSample stores (ChipSynth bulk PCM writes)
      pointer[index * 2] = value * 32767
      pointer[index * 2 + 1] = value * 32767
    else
      data:setSample(index, 1, value)
      data:setSample(index, 2, value)
    end
  end
  return love.audio.newSource(data, "static")
end

-- ---------------------------------------------------------------------------
-- test hooks (headless): synchronous synthesis straight through ChipSynth
-- ---------------------------------------------------------------------------

function ChipAudio._setAudioStatsForTest(flag)
  STATS = not not flag
  statFrames, statUnderruns, statRestarts = 0, 0, 0
  statDepthMin, statDepthSum, statDepthFrames = nil, 0, 0
  statWorkerJit, statWorkerXrt = nil, nil
  statXrtSum, statXrtCount, statXrtMax, lastCosted = 0, 0, nil, nil
end

function ChipAudio._audioStatsForTest()
  return { frames = statFrames, underruns = statUnderruns,
           restarts = statRestarts }
end

-- Force the "threaded, first buffer not yet queued" window so Music's
-- playOnce / pendingRestore race can be asserted without love.thread.
-- Returns a clear() that drops the override (call after the assertion).
function ChipAudio._simulateAwaitingFirstBufferForTest()
  local m = currentMusic
  if not m or not m.source then return nil end
  m.threaded = true
  m.started = false
  m.finished = false
  pcall(function() m.source.playing = false end)
  forceAwaitingFirstBuffer = true
  return function() forceAwaitingFirstBuffer = nil end
end

function ChipAudio._renderMusicForTest(data, header, seconds)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  return ChipSynth.soundData(engine, math.floor(seconds * sampleRate()), 2)
end

function ChipAudio._renderMusicChannelForTest(data, header, seconds, number)
  local SAMPLE_RATE = sampleRate()
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  local samples = math.floor(seconds * SAMPLE_RATE)
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)
  for index = 0, samples - 1 do
    result:setSample(index, engine:sampleChannel(number))
  end
  return result
end

function ChipAudio._traceFirstMusicSampleForTest(data, header)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  local result = {}
  for _, channel in ipairs(engine.channels) do
    local value = channel:sample()
    local event = channel.event or {}
    result[#result + 1] = {
      number = channel.number,
      value = value,
      register = event.register,
      duration = event.duration,
      volume = event.volume,
      duty = event.duty,
      wave = event.wave,
      waveInstrument = event.waveInstrument,
      drumSegments = event.drum and #event.drum or nil,
      noiseParameter = event.noiseParameter,
      sweep = event.sweep,
    }
  end
  return result
end

function ChipAudio._traceFirstSfxSampleForTest(data, header)
  local engine = ChipSynth.newEngine(data, header, {
    sfx = true,
    allowLoops = false,
  })
  local result = {}
  for _, channel in ipairs(engine.channels) do
    local value = channel:sample()
    local event = channel.event or {}
    result[#result + 1] = {
      number = channel.number,
      value = value,
      register = event.register,
      duration = event.duration,
      volume = event.volume,
      fade = event.fade,
      noiseParameter = event.noiseParameter,
      sweep = event.sweep,
    }
  end
  return result
end

function ChipAudio._renderSfxForTest(data, header, seconds)
  local engine = ChipSynth.newEngine(data, header, {
    sfx = true,
    allowLoops = false,
  })
  return ChipSynth.soundData(engine, math.floor(seconds * sampleRate()), 1)
end

return ChipAudio
