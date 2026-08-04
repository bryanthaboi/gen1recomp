-- Every one-shot the engine synthesizes must land in a two-channel buffer
-- (#626).  OpenAL only spatializes 1-channel Sources, and nothing in this
-- repo ever calls setPosition/setRelative, so a mono effect Source sat at the
-- default (0,0,0) -- on top of the listener -- which OpenAL Soft renders as
-- an ambient sound spread over EVERY output channel the device exposes.  On a
-- 6-channel interface the SFX therefore also came out of outputs 5+6 at gains
-- that differ from the front pair, while the music stayed put because
-- ChipAudio.playMusic is a 2-channel queueable source.  Multi-channel buffers
-- skip spatialization outright, so the channel count is the invariant to
-- guard; the routing itself only an ear on a multi-output interface can
-- settle (tests/drivers).
--
-- The duplication is also the faithful default: pokered's stereo panning byte
-- (audio/engine_1.asm Audio1_stereo_panning -> wStereoPanning -> rAUDTERM)
-- is 0xFF, both sides, for everything that never issues command 0xEE.
-- ROM-free: ChipAsm blobs, no data/generated/.
--   luajit tests/engine/effect_stereo_bug626.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

local ChipAsm = require("src.audio.ChipAsm")
local ChipSynth = require("src.core.ChipSynth")
local ChipAudio = require("src.core.ChipAudio")

-- a short blob effect: one audible note on a pulse channel, no loops (the
-- effect renderer forces allowLoops=false anyway)
local beep = ChipAsm.song{
  tempo = 0x100,
  channels = { { hw = 1, program = {
    { duty = 2 },
    { notetype = { speed = 12, volume = 12, fade = 0 } },
    { octave = 4 },
    { note = "C", len = 12 },
    { note = "E", len = 12 },
  } } },
}
local blobData = { audio = { sfx = {}, cries = {} } }

local sd = ChipSynth.renderEffectData(blobData, beep, {})
check(sd ~= nil, "the blob effect renders at all")
check(sd:getChannelCount() == 2,
  ("an effect buffer is stereo, not %d channel(s)")
    :format(sd:getChannelCount()))

-- both channels must carry the identical sample: the synthesis stays mono
-- (Engine:sample, not the music path's Engine:sampleStereo), so the only
-- thing that changed for a listener is which outputs the sound reaches
local frames = sd:getSampleCount()
local mismatched, nonzero = 0, 0
for index = 0, frames - 1 do
  local left, right = sd:getSample(index, 1), sd:getSample(index, 2)
  if left ~= right then mismatched = mismatched + 1 end
  if left ~= 0 then nonzero = nonzero + 1 end
end
check(nonzero > 0, "the effect buffer is not silent")
check(mismatched == 0,
  ("both channels carry the same sample (%d frames differ)")
    :format(mismatched))

-- The low-health siren is hand-synthesized rather than going through the
-- effect renderer, so it needs its own guard (ChipAudio.newLowHealthAlarm).
-- tests/love_stub carries no love.audio (headless suites never play), so the
-- buffer is caught on its way into newSource.
local captured
love.audio = { newSource = function(sd) captured = sd; return { sd } end }
local alarmOk, alarmErr = pcall(ChipAudio.newLowHealthAlarm)
love.audio = nil
check(alarmOk, ("the low-health siren builds: %s"):format(tostring(alarmErr)))
check(captured ~= nil and captured:getChannelCount() == 2,
  "the low-health siren is stereo")
if captured then
  local siren = 0
  for index = 0, captured:getSampleCount() - 1 do
    if captured:getSample(index, 1) ~= captured:getSample(index, 2) then
      siren = siren + 1
    end
  end
  check(siren == 0, "both siren channels carry the same sample")
end

T.finish("effect stereo (#626)")
