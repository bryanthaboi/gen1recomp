-- Gold on fused NX: gold/data/generated exists, but the overlay mount
-- onto data/generated often fails.  Game2/World used to love.filesystem.load
-- the unprefixed path and crash with "Gold cache incomplete / maps.lua
-- Does not exist" after a textless intro.  CacheFs.loadActive must read the
-- versioned file without any mount.
-- Self-contained: luajit tests/engine/cache_fs_gold_nx_load_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")

local savedVersion = GameVersion.get()
local savedPrefix = CacheFs.prefix

love.filesystem._mounts = {}
GameVersion.set("gold")
CacheFs.prefix = GameVersion.cachePrefix()

love.filesystem.write("gold/data/generated/maps.lua",
  "return { NEW_BARK_TOWN = { id = 1 } }")
love.filesystem.write("gold/data/generated/oak_speech.lua",
  "return { text = { _OakText1 = 'Hello!' } }")
love.filesystem.write("gold/data/generated/font.lua",
  "return { width = 8 }")

-- Unprefixed path is a miss: the NX mount hole.
eq(love.filesystem.read("data/generated/maps.lua"), nil,
  "unprefixed maps.lua is missing (mount hole)")
eq(love.filesystem.load("data/generated/maps.lua"), nil,
  "love.filesystem.load misses unprefixed maps.lua")

local maps, mapsErr = CacheFs.loadActive("data/generated/maps.lua")
check(maps ~= nil, "loadActive finds gold/data/generated/maps.lua ("
  .. tostring(mapsErr) .. ")")
eq(maps and maps.NEW_BARK_TOWN and maps.NEW_BARK_TOWN.id, 1,
  "loadActive returns the Gold maps table")

local oak = CacheFs.loadActive("data/generated/oak_speech.lua")
eq(oak and oak.text and oak.text._OakText1, "Hello!",
  "loadActive returns oak_speech.lua from gold/")

local font = CacheFs.loadActive("data/generated/font.lua")
eq(font and font.width, 8,
  "loadActive returns font.lua from gold/")

love.filesystem.remove("gold/data/generated/maps.lua")
love.filesystem.remove("gold/data/generated/oak_speech.lua")
love.filesystem.remove("gold/data/generated/font.lua")
CacheFs.prefix = savedPrefix
GameVersion.set(savedVersion)

T.finish()
