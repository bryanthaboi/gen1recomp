-- Minimal MP2K/M4A track bytecode interpreter (GOTO = native loop).
-- Sequencer advances in GBA VBlank units (MPlayMain), not wall-clock 60Hz guesses.

local Mix = require("src.core.game3.m4a_mix")

local Seq = {}

-- Matches pret gClockTable (0-based). Waits: [cmd-0x80]; Notes: [cmd-0xCF].
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44,
  48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88, 90, 92, 96,
}

local function clock_at(idx)
  idx = tonumber(idx) or 0
  if idx < 0 then idx = 0 end
  return CLOCK[idx] or idx
end

local function u8(blob, off)
  if off < 0 or off >= #blob then return nil end
  return blob:byte(off + 1)
end

local function u32le(blob, off)
  local b0 = u8(blob, off)
  if not b0 then return nil end
  return b0 + (u8(blob, off + 1) or 0) * 256
    + (u8(blob, off + 2) or 0) * 65536
    + (u8(blob, off + 3) or 0) * 16777216
end

function Seq.parseSongBin(blob)
  if type(blob) ~= "string" or #blob < 8 then return nil end
  local tracks = u8(blob, 0) or 0
  if tracks > 16 then tracks = 0 end
  local out = {
    tracks = tracks,
    blocks = u8(blob, 1),
    priority = u8(blob, 2),
    reverb = u8(blob, 3),
    voicegroup = u32le(blob, 4),
    trackData = {},
    trackEntries = {},
  }
  if tracks == 0 then return out end

  local first = u32le(blob, 8) or 0
  local packed = first > 0 and first < #blob and first < 0x01000000

  if packed then
    local stride = (out.blocks or 0) >= 128 and 12 or 8
    out.blocks = (out.blocks or 0) % 128
    for t = 0, tracks - 1 do
      local base = 8 + t * stride
      local off = u32le(blob, base) or 0
      local len = u32le(blob, base + 4) or 0
      if off > 0 and len > 0 and off + len <= #blob then
        out.trackData[t + 1] = blob:sub(off + 1, off + len)
        out.trackEntries[t + 1] = stride == 12 and (u32le(blob, base + 8) or 0) or 0
      else
        out.trackData[t + 1] = ""
      end
    end
    return out
  end

  local headerSize = 8 + tracks * 4
  local ptrs = {}
  for t = 0, tracks - 1 do
    ptrs[#ptrs + 1] = { idx = t, ptr = u32le(blob, 8 + t * 4) or 0 }
  end
  table.sort(ptrs, function(a, b) return a.ptr < b.ptr end)
  local cursor = headerSize
  local packedOff = {}
  for i, p in ipairs(ptrs) do
    local remainTracks = #ptrs - i + 1
    local remainBytes = #blob - cursor
    local approx = math.floor(remainBytes / remainTracks)
    if ptrs[i + 1] and p.ptr > 0 and ptrs[i + 1].ptr > p.ptr then
      approx = math.min(approx, ptrs[i + 1].ptr - p.ptr)
    end
    approx = math.max(16, math.min(approx, remainBytes))
    packedOff[p.idx] = { off = cursor, len = approx }
    cursor = cursor + approx
  end
  for t = 0, tracks - 1 do
    local p = packedOff[t]
    if p then
      out.trackData[t + 1] = blob:sub(p.off + 1, p.off + p.len)
    else
      out.trackData[t + 1] = ""
    end
  end
  return out
end

local function new_track(data)
  return {
    data = data or "",
    pc = 0,
    wait = 0,
    done = false,
    key = 60,
    vel = 127,
    voice = 0,
    volume = 100,
    pan = 0x40,
    bend = 0,
    bendRange = 2, -- pret MPlayTrack init
    tune = 0,      -- signed, C_V center = 0
    keyShift = 0,
    lfoSpeed = 22, -- pret default
    lfoDelay = 0,
    lfoDelayC = 0,
    lfoSpeedC = 0,
    mod = 0,
    modT = 0,
    modM = 0,
    callStack = {},
    -- pret: commands >= 0xBD update runningStatus; bytes < 0x80 reuse it.
    runningStatus = nil,
  }
end

--- pret TrkVolPitSet pitch half: keyM (semitones) + fine (0..255).
function Seq.trackPitch(tr)
  local bend = (tr.bend or 0) * (tr.bendRange or 2)
  local tune = tr.tune or 0
  local keyShift = tr.keyShift or 0
  local x = (tune + bend) * 4 + (keyShift * 256)
  if (tr.modT or 0) == 0 and (tr.mod or 0) > 0 then
    x = x + 16 * (tr.modM or 0)
  end
  return math.floor(x / 256), (x % 256)
end

-- pokefirered TrkVolPitSet + ChnVolSetAsm, retaining the integer truncation
-- and the separate rhythm pan multiplier. Gains are channel bytes / 256.
function Seq.trackVolume(tr, vel, rhythmPan)
  vel = tonumber(vel) or tr.vel or 100
  local x = math.floor((tr.volume or 100) * 64 / 32)
  if (tr.modT or 0) == 1 then
    x = math.floor(x * ((tr.modM or 0) + 128) / 128)
  end
  local pan = 2 * ((tr.pan or 0x40) - 0x40)
  if (tr.modT or 0) == 2 then pan = pan + (tr.modM or 0) end
  pan = math.max(-128, math.min(127, pan))
  local ml = math.floor((127 - pan) * x / 256) % 256
  local mr = math.floor((128 + pan) * x / 256) % 256
  local rp = rhythmPan or 0
  local l = math.min(255, math.floor((127 - rp) * vel * ml / 16384))
  local r = math.min(255, math.floor((128 + rp) * vel * mr / 16384))
  return l / 256, r / 256
end

local calc_track_vol = Seq.trackVolume

function Seq.newPlayer(song, opts)
  opts = opts or {}
  local tracks = {}
  for i = 1, (song and song.tracks) or 0 do
    local tr = new_track(song.trackData[i])
    tr.pc = song.trackEntries and song.trackEntries[i] or 0
    tr.index = i
    tracks[i] = tr
  end
  return {
    song = song,
    tracks = tracks,
    tempo = 150, -- tempoD
    tempoC = 0,
    frameC = 0,
    c15 = 0,
    voices = {},
    voiceResolver = opts.voiceResolver,
    muted = false,
  }
end

local function track_read(tr)
  if tr.pc >= #tr.data then
    tr.done = true
    return nil
  end
  local b = tr.data:byte(tr.pc + 1)
  tr.pc = tr.pc + 1
  return b
end

local function track_unread(tr)
  if tr.pc > 0 then tr.pc = tr.pc - 1 end
end

local function track_read32(tr)
  local b0 = track_read(tr) or 0
  local b1 = track_read(tr) or 0
  local b2 = track_read(tr) or 0
  local b3 = track_read(tr) or 0
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local MAX_DS = Mix.MAX_DS_CHANNELS

--- pret MPlayMain: after BEND/VOL/PAN/MOD, TrkVolPitSet + rewrite active channel freqs.
local function refresh_track_voices(player, tr)
  if not tr then return end
  local keyM, fine = Seq.trackPitch(tr)
  for _, v in ipairs(player.voices) do
    if v.track == tr and v.alive ~= false then
      if tr._volDirty then
        local nvel = v.noteVel or tr.vel or 127
        local volL, volR = calc_track_vol(tr, nvel, v.rhythmPan)
        v.volL = volL
        v.volR = volR
      end
      if tr._pitchDirty and not v.fixedFreq then
        local noteKey = v.noteKey or 60
        local absKey = noteKey + keyM
        if absKey < 0 then absKey = 0 end
        if absKey > 178 then absKey = 178 end
        if v.kind == "ds" and v.wavFreq then
          local rate = Mix.midiKeyToFreq(v.wavFreq, absKey, fine)
          v.step = rate / Mix.SAMPLE_RATE
        elseif v.kind == "cgb_pulse" then
          local period = Mix.cgbPeriod(absKey, fine, v.cgbFixed)
          v.periodReg = period
          if not v.sweepEnabled then
            v.freq = Mix.periodToPulseHz(period)
          end
        elseif v.kind == "cgb_wave" then
          v.freq = Mix.cgbWaveHz(absKey, fine, v.cgbFixed)
        elseif v.kind == "cgb_noise" then
          v.period = Mix.cgbNoisePeriod(absKey)
        end
      end
    end
  end
  tr._pitchDirty = false
  tr._volDirty = false
end

local function start_note(player, tr, key, vel, gate)
  vel = vel or tr.vel or 100
  if not player.voiceResolver then return end
  if (tr.lfoDelay or 0) > 0 then
    tr.lfoDelayC = tr.lfoDelay
    tr.modM = 0
    tr._pitchDirty, tr._volDirty = true, true
  end
  local volL, volR = calc_track_vol(tr, vel)
  local rawKey = tonumber(key) or 60
  local keyM, fine = Seq.trackPitch(tr)
  local absKey = rawKey + keyM
  if absKey < 0 then absKey = 0 end
  if absKey > 178 then absKey = 178 end

  -- Resolver gets standard args with absKey appended; voice stores base note key for live BEND.
  local voice = player.voiceResolver(tr.voice, rawKey, vel, tr, volL, volR, fine, absKey)
  if voice then
    gate = tonumber(gate) or 0
    if gate > 0 then
      voice.gateTicks = gate
    else
      voice.gateTicks = nil -- TIE (cmd == 0xCF): sustains indefinitely until EOT (0xCE) or sound stop
    end
    voice.track = tr
    if voice.noteKey == nil then
      voice.noteKey = rawKey
    end
    voice.noteVel = vel
    voice.midiKey = rawKey
    voice.priority = math.min(255, (player.song.priority or 0) + (tr.priority or 0))

    -- CGB: 4 physical hardware channels (1..4).
    -- pret MP2K (m4a_1.s lines 1648-1668): exactly one voice per CGB channel.
    -- Priority check: higher priority steals; equal priority earlier track steals; lower priority is dropped.
    if voice.cgbChan then
      local chan = voice.cgbChan
      local active = nil
      for _, v in ipairs(player.voices) do
        if v.alive ~= false and v.cgbChan == chan then
          active = v
          break
        end
      end
      if active then
        local oldPrio = active.priority or 0
        local newPrio = voice.priority
        if active.released or newPrio > oldPrio then
          active.alive = false
        elseif newPrio < oldPrio then
          return
        else
          local oldIdx = (active.track and active.track.index) or 999
          local newIdx = tr.index or 999
          if newIdx <= oldIdx then
            active.alive = false
          else
            return
          end
        end
      end
    elseif voice.kind == "ds" then
      -- ply_note prefers a released voice, then the lowest priority and latest
      -- track. A lower-priority note cannot evict a higher-priority active voice.
      local count, victim = 0, nil
      for _, v in ipairs(player.voices) do
        if v.alive ~= false and v.kind == "ds" then
          count = count + 1
          local eligible = v.released or (v.priority or 0) < voice.priority
            or ((v.priority or 0) == voice.priority
              and ((v.track and v.track.index) or 0) >= tr.index)
          if eligible then
            local vp, bp = v.priority or 0, victim and victim.priority or 0
            local vi = (v.track and v.track.index) or 0
            local bi = victim and victim.track and victim.track.index or 0
            if not victim or (v.released and not victim.released)
              or ((not not v.released) == (not not victim.released)
                and (vp < bp or (vp == bp and vi >= bi))) then
              victim = v
            end
          end
        end
      end
      if count >= MAX_DS then
        if not victim then return end
        victim.alive = false
      end
    end

    player.voices[#player.voices + 1] = voice
  end
end

local function ply_note(player, tr, cmd)
  local gate = clock_at(cmd - 0xCF)
  local key = track_read(tr)
  if not key then return end
  if key >= 0x80 then
    track_unread(tr)
    key = tr.key or 60
  else
    tr.key = key
    local vel = track_read(tr)
    if not vel then
      start_note(player, tr, key, tr.vel or 0x7F, gate)
      return
    end
    if vel >= 0x80 then
      track_unread(tr)
    else
      tr.vel = vel
      local add = track_read(tr)
      if not add then
        start_note(player, tr, key, vel, gate)
        return
      end
      if add >= 0x80 then
        track_unread(tr)
      else
        gate = gate + add
      end
    end
  end
  start_note(player, tr, key, tr.vel or 0x7F, gate)
end

local function exec_cmd(player, tr, cmd)
  if cmd == 0xB1 then
    tr.done = true
    for _, v in ipairs(player.voices) do
      if v.track == tr then Mix.releaseVoice(v) end
    end
  elseif cmd == 0xB2 then
    local addr = track_read32(tr)
    if addr < #tr.data then
      if addr < tr.pc then tr.loopCount = (tr.loopCount or 0) + 1 end
      tr.pc = addr
    else
      exec_cmd(player, tr, 0xB1)
    end
  elseif cmd == 0xB3 then
    local addr = track_read32(tr)
    if addr < #tr.data and #tr.callStack < 3 then
      tr.callStack[#tr.callStack + 1] = tr.pc
      tr.pc = addr
    else
      exec_cmd(player, tr, 0xB1)
    end
  elseif cmd == 0xB4 then
    if #tr.callStack > 0 then tr.pc = table.remove(tr.callStack) end
  elseif cmd == 0xB5 then
    local count = track_read(tr) or 0
    local addr = track_read32(tr)
    tr.repN = (tr.repN or 0) + 1
    if count == 0 or tr.repN < count then
      if addr < #tr.data then tr.pc = addr end
    else
      tr.repN = 0
    end
  elseif cmd == 0xBA then
    tr.priority = track_read(tr) or 0
  elseif cmd == 0xBB then
    local t = track_read(tr) or 75
    player.tempo = t * 2
  elseif cmd == 0xBC then
    tr.keyShift = track_read(tr) or 0
    if tr.keyShift > 127 then tr.keyShift = tr.keyShift - 256 end
    tr._pitchDirty = true
  elseif cmd == 0xBD then
    tr.voice = track_read(tr) or 0
    tr.toneOverrides = nil
  elseif cmd == 0xBE then
    tr.volume = track_read(tr) or 100
    tr._volDirty = true
  elseif cmd == 0xBF then
    tr.pan = track_read(tr) or 0x40
    tr._volDirty = true
  elseif cmd == 0xC0 then
    tr.bend = (track_read(tr) or 0x40) - 0x40
    tr._pitchDirty = true
  elseif cmd == 0xC1 then
    tr.bendRange = track_read(tr) or 2
    tr._pitchDirty = true
  elseif cmd == 0xC2 then
    tr.lfoSpeed = track_read(tr) or 22
    if tr.lfoSpeed == 0 and (tr.modM or 0) ~= 0 then
      tr.modM = 0
      if (tr.modT or 0) == 0 then tr._pitchDirty = true else tr._volDirty = true end
    end
  elseif cmd == 0xC3 then
    tr.lfoDelay = track_read(tr) or 0
    tr.lfoDelayC = tr.lfoDelay
  elseif cmd == 0xC4 then
    tr.mod = track_read(tr) or 0
    if tr.mod == 0 and (tr.modM or 0) ~= 0 then
      tr.modM = 0
      if (tr.modT or 0) == 0 then tr._pitchDirty = true else tr._volDirty = true end
    end
  elseif cmd == 0xC5 then
    local oldT = tr.modT or 0
    tr.modT = track_read(tr) or 0
    if oldT ~= tr.modT then
      tr._pitchDirty = true
      tr._volDirty = true
    end
  elseif cmd == 0xC8 then
    -- TUNE: signed around 0x40 (C_V)
    tr.tune = (track_read(tr) or 0x40) - 0x40
    tr._pitchDirty = true
  elseif cmd == 0xCD then
    local xop = track_read(tr) or 0
    local fields = { [2] = "type", [4] = "attack", [5] = "decay",
      [6] = "sustain", [7] = "release", [10] = "length", [11] = "pan" }
    if fields[xop] then
      tr.toneOverrides = tr.toneOverrides or {}
      tr.toneOverrides[fields[xop]] = track_read(tr) or 0
    elseif xop == 8 then
      tr.pseudoEchoVolume = track_read(tr) or 0
    elseif xop == 9 then
      tr.pseudoEchoLength = track_read(tr) or 0
    elseif xop == 12 then
      local low = track_read(tr) or 0
      local high = track_read(tr) or 0
      tr.wait = low + high * 256
    elseif xop == 13 then
      tr.sampleStart = track_read32(tr)
    elseif xop == 1 then
      -- Raw ROM pointer is not represented by the existing sample cache.
      track_read32(tr)
    else
      exec_cmd(player, tr, 0xB1)
    end
  elseif cmd == 0xCE then
    local key = tr.data:byte(tr.pc + 1)
    if key and key < 0x80 then
      tr.pc = tr.pc + 1
      tr.key = key
    else
      key = tr.key
    end
    -- ply_endtie releases the newest matching MIDI key, not the whole track.
    for i = #player.voices, 1, -1 do
      local v = player.voices[i]
      if v.track == tr and v.midiKey == key and v.alive and not v.released then
        Mix.releaseVoice(v)
        break
      end
    end
  elseif cmd >= 0xCF then
    ply_note(player, tr, cmd)
  elseif cmd >= 0x80 and cmd <= 0xB0 then
    tr.wait = clock_at(cmd - 0x80)
  elseif cmd == 0xCC then -- PORT register offset and value
    track_read(tr)
    track_read(tr)
  elseif cmd == 0xB9 then
    local op = track_read(tr) or 0
    local addr = track_read(tr) or 0
    local data = track_read(tr) or 0
    player.mem = player.mem or {}
    local value = player.mem[addr] or 0
    local operand = op >= 3 and op <= 5 or op >= 12
    operand = operand and (player.mem[data] or 0) or data
    if op <= 5 then
      local action = op % 3
      if action == 0 then value = operand
      elseif action == 1 then value = value + operand
      else value = value - operand end
      player.mem[addr] = value % 256
    elseif op <= 17 then
      local target = track_read32(tr)
      local cond = (op - 6) % 6
      local take = (cond == 0 and value == operand) or (cond == 1 and value ~= operand)
        or (cond == 2 and value > operand) or (cond == 3 and value >= operand)
        or (cond == 4 and value <= operand) or (cond == 5 and value < operand)
      if take and target < #tr.data then tr.pc = target end
    end
  else
    exec_cmd(player, tr, 0xB1)
  end
end

local function tick_track(player, tr)
  if tr.done then return end
  if tr.wait and tr.wait > 0 then
    tr.wait = tr.wait - 1
    return
  end
  local guard = 0
  while not tr.done and (not tr.wait or tr.wait <= 0) and guard < 64 do
    guard = guard + 1
    if tr.pc >= #tr.data then
      tr.done = true
      break
    end
    local b = tr.data:byte(tr.pc + 1)
    local cmd
    if b < 0x80 then
      -- Running status: data byte stays for the command handler (ply_note reads key).
      cmd = tr.runningStatus
      if not cmd or cmd < 0x80 then
        -- No status yet — skip orphan data byte.
        tr.pc = tr.pc + 1
        break
      end
    else
      tr.pc = tr.pc + 1
      cmd = b
      -- pret: only cmds >= 0xBD update runningStatus
      if cmd >= 0xBD then
        tr.runningStatus = cmd
      end
    end
    exec_cmd(player, tr, cmd)
    if tr._pitchDirty or tr._volDirty then
      refresh_track_voices(player, tr)
    end
    if tr.wait and tr.wait > 0 then
      tr.wait = tr.wait - 1
      break
    end
  end
end

local function seq_tick(player)
  -- MPlayMain ages each track's gates immediately before its commands.
  for _, tr in ipairs(player.tracks) do
    for _, v in ipairs(player.voices) do
      if v.track == tr and v.gateTicks then
        v.gateTicks = v.gateTicks - 1
        if v.gateTicks <= 0 then Mix.releaseVoice(v) end
      end
    end
    tick_track(player, tr)
  end

  -- Tick LFO modulation per active track
  for _, tr in ipairs(player.tracks) do
    if not tr.done and (tr.lfoSpeed or 0) > 0 and (tr.mod or 0) > 0 then
      if (tr.lfoDelayC or 0) > 0 then
        tr.lfoDelayC = tr.lfoDelayC - 1
      else
        tr.lfoSpeedC = ((tr.lfoSpeedC or 0) + tr.lfoSpeed) % 256
        local phase = tr.lfoSpeedC
        local tri
        if phase < 64 then
          tri = phase
        elseif phase < 192 then
          tri = 128 - phase
        else
          tri = phase - 256
        end
        local newModM = math.floor((tr.mod * tri) / 64)
        if newModM ~= (tr.modM or 0) then
          tr.modM = newModM
          if (tr.modT or 0) == 0 then
            tr._pitchDirty = true
          else
            tr._volDirty = true
          end
        end
      end
    end
  end

  for _, tr in ipairs(player.tracks) do
    if tr._pitchDirty or tr._volDirty then
      refresh_track_voices(player, tr)
    end
  end

end

--- Advance complete SoundMain frames. Tempo only governs MPlayMain ticks.
function Seq.update(player, vblanks)
  vblanks = tonumber(vblanks) or 1
  if not player or player.muted then return player and player.voices or {} end
  if vblanks <= 0 then return player.voices end
  player.frameC = (player.frameC or 0) + vblanks
  while player.frameC >= 1 do
    player.frameC = player.frameC - 1
    player.tempoC = (player.tempoC or 0) + (player.tempo or 150)
    while player.tempoC >= 150 do
      player.tempoC = player.tempoC - 150
      seq_tick(player)
    end
    player.c15 = (player.c15 == 0) and 14 or player.c15 - 1
    for _, v in ipairs(player.voices) do
      Mix.tickEnvelope(v, player.c15 == 0)
    end
  end
  local alive = {}
  for _, v in ipairs(player.voices) do
    if v.alive ~= false then alive[#alive + 1] = v end
  end
  player.voices = alive
  return alive
end

function Seq.snapshot(player)
  if not player then return nil end
  local tracks = {}
  for i, tr in ipairs(player.tracks or {}) do
    local t = {}
    for k, v in pairs(tr) do
      if k == "callStack" then
        local cs = {}
        for j, pc in ipairs(v) do cs[j] = pc end
        t.callStack = cs
      elseif k == "toneOverrides" then
        t.toneOverrides = {}
        for field, value in pairs(v) do t.toneOverrides[field] = value end
      elseif type(v) ~= "table" then
        t[k] = v
      end
    end
    tracks[i] = t
  end
  local mem = {}
  for k, v in pairs(player.mem or {}) do mem[k] = v end
  return { tracks = tracks, tempo = player.tempo, tempoC = player.tempoC,
    frameC = player.frameC, c15 = player.c15, mem = mem }
end

function Seq.restore(player, snap)
  if not (player and snap) then return end
  for i, tr in ipairs(player.tracks or {}) do
    local t = snap.tracks[i]
    if t then
      for k in pairs(tr) do
        if k ~= "callStack" and type(tr[k]) ~= "table" and t[k] == nil then tr[k] = nil end
      end
      for k, v in pairs(t) do
        if k ~= "callStack" then tr[k] = v end
      end
      local cs = {}
      for j, pc in ipairs(t.callStack or {}) do cs[j] = pc end
      tr.callStack = cs
      tr.toneOverrides = nil
      if t.toneOverrides then
        tr.toneOverrides = {}
        for k, v in pairs(t.toneOverrides) do tr.toneOverrides[k] = v end
      end
    end
  end
  player.tempo = snap.tempo
  player.tempoC = snap.tempoC
  player.frameC = snap.frameC or 0
  player.c15 = snap.c15 or 0
  player.mem = {}
  for k, v in pairs(snap.mem or {}) do player.mem[k] = v end
end

function Seq.allDone(player)
  if not player then return true end
  for _, tr in ipairs(player.tracks) do
    if not tr.done then return false end
  end
  return #player.voices == 0
end

return Seq
