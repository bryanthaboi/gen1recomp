-- Extract FireRed M4A song table, track bytecode, DirectSound samples, and cries.
-- Pure Lua (runs inside ExtractThread). Samples stored as raw little-endian s8 PCM.

local Versions = require("src.import.gba.versions")

local ExtractAudio = {}

ExtractAudio.SONG_COUNT = Versions.AUDIO and Versions.AUDIO.song_count or 347
ExtractAudio.SONG_TABLE = Versions.AUDIO and Versions.AUDIO.song_table or 0x4A32CC
ExtractAudio.CRY_TABLE = Versions.AUDIO and Versions.AUDIO.cry_table or 0x48C914
ExtractAudio.CRY_COUNT = Versions.AUDIO and Versions.AUDIO.cry_count or 388

-- pret sound.c sFanfares[] — frame durations for waitfanfare.
local FANFARES = {
  [256] = { frames = 160, name = "MUS_HEAL" },
  [257] = { frames = 80, name = "MUS_LEVEL_UP" },
  [258] = { frames = 160, name = "MUS_OBTAIN_ITEM" },
  [259] = { frames = 220, name = "MUS_EVOLVED" },
  [260] = { frames = 340, name = "MUS_OBTAIN_BADGE" },
  [261] = { frames = 220, name = "MUS_OBTAIN_TMHM" },
  [262] = { frames = 120, name = "MUS_OBTAIN_BERRY" },
  [268] = { frames = 250, name = "MUS_SLOTS_JACKPOT" },
  [269] = { frames = 150, name = "MUS_SLOTS_WIN" },
  [270] = { frames = 180, name = "MUS_MOVE_DELETED" },
  [271] = { frames = 160, name = "MUS_TOO_BAD" },
  [317] = { frames = 196, name = "MUS_DEX_RATING" },
  [318] = { frames = 170, name = "MUS_OBTAIN_KEY_ITEM" },
  [338] = { frames = 450, name = "MUS_POKE_FLUTE" },
}

local ROLES = {
  battleWild = 298, battleTrainer = 297, battleGymLeader = 296, battleChampion = 299,
  victoryWild = 311, victoryTrainer = 310, victoryGymLeader = 312,
  encounterBoy = 285, encounterGirl = 284, encounterRival = 315, encounterRocket = 283,
  encounterGymLeader = 342, pokeCenter = 303, heal = 256, surf = 305, cycling = 282,
  caught = 322, caughtIntro = 319, evolution = 264, evolutionIntro = 263, evolved = 259,
  levelUp = 257, obtainItem = 258, followMe = 272, title = 278,
}

local PLAYERS = { [0] = "bgm", [1] = "se1", [2] = "se2", [3] = "cry" }

local function write(cache, path, data)
  if cache and cache.write then
    return cache:write(path, data)
  end
  if love and love.filesystem and love.filesystem.write then
    return love.filesystem.write(path, data)
  end
  return false
end

local function rom_bytes(rom)
  if type(rom) == "string" then return rom end
  if rom and type(rom.data) == "string" then return rom.data end
  return nil
end

local function ru8(data, off)
  if off < 0 or off >= #data then return nil end
  return data:byte(off + 1)
end

local function ru16(data, off)
  local b0, b1 = ru8(data, off), ru8(data, off + 1)
  if not b0 or not b1 then return nil end
  return b0 + b1 * 256
end

local function ru32(data, off)
  local b0, b1, b2, b3 = ru8(data, off), ru8(data, off + 1), ru8(data, off + 2), ru8(data, off + 3)
  if not b0 then return nil end
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function gba_off(ptr)
  if not ptr or ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  return ptr - 0x08000000
end

--- Locate gSongTable when Versions.AUDIO.song_table is wrong (structural scan).
function ExtractAudio.findSongTable(data, count)
  count = count or ExtractAudio.SONG_COUNT
  local limit = #data - count * 8
  for base = 0, limit, 4 do
    local h0 = ru32(data, base)
    if h0 and h0 >= 0x08000000 and h0 < 0x09000000
        and ru16(data, base + 4) == 0 and ru16(data, base + 6) == 0 then
      local e5 = base + 5 * 8
      local h5 = ru32(data, e5)
      if ru16(data, e5 + 4) == 2 and ru16(data, e5 + 6) == 2
          and h5 and h5 >= 0x08000000 and h5 < 0x09000000
          and ru16(data, base + 8 + 4) == 1 and ru16(data, base + 8 + 6) == 1 then
        local e278 = base + 278 * 8
        if e278 + 8 <= #data and ru16(data, e278 + 4) == 0 and ru16(data, e278 + 6) == 0 then
          return base
        end
      end
    end
  end
  return nil
end

local function append_bytes(parts, data, off, len)
  if len <= 0 then return end
  parts[#parts + 1] = data:sub(off + 1, off + len)
end

local function encode_lua_table(tbl, indent)
  indent = indent or ""
  local parts = { "{\n" }
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb and ta == "number" then return a < b end
    if ta == "number" then return true end
    if tb == "number" then return false end
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do
    local v = tbl[k]
    local ks = type(k) == "number" and ("[%s]"):format(k) or ("[%q]"):format(tostring(k))
    if type(v) == "table" then
      parts[#parts + 1] = indent .. "  " .. ks .. " = " .. encode_lua_table(v, indent .. "  ") .. ",\n"
    elseif type(v) == "string" then
      parts[#parts + 1] = indent .. "  " .. ks .. " = " .. string.format("%q", v) .. ",\n"
    elseif type(v) == "boolean" then
      parts[#parts + 1] = indent .. "  " .. ks .. " = " .. tostring(v) .. ",\n"
    elseif type(v) == "number" then
      parts[#parts + 1] = indent .. "  " .. ks .. " = " .. tostring(v) .. ",\n"
    elseif v == nil then
      parts[#parts + 1] = indent .. "  " .. ks .. " = nil,\n"
    end
  end
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts)
end

-- GameFreak DPCM (WaveData.type == 1): 64 samples → 0x21 bytes per block.
-- Matches agbplay MP2KChnPCM::sampleFetchCallbackGFDPCMDecomp / pret gDeltaEncodingTable.
local DPCM_DELTA = {
  [0] = 0, 1, 4, 9, 16, 25, 36, 49, -64, -49, -36, -25, -16, -9, -4, -1,
}

local function s8_byte(b)
  return b >= 128 and (b - 256) or b
end

local function clamp_s8(v)
  if v > 127 then return 127 end
  if v < -128 then return -128 end
  return v
end

--- Decode GameFreak DPCM to a Lua string of raw s8 samples (length = sampleCount).
local function decode_gfdpcm(data, pcmOff, sampleCount)
  sampleCount = sampleCount or 0
  if sampleCount <= 0 then return "" end
  local blocks = math.ceil(sampleCount / 64)
  local need = blocks * 0x21
  if pcmOff + need > #data then
    -- Truncate to available blocks
    blocks = math.floor((#data - pcmOff) / 0x21)
    sampleCount = math.min(sampleCount, blocks * 64)
    if sampleCount <= 0 then return "" end
  end
  local out = {}
  local n = 0
  local function push(v)
    v = clamp_s8(v)
    n = n + 1
    out[n] = string.char((v + 256) % 256)
  end
  for bi = 0, blocks - 1 do
    local bp = pcmOff + bi * 0x21
    local acc = s8_byte(data:byte(bp + 1))
    push(acc)
    if n >= sampleCount then break end
    acc = acc + DPCM_DELTA[data:byte(bp + 2) % 16]
    push(acc)
    if n >= sampleCount then break end
    for h = 2, 32 do
      local byte = data:byte(bp + 1 + h)
      acc = acc + DPCM_DELTA[math.floor(byte / 16) % 16]
      push(acc)
      if n >= sampleCount then break end
      acc = acc + DPCM_DELTA[byte % 16]
      push(acc)
      if n >= sampleCount then break end
    end
    if n >= sampleCount then break end
  end
  return table.concat(out)
end

local function read_wave(data, wavOff, sampleMap, sampleParts, sampleCursor)
  if sampleMap[wavOff] then return sampleMap[wavOff] end
  local typ = ru16(data, wavOff) or 0
  -- WaveData.type low byte: 0 = linear s8 PCM, 1 = GameFreak DPCM
  local compressed = (typ % 256) == 1
  local status = ru16(data, wavOff + 2) or 0
  local freq = ru32(data, wavOff + 4) or 0
  local loopStart = ru32(data, wavOff + 8) or 0
  local size = ru32(data, wavOff + 12) or 0 -- decoded sample count
  if size > 2 * 1024 * 1024 then size = 0 end
  local pcmOff = wavOff + 16
  local n = 0
  for _ in pairs(sampleMap) do n = n + 1 end
  local id = n + 1
  local entry = {
    id = id,
    type = typ,
    compressed = compressed,
    status = status,
    freq = freq,
    loopStart = loopStart,
    size = size,
    offset = sampleCursor[1],
  }
  sampleMap[wavOff] = entry
  if size > 0 then
    local pcm
    if compressed then
      pcm = decode_gfdpcm(data, pcmOff, size)
    else
      if pcmOff + size <= #data then
        pcm = data:sub(pcmOff + 1, pcmOff + size)
      end
    end
    if pcm and #pcm > 0 then
      entry.size = #pcm
      sampleParts[#sampleParts + 1] = pcm
      sampleCursor[1] = sampleCursor[1] + #pcm
    else
      entry.size = 0
    end
  else
    entry.size = 0
  end
  return entry
end

local function read_tone_sample(data, toneOff, sampleMap, sampleParts, sampleCursor)
  local typ = ru8(data, toneOff) or 0
  -- DirectSound / fixed: type bits without CGB/SPL/RHY
  if typ >= 0x40 then
    -- SPL/RHY — wav field is a sub-voicegroup pointer, not WaveData
    return nil, typ
  end
  local kind = typ % 8
  if kind == 1 or kind == 2 or kind == 3 or kind == 4 then
    -- CGB square/wave/noise — no DirectSound WaveData
    return nil, typ
  end
  local wavPtr = ru32(data, toneOff + 4)
  local wavOff = gba_off(wavPtr)
  if not wavOff then return nil, typ end
  return read_wave(data, wavOff, sampleMap, sampleParts, sampleCursor), typ
end

--- Collect primary DirectSound sample for a song (voice 0), for SE-first playback.
local function song_primary_sample(data, headerOff, sampleMap, sampleParts, sampleCursor)
  local vgPtr = ru32(data, headerOff + 4)
  local vgOff = gba_off(vgPtr)
  if not vgOff then return nil end
  local sample = read_tone_sample(data, vgOff, sampleMap, sampleParts, sampleCursor)
  return sample and sample.id or nil
end

-- Dump one voicegroup (128 ToneData). SPL/RHY recurse into sub-groups once.
local function dump_voicegroup(data, vgOff, sampleMap, sampleParts, sampleCursor, vgMap, voicegroups, depth)
  if not vgOff or (depth or 0) > 5 then return nil end
  if vgMap[vgOff] then return vgMap[vgOff] end
  local id = 0
  for _ in pairs(vgMap) do id = id + 1 end
  id = id + 1
  vgMap[vgOff] = id
  local tones = {}
  for i = 0, 127 do
    local toff = vgOff + i * 12
    if toff + 12 > #data then break end
    local typ = ru8(data, toff) or 0
    local entry = {
      type = typ,
      key = ru8(data, toff + 1) or 60,
      length = ru8(data, toff + 2) or 0,
      pan = ru8(data, toff + 3) or 0,
    }
    local spl = math.floor(typ / 64) % 2 == 1
    local rhy = typ >= 128
    if spl or rhy then
      local subOff = gba_off(ru32(data, toff + 4))
      if subOff then
        entry.subVgId = dump_voicegroup(
          data, subOff, sampleMap, sampleParts, sampleCursor, vgMap, voicegroups, (depth or 0) + 1)
      end
      if spl then
        -- KeySplitTable* is packed where attack..release normally live.
        local ksOff = gba_off(ru32(data, toff + 8))
        if ksOff and ksOff + 128 <= #data then
          local ks = {}
          for k = 0, 127 do
            ks[k] = ru8(data, ksOff + k) or 0
          end
          entry.keySplit = ks
        end
      end
    else
      local kind = typ % 8
      if kind == 0 then
        local sample = read_tone_sample(data, toff, sampleMap, sampleParts, sampleCursor)
        entry.sampleId = sample and sample.id or nil
        entry.attack = ru8(data, toff + 8) or 0xFF
        entry.decay = ru8(data, toff + 9) or 0
        entry.sustain = ru8(data, toff + 10) or 0xFF
        entry.release = ru8(data, toff + 11) or 0
      else
        -- CGB: square stores duty in wav low bits; wave ch.3 points at 16-byte nibble table.
        local kind = typ % 8
        entry.wavParam = ru32(data, toff + 4) or 0
        entry.attack = ru8(data, toff + 8) or 0
        entry.decay = ru8(data, toff + 9) or 0
        entry.sustain = ru8(data, toff + 10) or 0
        entry.release = ru8(data, toff + 11) or 0
        if kind == 3 then
          local waveOff = gba_off(entry.wavParam)
          if waveOff and waveOff + 16 <= #data then
            local wave = {}
            for bi = 0, 15 do
              local b = ru8(data, waveOff + bi) or 0
              wave[#wave + 1] = math.floor(b / 16) % 16
              wave[#wave + 1] = b % 16
            end
            entry.wave = wave
          end
        end
      end
    end
    tones[i] = entry
  end
  voicegroups[id] = tones
  return id
end

-- Walk reachable bytecode, including patterns beyond FINE or before the entry.
-- Operands may contain command-valued bytes, so only instruction boundaries
-- can identify FINE or a pointer. Note/running-status operands are all < 0x80.
local function collect_track(data, entry)
  local pending, visited, pointers = { { pc = entry, pattern = false } }, {}, {}
  local first, last = entry, entry
  local budget = 65536
  local hasGoto = false
  local xargs = { [0]=0, 4, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 4 }
  while #pending > 0 do
    local branch = table.remove(pending)
    local pc, pattern = branch.pc, branch.pattern
    while pc and pc >= 0 and pc < #data do
      local state = pc * 2 + (pattern and 1 or 0)
      if visited[state] then break end
      budget = budget - 1
      if budget < 0 then error("M4A track exceeds bytecode limit") end
      visited[state] = true
      local cmd = ru8(data, pc)
      local length, pointer, stop = 1, nil, false
      if cmd == 0xB2 or cmd == 0xB3 then
        length, pointer = 5, pc + 1
        stop = cmd == 0xB2
        if stop then hasGoto = true end
      elseif cmd == 0xB5 then
        length, pointer = 6, pc + 2
      elseif cmd == 0xB4 then
        -- Inline patterns fall through PEND on their first, uncalled pass.
        stop = pattern
      elseif cmd == 0xB9 then
        length = 4
        local op = ru8(data, pc + 1) or 0
        if op >= 6 and op <= 17 then length, pointer = 8, pc + 4 end
      elseif cmd == 0xCD then
        local op = ru8(data, pc + 1) or 0
        length = 2 + (xargs[op] or 0)
        stop = op == 0 or op == 3 or xargs[op] == nil
      elseif cmd == 0xCC then -- PORT: register offset, value
        length = 3
      elseif cmd >= 0xBA and cmd <= 0xC5 or cmd == 0xC8 then
        length = 2
      elseif cmd >= 0xB1 and cmd <= 0xB8 or cmd == 0xC6 or cmd == 0xC7
        or cmd >= 0xC9 and cmd <= 0xCB then
        stop = true -- FINE, PEND, or an unused command mapped to ply_fine
      end
      if pc + length > #data then error("Truncated M4A instruction") end
      first = math.min(first, pc)
      last = math.max(last, pc + length)
      if last - first > 1024 * 1024 then error("M4A track span exceeds limit") end
      if pointer then
        local target = gba_off(ru32(data, pointer))
        if not target or target >= #data then error("Invalid M4A branch pointer") end
        pointers[pointer] = target
        pending[#pending + 1] = { pc = target, pattern = cmd == 0xB3 or pattern }
      end
      if stop then break end
      pc = pc + length
    end
  end
  local function le32(value)
    return string.char(value % 256, math.floor(value / 256) % 256,
      math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
  end
  local ordered = {}
  for pointer in pairs(pointers) do ordered[#ordered + 1] = pointer end
  table.sort(ordered)
  local parts, cursor = {}, first
  for _, pointer in ipairs(ordered) do
    parts[#parts + 1] = data:sub(cursor + 1, pointer)
    parts[#parts + 1] = le32(pointers[pointer] - first)
    cursor = pointer + 4
  end
  parts[#parts + 1] = data:sub(cursor + 1, last)
  return table.concat(parts), entry - first, hasGoto
end

--- Packed song bin: header + (offset,length,entry) per track. Bit 7 of blocks
-- marks the extended table; branch offsets and entries are relative to each body.
local function dump_song_tracks(data, headerOff, songId, cache, root)
  local tracks = ru8(data, headerOff) or 0
  if tracks == 0 or tracks > 16 then tracks = 0 end
  local blocks = ru8(data, headerOff + 1) or 0
  local priority = ru8(data, headerOff + 2) or 0
  local reverb = ru8(data, headerOff + 3) or 0
  local vgPtr = ru32(data, headerOff + 4) or 0

  local romOffs = {}
  for t = 0, tracks - 1 do
    romOffs[t] = gba_off(ru32(data, headerOff + 8 + t * 4))
  end

  local headerSize = 8 + tracks * 12
  local cursor = headerSize
  local trackMeta, bodyParts = {}, {}
  local hasGoto = false
  for t = 0, tracks - 1 do
    local off = romOffs[t]
    local body, entry = "", 0
    if off then
      local loop
      body, entry, loop = collect_track(data, off)
      hasGoto = hasGoto or loop
    end
    trackMeta[t] = { offset = cursor, length = #body, entry = entry }
    bodyParts[#bodyParts + 1] = body
    cursor = cursor + #body
  end

  local hdr = {
    string.char(tracks % 256, blocks % 128 + 128, priority % 256, reverb % 256),
    string.char(
      vgPtr % 256,
      math.floor(vgPtr / 256) % 256,
      math.floor(vgPtr / 65536) % 256,
      math.floor(vgPtr / 16777216) % 256
    ),
  }
  for t = 0, tracks - 1 do
    local m = trackMeta[t] or { offset = 0, length = 0 }
    local o, l, e = m.offset, m.length, m.entry or 0
    hdr[#hdr + 1] = string.char(
      o % 256, math.floor(o / 256) % 256, math.floor(o / 65536) % 256, math.floor(o / 16777216) % 256,
      l % 256, math.floor(l / 256) % 256, math.floor(l / 65536) % 256, math.floor(l / 16777216) % 256,
      e % 256, math.floor(e / 256) % 256, math.floor(e / 65536) % 256, math.floor(e / 16777216) % 256
    )
  end
  local blob = table.concat(hdr) .. table.concat(bodyParts)
  write(cache, string.format("%s/songs/%d.bin", root, songId), blob)
  return #blob, tracks, hasGoto
end

local function build_map_songs(rom, data)
  local mapSongs = {}
  local ok, Versions = pcall(require, "src.import.gba.versions")
  if not ok then return mapSongs end
  local headers = Versions.MAP_HEADERS
  if type(headers) ~= "table" then return mapSongs end
  local ExtractMapEvents = require("src.import.gba.extract_map_events")
  -- Prefer Rom object when available for u16 reads; else parse from data string.
  for mapId, headerOff in pairs(headers) do
    local music
    if rom and rom.u16 then
      local hdr = ExtractMapEvents.parseHeader(rom, headerOff)
      music = hdr and hdr.music
    elseif data then
      music = ru16(data, headerOff + 16)
    end
    if music and music ~= 0xFFFF then
      mapSongs[mapId] = music
    end
  end
  return mapSongs
end

local function species_to_cry_index(species)
  species = tonumber(species) or 0
  -- Audible mapping: Bulbasaur (1) → gCryTable[0]. pret SpeciesToCryId(1)=1 indexes
  -- the next slot; we store cryIds for playCry to use directly into cries[].
  if species < 1 then return 0 end
  if species < 251 then
    return species - 1
  end
  if species <= 276 then -- OLD_UNOWN_Z = 276
    return 200 -- SPECIES_UNOWN - 1
  end
  -- Hoenn: approximate national order into cry table (Treecko≈277 → cry ~251+)
  -- Full sHoennSpeciesIdToCryId is large; use contiguous gCryTable indices 251+.
  local idx = 251 + (species - 277)
  if idx < 0 then idx = 0 end
  if idx >= ExtractAudio.CRY_COUNT then idx = ExtractAudio.CRY_COUNT - 1 end
  return idx
end

function ExtractAudio.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.root or "data/generated/gba/audio"
  local data = rom_bytes(rom)
  local songs = {}
  local cries = {}
  local cryIds = {}
  local sampleIndex = {} -- id → meta
  local sampleMap = {}   -- wavOff → meta
  local sampleParts = {}
  local sampleCursor = { 0 }
  local vgMap = {}       -- vgOff → id
  local voicegroups = {} -- id → tones[0..127]

  local songTable = Versions.AUDIO.song_table
  local songCount = ExtractAudio.SONG_COUNT
  if data then
    local found = ExtractAudio.findSongTable(data, songCount)
    if found then songTable = found end
  end

  -- Song table binary + per-song metadata / track dumps / primary samples.
  local songtableParts = {}
  if data then
    append_bytes(songtableParts, data, songTable, songCount * 8)
    write(cache, root .. "/songtable.bin", table.concat(songtableParts))

    for id = 0, songCount - 1 do
      local off = songTable + id * 8
      local headerPtr = ru32(data, off)
      local ms = ru16(data, off + 4) or 0
      local me = ru16(data, off + 6) or 0
      local headerOff = gba_off(headerPtr)
      local info = {
        id = id,
        player = ms,
        playerEnd = me,
        kind = (ms == 0 and id >= 256 and FANFARES[id]) and "fanfare"
            or (ms == 0 and "bgm")
            or "se",
      }
      if FANFARES[id] then
        info.kind = "fanfare"
        info.fanfareFrames = FANFARES[id].frames
        info.name = FANFARES[id].name
      end
      if headerOff then
        info.tracks = ru8(data, headerOff)
        info.priority = ru8(data, headerOff + 2)
        info.reverb = ru8(data, headerOff + 3)
        info.loop = (info.kind == "bgm")
        local nbytes, _, hasGoto = dump_song_tracks(data, headerOff, id, cache, root)
        info.hasGoto = hasGoto
        info.songBytes = nbytes
        local sid = song_primary_sample(data, headerOff, sampleMap, sampleParts, sampleCursor)
        info.sampleId = sid
        local vgOff = gba_off(ru32(data, headerOff + 4))
        if vgOff then
          info.voicegroupId = dump_voicegroup(
            data, vgOff, sampleMap, sampleParts, sampleCursor, vgMap, voicegroups, 0)
        end
      else
        info.missing = true
      end
      songs[id] = info
    end
  end

  -- Cry table → samples
  local cryTable = Versions.AUDIO.cry_table
  local cryCount = ExtractAudio.CRY_COUNT
  if data and cryTable + cryCount * 12 <= #data then
    write(cache, root .. "/crytable.bin", data:sub(cryTable + 1, cryTable + cryCount * 12))
    for i = 0, cryCount - 1 do
      local toneOff = cryTable + i * 12
      local sample = read_tone_sample(data, toneOff, sampleMap, sampleParts, sampleCursor)
      local key = ru8(data, toneOff + 1) or 60
      local attack = ru8(data, toneOff + 8) or 0xFF
      local decay = ru8(data, toneOff + 9) or 0
      local sustain = ru8(data, toneOff + 10) or 0xFF
      local release = ru8(data, toneOff + 11) or 0
      cries[i] = {
        sampleId = sample and sample.id or nil,
        key = key,
        attack = attack,
        decay = decay,
        sustain = sustain,
        release = release,
        basePitch = sample and sample.freq or 0,
      }
    end
  end

  for species = 1, 411 do
    cryIds[species] = species_to_cry_index(species)
  end

  -- Flatten sampleMap → sampleIndex by id
  for _, meta in pairs(sampleMap) do
    sampleIndex[meta.id] = {
      id = meta.id,
      type = meta.type,
      compressed = meta.compressed and true or false,
      status = meta.status,
      freq = meta.freq,
      loopStart = meta.loopStart,
      size = meta.size,
      offset = meta.offset,
    }
  end

  write(cache, root .. "/samples.bin", table.concat(sampleParts))
  write(cache, root .. "/samples.lua", "return " .. encode_lua_table(sampleIndex) .. "\n")
  write(cache, root .. "/cries.lua", "return " .. encode_lua_table(cries) .. "\n")
  write(cache, root .. "/voicegroups.lua", "return " .. encode_lua_table(voicegroups) .. "\n")

  local mapSongs = build_map_songs(rom, data)

  local index = {
    version = Versions.AUDIO_VERSION or 1,
    romSha1 = opts.sha1 or "",
    songCount = songCount,
    songTable = songTable,
    cryTable = cryTable,
    cryCount = cryCount,
    players = PLAYERS,
    songs = songs,
    cries = cries,
    cryIds = cryIds,
    samples = sampleIndex,
    voicegroups = voicegroups,
    mapSongs = mapSongs,
    roles = ROLES,
    fanfares = FANFARES,
    none = 0xFFFF,
  }

  write(cache, root .. "/index.lua", "return " .. encode_lua_table(index) .. "\n")
  write(cache, root .. "/meta.json", string.format(
    '{"version":%d,"sha1":"%s","song_count":%d,"cry_count":%d,"sample_count":%d,"has_pcm":true}\n',
    index.version, tostring(opts.sha1 or ""), songCount, cryCount,
    (function()
      local n = 0
      for _ in pairs(sampleIndex) do n = n + 1 end
      return n
    end)()))

  -- Legacy filenames for older dataset paths
  write(cache, root .. "/songs.lua", "return " .. encode_lua_table(songs) .. "\n")
  write(cache, root .. "/se.lua", "return {}\n")

  return true, index
end

return ExtractAudio
