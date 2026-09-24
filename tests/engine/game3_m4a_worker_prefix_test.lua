package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")

local ROOT = "data/generated/gba/audio"
local INDEX = "return { songs = {} }"

local function newChannel()
  local c = { items = {} }
  function c:push(v) self.items[#self.items + 1] = v end
  function c:pop() return table.remove(self.items, 1) end
  function c:clear() self.items = {} end
  function c:getCount() return #self.items end
  return c
end

local channels
local function resetThreads(withThread)
  channels = {}
  love.thread = {
    getChannel = function(name)
      channels[name] = channels[name] or newChannel()
      return channels[name]
    end,
  }
  if withThread then
    love.thread.newThread = function()
      return { start = function() end, wait = function() end }
    end
  end
end

local reads
local function serve(files)
  reads = {}
  love.filesystem.read = function(path)
    reads[#reads + 1] = path
    return files[path]
  end
end

local function setOS(osName)
  love.system = { getOS = function() return osName end }
  Platform._resetForTests()
end

love.timer = love.timer or {}
love.timer.sleep = love.timer.sleep or function() end
for _, name in ipairs({ "love.thread", "love.sound", "love.timer", "love.filesystem" }) do
  package.preload[name] = package.preload[name] or function() return true end
end

local source = setmetatable({ queued = 0 }, {
  __index = function(_, key)
    if key == "getFreeBufferCount" then return function() return 1 end end
    if key == "isPlaying" then return function() return false end end
    if key == "queue" then return function(self) self.queued = self.queued + 1 return true end end
    if key == "stop" then return function(self) rawset(self, "stops", (rawget(self, "stops") or 0) + 1) end end
    return function() end
  end,
})
love.audio = love.audio or {}
love.audio.newQueueableSource = function() return source end

local function runWorker(cmds, files)
  resetThreads(false)
  local cmd = love.thread.getChannel("game3_m4a_cmd")
  for _, m in ipairs(cmds) do cmd:push(m) end
  cmd:push({ cmd = "quit" })
  serve(files)
  local chunk = assert(loadfile("src/core/game3/m4a_worker.lua"))
  chunk()
  return love.thread.getChannel("game3_m4a_status")
end

local function readPath(path)
  for _, p in ipairs(reads) do
    if p == path then return true end
  end
  return false
end

local nxOnly = { ["firered/" .. ROOT .. "/index.lua"] = INDEX }

local status = runWorker({ { cmd = "install", root = ROOT, prefix = "firered/" } }, nxOnly)
check(readPath("firered/" .. ROOT .. "/index.lua"), "worker reads the prefixed index when handed a prefix")
check(status:getCount() == 0 and not readPath(ROOT .. "/index.lua"),
  "worker install succeeds from the prefixed tree without touching the bare path")

status = runWorker({ { cmd = "install", root = ROOT } }, nxOnly)
local failed = status:pop()
check(type(failed) == "table" and failed.installFailed == true, "worker reports installFailed when the pack is missing")
eq(failed and failed.root, ROOT, "installFailed carries the install root")

status = runWorker({ { cmd = "install", root = ROOT, prefix = "firered/" } },
  { [ROOT .. "/index.lua"] = INDEX })
eq(status:getCount(), 0, "worker falls back to the bare path when the prefixed copy is absent")

GameVersion.set("firered")
local fakeCache = {
  read = function(_, rel)
    if rel == ROOT .. "/index.lua" then return INDEX end
    return nil
  end,
}

local function freshAudio()
  package.loaded["src.core.game3.audio"] = nil
  return require("src.core.game3.audio")
end

local function installs()
  local out = {}
  for _, m in ipairs(channels["game3_m4a_cmd"] and channels["game3_m4a_cmd"].items or {}) do
    if m.cmd == "install" then out[#out + 1] = m end
  end
  return out
end

setOS("NX")
resetThreads(true)
local Audio = freshAudio()
check(Audio.install(fakeCache, { root = ROOT }), "audio installs from the main-thread cache")
local sent = installs()
check(#sent > 0, "install pushed to the worker")
for i, m in ipairs(sent) do
  eq(m.prefix, "firered/", "NX install message " .. i .. " carries the firered/ prefix")
end

check(Audio.playSong(10), "playSong on the worker path")
check(Audio._bgmGen == 10, "worker path owns song 10")
love.thread.getChannel("game3_m4a_status"):push({ installFailed = true, root = ROOT, err = "missing index.lua" })
local cmdCh = channels["game3_m4a_cmd"]
Audio.pumpBgm()
eq(Audio._worker, false, "installFailed drops the worker")
check(Audio._bgmLocal ~= nil and Audio._bgmLocal.songId == 10, "installFailed restarts the current song on the sync path")
check(Audio._bgmSource ~= nil, "sync path after installFailed has a BGM source")
local quit = false
for _, m in ipairs(cmdCh.items) do
  if m.cmd == "quit" then quit = true end
end
check(quit, "installFailed tells the worker to quit")
Audio.shutdown()

GameVersion.set("leafgreen")
resetThreads(true)
Audio = freshAudio()
Audio.install(fakeCache, { root = ROOT })
sent = installs()
check(#sent > 0, "leafgreen install pushed to the worker")
for i, m in ipairs(sent) do
  eq(m.prefix, "leafgreen/", "NX leafgreen install message " .. i .. " carries the leafgreen/ prefix")
end
Audio.shutdown()
GameVersion.set("firered")

setOS("OS X")
resetThreads(true)
Audio = freshAudio()
Audio.install(fakeCache, { root = ROOT })
for i, m in ipairs(installs()) do
  eq(m.prefix, nil, "desktop install message " .. i .. " keeps the mount path")
end
Audio.shutdown()

love.thread = nil
Audio = freshAudio()
Audio.install(fakeCache, { root = ROOT })
Audio.playSong(10)
eq(Audio._worker, false, "no love.thread means no worker")
check(Audio._bgmLocal ~= nil, "sync fallback slot is set")
check(Audio._bgmSource ~= nil, "sync fallback creates the BGM source")
local stopsBefore = rawget(source, "stops") or 0
Audio.playSong(11)
eq(Audio._bgmLocal and Audio._bgmLocal.songId, 11, "sync song change swaps the slot")
check((rawget(source, "stops") or 0) > stopsBefore, "sync song change stops the source to flush queued PCM")
Audio.shutdown()

T.finish("game3 m4a worker prefix")
