-- BGM mixer worker: lock-free SPSC PCM ring via love.thread Channels.
-- Paces the M4A sequencer in GBA VBlank units (13379 Hz / 224 samples).
-- Sample rate is dictated by the main thread so QueueableSource and SoundData match.

require("love.thread")
require("love.sound")
require("love.timer")
require("love.filesystem")

local cmdCh = love.thread.getChannel("game3_m4a_cmd")
local outCh = love.thread.getChannel("game3_m4a_out")

-- Resilient module loader for threads
local function load_mod(rel, modName)
  if modName and package and package.loaded and package.loaded[modName] then
    return package.loaded[modName]
  end
  if love and love.filesystem and love.filesystem.load then
    local ok, chunk = pcall(love.filesystem.load, rel)
    if ok and chunk then
      local okCall, res = pcall(chunk)
      if okCall and res then return res end
    end
  end
  if modName then
    local ok, mod = pcall(require, modName)
    if ok and mod then return mod end
  end
  local chunk = loadfile(rel) or loadfile("./" .. rel)
  if chunk then return chunk() end
  error("Failed to load module: " .. tostring(rel))
end

local Mix = load_mod("src/core/game3/m4a_mix.lua", "src.core.game3.m4a_mix")
package.loaded["src.core.game3.m4a_mix"] = Mix
local Sample = load_mod("src/core/game3/m4a_sample.lua", "src.core.game3.m4a_sample")
package.loaded["src.core.game3.m4a_sample"] = Sample
local Seq = load_mod("src/core/game3/m4a_seq.lua", "src.core.game3.m4a_seq")
package.loaded["src.core.game3.m4a_seq"] = Seq
local Player = load_mod("src/core/game3/m4a_player.lua", "src.core.game3.m4a_player")
package.loaded["src.core.game3.m4a_player"] = Player

local WorkerFs = load_mod("src/core/WorkerFs.lua", "src.core.WorkerFs")
package.loaded["src.core.WorkerFs"] = WorkerFs

local pack = nil
local cache = WorkerFs.cache(nil)
local fanfareCh = love.thread.getChannel("game3_m4a_fanfare")
local statusCh = love.thread.getChannel("game3_m4a_status")

local bgm = { voices = {}, seq = nil, songId = nil, muted = false, volume = 1, abs = 0 }
local snaps = {}
local SNAP_KEEP = 64
local packRoot = nil
local baked = {}
local fanfareQueue = {}
local baking = nil
local bakingId = nil
local priority = nil
local FANFARE_ORDER = { 258, 256, 257, 318, 261, 259, 260, 262, 270, 271, 317, 269, 268, 338 }
local running = true
-- QueueableSource buffer size (underrun safety). Sequencer advances in
-- ~1 GBA vblank quanta inside Player.renderBuffered — not as one batch.
local BUFFER = Player.BUFFER_SAMPLES or 8192
-- Keep ~2s in the Channel so main-thread focus stalls don't underrun OpenAL.
local TARGET_QUEUED = Player.CHANNEL_TARGET or 12
local sampleRate = Mix.SAMPLE_RATE

local function apply_cmd(msg)
  if type(msg) ~= "table" then return end
  if msg.cmd == "quit" then
    running = false
  elseif msg.cmd == "install" then
    if msg.sampleRate then
      sampleRate = Mix.setSampleRate(msg.sampleRate)
      BUFFER = Player.BUFFER_SAMPLES or 8192
      TARGET_QUEUED = Player.CHANNEL_TARGET or 12
    end
    cache:setPrefix(msg.prefix)
    local err
    pack, err = Player.loadPack(cache, msg.root)
    if not pack then
      statusCh:push({ installFailed = true, root = msg.root, err = tostring(err) })
    end
    if msg.root ~= packRoot then
      packRoot = msg.root
      baked = {}
      baking = nil
      bakingId = nil
    end
    fanfareQueue = {}
    local ff = pack and pack.index and pack.index.fanfares
    if ff then
      local seen = {}
      for _, id in ipairs(FANFARE_ORDER) do
        if ff[id] or ff[tostring(id)] then
          fanfareQueue[#fanfareQueue + 1] = id
          seen[id] = true
        end
      end
      for k in pairs(ff) do
        local id = tonumber(k)
        if id and not seen[id] then
          fanfareQueue[#fanfareQueue + 1] = id
          seen[id] = true
        end
      end
    end
  elseif msg.cmd == "bakeFanfare" then
    priority = tonumber(msg.id)
  elseif msg.cmd == "play" then
    if not pack then return end
    bgm = { voices = {}, seq = nil, songId = msg.id, muted = false,
      volume = bgm.volume or 1, reverb = bgm.reverb, abs = 0, epoch = msg.epoch }
    snaps = {}
    Player.start(pack, cache, bgm, msg.id, { forceSeq = true })
  elseif msg.cmd == "stop" then
    bgm.voices = {}
    bgm.seq = nil
    bgm.songId = nil
    bgm.done = true
    snaps = {}
  elseif msg.cmd == "stopAt" then
    bgm.epoch = msg.epoch
    bgm.abs = Player.stopAt(bgm, snaps, msg.at, bgm.abs, pack, cache) or bgm.abs
    Mix._hpfCapL, Mix._hpfCapR = 0, 0
    bgm.muted = true
  elseif msg.cmd == "pause" then
    bgm.muted = true
  elseif msg.cmd == "resume" then
    bgm.muted = false
  elseif msg.cmd == "volume" then
    bgm.volume = msg.volume or 1
  elseif msg.cmd == "mix" then
    bgm.mono = msg.mono and true or false
  elseif msg.cmd == "dropFanfares" then
    baked = {}
  end
end

local function bake_fanfare(id, yieldEvery)
  if not pack then return end
  local ff = pack.index and pack.index.fanfares
  local e = ff and (ff[id] or ff[tostring(id)])
  local frames = (e and e.frames) or 160
  local root = packRoot
  -- pokefirered/src/sound.c:50
  local sd = Player.bakeSong(pack, cache, id, {
    mono = bgm.mono,
    sampleRate = sampleRate,
    maxSec = frames / 60 + 4,
    yieldEvery = yieldEvery,
  })
  if type(sd) == "userdata" and root == packRoot then
    fanfareCh:push({ id = id, root = root, data = sd })
  end
end

while running do
  local msg = cmdCh:pop()
  while msg do
    apply_cmd(msg)
    msg = cmdCh:pop()
  end

  if priority and pack then
    local id = priority
    priority = nil
    if baking and bakingId == id then
      while baking do
        local ok = coroutine.resume(baking)
        if not ok or coroutine.status(baking) == "dead" then baking = nil; bakingId = nil end
      end
    else
      baked[id] = true
      bake_fanfare(id, nil)
    end
  end

  local queued = outCh:getCount()
  if pack and bgm.songId and not bgm.muted and queued < TARGET_QUEUED then
    -- Interleave MPlayMain with mix (pret/mGBA: once per vblank).
    local at = bgm.abs or 0
    if bgm.seq then
      snaps[#snaps + 1] = Player.snapshotSlot(bgm, at)
      if #snaps > SNAP_KEEP then table.remove(snaps, 1) end
    end
    local sd = Player.renderBuffered(bgm, BUFFER, {
      master = 1,
      mono = bgm.mono,
      sampleRate = sampleRate,
    })
    bgm.abs = at + BUFFER
    if sd then
      outCh:push({ gen = bgm.songId, epoch = bgm.epoch, at = at, n = BUFFER, data = sd, rate = sampleRate })
    end
    if bgm.done and #(bgm.voices or {}) == 0 and not Mix.reverbActive(bgm.reverbState) then
      outCh:push({
        gen = bgm.songId,
        epoch = bgm.epoch,
        at = bgm.abs,
        n = BUFFER,
        data = love.sound.newSoundData(BUFFER, sampleRate, 16, 2),
        rate = sampleRate,
        ended = true,
      })
      bgm.abs = bgm.abs + BUFFER
    end
  elseif baking then
    local ok = coroutine.resume(baking)
    if not ok or coroutine.status(baking) == "dead" then baking = nil; bakingId = nil end
  elseif pack and #fanfareQueue > 0 then
    local id = table.remove(fanfareQueue, 1)
    if not baked[id] then
      baked[id] = true
      bakingId = id
      baking = coroutine.create(function() bake_fanfare(id, BUFFER) end)
    end
  else
    love.timer.sleep(0.002)
  end
end
