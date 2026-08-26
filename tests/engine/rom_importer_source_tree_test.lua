-- sourceTreeHasData must use the engine-owned cache contract. Gold's cache has
-- no Gen 1 trade art; validating it against the Gen 1 list made a Gold source
-- tree look incomplete forever.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local CacheContract = require("src.import.CacheContract")

local f = assert(io.open("src/import/RomImporter.lua", "r"))
local src = f:read("*a")
f:close()

local readyStart = src:find("function RomImporter.isReady", 1, true)
check(readyStart ~= nil, "isReady is defined")
local readyEnd = src:find("\nfunction RomImporter.syncAndroidShortcuts", readyStart, true)
check(readyEnd ~= nil, "isReady ends before the next importer helper")
local readyBody = src:sub(readyStart, readyEnd)

check(readyBody:find("CacheContract.isReady", 1, true) ~= nil,
  "isReady delegates source-tree and cache readiness to the contract")
check(readyBody:find("ipairs(REQUIRED_FILES)", 1, true) == nil,
  "isReady does not iterate the Gen 1 REQUIRED_FILES list raw")

local required, isOverride = CacheContract.requiredFilesFor("gold")
check(isOverride, "Gold uses the override required-file list")
local requiredSet = {}
for _, path in ipairs(required) do requiredSet[path] = true end
check(requiredSet["assets/generated/battle/hud/balls.png"],
  "Gold caches require the trainer HUD ball sheet")
check(not requiredSet["assets/generated/trade/game_boy.png"],
  "Gold does not inherit the Gen 1 trade-art requirement")

T.finish()
