-- Four M4A music players (BGM / SE1 / SE2 / cry) + pack loading.

local Sample = require("src.core.game3.m4a_sample")
local Mix = require("src.core.game3.m4a_mix")
local Seq = require("src.core.game3.m4a_seq")

local Player = {}

Player.SAMPLE_RATE = Mix.SAMPLE_RATE
-- Larger queueable buffers + deep QueueableSource ≈ ChipAudio's ~6s stall tolerance.
-- Mixing still advances the sequencer in ~1 GBA vblank quanta (see renderBuffered).
Player.BUFFER_SAMPLES = 8192
Player.BUFFER_COUNT = 32
-- Worker Channel backlog (~2s) so the main pump can hitch without starving OpenAL.
Player.CHANNEL_TARGET = 12

--- Output samples per GBA VBlank (≈738 @ 44100). Seq+mix must interleave at this
-- scale: batching many MPlayMain ticks then rendering with a frozen envelope is
-- what made intro/twinkle timings drift vs mGBA.
function Player.mixQuantum()
  local spv = Mix.samplesPerVBlank()
  local n = math.floor(spv + 0.5)
  if n < 256 then n = 256 end
  if n > 2048 then n = 2048 end
  return n
end

local function cache_read(cache, rel)
  if cache and cache.read then return cache:read(rel) end
  if love and love.filesystem and love.filesystem.read then
    return love.filesystem.read(rel)
  end
  return nil
end

local function load_lua(cache, rel)
  local src = cache_read(cache, rel)
  if type(src) ~= "string" then return nil end
  local chunk, err = load(src, "@" .. rel, "t", {})
  if not chunk then return nil, err end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  return result
end

function Player.loadPack(cache, root)
  root = root or "data/generated/gba/audio"
  local index = load_lua(cache, root .. "/index.lua")
  if type(index) ~= "table" then
    return nil, "missing index.lua"
  end
  local samplesBin = cache_read(cache, root .. "/samples.bin") or ""
  local samples = index.samples or load_lua(cache, root .. "/samples.lua") or {}
  local voicegroups = index.voicegroups or load_lua(cache, root .. "/voicegroups.lua") or {}
  return {
    root = root,
    index = index,
    samplesBin = samplesBin,
    samples = samples,
    voicegroups = voicegroups,
    songCache = {},
  }
end

function Player.songInfo(pack, id)
  id = tonumber(id) or id
  local songs = pack and pack.index and pack.index.songs
  if not songs then return nil end
  return songs[id] or songs[tostring(id)]
end

function Player.loadSongBin(pack, cache, id)
  id = tonumber(id)
  if not id or not pack then return nil end
  if pack.songCache[id] then return pack.songCache[id] end
  local blob = cache_read(cache, string.format("%s/songs/%d.bin", pack.root, id))
  if type(blob) ~= "string" then return nil end
  local parsed = Seq.parseSongBin(blob)
  pack.songCache[id] = parsed
  return parsed
end

local function tone_at(vg, idx)
  if not vg then return nil end
  return vg[idx] or vg[tostring(idx)]
end

--- Resolve ToneData through SPL/RHY to a concrete DS or CGB tone.
local function resolve_tone(pack, vgId, voiceId, rawKey, depth)
  depth = depth or 0
  if depth > 6 or not vgId then return nil end
  local vg = pack.voicegroups[vgId] or pack.voicegroups[tostring(vgId)]
  local tone = tone_at(vg, voiceId)
  if not tone then return nil end
  local typ = tone.type or 0
  local spl = math.floor(typ / 64) % 2 == 1
  local rhy = typ >= 128
  if spl then
    local ks = tone.keySplit
    local idx = 0
    if ks then
      idx = ks[rawKey] or ks[tostring(rawKey)] or 0
    end
    local subVg = pack.voicegroups[tone.subVgId] or pack.voicegroups[tostring(tone.subVgId)]
    if subVg and not tone_at(subVg, idx) then
      idx = 0
    end
    return resolve_tone(pack, tone.subVgId, idx, rawKey, depth + 1)
  end
  if rhy then
    local sub = resolve_tone(pack, tone.subVgId, rawKey, rawKey, depth + 1)
    if sub then
      sub = {
        type = sub.type,
        key = sub.key,
        length = sub.length,
        pan = sub.pan,
        sampleId = sub.sampleId,
        attack = sub.attack,
        decay = sub.decay,
        sustain = sub.sustain,
        release = sub.release,
        wavParam = sub.wavParam,
        wave = sub.wave,
        isRhy = true,
      }
    end
    return sub
  end
  return tone
end

local function make_voice_from_tone(pack, tone, rawKey, absKey, volL, volR, fine, tr)
  if not tone then return nil end
  fine = tonumber(fine) or 0
  local typ = tone.type or 0
  local kind = typ % 8
  local baseKey = rawKey or 60
  local noteKey = absKey or rawKey or 60
  if tone.isRhy and tone.key then
    local keyM = 0
    if tr then
      keyM = Seq.trackPitch(tr)
    end
    baseKey = tone.key
    noteKey = tone.key + keyM
  end
  if noteKey < 0 then noteKey = 0 end
  if noteKey > 178 then noteKey = 178 end

  local rhythmPan = 0
  if tone.isRhy and tone.pan and tone.pan >= 0x80 then
    rhythmPan = (tone.pan - 0xC0) * 2
  end
  if tr then volL, volR = Seq.trackVolume(tr, tr.vel, rhythmPan) end

  local v
  if kind == 0 and tone.sampleId then
    local meta = pack.samples[tone.sampleId] or pack.samples[tostring(tone.sampleId)]
    local pcm = Sample.loadPcm(pack.samplesBin, meta)
    if not pcm or not meta then return nil end
    local fixed = math.floor((tone.type or 0) / 8) % 2 == 1
    -- pret MidiKeyToFreq(wav, noteKey, fine) — returns playback Hz.
    local rate = fixed and Mix.GBA_MIX_RATE or Mix.midiKeyToFreq(meta.freq, noteKey, fine)
    -- WaveData.flags is the high byte of cached status; loops may start at zero.
    local loop = math.floor((meta.status or 0) / 16384) % 4 ~= 0
      and (meta.loopStart or 0) < (meta.size or 0)
    v = Mix.newDsVoice(pcm, meta, {
      rate = rate,
      loop = loop,
      volL = volL,
      volR = volR,
      tone = tone,
    })
    v.wavFreq = meta.freq
    v.fixedFreq = fixed
  -- CGB channels 1..4 (pulse uses MidiKeyToCgbFreq; wave is one octave below)
  elseif kind >= 1 and kind <= 4 then
    if kind == 1 or kind == 2 then
      local duty = 2
      local wp = tone.wavParam or 0
      if wp <= 3 then duty = wp end
      v = Mix.newCgbPulse({
        key = noteKey,
        fine = fine,
        duty = duty,
        cgbChan = kind,
        volL = volL, volR = volR,
        tone = tone,
      })
    elseif kind == 3 then
      local wave = tone.wave
      if type(wave) ~= "table" or #wave < 32 then
        wave = {}
        for i = 1, 32 do wave[i] = (i % 16) end
      end
      v = Mix.newCgbWave({
        key = noteKey,
        fine = fine,
        wave = wave,
        volL = volL, volR = volR,
        tone = tone,
      })
    elseif kind == 4 then
      v = Mix.newCgbNoise({
        key = noteKey,
        period = Mix.cgbNoisePeriod(noteKey),
        volL = volL, volR = volR,
        tone = tone,
      })
    end
  end
  if v then
    v.noteKey = baseKey
    v.rhythmPan = rhythmPan
    if v.adsr and tr then
      v.adsr.pseudoEchoVolume = tr.pseudoEchoVolume or 0
      v.adsr.pseudoEchoLength = tr.pseudoEchoLength or 0
    end
    if v.kind == "ds" then
      v.pos = tr and tr.sampleStart or 0
    elseif (tone.length or 0) > 0 then
      local maxLength = kind == 3 and 256 or 64
      v.lengthRemaining = (maxLength - tone.length % maxLength) * Mix.SAMPLE_RATE / 256
    end
  end
  return v
end

--- Start a song on a player slot. For SE-first, also supports sample-only mode.
function Player.start(pack, cache, slot, songId, opts)
  opts = opts or {}
  local info = Player.songInfo(pack, songId)
  slot.songId = songId
  slot.info = info
  slot.seq = nil
  slot.voices = {}
  slot.sampleOnly = false
  slot.done = false
  slot.frameSamplesLeft = 0
  slot.frameSampleCarry = 0
  slot.hpfState = { l = 0, r = 0 }
  local reverb = info and info.reverb or 0
  if reverb >= 128 then slot.reverb = reverb % 128 end
  slot.reverbState = Mix.newReverb(slot.reverb or 0)

  -- Prefer sequencer whenever track data exists. sampleOnly is only for
  -- explicit one-shots (cries) — SE like SE_SELECT are CGB sequences, not voice0 PCM.
  if opts.sampleOnly then
    local meta = info and (pack.samples[info.sampleId] or pack.samples[tostring(info.sampleId)])
    local pcm = Sample.loadPcm(pack.samplesBin, meta)
    if pcm and meta then
      slot.sampleOnly = true
      slot.voices = {
        Mix.newDsVoice(pcm, meta, {
          loop = false,
          volL = opts.volL or 0.7,
          volR = opts.volR or 0.7,
        }),
      }
      return true
    end
  end

  local song = Player.loadSongBin(pack, cache, songId)
  if not song then
    if info and info.sampleId then
      local meta = pack.samples[info.sampleId] or pack.samples[tostring(info.sampleId)]
      local pcm = Sample.loadPcm(pack.samplesBin, meta)
      if pcm and meta then
        slot.sampleOnly = true
        slot.voices = { Mix.newDsVoice(pcm, meta, { volL = 0.7, volR = 0.7 }) }
        return true
      end
    end
    return false
  end

  local vgId = info and info.voicegroupId
  slot.seq = Seq.newPlayer(song, {
    voiceResolver = function(voiceId, rawKey, vel, tr, volL, volR, fine, absKey)
      if not absKey then
        local keyM = tr and Seq.trackPitch(tr) or 0
        absKey = rawKey + keyM
      end
      local tone = resolve_tone(pack, vgId, voiceId, rawKey)
      if tone and tr.toneOverrides then
        local copy = {}
        for k, value in pairs(tone) do copy[k] = value end
        for k, value in pairs(tr.toneOverrides) do copy[k] = value end
        tone = copy
      end
      return make_voice_from_tone(pack, tone, rawKey, absKey, volL, volR, fine, tr)
    end,
  })
  return true
end

function Player.startCry(pack, species, opts)
  opts = opts or {}
  local cryIds = pack.index.cryIds or {}
  local idx = cryIds[species] or cryIds[tostring(species)] or math.max(0, (tonumber(species) or 1) - 1)
  local cry = pack.index.cries and (pack.index.cries[idx] or pack.index.cries[tostring(idx)])
  if not cry or not cry.sampleId then return false end
  local meta = pack.samples[cry.sampleId] or pack.samples[tostring(cry.sampleId)]
  local pcm = Sample.loadPcm(pack.samplesBin, meta)
  if not pcm or not meta then return false end
  local rate = Mix.waveRate(meta.freq)
  local pitch = opts.pitch or 1.0
  return {
    sampleOnly = true,
    voices = {
      Mix.newDsVoice(pcm, meta, {
        rate = rate * pitch,
        volL = opts.volL or 0.85,
        volR = opts.volR or 0.85,
      }),
    },
    songId = nil,
    info = { kind = "cry", cryIndex = idx },
    done = false,
  }
end

function Player.updateSlot(slot, vblanks)
  if not slot then return end
  vblanks = tonumber(vblanks) or 1
  if vblanks < 0 then vblanks = 0 end
  if slot.seq then
    slot.voices = Seq.update(slot.seq, vblanks)
    if Seq.allDone(slot.seq) then slot.done = true end
  else
    local any = false
    for _, v in ipairs(slot.voices or {}) do
      if v.alive then any = true end
    end
    if not any then slot.done = true end
  end
end

function Player.renderSlot(slot, n, opts)
  opts = opts or {}
  opts.reverbState = opts.reverbState or (slot and slot.reverbState)
  local voices = slot and slot.voices or {}
  if opts.raw then
    local outL, outR, alive = Mix.render(voices, n, opts)
    if slot then slot.voices = alive or voices end
    return outL, outR, alive
  end
  local sd, alive = Mix.render(voices, n, opts)
  if slot then slot.voices = alive or voices end
  return sd
end

--- Fill `n` output samples by interleaving MPlayMain (~1 vblank) with mix.
-- Pret/mGBA: SoundMain + MPlayMain each vblank. Advancing many ticks then
-- mixing one big buffer freezes ADSR and clumps short sparkle notes.
function Player.renderBuffered(slot, n, opts)
  opts = opts or {}
  n = math.floor(tonumber(n) or Player.BUFFER_SAMPLES or 8192)
  if n < 1 then n = 1 end
  local rate = opts.sampleRate or Mix.SAMPLE_RATE
  local master = opts.master or 1
  local L, R = {}, {}
  local produced = 0
  while produced < n do
    if (slot.frameSamplesLeft or 0) <= 0 then
      Player.updateSlot(slot, 1)
      local exact = rate / Mix.GBA_VBLANK_HZ + (slot.frameSampleCarry or 0)
      slot.frameSamplesLeft = math.floor(exact)
      slot.frameSampleCarry = exact - slot.frameSamplesLeft
    end
    local chunk = math.min(slot.frameSamplesLeft, n - produced)
    slot.hpfState = slot.hpfState or { l = 0, r = 0 }
    local outL, outR, alive = Mix.render(slot.voices or {}, chunk, {
      raw = true,
      master = master,
      sampleRate = rate,
      hpfCapL = slot.hpfState.l,
      hpfCapR = slot.hpfState.r,
      hpfState = slot.hpfState,
      reverbState = slot.reverbState,
    })
    if slot then
      slot.voices = alive or slot.voices
      if slot.seq then slot.seq.voices = slot.voices end
      slot.frameSamplesLeft = slot.frameSamplesLeft - chunk
    end
    for i = 1, chunk do
      L[#L + 1] = outL[i] or 0
      R[#R + 1] = outR[i] or 0
    end
    produced = produced + chunk
  end
  if opts.raw then
    return L, R
  end
  if not (love and love.sound and love.sound.newSoundData) then
    return L, R
  end
  local sd = love.sound.newSoundData(#L, rate, 16, 2)
  local function clip(x)
    if x > 1 then return 1 end
    if x < -1 then return -1 end
    return x
  end
  local mono = opts.mono and true or false
  -- master already applied in Mix.render; clip only here.
  for i = 1, #L do
    local l = clip(L[i] or 0)
    local r = clip(R[i] or 0)
    if mono then
      local m = (l + r) * 0.5
      l, r = m, m
    end
    sd:setSample(i - 1, 1, l)
    sd:setSample(i - 1, 2, r)
  end
  return sd
end

function Player.snapshotSlot(slot, at)
  if not (slot and slot.seq) then return nil end
  return { at = at, done = slot.done, seq = Seq.snapshot(slot.seq),
    frameSamplesLeft = slot.frameSamplesLeft, frameSampleCarry = slot.frameSampleCarry }
end

-- pokefirered/src/m4a.c:668
function Player.stopAt(slot, snaps, at, abs, pack, cache)
  if not slot then return abs end
  at = tonumber(at)
  local snap
  if at and slot.seq and snaps and (abs == nil or at < abs) then
    for i = #snaps, 1, -1 do
      if snaps[i].at <= at then snap = snaps[i]; break end
    end
  end
  if snap then
    Seq.restore(slot.seq, snap.seq)
    slot.seq.voices = {}
    slot.voices = {}
    slot.done = snap.done
    slot.frameSamplesLeft = snap.frameSamplesLeft or 0
    slot.frameSampleCarry = snap.frameSampleCarry or 0
    local left = at - snap.at
    local q = Player.mixQuantum()
    while left > 0 do
      local n = math.min(q, left)
      Player.renderBuffered(slot, n, { raw = true })
      left = left - n
    end
    for i = #snaps, 1, -1 do
      if snaps[i].at > at then table.remove(snaps, i) end
    end
    abs = at
  elseif at and slot.songId and (abs == nil or at < abs) and (pack or slot.pack) and (cache or slot.cache) then
    Player.start(pack or slot.pack, cache or slot.cache, slot, slot.songId, { forceSeq = true })
    if snaps then
      for i = #snaps, 1, -1 do table.remove(snaps, i) end
    end
    local left = at
    local q = Player.mixQuantum()
    while left > 0 do
      local n = math.min(q, left)
      Player.renderBuffered(slot, n, { raw = true })
      left = left - n
    end
    abs = at
  end
  slot.hpfState = { l = 0, r = 0 }
  slot.reverbState = Mix.newReverb(slot.reverb or 0)
  return abs
end

function Player.bakeSong(pack, cache, songId, opts)
  opts = opts or {}
  local slot = { voices = {} }
  if not Player.start(pack, cache, slot, songId, { forceSeq = true }) then return nil end
  local rate = opts.sampleRate or Mix.SAMPLE_RATE
  local quantum = Player.mixQuantum()
  local maxN = math.floor(rate * (opts.maxSec or 8))
  local L, R = {}, {}
  local total, idle, since = 0, 0, 0
  while total < maxN do
    local n = math.min(quantum, maxN - total)
    local outL, outR = Player.renderBuffered(slot, n, {
      raw = true,
      master = opts.master or 1,
      sampleRate = rate,
      quantum = quantum,
    })
    for i = 1, n do
      L[#L + 1] = outL[i] or 0
      R[#R + 1] = outR[i] or 0
    end
    total = total + n
    since = since + n
    if opts.yieldEvery and since >= opts.yieldEvery then
      since = 0
      coroutine.yield()
    end
    local any = false
    for _, v in ipairs(slot.voices or {}) do
      if v.alive then any = true; break end
    end
    if slot.done and not any and not Mix.reverbActive(slot.reverbState) then
      idle = idle + 1
      if idle >= 2 then break end
    else
      idle = 0
    end
  end
  if #L == 0 then L[1], R[1] = 0, 0 end
  if opts.raw or not (love and love.sound and love.sound.newSoundData) then
    return L, R
  end
  local sd = love.sound.newSoundData(#L, rate, 16, 2)
  local mono = opts.mono and true or false
  for i = 1, #L do
    local l, r = L[i], R[i]
    if l > 1 then l = 1 elseif l < -1 then l = -1 end
    if r > 1 then r = 1 elseif r < -1 then r = -1 end
    if mono then
      local m = (l + r) * 0.5
      l, r = m, m
    end
    sd:setSample(i - 1, 1, l)
    sd:setSample(i - 1, 2, r)
  end
  return sd
end

--- Render a started slot through the sequencer into one SoundData (or raw L/R).
function Player.bakeSlot(slot, opts)
  opts = opts or {}
  local rate = opts.sampleRate or Mix.SAMPLE_RATE
  local maxSec = opts.maxSec or 2.5
  -- Default to one GBA vblank so SE envelopes match hardware timing.
  local chunk = opts.chunk or Player.mixQuantum()
  local maxN = math.floor(rate * maxSec)
  local L, R = {}, {}
  local total = 0
  local idle = 0
  local stopOnGoto = opts.stopOnGoto == true
  local sawGoto = false
  while total < maxN do
    local n = math.min(chunk, maxN - total)
    local pcs
    if stopOnGoto and slot.seq and slot.seq.tracks then
      pcs = {}
      for i, tr in ipairs(slot.seq.tracks) do
        pcs[i] = tr.loopCount or 0
      end
    end
    local outL, outR = Player.renderBuffered(slot, n, { raw = true, sampleRate = rate })
    if pcs then
      for i, tr in ipairs(slot.seq.tracks) do
        if (tr.loopCount or 0) > (pcs[i] or 0) then
          sawGoto = true
        end
      end
    end
    for i = 1, n do
      L[#L + 1] = outL[i] or 0
      R[#R + 1] = outR[i] or 0
    end
    total = total + n
    if stopOnGoto and sawGoto and total > chunk then
      break
    end
    local any = false
    for _, v in ipairs(slot.voices or {}) do
      if v.alive then any = true; break end
    end
    if slot.done and not any and not Mix.reverbActive(slot.reverbState) then
      idle = idle + 1
      if idle >= 2 then break end
    else
      idle = 0
    end
  end
  if #L == 0 then
    L[1] = 0
    R[1] = 0
  end
  if opts.raw or not (love and love.sound and love.sound.newSoundData) then
    return L, R
  end
  local ch = opts.mono and 1 or 2
  local sd = love.sound.newSoundData(#L, rate, 16, ch)
  local master = opts.master or 1
  -- pret panpot (-64..+63): attenuate the far channel.
  local pan = tonumber(opts.pan) or 0
  if pan > 63 then pan = 63 end
  if pan < -64 then pan = -64 end
  local panN = pan / 64
  local gainL = 1 - math.max(0, panN)
  local gainR = 1 - math.max(0, -panN)
  local function clip(x)
    if x > 1 then return 1 end
    if x < -1 then return -1 end
    return x
  end
  for i = 1, #L do
    local l = clip((L[i] or 0) * master * gainL)
    local r = clip((R[i] or 0) * master * gainR)
    if ch == 1 then
      sd:setSample(i - 1, (l + r) * 0.5)
    else
      sd:setSample(i - 1, 1, l)
      sd:setSample(i - 1, 2, r)
    end
  end
  return sd
end

return Player
