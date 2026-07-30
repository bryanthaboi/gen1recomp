-- #420: importing a .sav on Android.  Two halves: a pick that fails has to be
-- retired so the next tap reopens the picker instead of re-running the same
-- file forever, and the crosswalk tables have to come out of the target game's
-- ROM cache -- the launcher runs before CacheFs.mountVersion, so a bare require
-- sees Red's copy at best and nothing at all in a fused build.
--   luajit tests/engine/save_import_retry_bug420.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")

-- ------------------------------------------------------------------
-- Bug A: a failed Android save pick must not block the retry
-- ------------------------------------------------------------------

local RomImporter = require("src.import.RomImporter")

local pickCalls = {}
love.system = {
  getOS = function() return "Android" end,
  pickFile = function(kind)
    pickCalls[#pickCalls + 1] = kind or "rom"
    return true
  end,
}
love.filesystem.getSaveDirectory = function() return "/sdcard/pokeport/save" end

local function clearSaveDir()
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    love.filesystem.remove(name)
  end
end

-- Only the fields the Android save-import path reads.  _importSave is stubbed
-- with the outcome consumePick keys on, since the whole question is what the
-- launcher does with the file afterwards.
local function freshImporter(importOk)
  pickCalls = {}
  return setmetatable({
    android = true,
    workState = nil,
    tab = "red",
    ready = { red = true, blue = false, yellow = false },
    saveNotice = {},
    notice = nil,
    _importSave = function(self, version, name)
      self._imports = self._imports or {}
      self._imports[#self._imports + 1] = { version = version, name = name }
      self.saveNotice[version] = { ok = importOk and true or false, text = "result" }
    end,
  }, RomImporter)
end

do
  clearSaveDir()
  love.filesystem.write("picked_save.sav", "too short to be SRAM")
  local ri = freshImporter(false)
  ri:chooseSaveImport("red")
  eq(#ri._imports, 1, "the pending SAF pick is what Import save consumes")
  eq(love.filesystem.getInfo("picked_save.sav"), nil,
    "a rejected SAF pick is dropped: it is GameActivity's own copy")
  ri:chooseSaveImport("red")
  eq(#pickCalls, 1, "the second tap reopens the picker instead of retrying it")
  eq(pickCalls[1], "sav", "and asks for a battery save")
  eq(#ri._imports, 1, "the rejected file is not run through the importer twice")
end

do
  clearSaveDir()
  love.filesystem.write("picked_save.sav", "32768 bytes, as far as this test cares")
  local ri = freshImporter(true)
  ri:chooseSaveImport("blue")
  eq(love.filesystem.getInfo("picked_save.sav"), nil,
    "a pick that imported cleanly is still removed")
  eq(#pickCalls, 0, "and the picker is not reopened over a successful import")
end

-- A USB copy is the player's own file sitting in the save dir, so a failed one
-- is skipped for the session rather than deleted.
do
  clearSaveDir()
  love.filesystem.write("pokemon_red.sav", "wrong size")
  local ri = freshImporter(false)
  ri:chooseSaveImport("red")
  eq(ri._imports[1].name, "pokemon_red.sav", "Import save picks up a USB copy")
  check(love.filesystem.getInfo("pokemon_red.sav") ~= nil,
    "the player's own .sav stays on disk")
  ri:chooseSaveImport("red")
  eq(#pickCalls, 1, "the skipped USB copy no longer wins the scan")
  eq(#ri._imports, 1, "and is not re-imported")
end

-- The focus path (SAF returns, GameActivity has written the pick) retires the
-- same way, so a refocus loop cannot re-run a rejected file.
do
  clearSaveDir()
  love.filesystem.write("picked_save.sav", "wrong size")
  local ri = freshImporter(false)
  ri.androidPendingVersion = "yellow"
  ri:focus(true)
  eq(ri._imports[1].version, "yellow", "focus imports for the game that was picked for")
  eq(love.filesystem.getInfo("picked_save.sav"), nil, "and retires the rejected pick")
  ri:focus(true)
  eq(#ri._imports, 1, "the next focus has nothing left to re-import")
end

clearSaveDir()

-- ------------------------------------------------------------------
-- Bug B: the crosswalk comes from the target game's ROM cache
-- ------------------------------------------------------------------

-- Fake CacheFs, installed before SaveConvert is required so its lazy require
-- picks it up.  Each read reports the prefix it was asked under and hands back
-- a module tagged with it, which is what makes "whose cache" observable.
local reads = {}
local SENTINEL = "SENTINEL/"
local cacheFails = false
local fakeCache = { prefix = SENTINEL }
function fakeCache.read(path)
  reads[#reads + 1] = { path = path, prefix = fakeCache.prefix }
  if cacheFails then error("no such cache entry: " .. path) end
  return ("return { cacheTag = %q, path = %q }")
    :format(tostring(fakeCache.prefix), path)
end
package.loaded["src.import.CacheFs"] = fakeCache

local SaveConvert = require("src.save_convert.SaveConvert")

local GENERATED = { "pokemon", "moves", "items", "maps" }

local function prefixes()
  local seen = {}
  for _, r in ipairs(reads) do seen[r.prefix] = (seen[r.prefix] or 0) + 1 end
  return seen
end

do
  reads = {}
  local data, err = SaveConvert.loadData("blue")
  check(type(data) == "table", "loadData(blue) resolves: " .. tostring(err))
  for _, name in ipairs(GENERATED) do
    eq(data and data[name] and data[name].cacheTag, GameVersion.VERSIONS.blue.cachePrefix,
      name .. " comes out of Blue's cache, not the un-prefixed read path")
  end
  eq(prefixes()[GameVersion.VERSIONS.blue.cachePrefix], #GENERATED,
    "all four generated tables are read under Blue's cache prefix")
  eq(fakeCache.prefix, SENTINEL,
    "CacheFs.prefix is launcher-owned state and is put back after the read")
  check(data and data.eventFlags ~= nil,
    "the save-convert-only crosswalks still load through require")
end

do
  reads = {}
  SaveConvert.loadData("blue")
  eq(#reads, 0, "a second load for the same game reuses the cached set")
end

-- importSav's 2nd arg is the save-format stamp; the 3rd is what selects the
-- crosswalk.  Red's cache prefix is the empty string, so the recorded prefix
-- doubles as proof the read went through CacheFs at all.
local zeros = string.rep("\0", SaveConvert.SAVE_SIZE)
do
  reads = {}
  SaveConvert.importSav(zeros, 2, "red")
  eq(prefixes()[GameVersion.VERSIONS.red.cachePrefix], #GENERATED,
    "importSav reads the crosswalk from the game named by its 3rd argument")
end

do
  reads = {}
  SaveConvert.importSav(zeros, 2)
  eq(#reads, 0, "with no game named, the format stamp is not read as one")
end

do
  reads = {}
  local ok, _, err = pcall(SaveConvert.exportSav, { meta = {} }, "yellow")
  check(ok, "exportSav takes the same game argument without raising: " .. tostring(err))
  eq(prefixes()[GameVersion.VERSIONS.yellow.cachePrefix], #GENERATED,
    "exportSav reads Yellow's crosswalk on the way back out")
end

do
  reads = {}
  local data = SaveConvert.loadData("yellow")
  eq(data and data.maps and data.maps.cacheTag, GameVersion.VERSIONS.yellow.cachePrefix,
    "Yellow gets Yellow's tables: the set is keyed per game, not global")
  eq(#reads, 0, "and shares the set exportSav already warmed")
end

-- The require path still has to carry SaveConvert under plain luajit, where
-- there is no cache to read from.
do
  reads = {}
  cacheFails = true
  local ok, data, err = pcall(SaveConvert.loadData, "red")
  cacheFails = false
  check(ok, "an unreadable cache falls back instead of raising: " .. tostring(data))
  if loadfile("data/generated/maps.lua") then
    check(type(data) == "table",
      "the require path still resolves the tables headless: " .. tostring(err))
  end
end

-- ------------------------------------------------------------------
-- The launcher's glue names the game it is importing for (cross-file contract)
-- ------------------------------------------------------------------

do
  local seen = {}
  package.loaded["src.save_convert.SaveConvert"] = {
    SAVE_SIZE = 32768,
    importSav = function(_, version, gameVersion)
      seen.import = { version = version, gameVersion = gameVersion }
      return nil, "stub"
    end,
    exportSav = function(_, gameVersion)
      seen.export = { gameVersion = gameVersion }
      return nil, "stub"
    end,
  }
  package.loaded["src.core.SaveData"] = {
    load = function() return { meta = {} } end,
    activeSlot = function() return "slot1" end,
    buildMeta = function() return {} end,
    createSlot = function() return "slot1" end,
    writeSlot = function() return true end,
    setActiveSlot = function() return true end,
  }
  local SaveFileIO = require("src.import.SaveFileIO")

  SaveFileIO.importToSlot(string.rep("\0", 32768), "yellow")
  eq(seen.import and seen.import.gameVersion, "yellow",
    "importToSlot tells SaveConvert whose cache to read")
  eq(seen.import and seen.import.version, "yellow",
    "and still passes the version stamp it always did")

  SaveFileIO.exportActiveSlot("blue")
  eq(seen.export and seen.export.gameVersion, "blue",
    "exportActiveSlot names the game on the way back out")
end

T.finish()
