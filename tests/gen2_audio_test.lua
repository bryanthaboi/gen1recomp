-- Gen 2 ChipSynth channel driver smoke against a Gold cache.
--   luajit tests/gen2_audio_test.lua
-- Also dofile'd by tests/run_tests.lua.  Skips when no gold cache / audio.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 audio")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local ChipSynth = require("src.core.ChipSynth")

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end

local audioPath = cache .. "/data/generated/audio.lua"
local progPath = cache .. "/assets/generated/audio/programs.bin"
local audioFile = io.open(audioPath, "r")
local progFile = io.open(progPath, "rb")
if not audioFile or not progFile then
  if audioFile then audioFile:close() end
  if progFile then progFile:close() end
  check(true, "gold audio cache absent : SKIP")
  S.finish()
  return
end
audioFile:close()
progFile:close()

local audio = assert(loadfile(audioPath))()
check(audio.generation == 2, "audio.generation is 2")
if audio.runtime ~= true then
  check(true, "audio.runtime still false : re-import Gold to exercise driver (SKIP synth)")
  S.finish()
  return
end
check(audio.bankOrder[1] == 0x07, "Gen 2 banks start at $07 (not Gen 1 $02)")
check(audio.bankOrder[3] == 0x3a, "engine/songs bank $3A present")
check(audio.songs and audio.songs.Music_TitleScreen, "Music_TitleScreen header")
check(audio.songs and audio.songs.Music_NewBarkTown, "Music_NewBarkTown header")
check(audio.waveBanks and audio.waveBanks["1"], "WaveSamples waveBanks[1]")
check(audio.drumkits and audio.drumkits.bank == 0x3a, "Drumkits in bank $3A")
eq(audio.mapSongs and audio.mapSongs.NEW_BARK_TOWN, "Music_NewBarkTown",
  "New Bark mapSongs → Music_NewBarkTown")

local title = audio.songs.Music_TitleScreen
eq(title.bank, 0x3a, "TitleScreen bank")
eq(title.address, 0x77b1, "TitleScreen address (pokegold.sym)")

-- love_stub has no real PhysFS; inject programs.bin for ChipSynth.loadBanks.
local prog = assert(io.open(progPath, "rb"))
local progBytes = prog:read("*a")
prog:close()
love.filesystem.write(audio.programFile, progBytes)

local data = { audio = audio }
local ok, engine = pcall(ChipSynth.newEngine, data, title, { allowLoops = true })
check(ok, "TitleScreen engine builds" .. (ok and "" or (": " .. tostring(engine))))
if ok then
  eq(engine.generation, 2, "engine.generation is 2")
  eq(#engine.channels, 4, "TitleScreen has 4 channels")
  -- Ch1 opens with tempo 256 (titlescreen.asm)
  engine.channels[1]:nextEvent()
  eq(engine.tempo, 256, "Ch1 tempo command → 256")
  -- Render a short slice; must produce non-silent PCM.
  local left, right = 0, 0
  local peak = 0
  for _ = 1, ChipSynth.SAMPLE_RATE do -- 1 second
    local l, r = engine:sampleStereo()
    left, right = left + l, right + r
    peak = math.max(peak, math.abs(l), math.abs(r))
  end
  check(peak > 0.01, "TitleScreen renders audible samples (peak=" .. peak .. ")")
  -- audio/drumkits.asm kit 5: the NR42 envelope rings on past the noise_note
  -- script, so a snare must outlast the one frame its script occupies.
  local frame = ChipSynth.SAMPLE_RATE / 60
  local snare = engine:drumInstrumentGen2(5, 1)
  check(snare[#snare].endSample > frame * 2,
    "kit 5 snare rings past its script (" .. snare[#snare].endSample .. " samples)")
end

local bark = audio.songs.Music_NewBarkTown
ok, engine = pcall(ChipSynth.newEngine, data, bark, { allowLoops = true })
check(ok, "NewBarkTown engine builds" .. (ok and "" or (": " .. tostring(engine))))
if ok then
  eq(#engine.channels, 3, "NewBarkTown has 3 channels")
  engine.channels[1]:nextEvent()
  eq(engine.tempo, 187, "NewBarkTown tempo 187")
end

-- SFX / cries (present after re-import with sfxOrder extract).
if type(audio.sfx) == "table" and audio.sfx.Sfx_CaughtMon then
  check(audio.sfx.Sfx_CaughtMon.generation == 2, "Sfx_CaughtMon is Gen 2 header")
  check(audio.sfxOrder and audio.sfxOrder[3] == "Sfx_CaughtMon",
    "sfxOrder[3] is Sfx_CaughtMon (SFX id 2)")
  check(audio.sfxOrder and audio.sfxOrder[48] == "Sfx_Kinesis",
    "sfxOrder[48] is Sfx_Kinesis (SFX id 47)")
  check(audio.sfxOrder and audio.sfxOrder[21] == "Sfx_WarpFrom",
    "sfxOrder[21] is Sfx_WarpFrom (SFX id 20)")
  local sfxOk, sfxEng = pcall(ChipSynth.newEngine, data, audio.sfx.Sfx_CaughtMon, {
    sfx = true, allowLoops = false,
  })
  check(sfxOk, "Sfx_CaughtMon engine builds"
    .. (sfxOk and "" or (": " .. tostring(sfxEng))))
else
  check(true, "sfx table absent : re-import Gold for SFX coverage (SKIP)")
end
if type(audio.cries) == "table" and audio.cries.MARILL then
  local cry = audio.cries.MARILL
  check(cry.header and cry.header.bank, "MARILL cry has header")
  check(type(cry.pitch) == "number", "MARILL cry pitch")

  -- A cry is a channel of `square_note` rows, not packed music notes, and the
  -- port used to parse it as the latter: the envelope byte read as a second
  -- note and the frequency low byte as a note_type command that ate two more.
  -- The audible result was a cry that ran until renderEffectData's five-second
  -- cap.  Cry_Marill_Ch5 opens `duty_cycle_pattern 0,2,0,2` then
  -- `square_note 2, 8, 8, 1752`, so the first event has to come back as a tone
  -- three frames long (SetNoteDuration: tempo 288 * (2+1) >> 8) at register
  -- 1752 + the cry's own pitch offset.
  local cryOk, cryEng = pcall(ChipSynth.newEngine, data, cry.header, {
    sfx = true, allowLoops = false,
    frequencyOffset = cry.pitch, cryLength = cry.length,
  })
  check(cryOk, "MARILL cry engine builds"
    .. (cryOk and "" or (": " .. tostring(cryEng))))
  if cryOk then
    -- "Tempo is effectively length" (_PlayCry): the length word IS the tempo,
    -- with no $80 base -- that base is Gen 1's Audio_SetSfxTempo.
    eq(cryEng.channels[1].frameTicks, cry.length,
      "the cry's tempo is its length word, not $80 + it")
    local event = cryEng.channels[1]:nextEvent()
    check(event ~= nil, "the first square_note yields an event")
    if event then
      eq(event.register, (1752 + cry.pitch) % 0x800,
        "and it is a tone at the note's own frequency register")
      eq(event.volume, 8, "with the envelope byte's volume")
      eq(math.floor(event.duration * 60 + 0.5), 3,
        "and SetNoteDuration's three frames")
    end
    -- The whole cry, which on the cart is well under a second.
    local frames = 0
    for _ = 1, 64 do
      local next_ = cryEng.channels[1]:nextEvent()
      if not next_ then break end
      frames = frames + next_.duration * 60
    end
    check(frames < 60,
      ("channel 5 runs %.0f frames, under a second"):format(frames))

    -- ../pokecrystal/audio/engine.asm:105
    local ch = cryEng.channels[1]
    local zero, worst = false, nil
    for tempo = 1, 576 do
      ch.frameTicks, ch.durationModifier, ch.noteLength = tempo, 0, 1
      for length = 0, 15 do
        if ch:durationTicksGen2(length) <= 0 then
          zero, worst = true, ("tempo %d length %d"):format(tempo, length)
        end
      end
    end
    check(not zero, "SetNoteDuration never yields a zero-frame note"
      .. (worst and (" (" .. worst .. ")") or ""))
  end
else
  check(true, "cries table absent : re-import Gold for cry coverage (SKIP)")
end

-- ../pokecrystal/audio/cries.asm:486
if type(audio.cries) == "table" and audio.cries.CYNDAQUIL then
  local cry = audio.cries.CYNDAQUIL
  eq(cry.length, 128, "CYNDAQUIL cry length word is 128")
  local cryOk, cryEng = pcall(ChipSynth.newEngine, data, cry.header, {
    sfx = true, allowLoops = false,
    frequencyOffset = cry.pitch, cryLength = cry.length,
  })
  check(cryOk, "CYNDAQUIL cry engine builds"
    .. (cryOk and "" or (": " .. tostring(cryEng))))
  if cryOk then
    for index = 1, 2 do
      local frames, events, dropped = 0, 0, 0
      for _ = 1, 128 do
        local event = cryEng.channels[index]:nextEvent()
        if not event then break end
        events = events + 1
        if event.duration * 60 < 0.5 then dropped = dropped + 1 end
        frames = frames + event.duration * 60
      end
      eq(dropped, 0, ("channel %d drops no note"):format(index + 4))
      eq(math.floor(frames + 0.5), 20,
        ("channel %d runs the cart's 20 frames"):format(index + 4))
      check(events == 17, ("channel %d keeps all 17 notes (%d)")
        :format(index + 4, events))
    end
  end
else
  check(true, "CYNDAQUIL cry absent : re-import Gold for cry coverage (SKIP)")
end

-- Which sfx silence the music.  On the cart sfx channel N takes hardware
-- channel N over from the music channel with the same number, so a
-- FOUR-channel sfx leaves the song nothing to play through -- and every jingle
-- is four channels.  The port used to duck on a six-name list, so the phone
-- number's jingle (and the TM, the badge, the egg) played over the top.
if type(audio.sfx) == "table" and audio.sfx.Sfx_RegisterPhoneNumber then
  local function channels(name)
    local list = ChipSynth.effectChannels(data, audio.sfx[name])
    return list and #list or 0
  end
  eq(channels("Sfx_RegisterPhoneNumber"), 4,
    "Sfx_RegisterPhoneNumber claims all four channels")
  eq(channels("Sfx_Item"), 4, "Sfx_Item claims all four")
  eq(channels("Sfx_GetBadge"), 4, "Sfx_GetBadge claims all four")
  -- Three-channel move sounds must NOT duck: they fire several times a second
  -- inside an animation and pausing the song under each would stutter.
  eq(channels("Sfx_Psychic"), 3, "Sfx_Psychic is three channels")
  eq(channels("Sfx_ReadText2"), 1, "the A-press beep is one channel")

  local Sound = require("src.core.Sound")
  check(Sound.ducksMusic(data, "Sfx_RegisterPhoneNumber"),
    "the phone-number jingle mutes the music")
  check(Sound.ducksMusic(data, "Sfx_GetBadge"),
    "so does the badge fanfare")
  check(not Sound.ducksMusic(data, "Sfx_Psychic"),
    "a three-channel move sound does not")
  check(not Sound.ducksMusic(data, "Sfx_ReadText2"),
    "and neither does the A-press beep")
  -- Sfx_Fanfare is only three channels (5, 6 and 8) and is a jingle anyway.
  check(Sound.ducksMusic(data, "Sfx_Fanfare"),
    "the three-channel Sfx_Fanfare is still named as a jingle")
else
  check(true, "sfx table absent, re-import Gold for duck coverage (SKIP)")
end

if bark then
  local function renderBark(rate, seconds)
    ChipSynth.setSampleRate(rate)
    local eng = ChipSynth.newEngine(data, bark, { allowLoops = true })
    local event = eng.channels[1]:nextEvent()
    local sd = ChipSynth.soundData(eng, math.floor(seconds * rate), 2)
    return sd, event
  end
  local full, fullEvent = renderBark(44100, 0.5)
  local half, halfEvent = renderBark(22050, 0.5)
  ChipSynth.setSampleRate(44100)
  eq(half:getSampleCount(), math.floor(full:getSampleCount() / 2),
    "half the synth rate is half the samples for the same half second")
  eq(half:getSampleRate(), 22050, "and the SoundData is tagged with it")
  eq(halfEvent.register, fullEvent.register,
    "the first note's frequency register does not move with the rate")
  eq(halfEvent.volume, fullEvent.volume, "nor its volume")
  check(math.abs(halfEvent.duration - fullEvent.duration) < 1e-9,
    "nor how long it lasts in seconds")
end

S.finish()
