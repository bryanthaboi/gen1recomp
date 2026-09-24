package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local WorkerFs = require("src.core.WorkerFs")

local savedSystem = love.system
local savedThread = love.thread
local savedVersion = GameVersion.get()
local savedRead = love.filesystem.read
local savedLoad = love.filesystem.load

local function setOS(osName)
  love.system = { getOS = function() return osName end }
  Platform._resetForTests()
end

local function fakeFs(files)
  local fs = { reads = {} }
  function fs.read(path)
    fs.reads[#fs.reads + 1] = path
    local bytes = files[path]
    if bytes then return bytes end
    return nil, path .. " does not exist"
  end
  return fs
end

local function readsInclude(fs, path)
  for _, p in ipairs(fs.reads) do
    if p == path then return true end
  end
  return false
end

local fs = fakeFs({ ["firered/a.bin"] = "P", ["a.bin"] = "B", ["b.bin"] = "B2" })
eq(WorkerFs.read("firered/", "a.bin", fs), "P", "prefixed copy wins")
eq(WorkerFs.read("firered/", "b.bin", fs), "B2", "bare fallback when the prefixed copy is absent")
fs = fakeFs({ ["firered/a.bin"] = "P", ["a.bin"] = "B" })
eq(WorkerFs.read(nil, "a.bin", fs), "B", "nil prefix reads only the bare path")
eq(#fs.reads, 1, "nil prefix never probes a prefixed path")
eq(WorkerFs.read("", "a.bin", fs), "B", "empty prefix is the desktop path")
local miss, err = WorkerFs.read("firered/", "c.bin", fakeFs({}))
eq(miss, nil, "double miss is nil")
eq(err, "c.bin does not exist", "double miss returns the bare read's error")

local cache = WorkerFs.cache(nil, fakeFs({ ["leafgreen/x"] = "L", ["x"] = "X" }))
eq(cache:read("x"), "X", "cache with no prefix reads bare")
cache:setPrefix("leafgreen/")
eq(cache:read("x"), "L", "setPrefix switches the cache to the versioned tree")
cache:setPrefix("")
eq(cache:read("x"), "X", "setPrefix('') returns to bare reads")

setOS("OS X")
for _, id in ipairs(GameVersion.ORDER) do
  GameVersion.set(id)
  eq(WorkerFs.prefix(), nil, "desktop hands workers no prefix for " .. id)
end
setOS("NX")
for _, id in ipairs(GameVersion.ORDER) do
  GameVersion.set(id)
  eq(WorkerFs.prefix(), GameVersion.cachePrefix(id), "NX hands workers " .. id .. "'s prefix")
end

local function newChannel()
  local c = { items = {} }
  function c:push(v) self.items[#self.items + 1] = v end
  function c:pop() return table.remove(self.items, 1) end
  function c:demand() return table.remove(self.items, 1) end
  function c:clear() self.items = {} end
  function c:getCount() return #self.items end
  return c
end

local channels
local function resetChannels()
  channels = {}
  love.thread = {
    getChannel = function(name)
      channels[name] = channels[name] or newChannel()
      return channels[name]
    end,
  }
end

for _, name in ipairs({ "love.thread", "love.sound", "love.timer", "love.filesystem" }) do
  package.preload[name] = package.preload[name] or function() return true end
end
love.timer = love.timer or {}
love.timer.getTime = love.timer.getTime or os.clock
love.timer.sleep = love.timer.sleep or function() end

local function serve(files)
  local reads = {}
  love.filesystem.read = function(path)
    reads[#reads + 1] = path
    if files[path] then return files[path] end
    return nil, "Could not open file " .. path .. ". Does not exist."
  end
  love.filesystem.load = function(path)
    if path:sub(1, 4) == "src/" then return loadfile(path) end
    return savedLoad(path)
  end
  return reads
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local function runChipWorker(audio, files)
  resetChannels()
  local reads = serve(files)
  local saved = package.loaded["src.core.WorkerFs"]
  package.loaded["src.core.WorkerFs"] = nil
  local cmd = love.thread.getChannel("chipaudio_cmd")
  cmd:push({ cmd = "play", gen = 1, header = { engine = 1 }, allowLoops = true, audio = audio })
  cmd:push({ cmd = "quit" })
  local chunk = assert(loadfile("src/core/chip_worker.lua"))
  chunk()
  package.loaded["src.core.WorkerFs"] = saved
  local errors = {}
  for _, m in ipairs(love.thread.getChannel("chipaudio_out").items) do
    if m.error then errors[#errors + 1] = m.error end
  end
  return reads, errors
end

local function programError(errors)
  for _, e in ipairs(errors) do
    if tostring(e):find("could not read sound programs", 1, true) then return true end
  end
  return false
end

local PROG = "assets/generated/audio/programs.bin"
local PROG_BYTES = string.rep("\0", 0x4000 * 2)
local ChipAudio = require("src.core.ChipAudio")
local fullAudio = { audio = { programFile = PROG, bankOrder = { 2, 8 }, waveBanks = {} } }

for _, id in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  setOS("NX")
  GameVersion.set(id)
  local prefix = GameVersion.cachePrefix(id)
  local nxOnly = { [prefix .. PROG] = PROG_BYTES }
  local slim = ChipAudio._slimAudioForTest(fullAudio)
  local reads, errors = runChipWorker(slim, nxOnly)
  check(contains(reads, prefix .. PROG), "NX chip worker reads " .. prefix .. PROG)
  check(not programError(errors), "NX chip worker finds programs.bin for " .. id)

  local bare = { programFile = PROG, bankOrder = { 2, 8 }, waveBanks = {} }
  local _, bareErrors = runChipWorker(bare, nxOnly)
  check(programError(bareErrors), "without the prefix the NX chip worker misses programs.bin for " .. id .. " (#2449 class)")
end

setOS("OS X")
GameVersion.set("blue")
local slimDesktop = ChipAudio._slimAudioForTest(fullAudio)
eq(slimDesktop.programPrefix, nil, "desktop chip payload carries no prefix")
local deskReads, deskErrors = runChipWorker(slimDesktop, { [PROG] = PROG_BYTES })
eq(deskReads[1], PROG, "desktop chip worker reads the mounted bare path first")
check(not contains(deskReads, "blue/" .. PROG), "desktop chip worker never probes a prefixed path")
check(not programError(deskErrors), "desktop chip worker finds programs.bin")

local ChipSynth = require("src.core.ChipSynth")
ChipSynth.invalidateBanks()
serve({ ["red/" .. PROG] = string.rep("R", 0x8000), ["blue/" .. PROG] = string.rep("U", 0x8000) })
local redBanks = ChipSynth._loadBanksForTest({ audio = { programFile = PROG, programPrefix = "red/", bankOrder = { 1, 2 } } })
local blueBanks = ChipSynth._loadBanksForTest({ audio = { programFile = PROG, programPrefix = "blue/", bankOrder = { 1, 2 } } })
eq(redBanks[1]:sub(1, 1), "R", "red prefix loads red banks")
eq(blueBanks[1]:sub(1, 1), "U", "bank cache is keyed by prefix, not just programFile")
ChipSynth.invalidateBanks()

local ROOT = "data/generated/gba/audio"
local INDEX = "return { songs = {} }"
local function runM4aWorker(prefix, files)
  resetChannels()
  local reads = serve(files)
  local saved = package.loaded["src.core.WorkerFs"]
  package.loaded["src.core.WorkerFs"] = nil
  local cmd = love.thread.getChannel("game3_m4a_cmd")
  cmd:push({ cmd = "install", root = ROOT, prefix = prefix })
  cmd:push({ cmd = "quit" })
  local chunk = assert(loadfile("src/core/game3/m4a_worker.lua"))
  chunk()
  package.loaded["src.core.WorkerFs"] = saved
  return reads, love.thread.getChannel("game3_m4a_status")
end

for _, id in ipairs({ "firered", "leafgreen" }) do
  setOS("NX")
  GameVersion.set(id)
  local prefix = WorkerFs.prefix()
  eq(prefix, id .. "/", "NX m4a install prefix for " .. id)
  local nxOnly = { [prefix .. ROOT .. "/index.lua"] = INDEX }
  local reads, status = runM4aWorker(prefix, nxOnly)
  check(contains(reads, prefix .. ROOT .. "/index.lua"), "NX m4a worker reads the " .. id .. " tree")
  eq(status:getCount(), 0, "NX m4a worker installs for " .. id)
  local _, bareStatus = runM4aWorker(nil, nxOnly)
  local failed = bareStatus:pop()
  check(type(failed) == "table" and failed.installFailed, "without the prefix the NX m4a worker misses the pack for " .. id .. " (#2449)")
end

setOS("OS X")
GameVersion.set("firered")
local deskM4aReads, deskStatus = runM4aWorker(WorkerFs.prefix(), { [ROOT .. "/index.lua"] = INDEX })
eq(deskStatus:getCount(), 0, "desktop m4a worker installs from the mounted path")
check(not contains(deskM4aReads, "firered/" .. ROOT .. "/index.lua"), "desktop m4a worker never probes a prefixed path")

love.filesystem.read = savedRead
love.filesystem.load = savedLoad
setOS("NX")
GameVersion.set("red")
local CacheFs = require("src.import.CacheFs")
local savedPrefix = CacheFs.prefix
CacheFs.prefix = "leafgreen/"
local REL = "data/generated/gba/items/pack.lua"
check(CacheFs.write(REL, "return {}"), "import worker write succeeds on NX")
eq(love.filesystem.read("leafgreen/" .. REL), "return {}", "import worker writes land under the version prefix on NX")
eq(love.filesystem.read(REL), nil, "import worker never writes the bare path on NX")
check(CacheFs.exists(REL), "import worker exists() sees its own prefixed write")
eq(CacheFs.readActive(REL), "return {}", "readActive in a worker state (GameVersion red) still finds the prefixed file")
love.filesystem.remove("leafgreen/" .. REL)
CacheFs.prefix = savedPrefix

love.system = savedSystem
love.thread = savedThread
Platform._resetForTests()
GameVersion.set(savedVersion)

T.finish("worker fs nx")
