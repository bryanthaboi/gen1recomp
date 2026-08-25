package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("UWP baseroms discovery")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

love.data = love.data or {}
love.system = love.system or {}
love.filesystem = love.filesystem or {}

local MiB = 1024 * 1024
local roms = {
  ["baseroms/z-red.gb"] = string.rep("R", MiB),
  ["baseroms/a-blue.gb"] = string.rep("B", MiB),
  ["baseroms/b-yellow.gbc"] = string.rep("Y", MiB),
  ["baseroms/small.gb"] = "small",
  ["baseroms/unknown.gb"] = string.rep("?", MiB),
}

local saved = {
  hash = love.data.hash,
  encode = love.data.encode,
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  getPickedFile = love.system.getPickedFile,
  read = love.filesystem.read,
  getInfo = love.filesystem.getInfo,
  getDirectoryItems = love.filesystem.getDirectoryItems,
  createDirectory = love.filesystem.createDirectory,
  isReady = RomImporter.isReady,
}

love.data.hash = function(_, data) return data:sub(1, 1) end
love.data.encode = function(_, _, digest)
  if digest == "R" then return GameVersion.info("red").sha1 end
  if digest == "B" then return GameVersion.info("blue").sha1 end
  if digest == "Y" then return GameVersion.info("yellow").sha1 end
  return "0000000000000000000000000000000000000000"
end

local reads, listings, picks = 0, 0, 0
love.filesystem.read = function(path)
  reads = reads + 1
  return roms[path]
end
love.filesystem.getInfo = function(path, filter)
  if path == "baseroms" then
    return filter and nil or { type = "directory" }
  end
  local data = roms[path]
  if data and (not filter or filter == "file") then
    return { type = "file", size = #data }
  end
  return nil
end
love.filesystem.getDirectoryItems = function(path)
  if path ~= "baseroms" then return {} end
  listings = listings + 1
  return { "z-red.gb", "small.gb", "unknown.gb", "b-yellow.gbc", "a-blue.gb" }
end
love.filesystem.createDirectory = function() return true end
love.system.pickFile = function()
  picks = picks + 1
  return true
end
love.system.getPickedFile = function() return nil end

local function importer(ready)
  return setmetatable({
    baseRomDiscovery = true,
    baseRoms = {},
    ready = ready or { red = false, blue = false, yellow = false },
    returning = {},
    workState = nil,
    nativePicker = true,
    isNX = false,
  }, RomImporter)
end

local allReady = importer({ red = true, blue = true, yellow = true, gold = true,
  silver = true, crystal = true })
allReady:_queueBaseRomScan()
eq(allReady.baseRomScan.state, "done", "ready launcher skips discovery")
eq(listings, 0, "ready launcher does not enumerate baseroms")

local imp = importer()
imp:_queueBaseRomScan()
for _ = 1, 5 do
  local before = reads
  imp:_stepBaseRomScan()
  check(reads - before <= 1, "discovery reads at most one ROM per step")
end
eq(listings, 1, "discovery enumerates baseroms once")
eq(imp.baseRoms.blue.name, "a-blue.gb", "Blue ROM is detected by SHA-1")
eq(imp.baseRoms.yellow.name, "b-yellow.gbc", "Yellow ROM is detected by SHA-1")
eq(imp.baseRoms.red.name, "z-red.gb", "Red ROM is detected by SHA-1")
eq(reads, 4, "wrong-sized files are skipped before reading")
eq(imp.baseRomScan.state, "done", "discovery stops when every missing ROM is found")

local settledReads, settledListings = reads, listings
for _ = 1, 10 do imp:_stepBaseRomScan() end
eq(reads, settledReads, "completed discovery does not read again")
eq(listings, settledListings, "completed discovery does not enumerate again")

local detected = importer()
detected.baseRoms.red = { path = "baseroms/z-red.gb", name = "z-red.gb" }
detected.startData = function(self, data, name)
  self.started = { data = data, name = name }
end
detected:choose("red")
eq(detected.started.name, "z-red.gb", "detected ROM uses the normal import path")
eq(picks, 0, "detected ROM does not open the picker")
check(roms["baseroms/z-red.gb"] ~= nil, "detected ROM remains in baseroms")

local missing = importer()
missing.baseRoms.red = { path = "baseroms/gone.gb", name = "gone.gb" }
missing:choose("red")
check(missing.notice ~= nil, "missing detected ROM reports a notice")
eq(picks, 0, "missing detected ROM does not open the picker unexpectedly")
missing:choose("red")
eq(picks, 1, "the next import attempt falls back to the native picker")

local rescanned = importer({ red = true, blue = true, yellow = true, gold = true,
  silver = true, crystal = true })
rescanned.baseRoms.red = { path = "baseroms/z-red.gb", name = "z-red.gb" }
rescanned:reimport("red")
check(rescanned.baseRoms.red == nil, "re-import clears the detected ROM")
eq(rescanned.baseRomScan.state, "queued", "re-import queues one fresh scan")

RomImporter.isReady = function() return false end
love.system.getOS = function() return "UWP" end
Platform._resetForTests()
local launcher = RomImporter.new(function() end, { launcher = true })
check(launcher.baseRomDiscovery, "UWP launcher enables baseroms discovery")
local importOnly = RomImporter.new(function() end)
check(not importOnly.baseRomDiscovery, "non-launcher UWP import stays unchanged")
love.system.getOS = function() return "Windows" end
Platform._resetForTests()
local desktop = RomImporter.new(function() end, { launcher = true })
check(not desktop.baseRomDiscovery, "desktop launcher does not scan baseroms")

love.data.hash = saved.hash
love.data.encode = saved.encode
love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.getPickedFile = saved.getPickedFile
love.filesystem.read = saved.read
love.filesystem.getInfo = saved.getInfo
love.filesystem.getDirectoryItems = saved.getDirectoryItems
love.filesystem.createDirectory = saved.createDirectory
RomImporter.isReady = saved.isReady
Platform._resetForTests()

S.finish()
