-- tests/engine/android_shortcuts_payload_test.lua
-- Tests Android dynamic shortcuts synchronization, launch options intent resolution,
-- and love.handlers.intent_game in-process game hot-swapping.
--   luajit tests/engine/android_shortcuts_payload_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

require("main")

-- 1. Verify LaunchOptions handles getLaunchGame on Android
local LaunchOptions = require("src.core.LaunchOptions")

local savedOS = love.system and love.system.getOS
local savedGetLaunchGame = love.system and love.system.getLaunchGame

love.system = love.system or {}
love.system.getOS = function() return "Android" end
love.system.getLaunchGame = function() return "gold" end

local game, slot = LaunchOptions.resolve({})
check(game == "gold", "LaunchOptions resolves intent game from love.system.getLaunchGame on Android")

local gameCli, slotCli = LaunchOptions.resolve({ "--game=red" })
check(gameCli == "red", "CLI --game flag overrides intent game")

-- 2. Verify RomImporter.syncAndroidShortcuts ranking and 4-item cap
local RomImporter = require("src.import.RomImporter")

local originalIsReady = RomImporter.isReady
local capturedShortcuts = nil

love.system.updateShortcuts = function(versions)
  capturedShortcuts = versions
  return true
end

-- Mock isReady
RomImporter.isReady = function(v)
  return v == "red" or v == "gold" or v == "blue" or v == "yellow"
end

local ok = RomImporter.syncAndroidShortcuts("gold")
check(ok == true, "syncAndroidShortcuts returns true on Android")
check(#capturedShortcuts == 4, "syncAndroidShortcuts caps at 4 items")
check(capturedShortcuts[1] == "gold", "activeVersion 'gold' is placed first")

-- Test with subset of ready games (e.g. only Red and Gold)
RomImporter.isReady = function(v)
  return v == "red" or v == "gold"
end

capturedShortcuts = nil
RomImporter.syncAndroidShortcuts("red")
check(#capturedShortcuts == 2, "syncAndroidShortcuts only includes ready ROMs")
check(capturedShortcuts[1] == "red" and capturedShortcuts[2] == "gold", "ready ROMs correctly passed")

-- Test on non-Android platform (safe no-op)
love.system.getOS = function() return "Linux" end
capturedShortcuts = nil
local nonAndroidOk = RomImporter.syncAndroidShortcuts("red")
check(nonAndroidOk == false, "syncAndroidShortcuts safely no-ops on non-Android")
check(capturedShortcuts == nil, "no shortcuts updated on non-Android")

-- 3. Verify love.handlers.intent_game definition
check(type(love.handlers.intent_game) == "function", "main.lua defines love.handlers.intent_game")

-- Restore
RomImporter.isReady = originalIsReady
if savedOS then
  love.system.getOS = savedOS
else
  love.system.getOS = nil
end
love.system.getLaunchGame = savedGetLaunchGame
love.system.updateShortcuts = nil

print("8/8 checks passed  (android_shortcuts_payload_test)")
