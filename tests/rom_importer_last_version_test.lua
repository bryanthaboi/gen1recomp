-- #835: the launcher must open on the game that was played last, instead of
-- always opening on Red.  Two halves, both asserted here: RomImporter:play
-- writes the chosen version to options.lua, and RomImporter:_applyLastVersionTab
-- reads it back when the constructor has finished filling self.ready.
-- Self-contained: `luajit tests/rom_importer_last_version_test.lua`; also
-- dofile'd by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer last version")
local eq = S.eq

love.mouse.isCursorSupported = function() return false end

local SaveData = require("src.core.SaveData")
local LaunchOptions = require("src.core.LaunchOptions")
local RomImporter = require("src.import.RomImporter")

-- The options round trip must not touch the developer's real save directory.
-- SaveData.persistFs consults SaveData.portableFs() before love.filesystem
-- (src/core/SaveData.lua:203-208), so overriding that one hook reroutes both
-- loadOptions and saveOptions onto this in-memory volume.  saveOptions reads
-- the file back after writing (#828), so read/write have to be truthful.
-- The override is process-global and tests/run_tests.lua dofiles every suite
-- into one process, so it MUST be put back before this file returns: leaving
-- it in place reroutes every later suite's save I/O into `disk` (parity_hof
-- reads its own save back and fails 6 assertions if this leaks).
local realPortableFs = SaveData.portableFs
local disk = {}
SaveData.portableFs = function()
  return {
    getInfo = function(name) return disk[name] and { type = "file" } or nil end,
    read = function(name) return disk[name] or nil, "no file: " .. name end,
    write = function(name, data) disk[name] = data return true end,
    remove = function(name) disk[name] = nil end,
  }
end

local function newImporter(fields)
  local ri = setmetatable(fields, RomImporter)
  return ri
end

-- ---- write side: play() records the version it hands off to boot

local booted = nil
local ri = newImporter({
  android = true,               -- skips the cursor restore; see #114 suite
  workState = nil,
  tab = "red",
  ready = { yellow = true },
  onComplete = function(version) booted = version end,
})
ri:play("yellow")
eq(booted, "yellow", "play boots the chosen version")
eq(SaveData.loadOptions().lastVersion, "yellow", "play remembers the version played")

-- ---- read side: a fresh launcher opens on that column

local ri2 = newImporter({ tab = "red", ready = { red = true, yellow = true } })
ri2:_applyLastVersionTab()
eq(ri2.tab, "yellow", "launcher opens on the last played version")

-- A remembered version whose cache is gone or stale must not open a column
-- with no Play button in it.
local ri3 = newImporter({ tab = "red", ready = { red = true, yellow = false } })
ri3:_applyLastVersionTab()
eq(ri3.tab, "red", "an unready remembered version leaves the tab alone")

-- An explicit --game shortcut (main.lua sets LaunchOptions.pendingTab) wins
-- over the remembered version.
LaunchOptions.pendingTab = "blue"
local ri4 = newImporter({ tab = "blue", ready = { red = true, yellow = true } })
ri4:_applyLastVersionTab()
eq(ri4.tab, "blue", "an explicit --game tab beats the remembered version")
LaunchOptions.pendingTab = nil   -- module is a singleton: do not leak this

-- A junk value in options.lua (hand-edited file, a build that knew other
-- versions) must not select a tab that does not exist.  Real version ids
-- stood here twice -- "gold", then "crystal" -- and each had to be swapped
-- out the day that game shipped, so this is "nonesuch": a deliberate
-- never-a-game token, not a version anyone is waiting on.
local opts = SaveData.loadOptions()
opts.lastVersion = "nonesuch"
SaveData.saveOptions(opts)
local ri5 = newImporter({ tab = "red", ready = { red = true, yellow = true } })
ri5:_applyLastVersionTab()
eq(ri5.tab, "red", "an unknown remembered version leaves the tab alone")

SaveData.portableFs = realPortableFs

S.finish()
