-- ChipAudio synthesis worker (love.thread).  Runs the Game Boy audio synth
-- (src/core/ChipSynth.lua) off the main thread so a map/battle song change
-- never stutters the render thread: filling the ~6s playback queue from
-- scratch is ~200ms of Lua synthesis, and this is where it now happens.
--
-- Protocol -- main thread pushes command tables onto the "chipaudio_cmd"
-- channel and drains produced buffers off "chipaudio_out":
--   cmd = "play"  { gen, header, allowLoops, audio,
--                   channelVolumes?, channelPitches?, stereo?, stereoEpoch? }
--   cmd = "stop"                                       halt production
--   cmd = "channelMix" { volumes, pitches, stereo?, stereoEpoch? }
--                   stereoEpoch present: live SOUND toggle; drop lookahead
--   cmd = "invalidate"                                 drop the bank cache
--   cmd = "quit"                                        end the thread
-- out buffers are tagged with the play's `gen` so the main thread can
-- discard anything left over from a superseded song:
--   { gen, sd = SoundData }   one rendered buffer
--   { gen, done = true }      the song ended (non-looping jingle finished)
--   { gen, error = msg }      build/synth failed; main logs and gives up

require("love.thread")
require("love.timer")
require("love.sound")
require("love.filesystem")

-- Load the synth explicitly via love.filesystem (a fresh thread Lua state does
-- not necessarily carry the package searcher that resolves "src.core..."):
local ChipSynth = assert(love.filesystem.load("src/core/ChipSynth.lua"))()

local cmdCh = love.thread.getChannel("chipaudio_cmd")
local outCh = love.thread.getChannel("chipaudio_out")

local BUF = ChipSynth.MUSIC_BUFFER_SAMPLES
-- how many finished buffers may sit in the hand-off channel before the worker
-- pauses.  The deep (~6s) playback depth lives in the main-thread Source; this
-- only bounds the worker's look-ahead (and its memory) between drains.
local LOOKAHEAD = 8

local gen = nil        -- active song generation, or nil when stopped
local engine = nil     -- the ChipSynth engine producing the current song
local finished = false -- the current song ran out (non-looping)
local data = nil       -- { audio = <slim audio tables> } for ROM bank/wave reads
local stereoEpoch = 0  -- matches ChipAudio; stale pan buffers are dropped

local function handle(cmd)
  if cmd.cmd == "play" then
    gen = cmd.gen
    finished = false
    engine = nil
    outCh:clear() -- drop any buffers left from the previous song
    data = { audio = cmd.audio }
    if cmd.channelVolumes ~= nil then
      ChipSynth.setChannelVolumes(cmd.channelVolumes)
    end
    if cmd.channelPitches ~= nil then
      ChipSynth.setChannelPitches(cmd.channelPitches)
    end
    if cmd.stereo ~= nil then
      ChipSynth.setStereo(cmd.stereo)
    end
    if cmd.stereoEpoch ~= nil then stereoEpoch = cmd.stereoEpoch end
    local ok, eng = pcall(ChipSynth.newEngine, data, cmd.header,
                          { allowLoops = cmd.allowLoops })
    if ok then
      engine = eng
    else
      outCh:push({ gen = gen, error = tostring(eng) })
      finished = true
    end
  elseif cmd.cmd == "stop" then
    gen = nil
    engine = nil
    finished = false
    outCh:clear()
  elseif cmd.cmd == "channelMix" then
    if cmd.volumes ~= nil then ChipSynth.setChannelVolumes(cmd.volumes) end
    if cmd.pitches ~= nil then ChipSynth.setChannelPitches(cmd.pitches) end
    if cmd.stereo ~= nil then ChipSynth.setStereo(cmd.stereo) end
    if engine and cmd.stereo ~= nil then ChipSynth.applyStereo(engine) end
    if cmd.stereoEpoch ~= nil then
      stereoEpoch = cmd.stereoEpoch
      outCh:clear()
    end
  elseif cmd.cmd == "invalidate" then
    ChipSynth.invalidateBanks()
  elseif cmd.cmd == "quit" then
    return true
  end
  return false
end

local idleWait = false

while true do
  -- drain every pending command first, so a stop/new-play is seen promptly
  local quit = false
  local cmd = idleWait and cmdCh:demand(0.05) or cmdCh:pop()
  while cmd do
    if handle(cmd) then quit = true end
    cmd = cmdCh:pop()
  end
  if quit then break end

  if engine and not finished and gen and outCh:getCount() < LOOKAHEAD then
    idleWait = false
    local activeGen = gen
    local ok, sd = pcall(ChipSynth.soundData, engine, BUF, 2)
    if not ok then
      outCh:push({ gen = activeGen, error = tostring(sd),
                   stereoEpoch = stereoEpoch })
      finished = true
    else
      outCh:push({ gen = activeGen, sd = sd, stereoEpoch = stereoEpoch })
      if engine:finished() then
        outCh:push({ gen = activeGen, done = true, stereoEpoch = stereoEpoch })
        finished = true
      end
    end
  elseif engine and not finished and gen then
    idleWait = false
    love.timer.sleep(0.005)
  else
    idleWait = true
  end
end
