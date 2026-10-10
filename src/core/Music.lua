local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local Music = {}

local VOLUME = 0.7

local volumeScale = 1
local storedVolumeLevel = 7
local currentAudioMode = "both"
local FILTER_HIGHGAIN = { 0.4, 0.16, 0.064 }
local filterLevel = 0

local state

local function applyVolume(src)
  if not src then return end
  local vol = VOLUME * volumeScale
  if Runtime.wantsHook("music.volume") then
    local ctx = {
      song = state.current,
      mapSong = state.mapSong,
      onBike = state.onBike,
      surfing = state.surfing,
      fading = state.fade ~= nil,
      optionScale = volumeScale,
    }
    local Game = package.loaded["src.core.Game"]
    if type(Game) == "table" then
      local ow = Game.overworld
      if ow and ow.player then
        ctx.x, ctx.y = ow.player.cellX, ow.player.cellY
        ctx.mapId = ow.map and ow.map.id
        ctx.tod = ow.tod
      end
    end
    vol = Runtime.call("music.volume", function(v) return v end, vol, ctx)
    vol = tonumber(vol) or (VOLUME * volumeScale)
    if vol < 0 then vol = 0 end
  end
  pcall(src.setVolume, src, vol)
end

-- Source:setFilter needs OpenAL EFX; the pcall degrades to unfiltered
-- audio where it's missing (and under the headless stub)
local function applyFilter(src)
  if not src then return end
  if filterLevel > 0 then
    pcall(src.setFilter, src, { type = "lowpass", volume = 1,
                                highgain = FILTER_HIGHGAIN[filterLevel] })
  else
    pcall(src.setFilter, src)
  end
end

state = {
  current = nil,      -- song label
  chip = false,       -- the playing song is a synthesized channel program
  source = nil,       -- currently playing source
  loopSource = nil,   -- pre-loaded loop body waiting for the intro to end
  mapSong = nil,      -- song to restore after a battle
  onBike = false,     -- bike theme overrides outdoor map themes
  surfing = false,    -- surf theme likewise (home/audio.asm MUSIC_SURFING)
  pendingRestore = nil,
  fanfare = nil,      -- fanfare SFX source; the song pauses while it plays
  fanfareResume = false, -- start/resume state.source when the fanfare ends
  fade = nil,         -- active volume-ramp fade-out (see Music.fadeOut)
  fadeCount = 0,      -- wMusicFadeCount (pokecrystal ram/wram.asm:71)
  tempo = nil,        -- alternate-tempo override in force for `current`
  start = nil,
  data = nil,
  loop = nil,
  failed = {},        -- labels whose def could not be started; logged once
}

-- Is a fanfare SFX (Sound.lua's FANFARES) still sounding?
local function fanfareActive()
  local src = state.fanfare
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  if ok and playing then return true end
  state.fanfare = nil
  require("src.core.ChipAudio").holdMusic(false)
  return false
end

-- Called by Sound.play when a fanfare starts: fanfares own the music
-- channels on the Game Boy, so the current song halts and resumes when
-- the jingle ends (see update()).
function Music.duckForFanfare(src)
  if not src then return end
  state.fanfare = src
  -- ChipAudio is what starts a chip song, so the pause below cannot hold one
  -- that has not started yet (nor one Music.play swaps in mid-jingle) (#398)
  require("src.core.ChipAudio").holdMusic(true)
  if state.source then
    local ok, playing = pcall(state.source.isPlaying, state.source)
    if ok and playing then
      pcall(state.source.pause, state.source)
      state.fanfareResume = true
    end
  end
end

local OUTDOOR = {
  Music_PalletTown = true,
  Music_Cities1 = true,
  Music_Cities2 = true,
  Music_Celadon = true,
  Music_Cinnabar = true,
  Music_Vermilion = true,
  Music_Lavender = true,
  Music_Routes1 = true,
  Music_Routes2 = true,
  Music_Routes3 = true,
  Music_Routes4 = true,
  Music_IndigoPlateau = true,
  Music_SafariZone = true,
  Music_Dungeon1 = true,
  Music_Dungeon2 = true,
  Music_Dungeon3 = true,
}

-- Scene themes the engine asks for by role rather than by label, so a total
-- conversion can rename every song.  data.audio.special supersedes this.
local SPECIAL = {
  heal = "Music_PkmnHealed",
  title = "Music_TitleScreen",
  credits = "Music_Credits",
  hallOfFame = "Music_HallOfFame",
  introBattle = "Music_IntroBattle",
  oakRoute = "Music_Routes2",
  bike = "Music_BikeRiding",
  surf = "Music_Surfing",
  evolution = "Music_SafariZone",
}

-- SpecialMapMusic (pokegold home/audio.asm:397)
local SPECIAL_GEN2 = {
  surf = "Music_Surf",
  bike = "Music_Bicycle",
  evolution = "Music_Evolution",
}

-- the label a scene role resolves to; call sites keep their own presence
-- guard on the resolved label
function Music.special(data, key)
  local special = data and data.audio and data.audio.special
  local label = special and special[key]
  if label ~= nil then return label end
  if data and data.audio and data.audio.generation == 2
     and SPECIAL_GEN2[key] ~= nil then
    return SPECIAL_GEN2[key]
  end
  return SPECIAL[key]
end

local function outdoorSongs(data)
  return data and data.audio and data.audio.outdoorSongs or OUTDOOR
end

local function songDef(data, song)
  return data and data.audio and data.audio.songs and data.audio.songs[song]
end

-- which mod put this label in the registry, for attributed failure logs
local function songOwner(data, song)
  local owners = data and data.audio and data.audio._owners
  local songs = owners and owners.songs
  return songs and songs[song] or "base"
end

-- one log line, plus an entry in the loader's error feed when a mod owns the
-- def, so the manager's errors screen can flag that mod
local function reportBadDef(data, song, err)
  local who = songOwner(data, song)
  Logger.warn("audio: bad song def %q (mod %s): %s", song, who, tostring(err))
  Runtime.reportError(who,
    ("audio: bad song def %q: %s"):format(song, tostring(err)))
end

local function stopSource(src)
  if src then pcall(src.stop, src) end
end

local function newSource(file)
  local ok, src = pcall(love.audio.newSource, file, "stream")
  if ok and src then return src end
  return nil, ok and "no source" or tostring(src)
end

-- Build the new song's sources; the caller only tears the old song down
-- once this succeeded, so a broken def costs nothing but a log line.
-- Returns src, loopSrc, isChip -- or nil plus the reason.
local function startSong(data, def, wantLoop)
  if def.chip or (def.address and def.bank) then
    local ok, src = pcall(
      require("src.core.ChipAudio").playMusic, data, def, wantLoop)
    if ok and src then return src, nil, true end
    return nil, nil, nil, ok and "no source" or tostring(src)
  elseif def.file then
    local src, err = newSource(def.file)
    if not src then return nil, nil, nil, err end
    -- a missing loop body degrades to the intro file alone
    local loopSrc = def.loopFile and newSource(def.loopFile) or nil
    return src, loopSrc, false
  end
  return nil, nil, nil, "no chip program and no file"
end

-- Music_MeetRival_Ch{1,2,3}_AlternateStart (audio/alternate_tempo.asm:7)
local RIVAL_ALT_START = {
  redblue = { 0x71a2, 0x721d, 0x72b5 },
  yellow = { 0x7075, 0x70f0, 0x7188 },
}

-- the single choke point every song choice passes through, so one hook
-- covers map themes, battle themes, jingles and scene music
local function selectSong(song, ctx)
  if ctx and ctx.selected then return song end
  if not Runtime.wantsHook("music.select") then return song end
  return Runtime.call("music.select", function(chosen) return chosen end, song, {
    reason = ctx and ctx.reason or "direct",
    mapId = ctx and ctx.mapId,
    mapSong = state.mapSong,
    onBike = state.onBike,
    surfing = state.surfing,
    kind = ctx and ctx.kind,
    battleKind = ctx and ctx.kind,
    trainerId = ctx and ctx.trainerId,
  })
end

function Music.play(data, song, loop, ctx)
  if not song then return end
  if not (love and love.audio) then return end -- headless test stub
  ctx = ctx or {}
  song = selectSong(song, ctx)

  local tempo = ctx and ctx.tempo or nil
  local start = ctx and ctx.start or nil
  -- a hook may silence the cue outright, or swap in a label the dedupe
  -- below has to compare against
  if not song then return end
  if song == state.current and tempo == state.tempo
      and start == state.start then
    -- ..(home/audio.asm ln 65)
    if state.fade and state.fade.pending then
      state.fade = nil
      applyVolume(state.source)
      applyVolume(state.loopSource)
    end
    return
  end
  local def = songDef(data, song)
  if not def or state.failed[song] then return end

  local gen2 = data and data.audio and data.audio.generation == 2
  -- pokecrystal home/audio.asm:308-322
  if ctx.fade and (state.source or gen2) then
    local queued = {}
    for key, value in pairs(ctx) do queued[key] = value end
    queued.fade, queued.selected = nil, true
    local pending = { data = data, song = song, loop = loop, ctx = queued }
    if state.fade and not state.fade.gen2 then
      state.fade.pending = pending
    else
      Music.fadeOut(ctx.fade, pending)
    end
    return
  end
  if tempo then
    -- shallow copy: the registry def is shared, only this playback is slowed
    local slowed = {}
    for key, value in pairs(def) do slowed[key] = value end
    slowed.tempo = tempo
    def = slowed
  end
  if start == "rival" and song == "Music_MeetRival"
     and def.bank == 2 and def.address == 17050 then
    local started = {}
    for key, value in pairs(def) do started[key] = value end
    local alt = require("src.core.GameVersion").isYellow()
      and RIVAL_ALT_START.yellow or RIVAL_ALT_START.redblue
    started.startChannels = {
      { number = 1, address = alt[1] },
      { number = 2, address = alt[2] },
      { number = 3, address = alt[3] },
    }
    def = started
  end
  local wantLoop = loop ~= false
  local src, loopSrc, isChip, err = startSong(data, def, wantLoop)
  if not src then
    state.failed[song] = true
    reportBadDef(data, song, err)
    return
  end
  stopSource(state.source)
  stopSource(state.loopSource)
  -- a chip song holds the streaming source; ChipAudio.playMusic already
  -- swapped it when the new song is chip-backed too
  if state.chip and not isChip then require("src.core.ChipAudio").stopMusic() end
  state.fade = nil
  if loopSrc then
    -- intro plays once, then update() chains to the loop body
    -- (for one-shot jingles the body plays once and doesn't repeat)
    pcall(src.setLooping, src, false)
    pcall(loopSrc.setLooping, loopSrc, wantLoop)
    applyVolume(loopSrc)
    applyFilter(loopSrc)
  else
    pcall(src.setLooping, src, wantLoop)
  end
  applyVolume(src)
  applyFilter(src)
  -- a fanfare owns the music channels: hold the new song until it ends
  -- (update() starts it, like the paused-song resume)
  if fanfareActive() then
    state.fanfareResume = true
  elseif not isChip then
    pcall(src.play, src)
  end
  local previous = state.current
  state.source, state.loopSource, state.chip = src, loopSrc, isChip
  state.current = song
  state.tempo = tempo
  state.start = start
  state.data = data
  state.loop = loop
  if Runtime.wants("music.started") then
    Runtime.emit("music.started", {
      song = song, previous = previous, chip = isChip,
      reason = ctx and ctx.reason or "direct",
    })
  end
end

function Music.stop()
  local previous = state.current
  stopSource(state.source)
  stopSource(state.loopSource)
  require("src.core.ChipAudio").stopMusic()
  state.current, state.source, state.loopSource, state.fade = nil, nil, nil, nil
  state.fadeCount = 0
  state.tempo, state.start = nil, nil
  state.data, state.loop = nil, nil
  state.chip = false
  state.pendingRestore = nil
  state.restoreLeft = nil
  if previous and Runtime.wants("music.stopped") then
    Runtime.emit("music.stopped", { song = previous })
  end
end

-- hot reload: forget the failed defs and the playing label so the next cue
-- re-resolves against the freshly merged registries
function Music.reload()
  state.failed = {}
  Music.stop()
end

function Music.fadeOut(control, pending)
  local data = state.data or (pending and pending.data)
  local gen2 = data and data.audio and data.audio.generation == 2
  if not state.source and not gen2 then
    Music.stop()
    if pending then
      Music.play(pending.data, pending.song, pending.loop, pending.ctx)
    end
    return
  end
  if gen2 then
    -- pokecrystal audio/engine.asm:603-631
    local running = state.fade
    state.fade = {
      control = (control or 10) % 64,
      level = running and running.level or 7,
      from = running and running.from or VOLUME * volumeScale,
      pending = pending,
      gen2 = true,
    }
    return
  end
  control = math.max(1, control or 10)
  state.fade = {
    control = control,
    counter = control,
    level = 7,
    from = VOLUME * volumeScale,
    pending = pending,
  }
end

local function fadeSetLevel(f, level)
  f.level = level
  local vol = f.from * level / 7
  if state.source then pcall(state.source.setVolume, state.source, vol) end
  if state.loopSource then
    pcall(state.loopSource.setVolume, state.loopSource, vol)
  end
end

-- pokecrystal audio/engine.asm:693-705, home/audio.asm:294
function Music.fadeIn(control, level)
  if not state.source then return end
  local running = state.fade
  state.fade = {
    control = (control or 4) % 64,
    level = level or (running and running.level) or 7,
    from = running and running.from or VOLUME * volumeScale,
    fadeIn = true,
    gen2 = true,
  }
  if level then fadeSetLevel(state.fade, level) end
end

Music.MAP_FADE = 10

-- the song a map should currently play, honoring the bike/surf overrides;
-- Gen 2 has no outdoor gate (pokegold home/audio.asm:437)
local function effectiveMapSong(data, song)
  if not song then return song end
  local gen2 = data and data.audio and data.audio.generation == 2
  if not gen2 and not outdoorSongs(data)[song] then return song end
  if state.onBike then
    local bike = Music.special(data, "bike")
    if bike and songDef(data, bike) then return bike end
  end
  if state.surfing then
    local surf = Music.special(data, "surf")
    if surf and songDef(data, surf) then return surf end
  end
  return song
end

-- overworld map theme; onBike/surfing override outdoor themes with the
-- bike/surf songs and restore the map theme when they end
function Music.playMap(data, mapId, onBike, surfing, fade, song)
  song = song or (data and data.audio and data.audio.mapSongs
    and mapId and data.audio.mapSongs[mapId]) or nil
  state.mapSong = song
  state.onBike = not not onBike
  state.surfing = not not surfing
  local play = effectiveMapSong(data, song)
  if play then
    Music.play(data, play, nil,
      { reason = "map", mapId = mapId, fade = fade })
  end
end

-- toggle the surf override mid-map (starting/ending a surf)
function Music.setSurfing(data, surfing)
  state.surfing = not not surfing
  local play = effectiveMapSong(data, state.mapSong)
  if play then Music.play(data, play, nil, { reason = "map" }) end
end

-- battle themes; kind = "wild"|"trainer"|"gym"|"final".  `song`, when
-- given, overrides the kind's default -- a mod-set trainer battleTheme.
function Music.playBattle(data, kind, trainerId, song)
  local b = data.audio and data.audio.battle
  if b then
    Music.play(data, song or b[kind] or b.wild, nil,
      { reason = "battle", kind = kind, trainerId = trainerId })
  end
end

-- victory theme (Music_DefeatedWildMon/Trainer/GymLeader): starts the
-- moment the win is decided and loops until the battle screen closes
-- (each Defeated* song ends in `sound_loop 0, .mainloop`); the battle's
-- finish() restores the map theme, like the overworld reload's
-- PlayDefaultMusicFadeOutCurrent.  Returns true if the theme started.
function Music.playVictory(data, kind, trainerId)
  local b = data.audio and data.audio.battle
  local jingle = b and b[kind .. "Win"]
  if jingle and songDef(data, jingle) then
    Music.play(data, jingle, nil,
      { reason = "victory", kind = kind, trainerId = trainerId })
    return true
  end
  return false
end

local function deviceSuspended()
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  return ChipAudio ~= nil and ChipAudio.isSuspended()
end

-- scripts/RedsHouse1F.asm:35-38
local ONE_SHOT_CEILING = 600
Music.ONE_SHOT_CEILING = ONE_SHOT_CEILING

-- one-shot jingle (PkmnHealed, Jigglypuff's song): the map theme
-- resumes when it ends, via update()
function Music.playOnce(data, song)
  if not songDef(data, song) then return false end
  if deviceSuspended() then return false end
  Music.play(data, song, false, { reason = "once" })
  -- play() can no-op (hook silence, failed def); only arm restore when
  -- the jingle actually became current
  if state.current ~= song then return false end
  state.pendingRestore = true
  state.restoreLeft = ONE_SHOT_CEILING
  return true
end

local function chipAwaitingFirstBuffer()
  return state.chip
     and require("src.core.ChipAudio").awaitingFirstBuffer()
end

-- is a playOnce jingle still in flight?  (AnimateHealingMachine's
-- .waitLoop2 / Mom heal / captain rub hold until MUSIC_PKMN_HEALED ends.)
-- pendingRestore stays set from playOnce until Music.update restores the
-- map theme, covering the threaded chip "empty QueueableSource" window
-- where Source:isPlaying is briefly false before the first buffer lands.
function Music.oneShotPlaying()
  return state.pendingRestore == true
end

-- The label of the song that is current, or nil.  A read-only window on the
-- state, for drivers and tests that need to assert what is playing.
function Music.current()
  return state.current
end

-- The remembered map song (wMapMusic), the same read-only window: what a
-- battle's restore will replay.  setMapSong below is the write half.
function Music.mapSong()
  return state.mapSong
end

function Music.fadeLevel()
  local f = state.fade
  if not f then return nil end
  local vol
  if state.source then
    local ok, v = pcall(state.source.getVolume, state.source)
    if ok then vol = v end
  end
  return f.level, f.pending and f.pending.song, vol
end

function Music.restoreMap(data, reason)
  state.current = nil
  state.pendingRestore = nil
  state.restoreLeft = nil
  local play = effectiveMapSong(data, state.mapSong)
  if play then Music.play(data, play, nil, { reason = reason or "map" }) end
end

-- Overwrite the remembered map song without playing anything: the wMapMusic
-- write in pokegold engine/pokegear/pokegear.asm RadioMusicRestartDE.  A radio
-- station's song becomes the map music itself, so a battle's restoreMap brings
-- the STATION back and only the next playMap (a map change) replaces it.
function Music.setMapSong(song)
  state.mapSong = song
end

-- 0-7 music volume (0 mutes), applied to the playing song and the
-- queued loop body as well as everything played later
function Music.setVolumeLevel(level)
  if level ~= nil then storedVolumeLevel = level end
  if currentAudioMode == "external_only" then
    volumeScale = 0
  else
    volumeScale = math.max(0, math.min(7, storedVolumeLevel or 7)) / 7
  end
  applyVolume(state.source)
  applyVolume(state.loopSource)
end

function Music.setAudioMode(mode)
  currentAudioMode = mode or "both"
  if love and love.audio and love.audio.setMixWithSystem then
    pcall(love.audio.setMixWithSystem, currentAudioMode ~= "game_only")
  end
  Music.setVolumeLevel(storedVolumeLevel)
end

function Music.audioMode()
  return currentAudioMode
end

-- music low-pass filter level, 0 (OFF) to 3
function Music.setFilterLevel(level)
  filterLevel = math.max(0, math.min(3, level or 0))
  applyFilter(state.source)
  applyFilter(state.loopSource)
end

function Music.setPitch(pitch)
  pitch = pitch or 1.0
  if state.source then pcall(state.source.setPitch, state.source, pitch) end
  if state.loopSource then pcall(state.loopSource.setPitch, state.loopSource, pitch) end
end

-- re-apply persisted audio options (Game calls this on boot and after
-- loading a save)
function Music.applyOptions(opts)
  if opts and opts.audioMode then
    Music.setAudioMode(opts.audioMode)
  else
    Music.setAudioMode(currentAudioMode)
  end
  Music.setVolumeLevel(opts and opts.musicVol or storedVolumeLevel or 7)
  Music.setFilterLevel(opts and opts.musicFilter or 0)
  -- engine/menus/options_menu.asm SOUND row (wOptions STEREO bit)
  local ChipAudio = require("src.core.ChipAudio")
  local data, song, loop = state.data, state.current, state.loop
  local tempo, start, wasChip = state.tempo, state.start, state.chip
  if ChipAudio.applyOptions(opts) and wasChip and data and song then
    Music.stop()
    Music.play(data, song, loop, { reason = "audiorate", selected = true,
                                   tempo = tempo, start = start })
  end
  ChipAudio.setStereo(opts and opts.sound == "STEREO")
  -- setStereo may swap the queueable source so the new pan is not sitting
  -- behind already-mixed buffers; re-bind so volume/filter follow (#1471)
  if state.chip then
    local src = ChipAudio.currentSource()
    if src then
      state.source = src
      applyVolume(src)
      applyFilter(src)
    end
  end
end

function Music.onDeviceReset()
  if not love.audio then return end
  if state.chip then
    local src = require("src.core.ChipAudio").currentSource()
    if not src then return end
    state.source = src
    applyVolume(src)
    applyFilter(src)
    return
  end
  local data, song = state.data, state.current
  if not (data and song) then return end
  local loop, tempo, start = state.loop, state.tempo, state.start
  state.current = nil
  Music.play(data, song, loop, { reason = "devicereset", selected = true,
                                 tempo = tempo, start = start })
end

local function sourceStopped(src)
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  return ok and not playing
end

-- call once per frame: chains a finished intro into its loop body and
-- restores the map theme after a one-shot jingle
function Music.update(data)
  if state.chip then require("src.core.ChipAudio").update() end
  -- distance / indoor muffling mods re-apply volume every frame while
  -- subscribed; otherwise applyVolume only runs on song/option changes
  if Runtime.wantsHook("music.volume") and not state.fade then
    applyVolume(state.source)
    applyVolume(state.loopSource)
  end
  if state.fade then
    local f = state.fade
    local function finish()
      -- home/fade_audio.asm:36-45
      state.fade = nil
      local pending = f.pending
      Music.stop()
      if pending then
        Music.play(pending.data, pending.song, pending.loop, pending.ctx)
      end
    end
    local function setLevel(level) fadeSetLevel(f, level) end
    if f.gen2 then
      -- pokecrystal audio/engine.asm:614-631
      if state.fadeCount > 0 then
        state.fadeCount = state.fadeCount - 1
        return
      end
      state.fadeCount = f.control
      if f.fadeIn then
        -- pokecrystal audio/engine.asm:693-705
        if f.level >= 7 then
          state.fade = nil
          return
        end
        setLevel(f.level + 1)
        return
      end
      if f.level > 0 then
        setLevel(f.level - 1)
        return
      end
      -- pokecrystal audio/engine.asm:644-691
      local pending = f.pending
      local bike = pending and state.mapSong ~= nil
        and state.mapSong == Music.special(pending.data, "bike")
      finish()
      if bike and state.source then
        state.fade = { control = 0, level = 0, from = VOLUME * volumeScale,
                       fadeIn = true, gen2 = true }
        fadeSetLevel(state.fade, 0)
      end
      return
    end
    -- home/fade_audio.asm:12-35
    if f.counter > 0 then
      f.counter = f.counter - 1
      return
    end
    f.counter = f.control
    if f.level <= 0 then
      finish()
      return
    end
    setLevel(f.level - 1)
    return
  end
  -- while a fanfare plays the song stays paused (a paused source reads
  -- as stopped, so the intro-chain/restore checks below must not run);
  -- when it ends, the song picks up where it left off
  if state.fanfare then
    if fanfareActive() then return end
    if state.fanfareResume and state.source then
      pcall(state.source.play, state.source)
    end
    state.fanfareResume = false
  end
  if state.chip and not state.fanfare then
    require("src.core.ChipAudio").ensureMusicPlaying()
  end
  if state.loopSource and sourceStopped(state.source) then
    local loopSrc = state.loopSource
    state.loopSource = nil
    state.source = loopSrc
    pcall(loopSrc.play, loopSrc)
  end
  -- do not treat "threaded source still waiting on its first buffer" as
  -- ended, or playOnce jingles get restored over before they can sound
  if state.pendingRestore then
    state.restoreLeft = (state.restoreLeft or ONE_SHOT_CEILING) - 1
    local ended = sourceStopped(state.source) and not state.loopSource
      and not chipAwaitingFirstBuffer()
    if ended then
      Music.restoreMap(data)
    elseif state.restoreLeft <= 0 then
      require("src.core.Logger").warn(
        "music: one-shot %s never finished; restoring map theme",
        tostring(state.current))
      Music.restoreMap(data)
    end
  end
end

return Music
