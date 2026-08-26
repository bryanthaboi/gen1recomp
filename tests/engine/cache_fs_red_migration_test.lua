-- Issue #899: Red's extracted cache lives under red/ like blue/ and
-- yellow/, and a legacy root cache (pre-fix installs) is migrated on first
-- boot instead of reading as "never imported".
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")

eq(GameVersion.cachePrefix("red"), "red/",
  "Red's cache is namespaced under red/")

-- legacy layout: the marker and both generated trees at the save-dir root
love.filesystem.write("rom-cache.complete", "rom-cache-v9:abc")
love.filesystem.write("data/generated/maps.lua", "return {}")
love.filesystem.write("data/generated/constants.lua", "return {}")
love.filesystem.write("assets/generated/fonts/font.png", "font-bytes")

CacheFs.migrateLegacyRedCache()

eq(love.filesystem.read("red/rom-cache.complete"), "rom-cache-v9:abc",
  "the marker moved under red/")
eq(love.filesystem.read("red/data/generated/maps.lua"), "return {}",
  "the data tree moved under red/")
eq(love.filesystem.read("red/assets/generated/fonts/font.png"), "font-bytes",
  "the assets tree moved under red/")
check(love.filesystem.read("rom-cache.complete") == nil,
  "the root marker is gone")
check(love.filesystem.read("data/generated/maps.lua") == nil,
  "the root data tree is gone")
check(love.filesystem.read("assets/generated/fonts/font.png") == nil,
  "the root assets tree is gone")

-- idempotent: a second run leaves the migrated tree alone
CacheFs.migrateLegacyRedCache()
eq(love.filesystem.read("red/rom-cache.complete"), "rom-cache-v9:abc",
  "a second run keeps the migrated cache")

-- an existing red/ cache wins over a legacy root leftover: no clobber
love.filesystem.write("rom-cache.complete", "rom-cache-v9:STALE")
CacheFs.migrateLegacyRedCache()
eq(love.filesystem.read("red/rom-cache.complete"), "rom-cache-v9:abc",
  "an existing red/ cache is not clobbered")
check(love.filesystem.read("rom-cache.complete") ~= nil,
  "the unmigrated leftover stays (a stale-marker re-import handles it)")
love.filesystem.remove("rom-cache.complete")

-- mountVersion("red") overlays red/ at the un-prefixed paths, like blue/
love.filesystem._mounts = {}
check(CacheFs.mountVersion("red") == true, "mountVersion(red) returns true")
eq(love.filesystem.read("assets/generated/fonts/font.png"), "font-bytes",
  "post-mount probe reads red assets at the un-prefixed path")
eq(love.filesystem.read("data/generated/constants.lua"), "return {}",
  "post-mount probe reads red data at the un-prefixed path")

-- unmountVersion peels generated overlays (LIFO) then the version folder, so
-- a later Play/Edit on another game cannot resolve this version's files.
do
  local mounts = love.filesystem._mounts
  local archives = {}
  for _, m in ipairs(mounts) do archives[#archives + 1] = m.archive end
  local function indexOf(name)
    for i, a in ipairs(archives) do if a == name then return i end end
  end
  local dataIdx = indexOf("red/data/generated")
  local assetsIdx = indexOf("red/assets/generated")
  check(dataIdx and assetsIdx, "mountVersion recorded generated-tree overlays")
  check(assetsIdx > dataIdx,
    "assets/generated was mounted after data/generated (LIFO unmount peels it first)")
end
check(CacheFs.unmountVersion("red") == true, "unmountVersion(red) returns true")
check(love.filesystem.read("assets/generated/fonts/font.png") == nil,
  "post-unmount probe no longer sees red assets at the un-prefixed path")
check(love.filesystem.read("data/generated/constants.lua") == nil,
  "post-unmount probe no longer sees red data at the un-prefixed path")
do
  local left = {}
  for _, m in ipairs(love.filesystem._mounts) do
    if tostring(m.archive):find("red", 1, true) then
      left[#left + 1] = m.archive
    end
  end
  eq(#left, 0, "no red/ mounts remain after unmountVersion")
end

-- no legacy cache at all: migration is a no-op, not an error
love.filesystem.remove("red/rom-cache.complete")
love.filesystem.remove("red/data/generated/maps.lua")
love.filesystem.remove("red/data/generated/constants.lua")
love.filesystem.remove("red/assets/generated/fonts/font.png")
CacheFs.migrateLegacyRedCache()
check(love.filesystem.read("red/rom-cache.complete") == nil,
  "nothing to migrate invents nothing")

T.finish()
