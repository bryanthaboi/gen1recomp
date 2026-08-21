package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("fixture boot routing")
local check = S.check

local realGetenv = os.getenv
local dataDir
os.getenv = function(name)
  if name == "POKEPORT_DATA_DIR" then return dataDir end
  return realGetenv(name)
end

local RomImporter = require("src.import.RomImporter")
check(not RomImporter.isReady("crystal"),
  "an unsupported external version is unready instead of crashing cache lookup")

-- main.lua must normalize environment/CLI values before asking CacheFs for a
-- version prefix.  Keep a dynamic check on the normalizer and a small source
-- guard on the boot wiring: the regression here crashed on `crystal` before
-- RomImporter had a chance to reject its unsupported hash.
local GameVersion = require("src.core.GameVersion")
local savedVersion = GameVersion.get()
check(GameVersion.set("crystal") == "red",
  "an unsupported scripted version normalizes to the safe Red default")
check(GameVersion.set("silver") == "silver",
  "normalization preserves a supported non-default version")
GameVersion.set(savedVersion)
local mainFile = assert(io.open("main.lua", "r"))
local mainSource = mainFile:read("*a")
mainFile:close()
local normalizedAt = mainSource:find(
  "local scriptedVersion = require(\"src.core.GameVersion\").set(requestedVersion)",
  1, true)
local readyAt = mainSource:find("RomImporter.isReady(scriptedVersion)", 1, true)
check(normalizedAt and readyAt and normalizedAt < readyAt
      and not mainSource:find("RomImporter.isReady(requestedVersion)", 1, true),
  "main boot checks readiness only after normalizing the requested version")

dataDir = "tests/fixture_data"
check(RomImporter.isReady("red"),
  "an explicit fixture dataset bypasses the interactive ROM importer")

-- Negative path: bypassing the importer is not permission to boot partial
-- data.  Data remains the validator and identifies the missing fixture module
-- instead of silently falling back to a developer's private ROM cache.
dataDir = "tests/fixture_data/does-not-exist"
local ok, err = pcall(function() require("src.core.Data"):load() end)
check(not ok and tostring(err):find("POKEPORT_DATA_DIR", 1, true) ~= nil,
  "an incomplete fixture fails fast with its configured source named")

os.getenv = realGetenv
S.finish()
