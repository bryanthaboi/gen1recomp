package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end,
  error = function() end,
  warn = function() end,
}

local ROOT = "/tmp/pokeport-shaderfx-2227"
local SAVE = ROOT .. "/save"
local PORTABLE = ROOT .. "/portable"
local REL = "shaders/handheld/probe.slangp"

os.execute("rm -rf " .. ROOT)
os.execute("mkdir -p " .. SAVE .. "/shaders/handheld " .. PORTABLE)
local seeded = io.open(SAVE .. "/" .. REL, "wb")
check(seeded ~= nil, "the fixture preset is seeded in the save root")
seeded:write("#reference \"x\"\n")
seeded:close()

local fs = love.filesystem
fs.write(REL, "#reference \"x\"\n")
fs.getSaveDirectory = function() return SAVE end
fs.getRealDirectory = function(rel)
  if rel:sub(1, 7) == "shaders" then return SAVE end
  return nil
end

local SaveData = require("src.core.SaveData")
SaveData.portableBaseDir = function() return PORTABLE end

package.loaded["src.import.CacheFs"] = package.loaded["src.import.CacheFs"] or {}
local CacheFs = package.loaded["src.import.CacheFs"]
CacheFs.prefix = CacheFs.prefix or ""
CacheFs.root = CacheFs.root or function() return nil end
local writes = {}
local prefixDuringWrite
CacheFs.write = function(rel, data)
  prefixDuringWrite = CacheFs.prefix
  writes[rel] = data
  return true
end

local ShaderFX = require("src.render.ShaderFX")

eq(ShaderFX.presetDir(), PORTABLE .. package.config:sub(1, 1) .. "shaders",
  "presetDir still answers the portable folder")

local list = ShaderFX.list()
eq(#list, 1, "the seeded preset is enumerated")
local entry = list[1]
check(entry.fullPath:find(SAVE, 1, true) == 1,
  "fullPath names the root PhysFS actually found it in (got " .. tostring(entry.fullPath) .. ")")
check(entry.fullPath:find(PORTABLE, 1, true) == nil,
  "and not the portable folder nothing ever wrote to")

local opened = io.open(entry.fullPath, "rb")
check(opened ~= nil, "io.open(entry.fullPath) succeeds, which is what the bridge does")
if opened then opened:close() end

eq(entry.fullPath:match("^(.*)/[^/]+$"), SAVE .. "/shaders/handheld",
  "the path still splits on / so ShaderSourcePatches.dirname keeps working")

eq(ShaderFX.artifactPath(entry), SAVE .. "/" .. (REL:gsub("%.slangp$", ".lua")),
  "the .lua artifact is written beside the preset that exists")

fs.getRealDirectory = nil
local fallback = ShaderFX.list()
eq(fallback[1].fullPath, PORTABLE .. package.config:sub(1, 1) .. "shaders/handheld/probe.slangp",
  "without getRealDirectory the pre-fix presetDir path is still what comes back")
fs.getRealDirectory = function() return SAVE end

CacheFs.prefix = "blue/"
fs.write("shaderfx_buildbot.zip", "PK")
fs.write("shaderfx_buildbot_mount/handheld/bevel.slangp", "shader0 = stub.slang\n")
local copied, installErr = ShaderFX.installDownloaded(false)
eq(installErr, nil, "installDownloaded reports no error")
eq(copied, 1, "the kept preset is copied")
eq(prefixDuringWrite, "", "installDownloaded pins CacheFs.prefix to the root for the copy")
eq(CacheFs.prefix, "blue/", "and hands the caller's prefix back afterwards")
check(writes["shaders/handheld/bevel.slangp"] ~= nil,
  "the extracted tree goes through CacheFs.write, not love.filesystem.write")

os.execute("rm -rf " .. ROOT)

T.finish("shaderfx portable preset paths (#2227/#2220)")
