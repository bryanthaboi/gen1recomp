local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Sample = require("src.core.game3.m4a_sample")
local Mix = require("src.core.game3.m4a_mix")
local Player = require("src.core.game3.m4a_player")
local SE = require("src.core.game3.se_ids")
local Song = require("src.core.game3.song_ids")
local Warm = require("src.core.game3.warm")
local ffiOk, ffi = pcall(require, "ffi")

local Audio = {}

local function audio_profile()
  local ok, row = pcall(function()
    return lazyReq("src.core.game3.profile").forSession(nil)
  end)
  if ok and type(row) == "table" then return row end
  return nil
end

function Audio.config()
  local row = audio_profile()
  return row and row.audio or {}
end

function Audio.songs()
  local row = audio_profile()
  if row and row.id then
    local ok, t = pcall(Song.forVersion, row.id)
    if ok and t then return t end
  end
  return Song
end

function Audio.mapMusicPolicy()
  return Audio.config().mapMusicPolicy or "frlg"
end

function Audio.questLogGating()
  return Audio.config().questLogGating ~= false
end

local function rse_policy()
  if Audio.mapMusicPolicy() == "rs" then return lazyReq("src.core.game3.audio_policy_rs") end
  if Audio.mapMusicPolicy() ~= "rse" then return nil end
  return lazyReq("src.core.game3.audio_policy_rse")
end

local RIDE_SONG_KEYS = { MUS_CYCLING = "cycling", MUS_SURF = "surf", MUS_UNDERWATER = "underwater" }

setmetatable(Audio, {
  __index = function(_, k)
    local role = RIDE_SONG_KEYS[k]
    if not role then return nil end
    local names = Audio.config().rideSongs
    return Audio.songs()[(names and names[role]) or k]
  end,
})

Audio._pack = nil
Audio._cache = nil
Audio._root = "data/generated/gba/audio"
Audio._meta = nil
Audio._currentSong = nil
Audio._mapSong = nil
Audio._savedSong = nil
Audio._log = false
Audio._ready = false
Audio._seSources = {}
Audio._seByPlayer = {} -- pret m4a: one active song per MusicPlayer (SE1/SE2/SE3)
Audio._seMeta = {} -- src → { id, player }
Audio._crySlot = nil
Audio._cryClock = 0
Audio._cryUntil = nil
Audio._fanfareFrames = 0
Audio._fanfareActive = false
Audio._fanfareSd = {}
Audio._fanfareSrc = {}
Audio._fanfareRoot = nil
Audio._fanfareRestore = nil
Audio._fanfareDeferred = nil
Audio._fanfarePending = nil
Audio._fanfareSource = nil
Audio._bgmPaused = false
Audio._bgmEpoch = 0
Audio._bgmQueuedAt = {}
Audio._bgmBaseAt = 0
Audio._bgmVolume = 1
Audio._sfxVolume = 1
Audio._duck = 1
Audio._duckHold = 0
Audio._seDuck = 1
Audio._mono = false
Audio._warned = {}

-- Threaded BGM
Audio._worker = nil
Audio._cmdCh = nil
Audio._outCh = nil
Audio._bgmSource = nil
Audio._bgmGen = nil
Audio._bgmLocal = nil -- sync fallback slot

local function fanfare_entry(id)
  local ff = Audio._pack and Audio._pack.index and Audio._pack.index.fanfares
  if not ff then return nil, false end
  return ff[id] or ff[tostring(id)], true
end

local function log(msg)
  if Audio._log then
    print("[game3.audio] " .. tostring(msg))
  end
end

local function warn_once(id, msg)
  if Audio._warned[id] then return end
  Audio._warned[id] = true
  print("[game3.audio] " .. msg)
end

local function filesystem_cache()
  return {
    read = function(_, rel)
      if love and love.filesystem then return love.filesystem.read(rel) end
      return nil
    end,
    write = function(_, rel, data)
      if love and love.filesystem then return love.filesystem.write(rel, data) end
      return false
    end,
    exists = function(_, rel)
      if love and love.filesystem and love.filesystem.getInfo then
        return love.filesystem.getInfo(rel) ~= nil
      end
      return false
    end,
  }
end

local function push_install()
  Audio._cmdCh:push({
    cmd = "install",
    root = Audio._root,
    prefix = lazyReq("src.core.WorkerFs").prefix(),
    sampleRate = Mix.SAMPLE_RATE,
  })
end

local function ensure_worker()
  if Audio._worker ~= nil then return Audio._worker end
  if not (love and love.thread and love.thread.newThread) then
    Audio._worker = false
    return false
  end
  local ok, thread = pcall(love.thread.newThread, "src/core/game3/m4a_worker.lua")
  if not ok or not thread then
    Audio._worker = false
    return false
  end
  Audio._cmdCh = love.thread.getChannel("game3_m4a_cmd")
  Audio._outCh = love.thread.getChannel("game3_m4a_out")
  Audio._fanfareCh = love.thread.getChannel("game3_m4a_fanfare")
  Audio._statusCh = love.thread.getChannel("game3_m4a_status")
  Audio._cmdCh:clear()
  Audio._outCh:clear()
  Audio._fanfareCh:clear()
  Audio._statusCh:clear()
  local started = pcall(function() thread:start() end)
  if not started then
    Audio._worker = false
    return false
  end
  Audio._worker = thread
  push_install()
  return true
end

local function ensure_bgm_source()
  if Audio._bgmSource then return Audio._bgmSource end
  if not (love and love.audio and love.audio.newQueueableSource) then return nil end
  Audio._bgmRate = Mix.SAMPLE_RATE
  Audio._bgmSource = love.audio.newQueueableSource(Audio._bgmRate, 16, 2, Player.BUFFER_COUNT)
  if Audio.applyBgmFilter then Audio.applyBgmFilter() end
  return Audio._bgmSource
end

--- Install pack from explicit root (never Sevii Extract.CACHE_ROOT default).
function Audio.install(cache, opts)
  opts = opts or {}
  Audio._root = opts.root or "data/generated/gba/audio"
  Audio._cache = cache or filesystem_cache()
  local pack, err = Player.loadPack(Audio._cache, Audio._root)
  if not pack then
    Audio._ready = false
    Audio._pack = nil
    warn_once("install", "audio pack unavailable: " .. tostring(err))
    return false, err
  end
  Audio._pack = pack
  Audio._meta = pack.index
  Audio._ready = true
  Audio._seRawClear()
  if Audio._fanfareRoot ~= Audio._root then
    Audio._fanfareSd = {}
    Audio._fanfareSrc = {}
    Audio._fanfareRoot = Audio._root
  end
  if ensure_worker() then
    push_install()
  end
  log("installed root=" .. Audio._root)
  return true
end

function Audio.isReady()
  return Audio._ready and Audio._pack ~= nil
end

function Audio.loadMeta(meta)
  -- Legacy shim: merge song table into meta without full pack.
  Audio._meta = type(meta) == "table" and meta or {}
end

function Audio.songInfo(id)
  id = tonumber(id) or id
  if Audio._pack then
    return Player.songInfo(Audio._pack, id)
  end
  local meta = Audio._meta or {}
  local songs = meta.songs or meta
  if type(songs) == "table" then
    return songs[id] or songs[tostring(id)]
  end
  return nil
end

function Audio.role(name)
  local roles = Audio._pack and Audio._pack.index and Audio._pack.index.roles
  if roles and roles[name] then return roles[name] end
  return nil
end

-- pokefirered/src/battle_setup.c:349 StartLegendaryBattle switches on the FRLG
-- internal species id, not the National Dex number. SPECIES_DEOXYS is 410
-- (include/constants/species.h:419); 386 is SPECIES_VOLBEAT and must not match.
Audio.LEGENDARY_BATTLE_SONGS = {
  SPECIES_MEWTWO = { "battleMewtwo", "MUS_VS_MEWTWO" },
  SPECIES_DEOXYS = { "battleDeoxys", "MUS_VS_DEOXYS" },
  SPECIES_ARTICUNO = { "battleLegend", "MUS_VS_LEGEND" },
  SPECIES_ZAPDOS = { "battleLegend", "MUS_VS_LEGEND" },
  SPECIES_MOLTRES = { "battleLegend", "MUS_VS_LEGEND" },
  SPECIES_RAIKOU = { "battleDeoxys", "MUS_VS_DEOXYS" },
  SPECIES_ENTEI = { "battleDeoxys", "MUS_VS_DEOXYS" },
  SPECIES_SUICUNE = { "battleDeoxys", "MUS_VS_DEOXYS" },
  SPECIES_LUGIA = { "battleLegend", "MUS_VS_LEGEND" },
  SPECIES_HO_OH = { "battleLegend", "MUS_VS_LEGEND" },
}

local function species_name(species)
  local row = audio_profile()
  local ok, C = pcall(function()
    return lazyReq("src.core.game3.constants").of(row and row.id or "firered")
  end)
  if not ok or not C then return nil end
  local byId = C.species.byId
  local rev = byId and (byId.SPECIES_ or byId)
  return type(rev) == "table" and rev[species] or nil
end

-- Returns the legendary battle theme for a species, or nil for any other mon.
function Audio.legendaryBattleSong(species, opts)
  local cfg = Audio.config()
  local tbl = cfg.legendaryBattleSongs or Audio.LEGENDARY_BATTLE_SONGS
  local n = tonumber(species)
  local entry = n and tbl[species_name(n)]
  local songs = Audio.songs()
  if not entry then
    local def = type(opts) == "table" and opts.legendary and cfg.legendaryBattleDefault
    return def and songs[def] or nil
  end
  if type(entry) == "table" then
    return Audio.role(entry[1]) or songs[entry[2]]
  end
  return songs[entry]
end

-- pokeruby/src/libs/m4a.c:1738
function Audio.setCryStereo(value)
  local mono = (tonumber(value) or 0) == 0
  if mono ~= Audio._mono then
    Audio._mono = mono
    Audio.pushMixOptions()
  end
  return mono and 0 or 1
end

function Audio.applyOptions(session)
  local Options = lazyReq("src.core.game3.options")
  local o = Options.ensure(session)
  return Audio.setCryStereo(o.sound)
end

local function bgm_gain(volume)
  return (volume or Audio._bgmVolume or 1)
    * math.min(Audio._duck or 1, Audio._seDuck or 1)
    * (Audio._helpActive and 0.5 or 1)
end

local function apply_bgm_gain()
  if not Audio._bgmSource then return end
  local gain = bgm_gain()
  local f = Audio._fadeOut
  if f and (f.gen == nil or f.gen == Audio._bgmGen)
    and (f.songId == nil or (Audio._currentSong and f.songId == Audio._currentSong.id)) then
    gain = bgm_gain(f.start) * (1 - math.min(1, f.t / math.max(f.dur, 0.01)))
  elseif Audio._fadeIn then
    f = Audio._fadeIn
    gain = gain * math.min(1, f.t / math.max(f.dur, 0.01))
  end
  Audio._bgmSource:setVolume(gain)
end

local function level_gain(level, default)
  local n = tonumber(level)
  if n == nil then n = default end
  if n < 0 then n = 0 end
  if n > 7 then n = 7 end
  return n / 7
end

function Audio.pushMixOptions()
  if Audio._mixMono ~= Audio._mono then
    Audio._mixMono = Audio._mono
    Audio._fanfareSd = {}
    Audio._fanfareSrc = {}
    if Audio._cmdCh then Audio._cmdCh:push({ cmd = "dropFanfares" }) end
  end
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "mix", mono = Audio._mono and true or false })
  end
  Audio.applyBgmFilter()
  Audio.applyGain()
end

local FILTER_HIGHGAIN = { 0.4, 0.16, 0.064 }

local function set_filter(src, level)
  if not (src and src.setFilter) then return end
  local gain = FILTER_HIGHGAIN[level]
  pcall(function()
    if gain then
      src:setFilter({ type = "lowpass", volume = 1, highgain = gain })
    else
      src:setFilter()
    end
  end)
end

function Audio.applyBgmFilter()
  set_filter(Audio._bgmSource, Audio._filterLevel)
  set_filter(Audio._fanfareSource, Audio._filterLevel)
end

function Audio.applyEngineOptions(opts)
  if type(opts) ~= "table" then return end
  local mode = opts.audioMode or "both"
  Audio._audioMode = mode
  require("src.audio.AudioMix").set(mode ~= "game_only")
  if mode == "external_only" then
    Audio._bgmVolume = 0
  else
    Audio._bgmVolume = level_gain(opts.musicVol, 7)
  end
  Audio._sfxVolume = level_gain(opts.sfxVol, 7)
  local filter = tonumber(opts.musicFilter) or 0
  if filter < 0 then filter = 0 end
  if filter > 3 then filter = 3 end
  Audio._filterLevel = filter > 0 and filter or nil
  Audio.pushMixOptions()
  Audio.applyGain()
end

function Audio.applyGain()
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "volume", volume = bgm_gain() })
  end
  apply_bgm_gain()
end

-- Baked effects cannot steal a voice from already queued music. Until the
-- players share a live mixer, give one-shot effects headroom at playback time.
-- Looping alarms do not hold the music down; cry ducking takes precedence.
local function update_se_duck(startingSource)
  local active = false
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and meta.duckBgm and (src == startingSource or src:isPlaying()) then
      active = true
      break
    end
  end
  local target = active and 0.6 or 1
  local old = Audio._seDuck or 1
  Audio._seDuck = target
  if target ~= old then apply_bgm_gain() end
end

-- Help lowers BGM without changing the user's volume or cry ducking state.
function Audio.setHelpActive(active)
  Audio._helpActive = active == true
  local volume = bgm_gain()
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "volume", volume = volume }) end
  if Audio._bgmSource then Audio._bgmSource:setVolume(volume) end
end

local function stop_bgm_source()
  if Audio._bgmSource then
    pcall(function() Audio._bgmSource:stop() end)
  end
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "stop" })
  end
  Audio._bgmLocal = nil
  Audio._bgmGen = nil
  Audio._pendingBgm = nil
  Audio._bgmQueuedAt = {}
  Audio._bgmBaseAt = 0
end

function Audio.resolveSong(id)
  if type(id) == "string" and not tonumber(id) then
    return Audio.songs()[id] or Song.resolve(id) or id
  end
  return tonumber(id) or id
end

function Audio.playSong(id, opts)
  opts = opts or {}
  id = Audio.resolveSong(id)
  if id == nil or id == 0 or id == 0xFFFF then
    Audio._fadeOut, Audio._fadeIn = nil, nil
    Audio._fanfareRestore, Audio._fanfareDeferred = nil, nil
    stop_bgm_source()
    Audio._currentSong = nil
    return true
  end
  if opts.fanfare or (Audio.songInfo(id) and Audio.songInfo(id).kind == "fanfare") or (fanfare_entry(id) ~= nil) then
    return Audio.playFanfare(id)
  end
  if not opts.restart and not Audio._fadeOut and Audio._currentSong and Audio._currentSong.id == id then
    if Audio._fanfareActive then Audio._fanfareDeferred = nil end
    return true
  end
  local info = Audio.songInfo(id) or {}
  Audio._currentSong = {
    id = id,
    duration = info.duration,
    loop = info.loop ~= false,
    startedAt = os.clock(),
  }
  Audio._mapSong = Audio._mapSong or id

  Audio._fadeOut = nil
  Audio._fadeIn = nil
  Audio._fanfareActive = false
  Audio._fanfareFrames = 0
  Audio._fanfareRestore = nil
  Audio._fanfareDeferred = nil
  Audio._fanfarePending = nil
  Audio._bgmPaused = false

  if not Audio.isReady() then
    log(string.format("playsong id=%s (no pack)", tostring(id)))
    return true
  end

  if ensure_worker() then
    Audio._pendingBgm = nil
    if Audio._outCh then Audio._outCh:clear() end
    Audio._bgmEpoch = (Audio._bgmEpoch or 0) + 1
    Audio._bgmQueuedAt = {}
    Audio._bgmBaseAt = 0
    Audio._cmdCh:push({ cmd = "play", id = id, epoch = Audio._bgmEpoch })
    Audio._cmdCh:push({ cmd = "volume", volume = bgm_gain() })
    Audio._bgmGen = id
    local src = ensure_bgm_source()
    if src then
      pcall(function()
        src:stop()
        src:setVolume(bgm_gain())
      end)
    end
  else
    -- Sync fallback
    Audio._bgmLocal = { voices = {}, songId = id }
    Player.start(Audio._pack, Audio._cache, Audio._bgmLocal, id, { forceSeq = true })
    local src = ensure_bgm_source()
    if src then
      pcall(function()
        src:stop()
        src:setVolume(bgm_gain())
      end)
    end
  end
  log(string.format("playsong id=%s", tostring(id)))
  return true
end

function Audio.currentMapMusic()
  if Audio._fanfareActive and Audio._fanfareDeferred ~= nil then
    return Audio._fanfareDeferred
  end
  if Audio._fadeOut then return Audio._fadeOut.nextSong or 0 end
  return (Audio._currentSong and Audio._currentSong.id) or 0
end

local function play_policy_song(id, fadeOut, fadeIn)
  if id == nil then return true end
  if Audio._fanfareActive then
    Audio._fanfareDeferred = id
    return true
  end
  if fadeOut then return Audio.fadeOutAndPlay(id, fadeOut, fadeIn) end
  return Audio.playSong(id)
end

-- pokeemerald/src/overworld.c:1142
function Audio.mapLoadMusic(info)
  info = info or {}
  local P = rse_policy()
  if not P then
    return Audio.playMapSong(info.song or info.music, { mapSong = info.music })
  end
  local after = P.live(Audio)
  Audio._mapSong = P.currLocationDefaultMusic(after)
  if info.seamless and info.fromMapId and info.mapId then
    -- pokeemerald/src/overworld.c:792
    local before = P.live(Audio, { locationMap = info.fromMapId })
    local t = P.transitionMapMusic(before, before.at(info.mapId, info.x, info.y))
    if t then return play_policy_song(t.song, t.fadeOut, t.fadeIn) end
    return true
  end
  local id = P.playSpecialMapMusic(after)
  if id then return play_policy_song(id) end
  return true
end

-- pokeemerald/src/overworld.c:1216
function Audio.tryFadeOutOldMapMusic(destMapId, x, y)
  local P = rse_policy()
  if not P then return nil end
  local ctx = P.live(Audio)
  local speed = P.tryFadeOutOldMapMusic(ctx, ctx.at(destMapId, x, y))
  if not speed then return 0 end
  Audio.fadeOutBgm(speed)
  return 16 * speed
end

function Audio.playMapSong(id, opts)
  opts = opts or {}
  id = Audio.resolveSong(id)
  if opts.mapSong ~= nil and not opts.exact and rse_policy() then
    return Audio.mapLoadMusic({ music = opts.mapSong })
  end
  if id == nil or id == 0xFFFF then return true end
  Audio._mapSong = opts.mapSong or id
  if Audio._fanfareActive then
    Audio._fanfareDeferred = id
    return true
  end
  if opts.fadeOut then
    Audio.fadeOutBgm(opts.fadeOut)
  end
  return Audio.playSong(id, opts)
end

function Audio.setMapSong(id)
  local R = rse_policy()
  if R then
    Audio._mapSong = R.currLocationDefaultMusic(R.live(Audio))
    return
  end
  Audio._mapSong = tonumber(id) or id
end

-- pokefirered/include/constants/region_map_sections.h:106
local NO_RIDE_MUSIC_SECTIONS = { [97] = true, [123] = true, [132] = true }

local function current_section()
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  return def and def.regionMapSectionId
end

-- pokefirered/src/overworld.c:1193
function Audio.canOverrideMapMusic(song, sectionId)
  if rse_policy() then return true end
  if song == Audio.MUS_CYCLING or song == Audio.MUS_SURF then
    if sectionId == nil then sectionId = current_section() end
    return not NO_RIDE_MUSIC_SECTIONS[tonumber(sectionId) or -1]
  end
  return true
end

-- pokefirered/src/overworld.c:1014
function Audio.specialMapSong(sectionId)
  local R = rse_policy()
  if R then return R.specialMapMusic(R.live(Audio)) end
  if Audio._savedSong then return Audio._savedSong end
  local P = package.loaded["src.core.game3.player"]
  if P and (P.surfing or P.surfHopping) and not P.dismounting
      and Audio.canOverrideMapMusic(Audio.MUS_SURF, sectionId) then
    return Audio.MUS_SURF
  end
  if P and P.biking and Audio.canOverrideMapMusic(Audio.MUS_CYCLING, sectionId) then
    return Audio.MUS_CYCLING
  end
  return Audio._mapSong
end

-- pokefirered/src/overworld.c:1039
function Audio.restoreMapSong(opts)
  local id = Audio.specialMapSong()
  if id then return Audio.playSong(id, opts) end
  return true
end

-- pokefirered/src/sound.c:152
function Audio.fadeOutAndPlay(id, speed, fadeInSpeed)
  id = Audio.resolveSong(id)
  if Audio._fanfareActive then
    Audio._fanfareDeferred = id
    return true
  end
  if not (Audio._currentSong and Audio._bgmSource) then
    return Audio.playSong(id)
  end
  Audio.fadeOutBgm(speed)
  if Audio._fadeOut then
    Audio._fadeOut.nextSong = id
    Audio._fadeOut.fadeIn = fadeInSpeed
  end
  return true
end

-- pokefirered/src/overworld.c:1096
function Audio.changeMusicTo(id)
  id = Audio.resolveSong(id)
  local R = rse_policy()
  if R then
    local t = R.changeMusicTo(R.live(Audio), id)
    if t then return Audio.fadeOutAndPlay(t.song, t.fadeOut) end
    return true
  end
  if Audio.currentMapMusic() == id then return true end
  return Audio.fadeOutAndPlay(id, 8)
end

-- pokefirered/src/overworld.c:1089
function Audio.changeMusicToDefault()
  local R = rse_policy()
  if R then
    local t = R.changeMusicToDefault(R.live(Audio))
    if t then return Audio.fadeOutAndPlay(t.song, t.fadeOut) end
    return true
  end
  if Audio._mapSong then return Audio.changeMusicTo(Audio._mapSong) end
  return true
end

-- pokefirered/src/field_effect.c:2986
function Audio.startSurfMusic()
  Audio.setSavedSong(nil)
  if Audio.canOverrideMapMusic(Audio.MUS_SURF) then Audio.changeMusicTo(Audio.MUS_SURF) end
end

-- pokefirered/src/field_player_avatar.c:1579
function Audio.stopSurfMusic()
  Audio.setSavedSong(nil)
  Audio.changeMusicToDefault()
end

-- pokefirered/src/bike.c:314
function Audio.bikeMusic(on, forced)
  if on then
    if forced or Audio.canOverrideMapMusic(Audio.MUS_CYCLING) then
      Audio.setSavedSong(Audio.MUS_CYCLING)
      Audio.changeMusicTo(Audio.MUS_CYCLING)
    end
    return
  end
  Audio.setSavedSong(nil)
  local id = Audio.specialMapSong()
  if id and id ~= Audio.currentMapMusic() then
    play_policy_song(id)
  end
end

-- pokefirered/src/overworld.c:1048
function Audio.setSavedSong(id)
  id = Audio.resolveSong(id)
  if id == 0 or id == 0xFFFF then id = nil end
  Audio._savedSong = id
end

-- pokeemerald/src/battle_setup.c:952 / pokefirered/src/overworld.c:1056 Overworld_ClearSavedMusic
function Audio.clearSavedSong()
  Audio._savedSong = nil
end

-- pokefirered/src/overworld.c:1089
function Audio.fadeDefaultBgm(speed)
  if rse_policy() then return Audio.changeMusicToDefault() end
  local id = Audio._mapSong
  if id and Audio.currentMapMusic() == id then return true end
  if Audio._fanfareActive then return play_policy_song(id) end
  Audio.fadeOutBgm(speed)
  if id then return Audio.playSong(id) end
  return true
end

function Audio.fadeOutBgm(speed)
  speed = tonumber(speed) or 4
  -- pret: seconds = 16 * speed / 60
  local seconds = 16 * speed / 60
  local songId = Audio._currentSong and Audio._currentSong.id
  if Audio._bgmSource and songId then
    -- Immediate approximate fade via volume step in update
    Audio._fadeOut = {
      t = 0,
      dur = seconds,
      start = Audio._bgmVolume or 1,
      songId = songId,
      gen = Audio._bgmGen,
    }
  else
    stop_bgm_source()
    Audio._currentSong = nil
  end
  log(string.format("fadeOutBgm speed=%s", tostring(speed)))
  return true
end

function Audio.fadeInBgm(id, speed)
  Audio.playSong(id)
  speed = tonumber(speed) or 4
  local seconds = 16 * speed / 60
  Audio._fadeIn = { t = 0, dur = seconds }
  if Audio._bgmSource then Audio._bgmSource:setVolume(0) end
  return true
end

function Audio.bgmHeardPosition()
  local q = Audio._bgmQueuedAt or {}
  if #q == 0 then return Audio._bgmBaseAt end
  local src = Audio._bgmSource
  if not src then return nil end
  local okFree, free = pcall(src.getFreeBufferCount, src)
  if not okFree or type(free) ~= "number" then return nil end
  local inAl = (Player.BUFFER_COUNT or 32) - free
  if inAl <= 0 then
    local last = q[#q]
    return last.at and (last.at + (last.n or 0)) or nil
  end
  local cur = q[#q - inAl + 1] or q[1]
  if not cur.at then return nil end
  local okTell, off = pcall(src.tell, src, "samples")
  off = okTell and tonumber(off) or 0
  if off < 0 then off = 0 end
  return cur.at + off
end

-- pokefirered/src/m4a.c:668
function Audio.pauseBgm()
  if Audio._bgmPaused then return end
  local at = Audio.bgmHeardPosition() or Audio._bgmBaseAt or 0
  Audio._bgmPaused = true
  Audio._bgmEpoch = (Audio._bgmEpoch or 0) + 1
  if Audio._outCh then Audio._outCh:clear() end
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "stopAt", at = at, epoch = Audio._bgmEpoch })
  end
  if Audio._bgmSource then pcall(function() Audio._bgmSource:stop() end) end
  Audio._pendingBgm = nil
  Audio._bgmQueuedAt = {}
  Audio._bgmBaseAt = at
  local slot = Audio._bgmLocal
  if slot then
    if slot.seq then slot.seq.voices = {} end
    slot.voices = {}
  end
end

-- pokefirered/src/m4a.c:186
function Audio.resumeBgm()
  Audio._bgmPaused = false
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "resume" }) end
  if Audio._bgmSource then
    pcall(function()
      Audio._bgmSource:setVolume(bgm_gain())
      if not Audio._bgmSource:isPlaying() then
        Audio._bgmSource:play()
      end
    end)
  end
  Audio.pumpBgm()
end

function Audio.isBgmStopped()
  if Audio._bgmPaused then return true end
  if Audio._bgmSource then
    return not Audio._bgmSource:isPlaying()
  end
  return Audio._currentSong == nil
end

Audio.SE_RAW_MAX_FRAMES = 1500000
-- pokefirered/src/m4a_1.s:751
Audio.SE_LOOP_MAX_SEC = 2.5
Audio.SE_ONESHOT_MAX_SEC = 30

function Audio._seRawClear()
  Audio._cryCache, Audio._cryCacheN = nil, 0
  Audio._seRaw = {}
  Audio._seRawFrames = 0
  Audio._seRawTick = 0
  if Audio._seSourceClear then Audio._seSourceClear() end
end

function Audio._seRawGet(id)
  local e = Audio._seRaw and Audio._seRaw[id]
  if not e then return nil end
  Audio._seRawTick = (Audio._seRawTick or 0) + 1
  e.tick = Audio._seRawTick
  return e
end

function Audio._seRawPut(id, loop, rawL, rawR, loopStart)
  if type(rawL) ~= "table" then return end
  local n = #rawL
  if n > Audio.SE_RAW_MAX_FRAMES then return end
  if not Audio._seRaw then Audio._seRawClear() end
  local prev = Audio._seRaw[id]
  if prev then Audio._seRawFrames = Audio._seRawFrames - prev.frames end
  Audio._seRawTick = Audio._seRawTick + 1
  Audio._seRaw[id] = { loop = loop, rawL = rawL, rawR = rawR, loopStart = loopStart, frames = n,
    tick = Audio._seRawTick }
  Audio._seRawFrames = Audio._seRawFrames + n
  while Audio._seRawFrames > Audio.SE_RAW_MAX_FRAMES do
    local oldId, oldTick
    for k, e in pairs(Audio._seRaw) do
      if k ~= id and (oldTick == nil or e.tick < oldTick) then oldId, oldTick = k, e.tick end
    end
    if oldId == nil then break end
    Audio._seRawFrames = Audio._seRawFrames - Audio._seRaw[oldId].frames
    Audio._seRaw[oldId] = nil
  end
end

-- Static Sources for one-shot / looping SEs, keyed by everything baked into
-- their PCM (id, pan, master gain, mono, loop).  A repeat SE (wall bump, ball
-- placement, menu cursor) used to rebuild its SoundData sample by sample and
-- upload a new Source on every play; now a cached Source is rewound and
-- replayed, or cloned (shares the uploaded buffer) while the cached one is
-- still live on another player slot.  Entries are tied to the memoized raw
-- PCM tables, so an evicted/rebaked SE never reuses a stale Source.
Audio.SE_SOURCE_CACHE_MAX = 32

function Audio._seSourceClear()
  Audio._seSrcCache = {}
  Audio._seSrcCount = 0
  Audio._seSrcTick = 0
end

function Audio._seSourceFor(id, rawL, rawR, master, pan, mono, loop)
  if not (love and love.audio and love.audio.newSource) then return nil end
  local hit = Audio._seRaw and Audio._seRaw[id]
  local cacheable = hit and hit.rawL == rawL and hit.rawR == rawR
  local key = cacheable and table.concat({ tostring(id), tostring(pan),
    tostring(master), mono and "m" or "s", loop and "l" or "o" }, ":")
  if not Audio._seSrcCache then Audio._seSourceClear() end
  local entry = key and Audio._seSrcCache[key]
  if entry and entry.rawL == rawL then
    Audio._seSrcTick = Audio._seSrcTick + 1
    entry.tick = Audio._seSrcTick
    local src = entry.src
    if Audio._seMeta[src] then
      -- still tracked as a live SE: play a copy rather than cut it off
      local ok, copy = pcall(function() return src:clone() end)
      src = ok and copy or nil
    end
    if src then
      pcall(function() src:stop() end)
      if loop then pcall(function() src:setLooping(true) end) end
      return src
    end
    key = nil -- no clone support: build a one-off, keep the cached entry
  end
  local sd = Audio._buildSeSoundData(rawL, rawR, master, pan, mono)
  if not sd then return nil end
  local src = love.audio.newSource(sd, "static")
  if loop then
    pcall(function() src:setLooping(true) end)
  end
  if key then
    if not Audio._seSrcCache[key] then
      Audio._seSrcCount = Audio._seSrcCount + 1
    end
    Audio._seSrcTick = Audio._seSrcTick + 1
    Audio._seSrcCache[key] = { src = src, rawL = rawL, tick = Audio._seSrcTick }
    while Audio._seSrcCount > Audio.SE_SOURCE_CACHE_MAX do
      local oldKey, oldTick
      for k, e in pairs(Audio._seSrcCache) do
        if k ~= key and (oldTick == nil or e.tick < oldTick) then
          oldKey, oldTick = k, e.tick
        end
      end
      if oldKey == nil then break end
      Audio._seSrcCache[oldKey] = nil
      Audio._seSrcCount = Audio._seSrcCount - 1
    end
  end
  return src
end

local function bake_se(id, opts, memoable)
  local slot = { voices = {} }
  -- SE must run the M4A sequencer (SE_SELECT is CGB pulse, not voice0 PCM).
  local ok = Player.start(Audio._pack, Audio._cache, slot, id, { forceSeq = true })
  if not ok then
    warn_once("se:" .. tostring(id), "SE " .. tostring(id) .. " missing")
    return nil
  end

  local loop = opts.loop
  if loop == nil then
    -- SE_LOW_HEALTH and any track with GOTO before FINE are hardware loops.
    loop = (id == SE.SE_LOW_HEALTH) or Audio._songHasGoto(slot)
  end

  local loopBody = loop and opts.loop == nil and id ~= SE.SE_LOW_HEALTH
  -- pokefirered/src/battle_anim_special.c:1200
  local cut = ((loop and not loopBody) or id == SE.SE_EXP)
  local maxSec = opts.maxSec
    or (cut and Audio.SE_LOOP_MAX_SEC or Audio.SE_ONESHOT_MAX_SEC)
  local rawL, rawR, loopStart = Player.bakeSlot(slot, {
    raw = true,
    maxSec = maxSec,
    stopOnGoto = loop and true or false,
    loopBody = loopBody,
  })
  if not cut and opts.maxSec == nil and type(rawL) == "table"
    and #rawL >= math.floor(Mix.SAMPLE_RATE * maxSec) then
    warn_once("selen:" .. tostring(id),
      "SE " .. tostring(id) .. " hit the " .. tostring(maxSec) .. "s bake ceiling")
  end
  if memoable then Audio._seRawPut(id, loop and true or false, rawL, rawR, loopStart) end
  return loop and true or false, rawL, rawR, loopStart
end

function Audio.prewarmSe(id, priority)
  id = SE.resolve(id)
  if id == nil or not Audio.isReady() then return false end
  if Audio._seRaw and Audio._seRaw[id] then return false end
  local info = Audio.songInfo(id)
  if info and info.kind == "fanfare" then return false end
  return Warm.add("se:" .. tostring(id), function()
    if Audio._seRaw and Audio._seRaw[id] then return end
    local loop, rawL, rawR = bake_se(id, {}, true)
    if loop == nil or loop then return end
    Audio._seSourceFor(id, rawL, rawR, Audio._sfxVolume or 1, Audio.normalizePan(nil), Audio._mono, false)
  end, priority)
end

function Audio.playSe(id, opts)
  opts = opts or {}
  id = SE.resolve(id)
  if id == nil then
    return false
  end
  if opts.fanfare or (Audio.songInfo(id) and Audio.songInfo(id).kind == "fanfare") then
    return Audio.playFanfare(id)
  end
  if not Audio.isReady() then
    log(string.format("playse id=%s (no pack)", tostring(id)))
    return true
  end
  local info = Audio.songInfo(id) or {}
  -- pret m4aSongNumStart: starting a song on a player replaces that player's song.
  local mplay = tonumber(info.player) or 1
  Audio._stopSePlayer(mplay)

  local memoable = opts.loop == nil and opts.maxSec == nil
  if memoable then Warm.flush("se:" .. tostring(id)) end
  local hit = memoable and Audio._seRawGet(id) or nil
  local loop, rawL, rawR, loopStart
  if hit then
    loop, rawL, rawR, loopStart = hit.loop, hit.rawL, hit.rawR, hit.loopStart
  else
    loop, rawL, rawR, loopStart = bake_se(id, opts, memoable)
    if loop == nil then return false end
  end

  local pan = Audio.normalizePan(opts.pan)
  local master = (Audio._sfxVolume or 1) * (opts.volume or 1)
  local src, body
  if loop and loopStart and love and love.audio and love.audio.newQueueableSource then
    src, body = Audio._newIntroLoopSource(rawL, rawR, loopStart, master, pan, Audio._mono)
  end
  if not src then
    src = Audio._seSourceFor(id, rawL, rawR, master, pan, Audio._mono, loop)
  end
  if src then
    src:setVolume(1)
    Audio._seSources[#Audio._seSources + 1] = src
    Audio._seByPlayer[mplay] = src
    Audio._seMeta[src] = { id = id, player = mplay,
      duckBgm = not loop and id ~= SE.SE_SELECT
        and (Audio._sfxVolume or 1) * (opts.volume or 1) > 0,
      rawL = rawL, rawR = rawR, master = master, pan = pan,
      mono = Audio._mono, loop = loop and true or false, body = body }
    update_se_duck(src)
    src:play()
    update_se_duck()
    while #Audio._seSources > 8 do
      local idx = 1
      if Audio._seSources[idx] == Audio._fanfareSource then idx = 2 end
      local old = table.remove(Audio._seSources, idx)
      if not old then break end
      Audio._forgetSeSource(old)
      pcall(function() old:stop() end)
    end
    log(string.format("playse id=%s player=%s pan=%s loop=%s", tostring(id), tostring(mplay), tostring(pan), tostring(loop)))
    return true
  end
  -- Headless / no device: still count as handled.
  log(string.format("playse id=%s (baked, no device)", tostring(id)))
  return true
end

function Audio.normalizePan(pan)
  if pan == nil then return 0 end
  if type(pan) == "number" then
    if pan > 63 then return 63 end
    if pan < -64 then return -64 end
    return pan
  end
  local s = tostring(pan)
  if s == "SOUND_PAN_TARGET" or s == "TARGET" then return 63 end
  if s == "SOUND_PAN_ATTACKER" or s == "ATTACKER" then return -64 end
  local n = tonumber(s)
  if n then return Audio.normalizePan(n) end
  return 0
end

function Audio._seGains(pan)
  pan = tonumber(pan) or 0
  if pan > 63 then pan = 63 end
  if pan < -64 then pan = -64 end
  local panN = pan / 64
  return 1 - math.max(0, panN), 1 - math.max(0, -panN)
end

function Audio._buildSeSoundData(L, R, master, pan, mono)
  if type(L) ~= "table" then return nil end
  if not (love and love.sound and love.sound.newSoundData) then return nil end
  local n = math.max(1, #L)
  local ch = mono and 1 or 2
  local sd = love.sound.newSoundData(n, Mix.SAMPLE_RATE, 16, ch)
  master = master or 1
  local gainL, gainR = Audio._seGains(pan)
  local gl, gr = master * gainL, master * gainR
  local warm = package.loaded["src.core.game3.warm"]
  local ptr
  if ffiOk and ffi and sd.getFFIPointer then
    local okP, p = pcall(sd.getFFIPointer, sd)
    if okP and p then ptr = ffi.cast("int16_t *", p) end
  end
  for i = 1, n do
    local l = (L[i] or 0) * gl
    local r = (R[i] or 0) * gr
    if l > 1 then l = 1 elseif l < -1 then l = -1 end
    if r > 1 then r = 1 elseif r < -1 then r = -1 end
    if ptr then
      if ch == 1 then
        ptr[i - 1] = (l + r) * 0.5 * 32767
      else
        ptr[(i - 1) * 2] = l * 32767
        ptr[(i - 1) * 2 + 1] = r * 32767
      end
    elseif ch == 1 then
      sd:setSample(i - 1, (l + r) * 0.5)
    else
      sd:setSample(i - 1, 1, l)
      sd:setSample(i - 1, 2, r)
    end
    if warm and i % 4096 == 0 then warm.yield() end
  end
  return sd
end

-- pokefirered/src/sound.c:606
function Audio.setSePan(pan)
  pan = Audio.normalizePan(pan)
  for _, mplay in ipairs({ 1, 2 }) do
    local old = Audio._seByPlayer[mplay]
    local meta = old and Audio._seMeta[old]
    if meta and meta.rawL and not meta.body and meta.pan ~= pan then
      local playing = false
      pcall(function() playing = old:isPlaying() end)
      meta.pan = pan
      if playing and not meta.mono then
        local sd = Audio._buildSeSoundData(meta.rawL, meta.rawR, meta.master, pan, meta.mono)
        if sd and love and love.audio and love.audio.newSource then
          local okN, src = pcall(love.audio.newSource, sd, "static")
          if okN and src then
            local pos = 0
            pcall(function() pos = old:tell("samples") end)
            pcall(function() src:setVolume(old:getVolume()) end)
            if meta.loop then pcall(function() src:setLooping(true) end) end
            pcall(function() src:seek(pos, "samples") end)
            Audio._seMeta[src] = meta
            Audio._seMeta[old] = nil
            Audio._seByPlayer[mplay] = src
            for i = 1, #Audio._seSources do
              if Audio._seSources[i] == old then Audio._seSources[i] = src end
            end
            pcall(function() old:stop() end)
            src:play()
          end
        end
      end
    end
  end
  return pan
end

local function slice(t, from, to)
  local out = {}
  for i = from, to do out[#out + 1] = t[i] end
  return out
end

function Audio._newIntroLoopSource(L, R, loopStart, master, pan, mono)
  local n = #L
  if loopStart <= 0 or loopStart >= n then return nil end
  local intro = Audio._buildSeSoundData(slice(L, 1, loopStart), slice(R, 1, loopStart), master, pan, mono)
  local body = Audio._buildSeSoundData(slice(L, loopStart + 1, n), slice(R, loopStart + 1, n), master, pan, mono)
  if not (intro and body) then return nil end
  local ok, src = pcall(love.audio.newQueueableSource, Mix.SAMPLE_RATE, 16, mono and 1 or 2, 3)
  if not (ok and src) then return nil end
  src:queue(intro)
  src:queue(body)
  return src, body
end

function Audio._pumpSeLoops()
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and meta.body and src:getFreeBufferCount() > 0 then
      src:queue(meta.body)
    end
  end
end

function Audio._songHasGoto(slot)
  if slot and slot.info and slot.info.hasGoto ~= nil then return slot.info.hasGoto end
  local seq = slot and slot.seq
  if not seq or not seq.tracks then return false end
  for _, tr in ipairs(seq.tracks) do
    local data = tr.data
    if type(data) == "string" and data:find(string.char(0xB2), 1, true) then
      return true
    end
  end
  return false
end

function Audio._forgetSeSource(src)
  if not src then return end
  local meta = Audio._seMeta[src]
  if meta and Audio._seByPlayer[meta.player] == src then
    Audio._seByPlayer[meta.player] = nil
  end
  Audio._seMeta[src] = nil
  update_se_duck()
end

function Audio._stopSePlayer(mplay)
  mplay = tonumber(mplay)
  if not mplay then return end
  local src = Audio._seByPlayer[mplay]
  if not src then return end
  pcall(function() src:stop() end)
  Audio._forgetSeSource(src)
  for i = #Audio._seSources, 1, -1 do
    if Audio._seSources[i] == src then
      table.remove(Audio._seSources, i)
    end
  end
end

function Audio.stopSe(id)
  if id == nil then
    for _, src in ipairs(Audio._seSources) do
      pcall(function() src:stop() end)
      Audio._forgetSeSource(src)
    end
    Audio._seSources = {}
    Audio._seByPlayer = {}
    return
  end
  local SE = lazyReq("src.core.game3.se_ids")
  id = SE.resolve(id)
  for i = #Audio._seSources, 1, -1 do
    local src = Audio._seSources[i]
    local meta = Audio._seMeta[src]
    if meta and meta.id == id then
      pcall(function() src:stop() end)
      Audio._forgetSeSource(src)
      table.remove(Audio._seSources, i)
    end
  end
end

function Audio.isSePlaying(id)
  if Audio._suspended then return false end
  if id == nil then
    local rse = rse_policy() ~= nil
    for _, src in ipairs(Audio._seSources) do
      local meta = Audio._seMeta[src]
      -- pokeemerald/src/sound.c:606
      if src:isPlaying() and not (rse and meta and tonumber(meta.player) == 3) then return true end
    end
    return false
  end
  local SE = lazyReq("src.core.game3.se_ids")
  id = SE.resolve(id)
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and meta.id == id and src:isPlaying() then return true end
  end
  return false
end

-- pokeemerald/src/sound.c:624
-- pokeruby/src/sound.c:554
function Audio.isSpecialSePlaying()
  if Audio._suspended then return false end
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and tonumber(meta.player) == 3 and src:isPlaying() then return true end
  end
  return false
end

function Audio.waitSe(id, cb)
  -- Poll in update via callback list with 180 frame (~3s) defensive timeout
  Audio._waitSe = Audio._waitSe or {}
  Audio._waitSe[#Audio._waitSe + 1] = { id = id, cb = cb, frames = 180 }
end

local function start_fanfare_source(id, mplay)
  Audio._fanfarePending = nil
  local old = Audio._fanfareSource
  if old then
    Audio._fanfareSource = nil
    pcall(function() old:stop() end)
    Audio._forgetSeSource(old)
    for i = #Audio._seSources, 1, -1 do
      if Audio._seSources[i] == old then table.remove(Audio._seSources, i) end
    end
  end
  Audio._stopSePlayer(mplay)
  local sd = Audio._fanfareSd[id]
  if not sd then
    if Audio._worker and Audio._cmdCh then
      Audio._cmdCh:push({ cmd = "bakeFanfare", id = id })
      Audio._fanfarePending = { id = id, player = mplay }
      return false
    end
    if Audio._worker == false and Audio.isReady() then
      local e = fanfare_entry(id)
      local baked = Player.bakeSong(Audio._pack, Audio._cache, id, {
        maxSec = ((e and e.frames) or 160) / 60 + 4,
      })
      if type(baked) == "userdata" then
        sd = baked
        Audio._fanfareSd[id] = sd
      end
    end
  end
  if not (sd and love and love.audio and love.audio.newSource) then return false end
  local src = Audio._fanfareSrc[id]
  if not src then
    local ok, made = pcall(love.audio.newSource, sd, "static")
    if not ok or not made then return false end
    src = made
    Audio._fanfareSrc[id] = src
    set_filter(src, Audio._filterLevel)
  end
  pcall(function()
    src:stop()
    src:setVolume(Audio._bgmVolume or 1)
    src:play()
  end)
  Audio._fanfareSource = src
  Audio._seSources[#Audio._seSources + 1] = src
  Audio._seByPlayer[mplay] = src
  Audio._seMeta[src] = { id = id, player = mplay }
  return true
end

function Audio.playFanfare(id)
  local SE = lazyReq("src.core.game3.se_ids")
  id = SE.resolve(id) or Audio.resolveSong(id)
  if type(id) ~= "number" then return false end
  local entry, haveTable = fanfare_entry(id)
  if haveTable and not entry then
    -- pokefirered/src/sound.c:245
    id = Audio.songs()[Audio.config().fanfareFallback or "MUS_LEVEL_UP"]
    entry = fanfare_entry(id)
  end
  local info = Audio.songInfo(id) or {}
  -- pokefirered/src/sound.c:50
  local frames = info.fanfareFrames or (entry and entry.frames) or 160
  -- pokefirered/src/sound.c:199
  if not Audio._fanfareActive then
    Audio._fanfareRestore = Audio._bgmGen or (Audio._currentSong and Audio._currentSong.id)
    Audio._fanfareDeferred = nil
    Audio.pauseBgm()
  end
  Audio._fanfareActive = true
  Audio._fanfareFrames = frames
  Audio.stopCry()
  if Audio.isReady() then
    start_fanfare_source(id, tonumber(info.player) or 2)
  end
  log(string.format("playFanfare id=%s frames=%s", tostring(id), tostring(frames)))
  return true
end

function Audio.pumpFanfares()
  local ch = Audio._fanfareCh
  if not ch then return end
  local msg = ch:pop()
  while msg do
    if type(msg) == "table" and msg.id and msg.data and msg.root == Audio._root then
      if not Audio._fanfareSd[msg.id] then
        Audio._fanfareSd[msg.id] = msg.data
      end
      local p = Audio._fanfarePending
      if p and p.id == msg.id and Audio._fanfareActive then
        start_fanfare_source(msg.id, p.player)
      end
    end
    msg = ch:pop()
  end
end

function Audio.isFanfareFinished()
  if Audio._suspended then return true end
  return not Audio._fanfareActive
end

function Audio.waitFanfare(cb)
  Audio._waitFanfareCb = cb
  if not Audio._fanfareActive and cb then cb() end
end

Audio.CRY_CACHE_MAX = 24

local function cry_inputs(mode, pan, volume)
  mode = tonumber(mode) or 0
  local cfg = Audio.config()
  -- pokeruby/src/sound.c:364
  if cfg.cryModeMax and (mode < 0 or mode > cfg.cryModeMax) then mode = 0 end
  local params = Sample.cryParams(mode, volume or cfg.cryDefaultVolume, cfg.cryModeOverrides)
  return params, pan and pan ~= 0 and Audio.normalizePan(pan) or nil
end

local function cry_meta(slot)
  local cry = slot and slot.info
  if not (cry and cry.cryIndex ~= nil) then return nil end
  local c = Audio._pack.index.cries[cry.cryIndex]
  return c and Audio._pack.samples[c.sampleId], cry.cryIndex
end

local function cry_render(slot, params, pan, mode, volume)
  local meta, cryIndex = cry_meta(slot)
  if not meta then return nil end
  local key = table.concat({ tostring(cryIndex), tostring(mode), tostring(volume), tostring(pan),
    Audio._mono and "m" or "s" }, ":")
  Warm.flush("cry:" .. key)
  local cache = Audio._cryCache or {}
  Audio._cryCache = cache
  local hit = cache[key]
  if hit then return hit.sd, hit.info end
  local pcm = Sample.loadPcm(Audio._pack.samplesBin, meta)
  if not pcm then return nil end
  local sd, info = Sample.renderCry(pcm, Mix.waveRate(meta.freq), params, {
    outRate = Mix.SAMPLE_RATE,
    pan = pan,
    mono = Audio._mono,
  })
  if sd then
    Audio._cryCacheN = (Audio._cryCacheN or 0) + 1
    if Audio._cryCacheN > Audio.CRY_CACHE_MAX then
      Audio._cryCache, Audio._cryCacheN = {}, 1
      cache = Audio._cryCache
    end
    cache[key] = { sd = sd, info = info }
  end
  return sd, info
end

function Audio.prewarmCry(species, mode, pan, priority)
  species = tonumber(species) or species
  if species == nil or not Audio.isReady() then return false end
  local params, npan = cry_inputs(mode, pan, nil)
  local slot = Player.startCry(Audio._pack, species, { pitch = 1.0 })
  local _, cryIndex = cry_meta(slot)
  if cryIndex == nil then return false end
  local key = table.concat({ tostring(cryIndex), tostring(tonumber(mode) or 0), "nil", tostring(npan),
    Audio._mono and "m" or "s" }, ":")
  if Audio._cryCache and Audio._cryCache[key] then return false end
  return Warm.add("cry:" .. key, function()
    cry_render(slot, params, npan, tonumber(mode) or 0, nil)
  end, priority)
end

-- pokefirered/src/sound.c:333
function Audio.playCry(species, mode, pan)
  species = tonumber(species) or species
  local volume, noDuck
  if type(mode) == "table" then
    local o = mode
    mode = o.mode
    if pan == nil then pan = o.pan end
    volume = o.volume
    noDuck = o.noDuck == true
  end
  mode = tonumber(mode) or 0
  local params, npan = cry_inputs(mode, pan, volume)
  local doubles = params.mode == 1 or noDuck
  Audio._cryParams = params
  log(string.format("playCry species=%s mode=%d", tostring(species), params.mode))
  if not Audio.isReady() then
    Audio._cryUntil = (Audio._cryClock or 0) + 64
    return true
  end
  local slot = Player.startCry(Audio._pack, species, { pitch = 1.0 })
  if not slot then
    Audio._cryUntil = (Audio._cryClock or 0) + 64
    return false
  end
  Audio._crySlot = slot
  if cry_meta(slot) then
    Audio._crySource = nil
    if not doubles then
      Audio._duck = 85 / 256
      Audio._duckHold = 2
      apply_bgm_gain()
    end
    local sd, info = cry_render(slot, params, npan, mode, volume)
    if info then
      Audio._cryUntil = (Audio._cryClock or 0) + info.frames
    end
    if sd and love and love.audio and love.audio.newSource then
      local src = love.audio.newSource(sd, "static")
      src:setVolume(Audio._sfxVolume or 1)
      src:play()
      Audio._crySource = src
    end
  end
  return true
end

function Audio.tickCry(dt)
  Audio._cryClock = (Audio._cryClock or 0) + (dt or 1 / 60) * 60
end

function Audio.isCryFinished()
  -- Timer is authoritative once expired (love Source:isPlaying can stick in tests).
  if Audio._cryUntil and (Audio._cryClock or 0) >= Audio._cryUntil then
    return true
  end
  if Audio._crySource then return not Audio._crySource:isPlaying() end
  if not Audio._cryUntil then return true end
  return (Audio._cryClock or 0) >= Audio._cryUntil
end

function Audio.stopCry()
  if Audio._crySource then pcall(function() Audio._crySource:stop() end) end
  Audio._crySource = nil
  Audio._cryUntil = nil
  Audio._duck = 1
  Audio._duckHold = 0
  apply_bgm_gain()
end

function Audio.currentSong()
  return Audio._currentSong
end

function Audio.stopAll()
  stop_bgm_source()
  Audio.stopSe()
  Audio.stopCry()
  Audio._seDuck = 1
  Audio._currentSong = nil
  Audio._fanfareActive = false
end

function Audio.update(dt)
  dt = dt or 1 / 60
  Audio.tickCry(dt)
  Audio._pumpSeLoops()
  update_se_duck()

  Audio.pumpFanfares()

  -- Fanfare countdown (frame-exact)
  if Audio._fanfareActive then
    Audio._fanfareFrames = (Audio._fanfareFrames or 0) - dt * 60
    if Audio._fanfareFrames <= 0 or Audio._suspended then
      Audio._fanfareActive = false
      Audio._fanfarePending = nil
      local deferred, restore = Audio._fanfareDeferred, Audio._fanfareRestore
      Audio._fanfareDeferred, Audio._fanfareRestore = nil, nil
      -- pokefirered/src/sound.c:264
      if deferred and deferred ~= Audio._bgmGen then
        Audio.playSong(deferred, { restart = true })
      elseif Audio._bgmGen or Audio._bgmLocal then
        Audio.resumeBgm()
      elseif restore then
        Audio.playSong(restore, { restart = true })
      else
        Audio._bgmPaused = false
      end
      local cb = Audio._waitFanfareCb
      Audio._waitFanfareCb = nil
      if cb then cb() end
    end
  end

  -- Cry duck restore
  if Audio._duckHold and Audio._duckHold > 0 then
    Audio._duckHold = Audio._duckHold - dt * 60
  elseif Audio._duck and Audio._duck < 1 and Audio.isCryFinished() then
    Audio._duck = 1
    apply_bgm_gain()
  end

  -- Fade out/in
  if Audio._fadeOut then
    local f = Audio._fadeOut
    f.t = f.t + dt
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    local stillSame = (f.gen == nil or f.gen == Audio._bgmGen)
      and (f.songId == nil or (Audio._currentSong and Audio._currentSong.id == f.songId))
    if stillSame and Audio._bgmSource then
      local vol = bgm_gain(f.start) * (1 - u)
      Audio._bgmSource:setVolume(vol)
    end
    if u >= 1 then
      -- Only stop if this fade still owns the current song (not a newer playSong).
      if stillSame then
        stop_bgm_source()
        Audio._currentSong = nil
      end
      Audio._fadeOut = nil
      if stillSame and f.nextSong then
        if f.fadeIn then
          -- pokeemerald/src/sound.c:151
          Audio.fadeInBgm(f.nextSong, f.fadeIn)
        else
          Audio.playSong(f.nextSong)
        end
      end
    end
  end
  if Audio._fadeIn and Audio._bgmSource then
    local f = Audio._fadeIn
    f.t = f.t + dt
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    Audio._bgmSource:setVolume(bgm_gain() * u)
    if u >= 1 then Audio._fadeIn = nil end
  end

  -- Pump worker buffers into QueueableSource without dropping.
  -- Dropping queued PCM while the sequencer has already advanced is what made
  -- songs start correct then race ahead (high/fast/early finish).
  Audio.pumpBgm()

  -- Sync BGM fallback
  if Audio._bgmLocal and Audio._bgmSource and not Audio._worker and not Audio._bgmPaused then
    local src = Audio._bgmSource
    local okFree, free = pcall(src.getFreeBufferCount, src)
    if okFree and type(free) == "number" and free > 0 then
      local n = Player.BUFFER_SAMPLES
      local sd = Player.renderBuffered(Audio._bgmLocal, n, {
        master = 1,
        sampleRate = Mix.SAMPLE_RATE,
      })
      if sd then
        pcall(function()
          src:queue(sd)
          if not src:isPlaying() then src:play() end
        end)
      end
    end
  end

  -- waitSe callbacks
  if Audio._waitSe then
    local pending = {}
    for _, w in ipairs(Audio._waitSe) do
      w.frames = (w.frames or 180) - dt * 60
      if not Audio.isSePlaying(w.id) or w.frames <= 0 or Audio._suspended then
        if w.cb then
          pcall(w.cb)
        end
      else
        pending[#pending + 1] = w
      end
    end
    Audio._waitSe = pending
  end
end

local function check_worker_status()
  local ch = Audio._statusCh
  if not (ch and Audio._worker) then return end
  local msg = ch:pop()
  while msg do
    if type(msg) == "table" and msg.installFailed and msg.root == Audio._root then
      warn_once("worker", "bgm worker could not load pack at " .. tostring(msg.root)
        .. ": " .. tostring(msg.err))
      if Audio._cmdCh then Audio._cmdCh:push({ cmd = "quit" }) end
      if Audio._outCh then Audio._outCh:clear() end
      if Audio._fanfareCh then Audio._fanfareCh:clear() end
      ch:clear()
      Audio._worker = false
      Audio._cmdCh = nil
      Audio._outCh = nil
      Audio._fanfareCh = nil
      Audio._statusCh = nil
      Audio._pendingBgm = nil
      Audio._bgmQueuedAt = {}
      local gen = Audio._bgmGen
      if gen and Audio.isReady() then
        Audio._bgmLocal = { voices = {}, songId = gen }
        Player.start(Audio._pack, Audio._cache, Audio._bgmLocal, gen, { forceSeq = true })
        ensure_bgm_source()
      end
      local p = Audio._fanfarePending
      if p and Audio._fanfareActive and Audio.isReady() then
        start_fanfare_source(p.id, p.player)
      end
      return
    end
    msg = ch:pop()
  end
end

--- Drain worker → QueueableSource. Safe to call from focus/resume hooks.
function Audio.pumpBgm()
  check_worker_status()
  if Audio._suspended then return end
  if not (Audio._outCh and Audio._bgmSource) or Audio._bgmPaused then return end
  local src = Audio._bgmSource
  local okFree, free = pcall(src.getFreeBufferCount, src)
  if not okFree or type(free) ~= "number" then free = 1 end

  local function accept(msg)
    if type(msg) ~= "table" or not msg.data then return true end
    if msg.gen ~= nil and msg.gen ~= Audio._bgmGen then return true end
    if msg.epoch ~= nil and msg.epoch ~= Audio._bgmEpoch then return true end
    local ok, res = pcall(src.queue, src, msg.data)
    if not ok or res == false then return false end
    local q = Audio._bgmQueuedAt
    q[#q + 1] = { at = msg.at, n = msg.n }
    while #q > (Player.BUFFER_COUNT or 32) + 8 do table.remove(q, 1) end
    if not src:isPlaying() then
      pcall(function()
        src:setVolume(bgm_gain())
        src:play()
      end)
    end
    return true
  end

  if Audio._pendingBgm then
    if free > 0 and accept(Audio._pendingBgm) then
      Audio._pendingBgm = nil
      free = free - 1
    elseif free <= 0 then
      free = 0
    else
      free = 0
    end
  end

  while free > 0 do
    local msg = Audio._outCh:pop()
    if not msg then break end
    if accept(msg) then
      free = free - 1
    else
      Audio._pendingBgm = msg
      break
    end
  end
end

function Audio.setSuspended(flag)
  Audio._suspended = not not flag
end

--- After focus regain / audio device reset: refill hard and restart if drained.
function Audio.onFocusGained()
  Audio._suspended = false
  if not Audio._bgmGen or Audio._bgmPaused then return end
  -- Worker kept synthesizing into the Channel while the main pump stalled;
  -- drain everything we can into the still-valid QueueableSource.
  for _ = 1, 16 do
    Audio.pumpBgm()
  end
  if Audio._bgmSource then
    pcall(function()
      Audio._bgmSource:setVolume(bgm_gain())
      if not Audio._bgmSource:isPlaying() then Audio._bgmSource:play() end
    end)
  end
end

function Audio.rebuildPlayback()
  Audio._suspended = false
  if not (love and love.audio and love.audio.newQueueableSource) then return false end
  if not Audio._bgmGen then return true end
  local ok, src = pcall(
    love.audio.newQueueableSource,
    Audio._bgmRate or Mix.SAMPLE_RATE, 16, 2, Player.BUFFER_COUNT)
  if not ok or not src then return false end
  local heard = Audio.bgmHeardPosition()
  local old = Audio._bgmSource
  Audio._bgmSource = src
  Audio.applyBgmFilter()
  Audio._pendingBgm = nil
  Audio._bgmQueuedAt = {}
  Audio._bgmBaseAt = heard or Audio._bgmBaseAt or 0
  if old then pcall(function() old:stop() end) end
  if Audio._outCh then Audio._outCh:clear() end
  -- Ask worker to keep producing; drain whatever arrives next frames.
  for _ = 1, 4 do Audio.pumpBgm() end
  pcall(function()
    src:setVolume(bgm_gain())
    src:play()
  end)
  return true
end

function Audio.endSession()
  Audio.stopAll()
  if Audio._fanfareSource then
    pcall(function() Audio._fanfareSource:stop() end)
    Audio._fanfareSource = nil
  end
  for _, src in pairs(Audio._fanfareSrc or {}) do
    pcall(function() src:stop() end)
  end
  Audio._fanfareSrc = {}
  Audio._fanfareSd = {}
  Audio._seRawClear()
  Audio._fanfareRoot = nil
  Audio._fanfareRestore = nil
  Audio._fanfareDeferred = nil
  Audio._fanfarePending = nil
  Audio._fanfareFrames = 0
  Audio._fanfareActive = false
  if Audio._bgmSource then
    pcall(function() Audio._bgmSource:stop() end)
    pcall(function() Audio._bgmSource:release() end)
    Audio._bgmSource = nil
  end
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "stop" })
    Audio._cmdCh:push({ cmd = "dropFanfares" })
  end
  if Audio._outCh then Audio._outCh:clear() end
  if Audio._fanfareCh then Audio._fanfareCh:clear() end
  Audio._pack = nil
  Audio._meta = nil
  Audio._cache = nil
  Audio._ready = false
  Audio._currentSong = nil
  Audio._mapSong = nil
  Audio._savedSong = nil
  Audio._bgmPaused = false
  Audio._suspended = false
  Audio._pendingBgm = nil
  Audio._bgmQueuedAt = {}
  Audio._bgmBaseAt = 0
  Audio._bgmGen = nil
  Audio._bgmLocal = nil
  Audio._duck = 1
  Audio._duckHold = 0
  Audio._seDuck = 1
end

function Audio.shutdown()
  pcall(Audio.endSession)
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "quit" }) end
  if Audio._worker then pcall(function() Audio._worker:wait() end) end
  if Audio._cmdCh then Audio._cmdCh:clear() end
  if Audio._outCh then Audio._outCh:clear() end
  if Audio._fanfareCh then Audio._fanfareCh:clear() end
  if Audio._statusCh then Audio._statusCh:clear() end
  Audio._worker = nil
  Audio._cmdCh = nil
  Audio._outCh = nil
  Audio._fanfareCh = nil
  Audio._statusCh = nil
end

pcall(function()
  lazyReq("src.core.SessionLifecycle").registerProcessShutdown(Audio.shutdown)
end)

return Audio
